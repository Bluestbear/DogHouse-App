import { initializeApp, getApp, App } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getAuth } from "firebase-admin/auth";
import { logger } from "firebase-functions/v2";
import {
  onDocumentWritten,
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, onRequest, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as nodemailer from "nodemailer";

const REGION = "europe-west1";

// ── Economy constants (mirror the Swift client) ──
const MAX_GRACE_CHARGES = 3;
const GRACE_RECHARGE_HOURS = 24;
const IMMUNITY_SECONDS = 3600;
const REDEMPTION_TREATS = 15;
const ROSES_COST = 5;

// Treat packs sold as App Store consumables, credited by revenuecatWebhook.
// Authoritative amounts: the client only ever displays what RevenueCat's
// Offering says the pack costs in money — how many treats it is worth is
// decided here, so a tampered client cannot inflate a purchase.
//
// Sized against the catalog (cosmetics run 50–300, whole catalog is 2570) and
// against idle earning (1–5 treats/hr by room level, so ~70–120/day at the top
// levels). Small ≈ a mid-tier cosmetic, large ≈ 60% of the catalog — a paying
// user still cannot buy the game out in one tap.
const TREAT_PRODUCTS: Record<string, number> = {
  "com.Harrison.DogHouse.treats.small": 250,
  "com.Harrison.DogHouse.treats.medium": 900,
  "com.Harrison.DogHouse.treats.large": 1600,
};

// Sandbox purchases credit treats like real ones — the mandatory pre-launch
// sandbox test depends on it, and exploiting it needs both the webhook secret
// and a sandbox Apple ID. Flip to false to accept PRODUCTION events only.
const ALLOW_SANDBOX_PURCHASES = true;

// How long a purchase idempotency key is kept. Must comfortably exceed any
// window in which RevenueCat could re-deliver an event — their automatic
// retry ladder is only ~155 minutes, but a human can hit "Retry" on the
// dashboard at any time, and that replay is what must not double-credit.
const PURCHASE_KEY_RETENTION_DAYS = 180;

// Shared secret set on the RevenueCat webhook's Authorization header.
// Set with: firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

// Cosmetic prices, keyed by item id — mirrors CosmeticItem.catalog in Swift.
// The server validates cost against this so clients can't spoof prices.
const COSMETIC_PRICES: Record<string, number> = {
  necklace_red: 50, necklace_blue: 50, necklace_green: 50, necklace_purple: 75,
  necklace_pink: 75, necklace_gold: 120, necklace_rainbow: 200,
  necklace_bone: 60, necklace_heart: 90, necklace_diamond: 300,
  hat_party: 80, hat_crown: 250, hat_cowboy: 100, hat_chef: 100,
  hat_wizard: 180, hat_beanie: 70, hat_halo: 220,
  glasses_cool: 80, glasses_heart: 100, glasses_star: 120,
  glasses_round: 90, glasses_ski: 110,
};

function categoryOf(itemId: string): string {
  return itemId.split("_")[0]; // "necklace_gold" -> "necklace"
}

/** Effective grace = stored + 1 per 24h since lastGraceRecharge, capped. */
function effectiveGraceCharges(stored: number, lastRecharge?: Timestamp): number {
  if (!lastRecharge) return stored;
  const hours = (Date.now() - lastRecharge.toMillis()) / 3_600_000;
  const recharged = Math.floor(hours / GRACE_RECHARGE_HOURS);
  return Math.min(stored + recharged, MAX_GRACE_CHARGES);
}

function requireAuth(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  return uid;
}

function coupleKeyOf(a: string, b: string): string {
  return [a, b].sort().join("_");
}

/**
 * Run a spend exactly once per client-supplied key.
 *
 * The client retries transient failures, and a call whose response was lost
 * in flight may already have committed on the server. Without this, that
 * retry charges the user twice. The key doc is claimed with create(), which
 * fails atomically if another attempt got there first; the stored result is
 * then replayed instead of re-running the operation.
 *
 * Keys are per-user, so one client cannot suppress another's action.
 * `cleanupIdempotencyKeys` prunes them daily.
 *
 * `kind` tags the key doc so the pruner can treat it differently. Callable
 * keys are disposable after a day; purchase keys must outlive that (see
 * PURCHASE_KEY_RETENTION_DAYS). Omitting it keeps the old behaviour.
 */
async function once<T extends Record<string, unknown>>(
  uid: string,
  key: unknown,
  operation: () => Promise<T>,
  kind?: string
): Promise<T> {
  // No key (older client) — run unguarded rather than reject.
  if (typeof key !== "string" || !key) return operation();

  const ref = db.collection("idempotencyKeys").doc(`${uid}_${key}`);
  try {
    await ref.create({
      uid,
      createdAt: Timestamp.now(),
      status: "pending",
      ...(kind ? { kind } : {}),
    });
  } catch {
    // Key already claimed: this is a retry of a call that reached us.
    const existing = (await ref.get()).data();
    if (existing?.status === "done") {
      return (existing.result ?? {}) as T;
    }
    throw new HttpsError("aborted", "That action is already being processed.");
  }

  let result: T;
  try {
    result = await operation();
  } catch (err) {
    // The operation itself threw, so nothing was committed. Release the key and
    // let the next attempt genuinely re-run rather than replaying a failure.
    await ref.delete().catch(() => undefined);
    throw err;
  }

  // Past this point the operation HAS committed, so the key must never be
  // released — recording the result is bookkeeping and is allowed to fail.
  // Releasing it here would let a retry apply the same spend (or, for a
  // re-delivered purchase webhook, the same credit) a second time. A key stuck
  // on "pending" only costs the caller an "already being processed" error; a
  // released key costs real money.
  try {
    await ref.update({ status: "done", result });
  } catch (err) {
    logger.error("[once] Committed but failed to record result", { uid, key, err });
  }
  return result;
}

// Initialize at module scope and pass the app handle explicitly to each
// service. Relying on default-app lookup (getFirestore() with no args)
// failed in production with "The default Firebase app does not exist".
function ensureApp(): App {
  try {
    return initializeApp();
  } catch {
    return getApp();
  }
}
const app = ensureApp();
const db = getFirestore(app);
const messaging = getMessaging(app);
const auth = getAuth(app);

// data.type drives in-app routing on tap; category enables action buttons.
interface NotifyOptions {
  data?: Record<string, string>;
  category?: string;
}

/** Owner-only document holding a user's push token and pairing code. */
function privateDataRef(userId: string) {
  return db.collection("users").doc(userId).collection("private").doc("data");
}

/**
 * Resolve a push token from the private document, falling back to the legacy
 * field on the public user document for accounts that have not yet run the
 * client migration. The fallback can be deleted once backfillPrivateUserData
 * reports zero remaining legacy documents.
 */
async function fcmTokenFor(userId: string): Promise<string | undefined> {
  const priv = await privateDataRef(userId).get();
  const token = priv.data()?.fcmToken as string | undefined;
  if (token) return token;

  const legacy = await db.collection("users").doc(userId).get();
  return legacy.data()?.fcmToken as string | undefined;
}

/** Drop a token FCM has told us is permanently dead. */
async function clearDeadToken(userId: string): Promise<void> {
  await Promise.all([
    privateDataRef(userId).set({ fcmToken: FieldValue.delete() }, { merge: true }),
    db.collection("users").doc(userId)
      .update({ fcmToken: FieldValue.delete() })
      .catch(() => undefined), // legacy field may already be gone
  ]);
  logger.info(`[notifyUser] Cleared unregistered token for userId=${userId}`);
}

async function notifyUser(
  userId: string,
  title: string,
  body: string,
  options: NotifyOptions = {}
): Promise<void> {
  try {
    const fcmToken = await fcmTokenFor(userId);
    if (!fcmToken) {
      logger.warn(`[notifyUser] No FCM token for userId=${userId}`);
      return;
    }

    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data: options.data,
      apns: {
        headers: {
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            ...(options.category ? { category: options.category } : {}),
          },
        },
      },
    });
    logger.info(`[notifyUser] Successfully sent to userId=${userId}`);
  } catch (err) {
    // A token that FCM reports as unregistered will never work again — the
    // app was deleted or the token rotated. Left in place these accumulate
    // forever and every future send burns a wasted call.
    const code = (err as { errorInfo?: { code?: string }; code?: string })
      ?.errorInfo?.code ?? (err as { code?: string })?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      await clearDeadToken(userId).catch((e) =>
        logger.error(`[notifyUser] Token cleanup failed for ${userId}:`, e));
      return;
    }
    logger.error(`[notifyUser] Failed to notify userId=${userId}:`, err);
  }
}

async function notifyUsers(
  userIds: string[],
  title: string,
  body: string,
  options: NotifyOptions = {}
): Promise<void> {
  await Promise.all(
    [...new Set(userIds)].map((id) => notifyUser(id, title, body, options))
  );
}

async function displayName(userId: string): Promise<string> {
  const doc = await db.collection("users").doc(userId).get();
  return (doc.data()?.displayName as string | undefined) ?? "Someone";
}

// ─────────────────────────────────────────────────────────────
// 1. Doghouse events — "sent" and "released" notifications
// ─────────────────────────────────────────────────────────────
export const onDoghouseEvent = onDocumentWritten(
  { document: "doghouseEvents/{eventId}", region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!after) return;

    const receiverId: string = after.receiverId;
    const senderId: string = after.senderId;

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName: string =
      senderDoc.data()?.displayName ?? "Your partner";

    if (!before && after.isActive === true) {
      const reason: string = after.reason ?? "No reason given";
      await notifyUser(
        receiverId,
        "🐕 You've been sent to the DogHouse!",
        `${senderName}: "${reason}"`,
        { data: { type: "doghouse" } }
      );
      return;
    }

    // Redemption requested: the dog says they made it up — ask the sender
    if (
      before?.redemptionRequested !== true &&
      after.redemptionRequested === true &&
      after.isActive === true
    ) {
      const receiverName = await displayName(receiverId);
      const suggestion: string = after.suggestion ?? "made it up to you";
      await notifyUser(
        senderId,
        `🦴 ${receiverName} says they made it up!`,
        `"${suggestion}" — confirm to let them out`,
        { data: { type: "redemption" }, category: "REDEMPTION" }
      );
      return;
    }

    if (before?.isActive === true && after.isActive === false) {
      if (after.releasedBy === "vote") {
        await notifyUser(
          receiverId,
          "🗳️ The people have spoken!",
          "Your friends voted you out of the DogHouse. You're FREE! 🎉",
          { data: { type: "doghouse" } }
        );
      } else if (after.releasedBy === "redemption") {
        // The releasePartner callable already granted the treat reward +
        // immunity atomically; here we only notify.
        await notifyUser(
          receiverId,
          "🦴 Redemption complete!",
          `${senderName} confirmed you made it up. You're free + ${REDEMPTION_TREATS} treats! 🎉`,
          { data: { type: "doghouse" } }
        );
      } else {
        await notifyUser(
          receiverId,
          "🏠 You've been released!",
          `${senderName} let you out! Welcome home 🎉`,
          { data: { type: "doghouse" }, category: "RELEASED" }
        );
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 1b. Mutual pairing — clients can only write their OWN partnerId
//     (security rules). When user A sets partnerId=B, this trigger
//     completes the link by setting B.partnerId=A, so the partner
//     sitting on the "waiting" screen advances without entering a
//     code themselves. No loop: when B's doc updates, A already
//     points at B, so the trigger no-ops.
// ─────────────────────────────────────────────────────────────
export const onUserPaired = onDocumentUpdated(
  { document: "users/{uid}", region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const uid = event.params.uid;
    const newPartnerId = after.partnerId as string | undefined;
    if (!newPartnerId || newPartnerId === "skipped") return;
    if (before?.partnerId === newPartnerId) return; // not a new pairing

    const partnerRef = db.collection("users").doc(newPartnerId);
    const partnerSnap = await partnerRef.get();
    if (!partnerSnap.exists) return;
    const partnerCurrent = partnerSnap.data()?.partnerId as string | undefined;

    if (partnerCurrent === uid) return; // already mutual — nothing to do
    if (partnerCurrent && partnerCurrent !== "skipped") {
      // Partner is paired with someone else; don't steal them.
      logger.warn(`[pairing] ${uid} → ${newPartnerId}, but they're paired with ${partnerCurrent}`);
      return;
    }

    await partnerRef.update({ partnerId: uid });
    const myName = (after.displayName as string | undefined) ?? "Your partner";
    await notifyUser(
      newPartnerId,
      "❤️ You're paired!",
      `${myName} connected with you on DogHouse. Let the games begin!`,
      { data: { type: "doghouse" } }
    );
    logger.info(`[pairing] Completed mutual pairing ${uid} ↔ ${newPartnerId}`);
  }
);

// ─────────────────────────────────────────────────────────────
// 2. Belly rubs
// ─────────────────────────────────────────────────────────────
export const onBellyRub = onDocumentWritten(
  { document: "bellyRubs/{userId}", region: REGION },
  async (event) => {
    if (!event.data?.after.exists) return;

    const userId = event.params.userId;
    const data = event.data.after.data();
    if (!data) return;

    const fromName: string = data.fromDisplayName ?? "Your partner";
    await notifyUser(
      userId,
      "🐾 Belly rub!",
      `${fromName} gave you a belly rub ❤️`,
      { data: { type: "belly_rub" }, category: "BELLY_RUB" }
    );
  }
);

// ─────────────────────────────────────────────────────────────
// 3. Vote events — notify everyone who can vote when one starts
// ─────────────────────────────────────────────────────────────
export const onVoteEventCreated = onDocumentCreated(
  { document: "voteEvents/{voteId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== "active") return;

    // Joint doghouse votes carry their own audience and are announced
    // by onFeedPostCreated (richer message) — skip here.
    if (data.type === "joint_doghouse") return;

    const groupId: string | undefined = data.groupId;
    if (!groupId) return;
    const groupDoc = await db.collection("friendGroups").doc(groupId).get();
    const memberIds: string[] = groupDoc.data()?.memberIds ?? [];

    await notifyUsers(
      memberIds,
      "🗳️ Vote started in your squad!",
      "Who Let The Dogs Out? Tap to cast your vote!",
      { data: { type: "vote" } }
    );
  }
);

// (Individual friendships removed — couples befriend couples via the
//  addCoupleFriend / removeCoupleFriend callables further below.)

// ─────────────────────────────────────────────────────────────
// 5. Feed posts — notify friends of a public sending, and detect
//    the "two friends in the doghouse" jailbreak vote.
// ─────────────────────────────────────────────────────────────
export const onFeedPostCreated = onDocumentCreated(
  { document: "feedPosts/{postId}", region: REGION },
  async (event) => {
    const post = event.data?.data();
    if (!post || post.status !== "active") return;
    const postId = event.params.postId;

    const senderId: string = post.senderId;
    const receiverId: string = post.receiverId;
    const senderName: string = post.senderName ?? "Someone";
    const receiverName: string = post.receiverName ?? "their partner";
    const audienceIds: string[] = post.audienceIds ?? [];

    // Notify the audience (friends only — the couple already knows)
    const friendsToNotify = audienceIds.filter(
      (id) => id !== senderId && id !== receiverId
    );
    await notifyUsers(
      friendsToNotify,
      "📣 DogHouse news!",
      `${senderName} sent ${receiverName} to the DogHouse: "${post.reason}"`,
      { data: { type: "feed" } }
    );

    // ── Jailbreak vote detection ──
    // Is someone in a FRIENDED COUPLE also publicly in the doghouse?
    // The post's audience already spans the couple + friended couples, so
    // anyone in it besides this couple is a valid jailbreak partner.
    const jailbreakCandidates = new Set(
      audienceIds.filter((id) => id !== senderId && id !== receiverId)
    );
    if (jailbreakCandidates.size === 0) return;

    const activePosts = await db
      .collection("feedPosts")
      .where("status", "==", "active")
      .get();

    const otherPost = activePosts.docs.find(
      (d) =>
        d.id !== postId &&
        d.data().receiverId !== receiverId &&
        jailbreakCandidates.has(d.data().receiverId)
    );
    if (!otherPost) return;

    const other = otherPost.data();

    // Don't start a second vote if either dog is already in an active one
    const existingVotes = await db
      .collection("voteEvents")
      .where("status", "==", "active")
      .where("doghousedUserIds", "array-contains-any", [
        receiverId,
        other.receiverId,
      ])
      .get();
    if (!existingVotes.empty) return;

    const audience = [
      ...new Set([...audienceIds, ...(other.audienceIds ?? [])]),
    ];
    const dogs = [receiverId, other.receiverId as string];
    const dogNames: Record<string, string> = {
      [receiverId]: receiverName,
      [other.receiverId]: other.receiverName ?? "A friend",
    };

    const voteRef = db.collection("voteEvents").doc();
    const now = Timestamp.now();
    await voteRef.set({
      type: "joint_doghouse",
      doghousedUserIds: dogs,
      doghousedUserNames: dogNames,
      votes: {},
      startedAt: now,
      endsAt: Timestamp.fromMillis(now.toMillis() + 30 * 60 * 1000),
      winnerId: null,
      status: "active",
      audienceIds: audience,
      feedPostIds: [postId, otherPost.id],
    });

    const batch = db.batch();
    batch.update(event.data!.ref, { voteEventId: voteRef.id });
    batch.update(otherPost.ref, { voteEventId: voteRef.id });
    await batch.commit();

    await notifyUsers(
      audience,
      "🚨 Two dogs in the house!",
      `${dogNames[dogs[0]]} and ${dogNames[dogs[1]]} are BOTH in the DogHouse. Vote who goes free! 🗳️`,
      { data: { type: "vote", voteId: voteRef.id } }
    );
    logger.info(`[jailbreakVote] Created vote ${voteRef.id} for ${dogs.join(", ")}`);
  }
);

// ─────────────────────────────────────────────────────────────
// 6. Feed reactions — ❤️ backs the sender, 🐶 sides with the dog
// ─────────────────────────────────────────────────────────────
export const onFeedPostReaction = onDocumentUpdated(
  { document: "feedPosts/{postId}", region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeReactions: Record<string, string> = before.reactions ?? {};
    const afterReactions: Record<string, string> = after.reactions ?? {};

    for (const [uid, reaction] of Object.entries(afterReactions)) {
      if (beforeReactions[uid] === reaction) continue; // unchanged
      const reactorName = await displayName(uid);
      if (reaction === "back" && uid !== after.senderId) {
        await notifyUser(
          after.senderId,
          "❤️ Someone backs your call!",
          `${reactorName} supports sending ${after.receiverName} to the DogHouse`,
          { data: { type: "feed" } }
        );
      } else if (reaction === "dog" && uid !== after.receiverId) {
        await notifyUser(
          after.receiverId,
          "🐶 Someone's on your side!",
          `${reactorName} thinks you don't belong in the DogHouse`,
          { data: { type: "feed" } }
        );
      }
    }

    // Roasts — playful canned one-liners aimed at the dog
    const beforeRoasts: Record<string, string> = before.roasts ?? {};
    const afterRoasts: Record<string, string> = after.roasts ?? {};
    for (const [uid, roast] of Object.entries(afterRoasts)) {
      if (beforeRoasts[uid] === roast) continue;
      if (uid === after.receiverId) continue;
      const roasterName = await displayName(uid);
      await notifyUser(
        after.receiverId,
        `🔥 ${roasterName} roasted you`,
        `"${roast}"`,
        { data: { type: "feed" } }
      );
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 7. Vote resolution — runs every minute; releases the winner.
//    Server-side so no client races and no client can cheat.
// ─────────────────────────────────────────────────────────────
export const resolveExpiredVotes = onSchedule(
  { schedule: "every 1 minutes", region: REGION },
  async () => {
    const now = Timestamp.now();
    const active = await db
      .collection("voteEvents")
      .where("status", "==", "active")
      .get();

    for (const voteDoc of active.docs) {
      const vote = voteDoc.data();
      const endsAt = vote.endsAt as Timestamp | undefined;
      if (!endsAt || endsAt.toMillis() > now.toMillis()) continue;

      // Tally
      const counts: Record<string, number> = {};
      for (const votedForId of Object.values(vote.votes ?? {})) {
        counts[votedForId as string] = (counts[votedForId as string] ?? 0) + 1;
      }
      const maxVotes = Math.max(0, ...Object.values(counts));
      const winners =
        maxVotes > 0
          ? Object.keys(counts).filter((id) => counts[id] === maxVotes)
          : [];

      // Release every winner's active doghouse event (tie → both go free)
      const releasedNames: string[] = [];
      const overruledSenderIds: string[] = [];
      for (const winnerId of winners) {
        const events = await db
          .collection("doghouseEvents")
          .where("receiverId", "==", winnerId)
          .where("isActive", "==", true)
          .get();
        for (const ev of events.docs) {
          await ev.ref.update({
            isActive: false,
            endedAt: now,
            releasedBy: "vote",
          });
          overruledSenderIds.push(ev.data().senderId as string);
        }
        // Grant the freed dog immunity (clients can no longer self-write it)
        await db.collection("users").doc(winnerId).update({
          immunityUntil: Timestamp.fromMillis(now.toMillis() + IMMUNITY_SECONDS * 1000),
        });
        const posts = await db
          .collection("feedPosts")
          .where("voteEventId", "==", voteDoc.id)
          .where("receiverId", "==", winnerId)
          .get();
        for (const p of posts.docs) {
          await p.ref.update({
            status: "released",
            endedAt: now,
            releasedByVote: true,
          });
        }
        releasedNames.push(
          (vote.doghousedUserNames?.[winnerId] as string | undefined) ??
            (await displayName(winnerId))
        );
      }

      await voteDoc.ref.update({
        status: "completed",
        winnerId: winners.length === 1 ? winners[0] : null,
        winnerIds: winners,
      });

      // Announce the outcome
      let audience: string[] = vote.audienceIds ?? [];
      if (audience.length === 0 && vote.groupId) {
        const groupDoc = await db
          .collection("friendGroups")
          .doc(vote.groupId)
          .get();
        audience = groupDoc.data()?.memberIds ?? [];
      }
      // Winners get their own richer push from onDoghouseEvent, and the
      // senders whose dogs were freed get the anthem instead.
      audience = audience.filter(
        (id) => !winners.includes(id) && !overruledSenderIds.includes(id)
      );

      // The sender whose dog the crowd freed gets the classic
      await notifyUsers(
        overruledSenderIds,
        "🎶 Who?! Who?! Who?! Who?!",
        `WHO LET THE DOGS OUT?! Your friends did — ${releasedNames.join(" and ")} walked free! 🐕🎉`,
        { data: { type: "doghouse" } }
      );

      if (winners.length === 0) {
        await notifyUsers(
          audience,
          "🗳️ The vote is over",
          "No votes were cast... nobody goes free 😬",
          { data: { type: "feed" } }
        );
      } else if (winners.length === 1) {
        await notifyUsers(
          audience,
          "🗳️ The people have spoken!",
          `${releasedNames[0]} has been voted out of the DogHouse! 🎉`,
          { data: { type: "feed" } }
        );
      } else {
        await notifyUsers(
          audience,
          "🤝 It's a tie!",
          `${releasedNames.join(" and ")} both go free! JAILBREAK! 🎉`,
          { data: { type: "feed" } }
        );
      }
      logger.info(
        `[resolveVotes] Resolved ${voteDoc.id}: winners=${winners.join(",") || "none"}`
      );
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 7b. Feedback → email. The Input tab writes feedback/{id}; this
//     emails it to the developer via Gmail. Requires the
//     GMAIL_APP_PASSWORD secret (a Google "app password" for the
//     developer's account). The Firestore doc is the source of
//     truth — if email fails, the feedback is still saved.
// ─────────────────────────────────────────────────────────────
const FEEDBACK_EMAIL = "harrisonkennykrampe@gmail.com";
const gmailAppPassword = defineSecret("GMAIL_APP_PASSWORD");

export const onFeedbackCreated = onDocumentCreated(
  { document: "feedback/{feedbackId}", region: REGION, secrets: [gmailAppPassword] },
  async (event) => {
    const fb = event.data?.data();
    if (!fb) return;

    const kind: string = fb.type ?? "feedback";
    const fromName: string = fb.fromName ?? "Unknown";
    const text: string = fb.text ?? "";

    try {
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: { user: FEEDBACK_EMAIL, pass: gmailAppPassword.value() },
      });
      await transporter.sendMail({
        from: `"DogHouse App" <${FEEDBACK_EMAIL}>`,
        to: FEEDBACK_EMAIL,
        subject: `[DogHouse ${kind}] from ${fromName}`,
        text: `${text}\n\n— ${fromName} (uid: ${fb.fromUserId ?? "?"})`,
      });
      logger.info(`[feedback] Emailed ${kind} from ${fromName}`);
    } catch (err) {
      logger.error("[feedback] Email failed (doc is still in Firestore):", err);
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 8. Account deletion — client writes deletionRequests/{uid};
//    this function wipes all their data and the Auth account.
// ─────────────────────────────────────────────────────────────
export const onDeletionRequest = onDocumentCreated(
  { document: "deletionRequests/{uid}", region: REGION },
  async (event) => {
    const uid = event.params.uid;
    logger.info(`[deleteAccount] Processing deletion for ${uid}`);

    async function deleteWhere(
      collection: string,
      field: string,
      value: string
    ): Promise<void> {
      const snap = await db.collection(collection).where(field, "==", value).get();
      await Promise.all(snap.docs.map((d) => d.ref.delete()));
    }

    try {
      // Unlink partner (only if still pointing at this user)
      const userDoc = await db.collection("users").doc(uid).get();
      const partnerId = userDoc.data()?.partnerId as string | undefined;
      if (partnerId && partnerId !== "skipped") {
        const partnerDoc = await db.collection("users").doc(partnerId).get();
        if (partnerDoc.data()?.partnerId === uid) {
          await partnerDoc.ref.update({ partnerId: null });
          await notifyUser(
            partnerId,
            "💔 Your partner left DogHouse",
            "Their account was deleted. You can pair with a new partner anytime."
          );
        }
      }

      // Remove couple friendships this user was part of (deleting one
      // member dissolves the couple, so the link goes too)
      const coupleLinks = await db
        .collection("coupleFriendships")
        .where("memberIds", "array-contains", uid)
        .get();
      await Promise.all(coupleLinks.docs.map((d) => d.ref.delete()));

      async function deleteArrayContains(
        collection: string,
        field: string,
        value: string
      ): Promise<void> {
        const snap = await db.collection(collection)
          .where(field, "array-contains", value).get();
        await Promise.all(snap.docs.map((d) => d.ref.delete()));
      }

      // Delete owned/related documents
      await deleteWhere("partnerCodes", "userId", uid);
      await deleteWhere("feedPosts", "senderId", uid);
      await deleteWhere("feedPosts", "receiverId", uid);
      await deleteWhere("doghouseEvents", "senderId", uid);
      await deleteWhere("doghouseEvents", "receiverId", uid);
      await deleteWhere("wishes", "fromUserId", uid);
      await deleteWhere("wishes", "toUserId", uid);
      await deleteWhere("feedback", "fromUserId", uid);
      await deleteArrayContains("challenges", "participants", uid);
      await deleteArrayContains("voteEvents", "audienceIds", uid);
      await db.collection("bellyRubs").doc(uid).delete();
      await db.collection("roses").doc(uid).delete();

      // Couple-scoped documents are keyed by the sorted uid pair, so they
      // are only reachable while we still know who the partner was.
      if (partnerId && partnerId !== "skipped") {
        const key = coupleKeyOf(uid, partnerId);
        await Promise.all([
          db.collection("coupleTasks").doc(key).delete(),
          db.collection("coupleMeta").doc(key).delete(),
          db.collection("onboardingTasks").doc(key).delete(),
        ]);
      }

      // Subcollections are NOT removed when the parent document is deleted.
      // Without this the owner-only private document — pairing code and push
      // token — would outlive the account it belongs to.
      const privateDocs = await db.collection("users").doc(uid)
        .collection("private").listDocuments();
      await Promise.all(privateDocs.map((d) => d.delete()));

      await db.collection("users").doc(uid).delete();

      // Delete the Firebase Auth account
      try {
        await auth.deleteUser(uid);
      } catch (err) {
        logger.warn(`[deleteAccount] Auth user already gone for ${uid}:`, err);
      }

      // Clean up the request marker itself
      await event.data?.ref.delete();
      logger.info(`[deleteAccount] Completed deletion for ${uid}`);
    } catch (err) {
      logger.error(`[deleteAccount] Failed for ${uid}:`, err);
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 9. Challenges — quiz resolution + "Whatever I Want" card awards
// ─────────────────────────────────────────────────────────────
export const onChallengeWritten = onDocumentWritten(
  { document: "challenges/{challengeId}", region: REGION },
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    const ref = event.data!.after.ref;
    const participants: string[] = after.participants ?? [];

    // Quiz: resolve once both partners have answered. Quizzes have no
    // winner — the fun is finding out whether the answers match.
    if (
      after.type === "quiz" &&
      after.status === "active" &&
      participants.length === 2 &&
      participants.every((uid) => after.answers?.[uid]?.own)
    ) {
      const [a, b] = participants;
      const aOwn: string = after.answers[a].own;
      const bOwn: string = after.answers[b].own;
      await ref.update({
        status: "completed",
        winnerId: null,
        completedAt: Timestamp.now(),
      });
      const result =
        aOwn === bOwn
          ? `You both picked "${aOwn}" — a perfect match! 💞`
          : "You picked different answers... time to compare notes 😅";
      await notifyUsers(participants, "🧠 Quiz over!", result, {
        data: { type: "challenge" },
      });
      return;
    }

    // Award: any completed challenge with a winner grants one card (once)
    if (after.status === "completed" && after.winnerId && after.cardAwarded !== true) {
      const winnerId: string = after.winnerId;
      const loserId = participants.find((p) => p !== winnerId);
      await ref.update({ cardAwarded: true });
      await db.collection("users").doc(winnerId).update({
        wishCards: FieldValue.increment(1),
      });

      const winnerName = await displayName(winnerId);
      const flavor: Record<string, [string, string]> = {
        quiz: ["🧠 You know them best!", "knew you better than you knew them"],
        photo: ["📸 Photo Dash won!", "was faster on the draw"],
        anniversary: ["💍 Anniversary race won!", "wished it first this year"],
      };
      const [winTitle, loseVerb] = flavor[after.type as string] ?? ["🏆 Challenge won!", "won"];

      await notifyUser(
        winnerId,
        winTitle,
        "You earned a Whatever-I-Want card 🎟️ Redeem it wisely...",
        { data: { type: "challenge" } }
      );
      if (loserId) {
        await notifyUser(
          loserId,
          after.type === "anniversary"
            ? `💍 ${winnerName} beat you to it!`
            : "😬 You lost this one...",
          `${winnerName} ${loseVerb} and now holds a Whatever-I-Want card over you.`,
          { data: { type: "challenge" } }
        );
      }
      logger.info(`[challenge] ${after.type} won by ${winnerId}, card awarded`);
    }
  }
);

// ─────────────────────────────────────────────────────────────
// 10. Wish redeemed — deliver the "Whatever I Want" demand
// ─────────────────────────────────────────────────────────────
export const onWishCreated = onDocumentCreated(
  { document: "wishes/{wishId}", region: REGION },
  async (event) => {
    const wish = event.data?.data();
    if (!wish) return;
    await notifyUser(
      wish.toUserId,
      `🎟️ ${wish.fromName ?? "Your partner"} redeemed their card!`,
      `"${wish.text}" — a card's a card. No take-backs.`,
      { data: { type: "challenge" } }
    );
  }
);

// ─────────────────────────────────────────────────────────────
// 11. Anniversary morning reminder — kicks off the race
// ─────────────────────────────────────────────────────────────
export const dailyAnniversaryCheck = onSchedule(
  { schedule: "every day 09:00", timeZone: "Europe/Berlin", region: REGION },
  async () => {
    const metas = await db.collection("coupleMeta").get();
    const today = new Date();
    for (const doc of metas.docs) {
      const anniversary = (doc.data().anniversary as Timestamp | undefined)?.toDate();
      const userIds: string[] = doc.data().userIds ?? [];
      if (!anniversary || userIds.length !== 2) continue;
      if (
        anniversary.getMonth() === today.getMonth() &&
        anniversary.getDate() === today.getDate()
      ) {
        await notifyUsers(
          userIds,
          "💍 It's your anniversary!",
          "First one to wish a happy anniversary in the app wins a Whatever-I-Want card. GO!",
          { data: { type: "challenge" } }
        );
        logger.info(`[anniversary] Race day for couple ${doc.id}`);
      }
    }
  }
);

// ═════════════════════════════════════════════════════════════
// CALLABLE FUNCTIONS — the only path allowed to touch protected
// economy fields (treats, graceCharges, immunityUntil, wishCards,
// ownedItemIds). Security rules make those read-only to clients.
// ═════════════════════════════════════════════════════════════

/** Union of all uids in the caller's own couple + friended couples. */
async function audienceForCouple(uid: string, partnerId: string): Promise<string[]> {
  const key = coupleKeyOf(uid, partnerId);
  const ids = new Set<string>([uid, partnerId]);
  const friends = await db
    .collection("coupleFriendships")
    .where("coupleKeys", "array-contains", key)
    .get();
  friends.forEach((d) => (d.data().memberIds ?? []).forEach((m: string) => ids.add(m)));
  return [...ids];
}

// Send partner to the doghouse — validates immunity + grace server-side.
export const sendToDoghouse = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const reason: string = (req.data?.reason ?? "").toString().slice(0, 500);
    const suggestion: string | null = req.data?.suggestion
      ? req.data.suggestion.toString().slice(0, 500) : null;
    const isPublic = req.data?.isPublic === true;
    if (!reason) throw new HttpsError("invalid-argument", "A reason is required.");

    const meRef = db.collection("users").doc(uid);
    const partnerId: string | undefined = (await meRef.get()).data()?.partnerId;
    if (!partnerId || partnerId === "skipped") {
      throw new HttpsError("failed-precondition", "You have no partner.");
    }
    const partnerRef = db.collection("users").doc(partnerId);

    // The friend audience is not part of the race, so it is resolved before the
    // transaction — queries inside a transaction would be re-run on every retry.
    const audience = isPublic ? await audienceForCouple(uid, partnerId) : [];

    // Grace is checked and spent inside a transaction. Previously this read the
    // balance, then wrote `effective - 1` as an absolute value from that stale
    // read: two sends fired close together both computed the same figure and
    // both wrote it, so the second sending was free.
    const key = coupleKeyOf(uid, partnerId);
    const eventRef = db.collection("doghouseEvents").doc();

    const graceRemaining = await db.runTransaction(async (tx) => {
      const [meSnap, partnerSnap] = await Promise.all([
        tx.get(meRef),
        tx.get(partnerRef),
      ]);
      const me = meSnap.data() ?? {};
      const partner = partnerSnap.data() ?? {};

      const immunity = partner.immunityUntil as Timestamp | undefined;
      if (immunity && immunity.toMillis() > Date.now()) {
        throw new HttpsError("failed-precondition",
          "Your partner has immunity! They can't be sent yet.");
      }

      const stored = (me.graceCharges as number | undefined) ?? MAX_GRACE_CHARGES;
      const effective = effectiveGraceCharges(
        stored, me.lastGraceRecharge as Timestamp | undefined);
      if (effective <= 0) {
        throw new HttpsError("resource-exhausted",
          "You're out of grace! Wait for it to recharge (1 per day).");
      }

      const now = Timestamp.now();
      tx.set(eventRef, {
        senderId: uid, receiverId: partnerId, reason, suggestion,
        startedAt: now, endedAt: null, isActive: true, coupleKey: key,
      });
      tx.update(meRef, {
        graceCharges: effective - 1,
        lastGraceRecharge: now,
      });

      if (isPublic) {
        tx.set(db.collection("feedPosts").doc(), {
          eventId: eventRef.id, senderId: uid, receiverId: partnerId,
          senderName: me.displayName ?? "Someone",
          receiverName: partner.displayName ?? "their partner",
          senderAvatarId: me.avatarId ?? "dog_1",
          receiverAvatarId: partner.avatarId ?? "dog_1",
          reason, createdAt: now, status: "active", audienceIds: audience,
          reactions: {}, coupleKey: key,
        });
      }
      return effective - 1;
    });

    return { ok: true, graceRemaining };
  });
});

// Release partner (or confirm redemption) — grants immunity + reward server-side.
export const releasePartner = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const eventId: string = req.data?.eventId;
    const byRedemption = req.data?.byRedemption === true;
    if (!eventId) throw new HttpsError("invalid-argument", "Missing eventId.");

    const ref = db.collection("doghouseEvents").doc(eventId);

    // Transactional so the isActive check and the release cannot interleave:
    // two concurrent releases previously both saw an active event and both
    // credited REDEMPTION_TREATS.
    const now = Timestamp.now();
    const alreadyReleased = await db.runTransaction(async (tx) => {
      const ev = (await tx.get(ref)).data();
      if (!ev || ev.senderId !== uid) {
        throw new HttpsError("permission-denied", "Only the sender can release.");
      }
      if (ev.isActive !== true) return true;

      tx.update(ref, {
        isActive: false, endedAt: now,
        releasedBy: byRedemption ? "redemption" : "sender",
      });
      // Grant the released dog immunity (was previously a client self-write).
      // Both partners' treat clocks restart now: claimHomeTreats pays for
      // every hour since lastTreatAward, and without this reset the hours one
      // of them spent in the doghouse would be paid out at release.
      tx.update(db.collection("users").doc(ev.receiverId as string), {
        immunityUntil: Timestamp.fromMillis(now.toMillis() + IMMUNITY_SECONDS * 1000),
        lastTreatAward: now,
        ...(byRedemption ? { treats: FieldValue.increment(REDEMPTION_TREATS) } : {}),
      });
      tx.update(db.collection("users").doc(uid), { lastTreatAward: now });
      return false;
    });

    if (alreadyReleased) return { ok: true };

    // Close any public feed post for this sending
    const posts = await db.collection("feedPosts")
      .where("eventId", "==", eventId).where("status", "==", "active").get();
    await Promise.all(posts.docs.map((p) =>
      p.ref.update({ status: "released", endedAt: now })));
    return { ok: true };
  });
});

// Request redemption — the dog flags they made it up (only their own event).
export const requestRedemption = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const eventId: string = req.data?.eventId;
  if (!eventId) throw new HttpsError("invalid-argument", "Missing eventId.");
  const ref = db.collection("doghouseEvents").doc(eventId);
  const ev = (await ref.get()).data();
  if (!ev || ev.receiverId !== uid || ev.isActive !== true) {
    throw new HttpsError("permission-denied", "Not your active doghouse event.");
  }
  await ref.update({ redemptionRequested: true });
  return { ok: true };
});

// Send roses to the partner — costs treats, so it must run server-side.
// Works like a belly rub: writes roses/{partnerId} (the partner's client
// listens on that doc for the in-app burst) and sends a push.
export const sendRoses = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const meRef = db.collection("users").doc(uid);

    // Balance check and debit must be atomic: reading treats and then writing
    // increment(-cost) outside a transaction let two rapid taps both pass the
    // affordability check and drive the balance negative.
    const { partnerId, fromName, treatsRemaining } = await db.runTransaction(
      async (tx) => {
        const me = (await tx.get(meRef)).data() ?? {};
        const pid = me.partnerId as string | undefined;
        if (!pid || pid === "skipped") {
          throw new HttpsError("failed-precondition", "You have no partner.");
        }

        const treats = (me.treats as number | undefined) ?? 100;
        if (treats < ROSES_COST) {
          throw new HttpsError("failed-precondition",
            `Roses cost ${ROSES_COST} treats — you only have ${treats} 🦴`);
        }

        const name = (me.displayName as string | undefined) ?? "Your partner";
        tx.update(meRef, { treats: FieldValue.increment(-ROSES_COST) });
        tx.set(db.collection("roses").doc(pid), {
          fromUserId: uid,
          fromDisplayName: name,
          sentAt: Timestamp.now(),
        });
        return { partnerId: pid, fromName: name, treatsRemaining: treats - ROSES_COST };
      }
    );

    await notifyUser(
      partnerId,
      "🌹 Roses for you!",
      `${fromName} sent you roses ❤️`,
      { data: { type: "roses" } }
    );
    return { ok: true, treatsRemaining };
  });
});

// Purchase a cosmetic — for self or as a gift to the partner.
export const purchaseCosmetic = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const itemId: string = req.data?.itemId;
    const forPartner = req.data?.forPartner === true;
    const price = COSMETIC_PRICES[itemId];
    if (price === undefined) throw new HttpsError("invalid-argument", "Unknown item.");

    const meRef = db.collection("users").doc(uid);

    // Atomic so a double-tap cannot buy two items for the price of one.
    const { targetId, buyerName, treatsRemaining } = await db.runTransaction(
      async (tx) => {
        const me = (await tx.get(meRef)).data() ?? {};
        const treats = (me.treats as number | undefined) ?? 100;
        if (treats < price) {
          throw new HttpsError("failed-precondition", "Not enough treats! Keep playing 🦴");
        }

        let target = uid;
        if (forPartner) {
          const partnerId = me.partnerId as string | undefined;
          if (!partnerId || partnerId === "skipped") {
            throw new HttpsError("failed-precondition", "You have no partner to gift to.");
          }
          target = partnerId;
        }

        tx.update(meRef, { treats: FieldValue.increment(-price) });
        tx.update(db.collection("users").doc(target), {
          ownedItemIds: FieldValue.arrayUnion(itemId),
        });
        return {
          targetId: target,
          buyerName: (me.displayName as string | undefined) ?? "Your partner",
          treatsRemaining: treats - price,
        };
      }
    );

    if (forPartner) {
      await notifyUser(targetId, "🎁 A gift!",
        `${buyerName} bought you something for your dog. Go check the shop!`,
        { data: { type: "shop" } });
    }
    return { ok: true, treatsRemaining };
  });
});

// Equip / unequip a cosmetic on self or partner (validates ownership).
export const equipCosmetic = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const itemId: string | null = req.data?.itemId ?? null; // null = unequip
  const category: string = req.data?.category;
  const forPartner = req.data?.forPartner === true;
  if (!category) throw new HttpsError("invalid-argument", "Missing category.");

  const me = (await db.collection("users").doc(uid).get()).data() ?? {};
  let targetId = uid;
  if (forPartner) {
    const partnerId = me.partnerId as string | undefined;
    if (!partnerId || partnerId === "skipped") {
      throw new HttpsError("failed-precondition", "You have no partner.");
    }
    targetId = partnerId;
  }

  const targetRef = db.collection("users").doc(targetId);
  if (itemId) {
    if (categoryOf(itemId) !== category) {
      throw new HttpsError("invalid-argument", "Item/category mismatch.");
    }
    const owned: string[] = (await targetRef.get()).data()?.ownedItemIds ?? [];
    if (!owned.includes(itemId)) {
      throw new HttpsError("failed-precondition", "That dog doesn't own this item.");
    }
    await targetRef.update({ [`equippedItemIds.${category}`]: itemId });
  } else {
    await targetRef.update({ [`equippedItemIds.${category}`]: FieldValue.delete() });
  }
  return { ok: true };
});

// Award treats for time spent at home — server computes from event history.
export const claimHomeTreats = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const meRef = db.collection("users").doc(uid);

    // Guard: no award while EITHER partner is in the doghouse. Treats are the
    // couple's reward for both behaving, not one partner's idle income while
    // the other sits in the rain. Racing this guard is harmless (worst case
    // one extra idle award), so it stays outside the transaction.
    const inDoghouse = async (id: string) =>
      !(await db.collection("doghouseEvents")
        .where("receiverId", "==", id).where("isActive", "==", true).limit(1).get()).empty;
    if (await inDoghouse(uid)) return { ok: true, awarded: 0 };
    const partnerId = (await meRef.get()).data()?.partnerId as string | undefined;
    if (partnerId && partnerId !== "skipped" && await inDoghouse(partnerId)) {
      return { ok: true, awarded: 0 };
    }

    // Rate scales with room level (time since last release), matching the client.
    const rate = Math.max(1, Math.min(5, Number(req.data?.treatsPerHour ?? 1)));

    // The elapsed-hours read and the lastTreatAward write must be atomic, or two
    // concurrent claims each award the same accrued hours.
    const awarded = await db.runTransaction(async (tx) => {
      const me = (await tx.get(meRef)).data() ?? {};
      const last = me.lastTreatAward as Timestamp | undefined;
      const sinceMs = last ? last.toMillis() : Date.now() - 3_600_000;
      const hours = Math.floor((Date.now() - sinceMs) / 3_600_000);
      if (hours < 1) return 0;

      const amount = hours * rate;
      tx.update(meRef, {
        treats: FieldValue.increment(amount),
        lastTreatAward: Timestamp.now(),
      });
      return amount;
    });

    return { ok: true, awarded };
  });
});

// Redeem a "Whatever I Want" card — server checks and decrements the balance.
export const redeemWishCard = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const text: string = (req.data?.text ?? "").toString().slice(0, 300);
    if (!text) throw new HttpsError("invalid-argument", "Say what you want!");

    const meRef = db.collection("users").doc(uid);

    // Atomic: a card must be spendable exactly once.
    const cardsRemaining = await db.runTransaction(async (tx) => {
      const me = (await tx.get(meRef)).data() ?? {};
      const cards = (me.wishCards as number | undefined) ?? 0;
      const partnerId = me.partnerId as string | undefined;
      if (cards <= 0) throw new HttpsError("failed-precondition", "You have no cards to redeem.");
      if (!partnerId || partnerId === "skipped") {
        throw new HttpsError("failed-precondition", "You have no partner.");
      }

      tx.set(db.collection("wishes").doc(), {
        fromUserId: uid, toUserId: partnerId,
        fromName: me.displayName ?? "Your partner", text, createdAt: Timestamp.now(),
      });
      tx.update(meRef, { wishCards: FieldValue.increment(-1) });
      return cards - 1;
    });

    return { ok: true, cardsRemaining };
  });
});

// ─────────────────────────────────────────────────────────────
// 12. Random photo dash — the app itself starts these at random
//     intervals through the WEEK (not daily). The scheduler ticks
//     hourly during waking hours; each couple has a small chance
//     per tick plus a 48h cooldown, which averages out to ~2
//     dashes per week at unpredictable days and times.
//     First partner to send a photo wins a Whatever-I-Want card.
// ─────────────────────────────────────────────────────────────
const PHOTO_DASH_CHANCE = 0.03; // per hourly tick
const PHOTO_DASH_COOLDOWN_MS = 48 * 3_600_000;
const PHOTO_DASH_PROMPTS = [
  "First to send a selfie wins! 🤳",
  "First to send a pic of what you're doing right now 📸",
  "First to send a photo of something that reminds you of them ❤️",
  "First to send your best silly face 🤪",
  "First to send the view from where you are 🪟",
];

export const randomPhotoDash = onSchedule(
  { schedule: "0 9-21 * * *", timeZone: "Europe/Berlin", region: REGION },
  async () => {
    // Gather paired users, dedupe into couples by coupleKey
    const paired = await db.collection("users")
      .where("partnerId", "!=", "skipped").get();
    const couples = new Map<string, [string, string]>();
    paired.forEach((doc) => {
      const uid = doc.id;
      const partnerId = doc.data().partnerId as string | undefined;
      if (!partnerId || partnerId === "skipped") return;
      couples.set(coupleKeyOf(uid, partnerId), [uid, partnerId]);
    });

    const now = Date.now();
    for (const [key, [a, b]] of couples) {
      // Small chance per hourly tick → a couple of dashes per week,
      // landing on random days and hours rather than daily.
      if (Math.random() > PHOTO_DASH_CHANCE) continue;

      // Cooldown: no new dash within 48h of the couple's last one,
      // and never stack with one that's still active. (Equality-only
      // query — no composite index needed; couples have few dashes.)
      const previous = await db.collection("challenges")
        .where("coupleKey", "==", key).where("type", "==", "photo")
        .get();
      const blocked = previous.docs.some((d) => {
        const data = d.data();
        if (data.status === "active") return true;
        const createdAt = data.createdAt as Timestamp | undefined;
        return createdAt !== undefined &&
          now - createdAt.toMillis() < PHOTO_DASH_COOLDOWN_MS;
      });
      if (blocked) continue;

      const prompt = PHOTO_DASH_PROMPTS[Math.floor(Math.random() * PHOTO_DASH_PROMPTS.length)];
      await db.collection("challenges").doc().set({
        coupleKey: key, type: "photo", title: "Photo Dash", prompt,
        createdBy: "system", participants: [a, b], status: "active",
        createdAt: Timestamp.now(),
      });
      await notifyUsers([a, b], "📸 Photo Dash!",
        `${prompt} First one to send wins a card 🎟️`,
        { data: { type: "challenge" } });
      logger.info(`[photoDash] Started for couple ${key}`);
    }
  }
);

// ═════════════════════════════════════════════════════════════
// COUPLE FRIENDSHIPS — couples befriend other couples by code.
// A couple is identified by its coupleKey (sorted uids). Adding by
// code links all four people; the feed audience (audienceForCouple)
// already spans coupleFriendships.
// ═════════════════════════════════════════════════════════════

function friendshipIdFor(k1: string, k2: string): string {
  return [k1, k2].sort().join("__");
}

export const addCoupleFriend = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const code: string = (req.data?.code ?? "").toString().toUpperCase();
  if (!code) throw new HttpsError("invalid-argument", "Enter a couple code.");

  const me = (await db.collection("users").doc(uid).get()).data();
  const myPartner: string | undefined = me?.partnerId;
  if (!myPartner || myPartner === "skipped") {
    throw new HttpsError("failed-precondition", "Pair with your partner first.");
  }

  // Resolve the code → a user, then their partner
  const codeDoc = await db.collection("partnerCodes").doc(code).get();
  const themId = codeDoc.data()?.userId as string | undefined;
  if (!themId) throw new HttpsError("not-found", "No couple found with that code.");
  const them = (await db.collection("users").doc(themId).get()).data();
  const themPartner: string | undefined = them?.partnerId;
  if (!themPartner || themPartner === "skipped") {
    throw new HttpsError("failed-precondition", "That user isn't paired yet.");
  }

  const myKey = coupleKeyOf(uid, myPartner);
  const themKey = coupleKeyOf(themId, themPartner);
  if (myKey === themKey) {
    throw new HttpsError("invalid-argument", "That's your own couple!");
  }

  const docId = friendshipIdFor(myKey, themKey);
  await db.collection("coupleFriendships").doc(docId).set({
    coupleKeys: [myKey, themKey],
    memberIds: [uid, myPartner, themId, themPartner],
    createdAt: Timestamp.now(),
  });

  const myName = me?.displayName ?? "A couple";
  await notifyUsers([themId, themPartner], "💞 New couple friend!",
    `${myName}'s couple added yours on DogHouse`, { data: { type: "friends" } });
  return { ok: true };
});

export const removeCoupleFriend = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const otherKey: string = req.data?.coupleKey;
  if (!otherKey) throw new HttpsError("invalid-argument", "Missing couple.");
  const me = (await db.collection("users").doc(uid).get()).data();
  const myPartner: string | undefined = me?.partnerId;
  if (!myPartner) throw new HttpsError("failed-precondition", "No partner.");
  const myKey = coupleKeyOf(uid, myPartner);
  const docId = friendshipIdFor(myKey, otherKey);
  const snap = await db.collection("coupleFriendships").doc(docId).get();
  if (snap.exists && (snap.data()?.memberIds ?? []).includes(uid)) {
    await snap.ref.delete();
  }
  return { ok: true };
});

// ─────────────────────────────────────────────────────────────
// Backfill: relocate legacy secrets off the public user document.
//
// fcmToken and partnerCode used to live on /users/{uid}, which every signed-in
// account could read. The client migrates its own document on next launch
// (AuthService.migrateLegacyPrivateFields); this sweep covers accounts that
// never open the app again.
//
// Safe to delete — along with the legacy fallback in fcmTokenFor — once this
// logs "0 remaining" on a run.
// ─────────────────────────────────────────────────────────────
export const backfillPrivateUserData = onSchedule(
  { schedule: "0 4 * * *", timeZone: "Europe/Berlin", region: REGION },
  async () => {
    const BATCH = 200;
    let migrated = 0;

    for (const field of ["partnerCode", "fcmToken"]) {
      const snap = await db
        .collection("users")
        .orderBy(field)
        .limit(BATCH)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const priv: Record<string, unknown> = {};
        if (data.partnerCode) priv.partnerCode = data.partnerCode;
        if (data.fcmToken) priv.fcmToken = data.fcmToken;
        if (Object.keys(priv).length === 0) continue;

        try {
          await privateDataRef(doc.id).set(priv, { merge: true });
          await doc.ref.update({
            partnerCode: FieldValue.delete(),
            fcmToken: FieldValue.delete(),
          });
          migrated += 1;
        } catch (err) {
          logger.error(`[backfill] Failed for ${doc.id}:`, err);
        }
      }
    }

    // orderBy(field) only returns documents where the field exists, so an
    // empty result means the migration is complete.
    const remaining = (await db.collection("users")
      .orderBy("partnerCode").limit(1).get()).size
      + (await db.collection("users").orderBy("fcmToken").limit(1).get()).size;
    logger.info(`[backfill] Migrated ${migrated} document(s), ${remaining} remaining`);
  }
);

// ─────────────────────────────────────────────────────────────
// Prune idempotency keys. A key only needs to outlive the client's retry
// window (seconds); a day of history is generous and keeps the collection
// from growing without bound. No security rule grants clients access to
// this collection — the default deny applies.
// ─────────────────────────────────────────────────────────────
export const cleanupIdempotencyKeys = onSchedule(
  { schedule: "30 3 * * *", timeZone: "Europe/Berlin", region: REGION },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 24 * 3_600_000);
    const purchaseCutoff = Timestamp.fromMillis(
      Date.now() - PURCHASE_KEY_RETENTION_DAYS * 24 * 3_600_000);
    let deleted = 0;
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    // Bounded per run so one invocation cannot blow the memory limit. The
    // cursor matters: retained purchase keys are skipped rather than deleted,
    // and without startAfter the same ones would refill every page and stall
    // the sweep before it reached anything else.
    for (let i = 0; i < 10; i++) {
      let q = db.collection("idempotencyKeys")
        .where("createdAt", "<", cutoff)
        .orderBy("createdAt")
        .limit(500);
      if (cursor) q = q.startAfter(cursor);

      const snap = await q.get();
      if (snap.empty) break;
      cursor = snap.docs[snap.docs.length - 1];

      const batch = db.batch();
      let batched = 0;
      snap.docs.forEach((d) => {
        // A purchase key is the ONLY thing stopping a re-delivered RevenueCat
        // webhook from crediting the same transaction twice, and manual
        // re-delivery from their dashboard has no time bound. 24h is plenty
        // for a callable retry but far too short here — do not collapse these
        // two cutoffs back into one.
        if (d.get("kind") === "purchase") {
          const created = d.get("createdAt") as Timestamp | undefined;
          if (!created || created.toMillis() >= purchaseCutoff.toMillis()) return;
        }
        batch.delete(d.ref);
        batched++;
      });

      if (batched > 0) {
        await batch.commit();
        deleted += batched;
      }
      if (snap.size < 500) break;
    }
    logger.info(`[cleanupIdempotencyKeys] Deleted ${deleted} key(s)`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// In-app purchases: RevenueCat webhook → treats
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Resolve the Firebase uid a purchase belongs to.
 *
 * RevenueCat's app_user_id is set to the Firebase uid by the client
 * (PurchaseService.login), but a purchase made before that logIn lands is
 * attributed to a generated `$RCAnonymousID:…` instead, and RevenueCat then
 * lists the real uid under `aliases` once the accounts merge. Anonymous ids
 * are never a uid, so they are rejected outright rather than used to create a
 * junk user document.
 */
async function resolvePurchaseUid(event: Record<string, unknown>): Promise<string | null> {
  const aliases = Array.isArray(event.aliases) ? event.aliases : [];
  const candidates = [event.app_user_id, ...aliases].filter(
    (v): v is string =>
      typeof v === "string" && v.length > 0 && !v.startsWith("$RCAnonymousID:")
  );

  for (const uid of candidates) {
    if ((await db.collection("users").doc(uid).get()).exists) return uid;
  }
  return null;
}

/**
 * Credits treats for a consumable treat-pack purchase.
 *
 * The phone never credits treats — it runs the StoreKit purchase and then just
 * watches its own users/{uid} document, exactly as cosmetic purchases already
 * work. RevenueCat verifies the receipt with Apple and calls this.
 *
 * Exactly-once comes from the existing once() primitive keyed on the store
 * transaction id; see PURCHASE_KEY_RETENTION_DAYS for why those keys outlive
 * ordinary callable keys.
 */
export const revenuecatWebhook = onRequest(
  { region: REGION, secrets: [revenuecatWebhookSecret] },
  async (req, res) => {
    // Shared secret configured on the RevenueCat webhook. Anything else is
    // not RevenueCat and must never reach the crediting path.
    if (req.get("Authorization") !== revenuecatWebhookSecret.value()) {
      logger.warn("[revenuecatWebhook] Rejected request with bad Authorization");
      res.status(401).send("unauthorized");
      return;
    }

    const event = req.body?.event as Record<string, unknown> | undefined;
    if (!event) {
      res.status(200).send("no event");
      return;
    }

    const type = event.type;
    if (type !== "NON_RENEWING_PURCHASE") {
      // Consumables can also produce refunds/chargebacks. Treats may already
      // be spent, so there is no claw-back — but log it so a support case can
      // be traced back to a real transaction.
      if (type === "REFUND" || type === "CANCELLATION") {
        logger.warn("[revenuecatWebhook] Unhandled refund-shaped event", {
          type, transactionId: event.transaction_id, productId: event.product_id,
        });
      }
      res.status(200).send("ignored");
      return;
    }

    const environment = typeof event.environment === "string" ? event.environment : "UNKNOWN";
    if (environment === "SANDBOX" && !ALLOW_SANDBOX_PURCHASES) {
      logger.info("[revenuecatWebhook] Ignoring SANDBOX purchase");
      res.status(200).send("sandbox ignored");
      return;
    }

    const productId = typeof event.product_id === "string" ? event.product_id : undefined;
    const transactionId =
      typeof event.transaction_id === "string" ? event.transaction_id :
        typeof event.id === "string" ? event.id : undefined;
    const amount = productId ? TREAT_PRODUCTS[productId] : undefined;

    if (!transactionId || !amount) {
      // An unmapped product is a configuration mistake, not a transient fault:
      // retrying cannot fix it, so acknowledge and surface it in the logs.
      logger.warn("[revenuecatWebhook] Nothing to credit", { productId, transactionId });
      res.status(200).send("nothing to credit");
      return;
    }

    const uid = await resolvePurchaseUid(event);
    if (!uid) {
      // A missing user never becomes present on retry — 200 rather than burn
      // the retry ladder. Logged loudly because this is money already taken.
      logger.error("[revenuecatWebhook] No user for purchase", {
        appUserId: event.app_user_id, transactionId, productId,
      });
      res.status(200).send("no such user");
      return;
    }

    try {
      const result = await once(uid, `treatpack_${transactionId}`, async () => {
        await db.runTransaction(async (tx) => {
          const meRef = db.collection("users").doc(uid);
          const me = await tx.get(meRef);
          if (!me.exists) {
            throw new Error(`user ${uid} vanished before credit`);
          }
          tx.update(meRef, { treats: FieldValue.increment(amount) });
        });
        // Doubles as the purchase record: once() persists this on the key doc,
        // which is now retained for PURCHASE_KEY_RETENTION_DAYS.
        return { credited: amount, productId, environment };
      }, "purchase");

      logger.info("[revenuecatWebhook] Credited treats", {
        uid, transactionId, productId, environment, credited: result.credited,
      });
      res.status(200).send("ok");
    } catch (e) {
      // once() throws "aborted" while a concurrent delivery of the same
      // transaction is still in flight. 500 lets RevenueCat retry, by which
      // point the first attempt has finished and its stored result replays.
      logger.error("[revenuecatWebhook] Credit failed", { uid, transactionId, error: e });
      res.status(500).send("error");
    }
  }
);
