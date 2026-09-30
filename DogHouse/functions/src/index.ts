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
import { pickNudge, preflight, NudgeMarkers, ActiveEvent } from "./nudges";
import {
  FREE_GAMES_PER_DAY, LEGACY_SUBSCRIPTION_PRODUCTS, dayKey, gameDayCount, isCouplePremium,
  premiumPatch, premiumProductOf, premiumSkipReason,
} from "./premium";

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
// Sized against the catalog (cosmetics run 50–300, whole catalog is 2880) and
// against idle earning (1–5 treats/hr by room level, so ~70–120/day at the top
// levels). Small ≈ a mid-tier cosmetic, large ≈ 55% of the catalog — a paying
// user still cannot buy the game out in one tap.
const TREAT_PRODUCTS: Record<string, number> = {
  "com.Harrison.DogHouse.treats.small": 250,
  "com.Harrison.DogHouse.treats.medium": 900,
  "com.Harrison.DogHouse.treats.large": 1600,
};

// Only PRODUCTION store events credit treats or premium. Set to true for the
// pre-launch sandbox test, then back to false: with it on, any TestFlight
// tester's free sandbox purchase is delivered by RevenueCat and credited.
const ALLOW_SANDBOX_PURCHASES = false;

// How long a purchase idempotency key is kept. Must comfortably exceed any
// window in which RevenueCat could re-deliver an event — their automatic
// retry ladder is only ~155 minutes, but a human can hit "Retry" on the
// dashboard at any time, and that replay is what must not double-credit.
const PURCHASE_KEY_RETENTION_DAYS = 180;

// How long the per-user session history is kept before cleanupSessions prunes it.
const SESSION_RETENTION_DAYS = 90;

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
  hat_wizard: 180, hat_beanie: 70, hat_halo: 220, hat_top: 160,
  glasses_cool: 80, glasses_heart: 100, glasses_star: 120,
  glasses_round: 90, glasses_ski: 110, glasses_pixel: 150,
};

// Room progression — mirrors RoomLevel in Swift (RoomProgression.swift).
// Thresholds are hours at home since the last release (or account creation);
// treats/hour is the rate for that level. The client shows this; the server
// is the authority for what claimHomeTreats actually pays.
const ROOM_LEVELS: Array<{ hours: number; rate: number }> = [
  { hours: 0, rate: 1 },      // bareBones
  { hours: 1, rate: 1 },      // basicChair
  { hours: 6, rate: 2 },      // blanket
  { hours: 24, rate: 2 },     // pillowAndRug
  { hours: 72, rate: 3 },     // fireplace
  { hours: 168, rate: 3 },    // tvAndArt
  { hours: 336, rate: 4 },    // plantsAndBooks
  { hours: 720, rate: 4 },    // luxury
  { hours: 1440, rate: 5 },   // penthouse
  { hours: 2160, rate: 5 },   // palace
];

/** Treats per hour for someone who has been home since `homeStartMs`. */
export function roomRateFor(homeStartMs: number, nowMs: number): number {
  const hours = Math.max(0, nowMs - homeStartMs) / 3_600_000;
  let rate = ROOM_LEVELS[0].rate;
  for (const level of ROOM_LEVELS) {
    if (hours >= level.hours) rate = level.rate;
  }
  return rate;
}

/**
 * When this user's current stay at home began: their most recent release,
 * else account creation. Mirrors DoghouseService.homeStartDate.
 */
async function homeStartMsFor(uid: string, createdAt?: Timestamp): Promise<number> {
  const last = await db.collection("doghouseEvents")
    .where("receiverId", "==", uid).where("isActive", "==", false)
    .orderBy("endedAt", "desc").limit(1).get();
  const endedAt = last.docs[0]?.data().endedAt as Timestamp | undefined;
  return endedAt?.toMillis() ?? createdAt?.toMillis() ?? Date.now();
}

function categoryOf(itemId: string): string {
  return itemId.split("_")[0]; // "necklace_gold" -> "necklace"
}

/** Balance a brand-new account is shown (client: UserProfile.effectiveTreats). */
const STARTING_TREATS = 100;

/**
 * Balance after a credit or debit. Accounts are created WITHOUT a `treats`
 * field and every reader treats "absent" as STARTING_TREATS, so a bare
 * FieldValue.increment on the absent field computed from 0 and silently wiped
 * the 100 starter treats on the first claim, purchase or roses (found by the
 * 2026-09-22 QA run). Always write the absolute value, from inside the
 * transaction that read the doc.
 */
function treatsAfter(me: FirebaseFirestore.DocumentData | undefined, delta: number): number {
  const current = me?.treats;
  const base = typeof current === "number" && Number.isFinite(current) ? current : STARTING_TREATS;
  return base + delta;
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
 * Partner-scoped actions must check BOTH halves of the link. `partnerId` on
 * the caller's own document is self-asserted (owner-writable by rule), so on
 * its own it proves nothing: anyone could point it at a stranger's uid and
 * then send them to the doghouse, gift to them, or deliver wishes.
 * The partner's document pointing back is the proof.
 */
function requireMutualPartner(
  uid: string,
  partnerId: string | undefined,
  partner: FirebaseFirestore.DocumentData | undefined
): string {
  if (!partnerId || partnerId === "skipped" || partner?.partnerId !== uid) {
    throw new HttpsError("failed-precondition", "You have no partner.");
  }
  return partnerId;
}

/**
 * When this account really started: the later of the profile's createdAt and
 * the Firebase Auth account's creation time. createdAt sits on a document the
 * owner can write (and older accounts may already have edited it), and it
 * feeds the room-level treat rate, so it is clamped to something only the
 * server controls.
 */
async function accountCreatedMs(uid: string, createdAt?: Timestamp): Promise<number | undefined> {
  let authMs: number | undefined;
  try {
    const t = Date.parse((await auth.getUser(uid)).metadata.creationTime);
    if (!Number.isNaN(t)) authMs = t;
  } catch (err) {
    logger.warn(`[accountCreatedMs] No auth record for ${uid}`, err);
  }
  const docMs = createdAt?.toMillis();
  if (authMs === undefined) return docMs;
  return docMs === undefined ? authMs : Math.max(authMs, docMs);
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
// 1b. Un-pairing. Pairing itself goes through the pairWithCode callable,
//     which checks the code and links both halves atomically; the rules
//     only let a client clear its own partnerId (or skip). This trigger
//     dissolves the old couple's friendships when that happens.
// ─────────────────────────────────────────────────────────────
export const onUserPaired = onDocumentUpdated(
  { document: "users/{uid}", region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const uid = event.params.uid;
    const newPartnerId = after.partnerId as string | undefined;

    // Un-pairing (or re-pairing with someone else) dissolves the old
    // couple, and its friendships with it. Runs for both halves; the second
    // run finds nothing left to delete.
    const oldPartnerId = before?.partnerId as string | undefined;
    if (oldPartnerId && oldPartnerId !== "skipped" && oldPartnerId !== newPartnerId) {
      await dissolveCoupleFriendships(coupleKeyOf(uid, oldPartnerId));
    }
  }
);

/**
 * Pair with the owner of a pairing code. The code is the proof of consent:
 * it lives on the owner's private document and is only shared on purpose.
 * Both profiles are linked in one transaction, so there is never a window in
 * which only one half points at the other.
 */
export const pairWithCode = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const code = (req.data?.code ?? "").toString().trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Invalid partner code");
  }

  const partnerUid = (await db.collection("partnerCodes").doc(code).get())
    .data()?.userId as string | undefined;
  if (!partnerUid) throw new HttpsError("not-found", "Invalid partner code");
  if (partnerUid === uid) {
    throw new HttpsError("invalid-argument", "You cannot pair with yourself");
  }

  const meRef = db.collection("users").doc(uid);
  const partnerRef = db.collection("users").doc(partnerUid);
  const alreadyMutual = await db.runTransaction(async (tx) => {
    const [meSnap, partnerSnap] = await Promise.all([tx.get(meRef), tx.get(partnerRef)]);
    if (!meSnap.exists || !partnerSnap.exists) {
      throw new HttpsError("failed-precondition", "Invalid partner code");
    }
    const mine = meSnap.data()?.partnerId as string | undefined;
    const theirs = partnerSnap.data()?.partnerId as string | undefined;
    if (mine === partnerUid && theirs === uid) return true;
    if (theirs && theirs !== "skipped" && theirs !== uid) {
      throw new HttpsError("failed-precondition", "This user is already paired with someone");
    }
    if (mine && mine !== "skipped" && mine !== partnerUid) {
      throw new HttpsError("failed-precondition", "Unpair from your current partner first");
    }
    tx.update(meRef, { partnerId: partnerUid });
    tx.update(partnerRef, { partnerId: uid });
    return false;
  });

  if (!alreadyMutual) {
    // onUserPaired sees an already-mutual pair and stays quiet, so the
    // "you're paired" push is sent from here.
    await notifyUser(
      partnerUid,
      "❤️ You're paired!",
      `${await displayName(uid)} connected with you on DogHouse. Let the games begin!`,
      { data: { type: "doghouse" } }
    );
    logger.info(`[pairing] Paired by code ${uid} ↔ ${partnerUid}`);
  }
  return { ok: true, partnerId: partnerUid };
});

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

    // Dogs already being voted on are out of the pool. Previously only the
    // FIRST matching post was examined, and if that dog was already in a
    // vote the search stopped there — a third friend in the doghouse never
    // got a vote even when another free candidate was waiting.
    const activeVotes = await db
      .collection("voteEvents")
      .where("status", "==", "active")
      .get();
    const alreadyVotedOn = new Set<string>();
    activeVotes.forEach((v) =>
      ((v.data().doghousedUserIds ?? []) as string[]).forEach((id) => alreadyVotedOn.add(id))
    );
    if (alreadyVotedOn.has(receiverId)) return;

    const activePosts = await db
      .collection("feedPosts")
      .where("status", "==", "active")
      .get();

    const millis = (t: unknown) => (t instanceof Timestamp ? t.toMillis() : 0);
    const otherPost = activePosts.docs
      .filter((d) => {
        const dog = d.data().receiverId as string;
        return d.id !== postId && dog !== receiverId
          && jailbreakCandidates.has(dog) && !alreadyVotedOn.has(dog);
      })
      // Newest sending first — the most topical pairing
      .sort((a, b) => millis(b.data().createdAt) - millis(a.data().createdAt))[0];
    if (!otherPost) return;

    const other = otherPost.data();

    const audience = [
      ...new Set([...audienceIds, ...(other.audienceIds ?? [])]),
    ];
    const dogs = [receiverId, other.receiverId as string];
    const dogNames: Record<string, string> = {
      [receiverId]: receiverName,
      [other.receiverId]: other.receiverName ?? "A friend",
    };

    // Deterministic id: two sendings landing within the same second each
    // run this trigger, each sees the other as "the other post", and both
    // would open a vote for the same pair. Deriving the id from the pair of
    // posts makes the second create() fail instead.
    const voteId = `joint_${[postId, otherPost.id].sort().join("_")}`;
    const voteRef = db.collection("voteEvents").doc(voteId);
    const now = Timestamp.now();
    try {
      await voteRef.create({
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
    } catch {
      logger.info(`[jailbreakVote] Vote ${voteId} already exists — concurrent trigger`);
      return;
    }

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
/**
 * The roasts the app offers (CannedRoast.all in Models/FeedPost.swift). Keep
 * the two lists identical: a line missing here is silently not pushed.
 */
const CANNED_ROASTS = new Set<string>([
  "Justice served 🍖",
  "FREE MY BOY",
  "Guilty as charged 🐕‍🦺",
  "The audacity!",
  "Somebody call the pawlice 🚨",
  "Straight to the pound",
  "He would never!! (he did)",
  "Bad dog. No treats.",
]);

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
      // The field is client-written, so only the app's own canned lines are
      // pushed; anything else would put arbitrary text on someone's lock screen.
      if (!CANNED_ROASTS.has(roast)) {
        logger.warn(`[feed] Ignoring non-canned roast from ${uid} on ${event.params.postId}`);
        continue;
      }
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

      // Tally — only votes for the dogs actually in this vote count. The
      // rules enforce that too, but this is the code that hands out a
      // release and an hour of immunity, so it must not trust the document.
      const candidates = new Set<string>((vote.doghousedUserIds ?? []) as string[]);
      const counts: Record<string, number> = {};
      for (const votedForId of Object.values(vote.votes ?? {})) {
        const id = votedForId as string;
        if (!candidates.has(id)) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      const maxVotes = Math.max(0, ...Object.values(counts));
      const winners =
        maxVotes > 0
          ? Object.keys(counts).filter((id) => counts[id] === maxVotes)
          : [];

      // Release every winner's active doghouse event (tie → both go free)
      const releasedNames: string[] = [];
      const freedIds: string[] = [];
      const overruledSenderIds: string[] = [];
      for (const winnerId of winners) {
        const events = await db
          .collection("doghouseEvents")
          .where("receiverId", "==", winnerId)
          .where("isActive", "==", true)
          .get();
        if (events.empty) {
          // Let out by their partner before the deadline (releasePartner
          // normally cancels the vote, but the two can race by a minute).
          // Nothing to release, and no fresh immunity for a dog who is home.
          logger.info(`[resolveVotes] ${winnerId} won ${voteDoc.id} but is already out`);
          continue;
        }
        for (const ev of events.docs) {
          await ev.ref.update({
            isActive: false,
            endedAt: now,
            releasedBy: "vote",
          });
          const senderId = ev.data().senderId as string;
          overruledSenderIds.push(senderId);
          // Same bookkeeping as releasePartner: the sender's treat clock
          // restarts too, so the doghouse hours are never paid out.
          await db.collection("users").doc(senderId).update({ lastTreatAward: now });
        }
        // Grant the freed dog immunity (clients can no longer self-write it)
        await db.collection("users").doc(winnerId).update({
          immunityUntil: Timestamp.fromMillis(now.toMillis() + IMMUNITY_SECONDS * 1000),
          lastTreatAward: now,
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
        freedIds.push(winnerId);
        releasedNames.push(
          (vote.doghousedUserNames?.[winnerId] as string | undefined) ??
            (await displayName(winnerId))
        );
      }

      await voteDoc.ref.update({
        status: "completed",
        endedAt: now,
        winnerId: freedIds.length === 1 ? freedIds[0] : null,
        winnerIds: freedIds,
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
        (id) => !freedIds.includes(id) && !overruledSenderIds.includes(id)
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
      } else if (freedIds.length === 0) {
        await notifyUsers(
          audience,
          "🗳️ The vote is over",
          "The winner had already been let out. Nobody else goes free 😬",
          { data: { type: "feed" } }
        );
      } else if (freedIds.length === 1) {
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
        `[resolveVotes] Resolved ${voteDoc.id}: winners=${winners.join(",") || "none"} freed=${freedIds.join(",") || "none"}`
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

/** Emails per user per hour, feedback and reports combined. */
const EMAIL_QUOTA_PER_HOUR = 10;

/**
 * Whether this user may still trigger a developer email this hour. Feedback
 * and reports are one client write each, so without a cap a single account
 * could loop creates and bury the mailbox (and burn the Gmail sending
 * limit). Over-quota submissions are still stored in Firestore; they just
 * don't send an email. emailQuota/{uid} is server-only (no rule matches it).
 */
async function withinEmailQuota(uid: string | undefined): Promise<boolean> {
  if (!uid) return false;
  const ref = db.collection("emailQuota").doc(uid);
  return db.runTransaction(async (tx) => {
    const q = (await tx.get(ref)).data();
    const now = Date.now();
    const windowStart = (q?.windowStart as Timestamp | undefined)?.toMillis() ?? 0;
    if (now - windowStart >= 3_600_000) {
      tx.set(ref, { windowStart: Timestamp.fromMillis(now), count: 1 });
      return true;
    }
    const count = (q?.count as number | undefined) ?? 0;
    if (count >= EMAIL_QUOTA_PER_HOUR) return false;
    tx.update(ref, { count: count + 1 });
    return true;
  });
}

export const onFeedbackCreated = onDocumentCreated(
  { document: "feedback/{feedbackId}", region: REGION, secrets: [gmailAppPassword] },
  async (event) => {
    const fb = event.data?.data();
    if (!fb) return;

    const kind: string = fb.type ?? "feedback";
    const fromName: string = fb.fromName ?? "Unknown";
    const text: string = fb.text ?? "";
    if (!(await withinEmailQuota(fb.fromUserId))) {
      logger.warn(`[feedback] Email quota exceeded for ${fb.fromUserId}; stored only`);
      return;
    }

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

      // Delete owned/related documents
      await deleteWhere("partnerCodes", "userId", uid);
      await deleteWhere("feedPosts", "senderId", uid);
      await deleteWhere("feedPosts", "receiverId", uid);
      await deleteWhere("doghouseEvents", "senderId", uid);
      await deleteWhere("doghouseEvents", "receiverId", uid);
      await deleteWhere("wishes", "fromUserId", uid);
      await deleteWhere("wishes", "toUserId", uid);
      await deleteWhere("feedback", "fromUserId", uid);
      await deleteWhere("reports", "reporterId", uid);
      await db.collection("blocks").doc(uid).delete();
      await db.collection("emailQuota").doc(uid).delete();
      // Challenges, with the hidden answer a Play-tab game keeps in its
      // private subcollection (deleting a parent does not delete it).
      const challenges = await db.collection("challenges")
        .where("participants", "array-contains", uid).get();
      await Promise.all(challenges.docs.map(async (d) => {
        await d.ref.collection("private").doc("answer").delete();
        await d.ref.delete();
      }));
      // Votes: a deleted account merely leaves the audience. Deleting every
      // vote it could see wiped other couples' running jailbreak votes. A
      // vote it was a candidate in is meaningless without it and goes.
      const votes = await db.collection("voteEvents")
        .where("audienceIds", "array-contains", uid).get();
      await Promise.all(votes.docs.map((d) =>
        ((d.data().doghousedUserIds ?? []) as string[]).includes(uid)
          ? d.ref.delete()
          : d.ref.update({ audienceIds: FieldValue.arrayRemove(uid) })));
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
          db.collection("gameStats").doc(key).delete(),
          db.collection("taskRenegotiation").doc(key).delete(),
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

/**
 * Whether a completed challenge is one that pays a card: a photo dash the
 * scheduler started, or the couple's one anniversary race for this year
 * (deterministic id, created by its winner — see ChallengeService). Quizzes
 * never pay. The caller separately checks that the couple is mutual.
 */
function earnsCard(id: string, c: FirebaseFirestore.DocumentData): boolean {
  const participants = c.participants as unknown;
  if (!Array.isArray(participants) || participants.length !== 2) return false;
  const [a, b] = participants as string[];
  if (typeof a !== "string" || typeof b !== "string" || a === b) return false;
  if (!participants.includes(c.winnerId)) return false;
  const key = coupleKeyOf(a, b);
  if (c.coupleKey !== key) return false;

  if (c.type === "photo") return c.createdBy === "system";
  if (c.type === "anniversary") {
    const year = new Date().getUTCFullYear();
    return c.createdBy === c.winnerId &&
      [year - 1, year, year + 1].some((y) => id === `anniv_${key}_${y}`);
  }
  return false;
}
export const onChallengeWritten = onDocumentWritten(
  { document: "challenges/{challengeId}", region: REGION },
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    // Play-tab games are settled (and any card paid) inside answerGame; this
    // trigger must never touch them, least of all the card-award path below.
    if (after.type === "game") return;
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

    // Award: a legitimately won challenge grants one card (once). The
    // document is client-written, so "completed with a winner" alone proves
    // nothing — a client could create one naming itself. Only the two
    // card-bearing kinds count, each checked for provenance, and the flag
    // and the increment commit together so a redelivered event can't pay twice.
    if (after.status === "completed" && after.winnerId && after.cardAwarded !== true) {
      const winnerId: string = after.winnerId;
      const loserId = participants.find((p) => p !== winnerId);
      const awarded = await db.runTransaction(async (tx) => {
        const c = (await tx.get(ref)).data();
        if (!c || c.cardAwarded === true || c.status !== "completed" ||
            c.winnerId !== winnerId || !earnsCard(event.params.challengeId, c)) {
          return false;
        }
        const [a, b] = c.participants as string[];
        const [aSnap, bSnap] = await Promise.all([
          tx.get(db.collection("users").doc(a)),
          tx.get(db.collection("users").doc(b)),
        ]);
        if (aSnap.data()?.partnerId !== b || bSnap.data()?.partnerId !== a) return false;
        tx.update(ref, { cardAwarded: true });
        tx.update(db.collection("users").doc(winnerId), {
          wishCards: FieldValue.increment(1),
        });
        return true;
      });
      if (!awarded) {
        logger.warn(`[challenge] No card for ${event.params.challengeId} (won by ${winnerId})`);
        return;
      }

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
// 9b. Play tab — couple games (createGame / answerGame) and the
//     "redo our tasks" request (taskRenegotiation)
// ─────────────────────────────────────────────────────────────

// A game is written ONLY by these callables (admin SDK); the challenge rules
// admit no client create or update of type "game". The author's answer lives
// in challenges/{id}/private/answer, which no client can read, so the partner
// cannot peek before guessing. onChallengeWritten ignores games entirely:
// their result and any card are settled here, in one transaction.

type GameKind = "preference" | "ballKnowledge" | "twoTruths" | "likelyTo";

const GAME_KINDS: Record<GameKind, { title: string; min: number; max: number }> = {
  preference: { title: "Preference Quiz", min: 2, max: 2 },
  ballKnowledge: { title: "Ball Knowledge", min: 2, max: 4 },
  twoTruths: { title: "Two Truths & a Lie", min: 3, max: 3 },
  likelyTo: { title: "Who's More Likely To", min: 2, max: 2 },
};
const GAME_PROMPT_MAX = 200;
const GAME_OPTION_MAX = 120;
const MAX_ACTIVE_GAMES = 20;
// Wins fill a card meter; a full meter pays a Whatever-I-Want card, at most
// GAME_CARDS_PER_WEEK per player per ISO week. A full meter over the cap
// stays full and pays out on the first win of an uncapped week.
const GAME_CARD_WINS = 5;
const GAME_CARDS_PER_WEEK = 2;

/**
 * Length in user-perceived-ish characters. The Swift client counts
 * Characters; UTF-16 `.length` would count an emoji as two and reject text
 * the client allowed. Code points are never more than UTF-16 units, so the
 * server is at least as lenient as the client.
 */
function charCount(s: string): number {
  return Array.from(s).length;
}

/** ISO-8601 week of `now` in UTC, as "YYYY-Www" (the week-year, not the calendar year). */
function isoWeekKey(now: Date): string {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7)); // Thursday of this week
  const year = d.getUTCFullYear();
  const week = Math.ceil(((d.getTime() - Date.UTC(year, 0, 1)) / 864e5 + 1) / 7);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

// Start a game for the partner to answer. Validation rejects rather than
// trims over-long text: silently cutting a Two Truths statement would change
// the game the author thinks they sent.
export const createGame = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const kind = req.data?.kind as GameKind;
    const spec = typeof kind === "string" ? GAME_KINDS[kind] : undefined;
    if (!spec || !Object.prototype.hasOwnProperty.call(GAME_KINDS, kind)) {
      throw new HttpsError("invalid-argument", "That game doesn't exist.");
    }

    const prompt = (typeof req.data?.prompt === "string" ? req.data.prompt : "").trim();
    if (!prompt) throw new HttpsError("invalid-argument", "Your game needs a question.");
    if (charCount(prompt) > GAME_PROMPT_MAX) {
      throw new HttpsError("invalid-argument",
        `Keep the question under ${GAME_PROMPT_MAX} characters.`);
    }

    let options: string[];
    if (kind === "likelyTo") {
      // "me" = the author, "you" = the partner; the client renders names.
      options = ["me", "you"];
    } else {
      const raw = req.data?.options;
      if (!Array.isArray(raw) || raw.some((o) => typeof o !== "string")) {
        throw new HttpsError("invalid-argument", "Those answers don't look right.");
      }
      options = (raw as string[]).map((o) => o.trim());
      if (options.length < spec.min || options.length > spec.max) {
        throw new HttpsError("invalid-argument", spec.min === spec.max
          ? `${spec.title} needs exactly ${spec.min} answers.`
          : `${spec.title} needs ${spec.min} to ${spec.max} answers.`);
      }
      if (options.some((o) => !o)) {
        throw new HttpsError("invalid-argument", "Fill in every answer.");
      }
      if (options.some((o) => charCount(o) > GAME_OPTION_MAX)) {
        throw new HttpsError("invalid-argument",
          `Keep each answer under ${GAME_OPTION_MAX} characters.`);
      }
    }

    const answerIndex = req.data?.answerIndex;
    if (!Number.isInteger(answerIndex) || answerIndex < 0 || answerIndex >= options.length) {
      throw new HttpsError("invalid-argument", "Pick your answer first.");
    }

    const meRef = db.collection("users").doc(uid);
    const gameRef = db.collection("challenges").doc();
    // Equality-only: served by single-field indexes, no composite needed.
    const activeQuery = db.collection("challenges")
      .where("createdBy", "==", uid)
      .where("type", "==", "game")
      .where("status", "==", "active");

    const { partnerId, myName } = await db.runTransaction(async (tx) => {
      // ── reads (all before any write) ──
      const me = (await tx.get(meRef)).data() ?? {};
      const claimed = me.partnerId as string | undefined;
      const partner = claimed && claimed !== "skipped" ?
        (await tx.get(db.collection("users").doc(claimed))).data() : undefined;
      const partnerId = requireMutualPartner(uid, claimed, partner);
      const coupleKey = coupleKeyOf(uid, partnerId);
      const statsRef = db.collection("gameStats").doc(coupleKey);
      const [privSnap, statsSnap, active] = await Promise.all([
        tx.get(privateDataRef(uid)), tx.get(statsRef), tx.get(activeQuery),
      ]);

      // No new games while either partner is in the doghouse: sort it out first.
      const stay = await tx.get(db.collection("doghouseEvents")
        .where("receiverId", "in", [uid, partnerId]).where("isActive", "==", true).limit(1));
      if (!stay.empty) {
        const inside = stay.docs[0].get("receiverId") === uid ? "You're" :
          `${(partner?.displayName as string | undefined) ?? "Your partner"} is`;
        throw new HttpsError("failed-precondition",
          `${inside} in the doghouse. Resolve the issue and you can play!`);
      }

      if (active.size >= MAX_ACTIVE_GAMES) {
        throw new HttpsError("resource-exhausted",
          "You have lots of games waiting already. Let your partner catch up first!");
      }

      // Free couples get FREE_GAMES_PER_DAY per calendar day in the creator's
      // time zone; premium (either partner subscribed) is unlimited. Enforced
      // here, inside once(), so a retried call never counts twice. The
      // counter is written for premium couples too, so a subscription lapsing
      // mid-day limits the very next game.
      const nowMs = Date.now();
      const today = dayKey(nowMs, privSnap.data()?.timeZone as string | undefined);
      const { day, gamesToday } = gameDayCount(
        statsSnap.data()?.lastGameDay, statsSnap.data()?.gamesToday, today);
      if (!isCouplePremium(me, partner, nowMs) && gamesToday >= FREE_GAMES_PER_DAY) {
        throw new HttpsError("resource-exhausted", "daily-game-limit",
          { reason: "daily-game-limit" });
      }

      // ── writes ──
      // gameStats also holds the couple's scorecard (answerGame), so merge:
      // a plain set would wipe wins/played/cardProgress.
      tx.set(statsRef, { lastGameDay: day, gamesToday: gamesToday + 1 }, { merge: true });
      tx.set(gameRef, {
        coupleKey, type: "game", kind,
        title: spec.title, prompt, options, createdBy: uid,
        participants: [uid, partnerId], status: "active", createdAt: Timestamp.now(),
      });
      tx.set(gameRef.collection("private").doc("answer"), { answerIndex });
      return { partnerId, myName: (me.displayName as string | undefined) ?? "Your partner" };
    });

    await notifyUser(partnerId, `🎲 ${myName} sent you a ${spec.title}`, prompt,
      { data: { type: "game" } });
    return { ok: true, challengeId: gameRef.id };
  });
});

// The partner answers. Scoring, stats and any card are one transaction, so
// a game resolves exactly once however many times the call is retried.
export const answerGame = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const challengeId = req.data?.challengeId;
    if (typeof challengeId !== "string" || !challengeId || challengeId.includes("/")) {
      throw new HttpsError("invalid-argument", "Missing game.");
    }
    const guessIndex = req.data?.guessIndex;
    if (!Number.isInteger(guessIndex)) {
      throw new HttpsError("invalid-argument", "Pick an answer first.");
    }

    const gameRef = db.collection("challenges").doc(challengeId);
    const answerRef = gameRef.collection("private").doc("answer");

    const outcome = await db.runTransaction(async (tx) => {
      // ── reads ──
      const [gameSnap, answerSnap, meSnap] = await Promise.all([
        tx.get(gameRef), tx.get(answerRef), tx.get(db.collection("users").doc(uid)),
      ]);
      const game = gameSnap.data();
      if (!game || game.type !== "game") {
        throw new HttpsError("not-found", "That game is gone.");
      }
      if (game.status !== "active") {
        throw new HttpsError("failed-precondition", "This game has already been played.");
      }
      const participants = (game.participants ?? []) as string[];
      const authorId = game.createdBy as string;
      if (!participants.includes(uid)) {
        throw new HttpsError("permission-denied", "This isn't your game.");
      }
      if (uid === authorId) {
        throw new HttpsError("failed-precondition", "You can't answer your own game!");
      }
      const options = (game.options ?? []) as string[];
      if (guessIndex < 0 || guessIndex >= options.length) {
        throw new HttpsError("invalid-argument", "Pick one of the answers.");
      }
      const answerIndex = answerSnap.data()?.answerIndex;
      if (!Number.isInteger(answerIndex)) {
        throw new HttpsError("internal", "This game is broken. Ask for a new one!");
      }

      // Both halves must still point at each other, and at THIS game's author.
      const me = meSnap.data() ?? {};
      if (me.partnerId !== authorId) {
        throw new HttpsError("failed-precondition", "You have no partner.");
      }
      const key = coupleKeyOf(uid, authorId);
      const statsRef = db.collection("gameStats").doc(key);
      const [authorSnap, statsSnap] = await Promise.all([
        tx.get(db.collection("users").doc(authorId)), tx.get(statsRef),
      ]);
      requireMutualPartner(uid, me.partnerId as string, authorSnap.data());
      if (game.coupleKey !== key) {
        throw new HttpsError("failed-precondition", "This isn't your game.");
      }

      // ── scoring ──
      const isLikely = game.kind === "likelyTo";
      // likelyTo: guesser 0 = themselves, author 0 = the author. Naming the
      // same person means different indices.
      const correct = isLikely ? guessIndex !== answerIndex : guessIndex === answerIndex;
      const winnerId: string | null = isLikely ? null : (correct ? uid : authorId);

      const stats = statsSnap.data() ?? {};
      // increment(0) still creates a missing counter as 0, so every counter
      // exists after the first game of any kind.
      const statsUpdate: Record<string, unknown> = {
        played: FieldValue.increment(1),
        likelyToPlayed: FieldValue.increment(isLikely ? 1 : 0),
        inSync: FieldValue.increment(isLikely && correct ? 1 : 0),
        updatedAt: Timestamp.now(),
      };

      let cardEarned = false;
      if (winnerId) {
        statsUpdate.wins = { [winnerId]: FieldValue.increment(1) };
        const progress = Math.min(
          ((stats.cardProgress?.[winnerId] as number | undefined) ?? 0) + 1, GAME_CARD_WINS);
        const week = isoWeekKey(new Date());
        const earnedThisWeek = stats.cardsWeek?.[winnerId] === week ?
          ((stats.cardsThisWeek?.[winnerId] as number | undefined) ?? 0) : 0;
        if (progress >= GAME_CARD_WINS && earnedThisWeek < GAME_CARDS_PER_WEEK) {
          cardEarned = true;
          statsUpdate.cardProgress = { [winnerId]: 0 };
          statsUpdate.cardsWeek = { [winnerId]: week };
          statsUpdate.cardsThisWeek = { [winnerId]: earnedThisWeek + 1 };
        } else {
          statsUpdate.cardProgress = { [winnerId]: progress };
        }
      }

      // ── writes ──
      tx.update(gameRef, {
        status: "completed", answerIndex, guessIndex, correct, winnerId,
        completedAt: Timestamp.now(),
      });
      // Nested maps (not dotted keys) so merge deep-merges per uid, and the
      // first game can create the document.
      tx.set(statsRef, statsUpdate, { merge: true });
      if (cardEarned && winnerId) {
        tx.update(db.collection("users").doc(winnerId), { wishCards: FieldValue.increment(1) });
      }
      return {
        correct, answerIndex: answerIndex as number, winnerId, cardEarned,
        authorId, isLikely, prompt: (game.prompt as string | undefined) ?? "",
        guesserName: (me.displayName as string | undefined) ?? "Your partner",
      };
    });

    const { correct, answerIndex, winnerId, cardEarned, authorId, isLikely, guesserName } = outcome;
    let title: string;
    let body: string;
    if (isLikely) {
      title = correct ? "💞 You're in sync!" : "🤔 Agree to disagree?";
      body = correct
        ? `${guesserName} picked the same person: "${outcome.prompt}"`
        : `${guesserName} sees it differently: "${outcome.prompt}"`;
    } else if (correct) {
      title = `🎯 ${guesserName} got it!`;
      body = `They knew the answer to "${outcome.prompt}"`;
    } else {
      title = `😈 You stumped ${guesserName}!`;
      body = cardEarned
        ? "That win filled your meter: you earned a Whatever-I-Want card 🎟️"
        : `They got "${outcome.prompt}" wrong.`;
    }
    await notifyUser(authorId, title, body, { data: { type: "game" } });

    return { ok: true, correct, answerIndex, winnerId, cardEarned };
  });
});

// Ask to redo the couple's task list. One request per couple, kept at
// taskRenegotiation/{coupleKey} (server-written only):
//   request  → { status: "pending" }        (no request may already exist)
//   accept   → { status: "accepted" } and onboardingTasks is cleared so both
//              partners renegotiate; coupleTasks stays in force until the
//              new list is confirmed. The accepted doc tells both apps to
//              show "negotiate new tasks".
//   complete → the renegotiated list is final; the request doc goes.
//   decline / cancel → the request doc goes.
export const taskRenegotiation = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  return once(uid, req.data?.idempotencyKey, async () => {
    const action = req.data?.action;
    if (!["request", "cancel", "accept", "decline", "complete"].includes(action)) {
      throw new HttpsError("invalid-argument", "Unknown request.");
    }

    const meRef = db.collection("users").doc(uid);
    const result = await db.runTransaction(async (tx) => {
      // ── reads ──
      const me = (await tx.get(meRef)).data() ?? {};
      const claimed = me.partnerId as string | undefined;
      const partner = claimed && claimed !== "skipped" ?
        (await tx.get(db.collection("users").doc(claimed))).data() : undefined;
      const partnerId = requireMutualPartner(uid, claimed, partner);
      const key = coupleKeyOf(uid, partnerId);
      const reqRef = db.collection("taskRenegotiation").doc(key);
      const onboardingRef = db.collection("onboardingTasks").doc(key);
      const [reqSnap, onboardingSnap] = await Promise.all([
        tx.get(reqRef), tx.get(onboardingRef),
      ]);
      const current = reqSnap.data();
      const status = current?.status as string | undefined;
      const mine = current?.requestedBy === uid;

      // ── checks + writes ──
      switch (action) {
      case "request":
        if (current) {
          throw new HttpsError("failed-precondition", status === "accepted"
            ? "You're already redoing your tasks. Finish that first!"
            : mine
              ? "You've already asked. Waiting on your partner!"
              : "Your partner already asked to redo tasks. Answer them first!");
        }
        tx.set(reqRef, { requestedBy: uid, requestedAt: Timestamp.now(), status: "pending" });
        break;
      case "accept":
      case "decline":
        if (status !== "pending") {
          throw new HttpsError("failed-precondition", "There's no request to answer.");
        }
        if (mine) {
          throw new HttpsError("permission-denied", "Your partner has to answer this one.");
        }
        if (action === "accept") {
          tx.delete(onboardingRef);
          tx.update(reqRef, { status: "accepted", acceptedAt: Timestamp.now() });
        } else {
          tx.delete(reqRef);
        }
        break;
      case "cancel":
        if (status === "pending") {
          if (!mine) {
            throw new HttpsError("permission-denied", "Only the person who asked can cancel.");
          }
        } else if (status !== "accepted") {
          throw new HttpsError("failed-precondition", "There's nothing to cancel.");
        }
        tx.delete(reqRef);
        break;
      case "complete": {
        const finalTasks = onboardingSnap.data()?.finalTasks;
        if (status !== "accepted" || !Array.isArray(finalTasks) || finalTasks.length === 0) {
          throw new HttpsError("failed-precondition",
            "Finish agreeing on your new tasks first.");
        }
        tx.delete(reqRef);
        break;
      }
      }
      return {
        partnerId,
        myName: (me.displayName as string | undefined) ?? "Your partner",
      };
    });

    const { partnerId, myName } = result;
    const push: Record<string, [string, string] | undefined> = {
      request: [`📝 ${myName} wants to redo your tasks`,
        "Open DogHouse to accept or decline."],
      accept: [`✅ ${myName} said yes!`, "Time to rework your task list together."],
      decline: [`🙅 ${myName} wants to keep your tasks`, "Your task list stays as it is."],
    };
    const message = push[action as string];
    if (message) {
      await notifyUser(partnerId, message[0], message[1], { data: { type: "tasks" } });
    }
    return { ok: true };
  });
});

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
        // coupleMeta is client-written: push only to a couple that is real
        // and actually owns this document.
        const [a, b] = userIds;
        if (doc.id !== coupleKeyOf(a, b)) continue;
        const [aDoc, bDoc] = await Promise.all([
          db.collection("users").doc(a).get(), db.collection("users").doc(b).get(),
        ]);
        if (aDoc.data()?.partnerId !== b || bDoc.data()?.partnerId !== a) continue;
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
      requireMutualPartner(uid, me.partnerId as string | undefined, partner);

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
    const askedForRedemption = req.data?.byRedemption === true;
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
      // The redemption reward is only for a dog who asked for redemption
      // (requestRedemption, receiver-only). Without this the sender could
      // pay their partner REDEMPTION_TREATS on every release. A flag the
      // event doesn't back is a plain release, not an error.
      const byRedemption = askedForRedemption && ev.redemptionRequested === true;

      // All reads before any write (Firestore transaction rule).
      const receiverRef = db.collection("users").doc(ev.receiverId as string);
      const receiver = (await tx.get(receiverRef)).data();

      tx.update(ref, {
        isActive: false, endedAt: now,
        releasedBy: byRedemption ? "redemption" : "sender",
      });
      // Grant the released dog immunity (was previously a client self-write).
      // Both partners' treat clocks restart now: claimHomeTreats pays for
      // every hour since lastTreatAward, and without this reset the hours one
      // of them spent in the doghouse would be paid out at release.
      tx.update(receiverRef, {
        immunityUntil: Timestamp.fromMillis(now.toMillis() + IMMUNITY_SECONDS * 1000),
        lastTreatAward: now,
        ...(byRedemption ? { treats: treatsAfter(receiver, REDEMPTION_TREATS) } : {}),
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

    // A dog let out by their partner is no longer a jailbreak candidate.
    // Leaving the vote running kept the "both in the DogHouse" banner up on
    // every friend's phone for the rest of the half hour, and let the
    // resolver "free" — and re-immunise — a dog who was already home.
    for (const p of posts.docs) {
      const voteId = p.data().voteEventId as string | undefined;
      if (voteId) {
        await cancelVoteForReleasedDog(voteId, p.data().receiverId as string, uid);
      }
    }
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
        const claimed = me.partnerId as string | undefined;
        const partner = claimed && claimed !== "skipped" ?
          (await tx.get(db.collection("users").doc(claimed))).data() : undefined;
        const pid = requireMutualPartner(uid, claimed, partner);

        const treats = (me.treats as number | undefined) ?? 100;
        if (treats < ROSES_COST) {
          throw new HttpsError("failed-precondition",
            `Roses cost ${ROSES_COST} treats — you only have ${treats} 🦴`);
        }

        const name = (me.displayName as string | undefined) ?? "Your partner";
        tx.update(meRef, { treats: treats - ROSES_COST });
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
    // Own-property check: a prototype key like "constructor" would otherwise
    // resolve to a function, and `treats - price` would write NaN.
    if (typeof itemId !== "string" ||
        !Object.prototype.hasOwnProperty.call(COSMETIC_PRICES, itemId)) {
      throw new HttpsError("invalid-argument", "Unknown item.");
    }
    const price = COSMETIC_PRICES[itemId];

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
          const claimed = me.partnerId as string | undefined;
          const partner = claimed && claimed !== "skipped" ?
            (await tx.get(db.collection("users").doc(claimed))).data() : undefined;
          if (!claimed || claimed === "skipped" || partner?.partnerId !== uid) {
            throw new HttpsError("failed-precondition", "You have no partner to gift to.");
          }
          target = claimed;
        }

        tx.update(meRef, { treats: treats - price });
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

// Equip / unequip a cosmetic on your own dog (validates ownership). Gifts
// land in the partner's wardrobe, but only they choose to wear them.
export const equipCosmetic = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const itemId: string | null = req.data?.itemId ?? null; // null = unequip
  const category: string = req.data?.category;
  if (!category) throw new HttpsError("invalid-argument", "Missing category.");
  if (req.data?.forPartner === true) {
    throw new HttpsError("permission-denied",
      "Only your partner can choose what their dog wears.");
  }

  const meRef = db.collection("users").doc(uid);
  if (itemId) {
    if (categoryOf(itemId) !== category) {
      throw new HttpsError("invalid-argument", "Item/category mismatch.");
    }
    const owned: string[] = (await meRef.get()).data()?.ownedItemIds ?? [];
    if (!owned.includes(itemId)) {
      throw new HttpsError("failed-precondition", "Your dog doesn't own this item.");
    }
    await meRef.update({ [`equippedItemIds.${category}`]: itemId });
  } else {
    await meRef.update({ [`equippedItemIds.${category}`]: FieldValue.delete() });
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
    const meData = (await meRef.get()).data() ?? {};
    const partnerId = meData.partnerId as string | undefined;
    if (partnerId && partnerId !== "skipped" && await inDoghouse(partnerId)) {
      return { ok: true, awarded: 0 };
    }

    // Rate scales with room level (time since last release). Derived here
    // from event history; the client used to send it and any client could
    // simply claim the top rate.
    const createdMs = await accountCreatedMs(uid, meData.createdAt as Timestamp | undefined);
    const rate = roomRateFor(
      await homeStartMsFor(uid, createdMs === undefined ? undefined : Timestamp.fromMillis(createdMs)),
      Date.now());

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
        treats: treatsAfter(me, amount),
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
      if (cards <= 0) throw new HttpsError("failed-precondition", "You have no cards to redeem.");
      const claimed = me.partnerId as string | undefined;
      const partner = claimed && claimed !== "skipped" ?
        (await tx.get(db.collection("users").doc(claimed))).data() : undefined;
      const partnerId = requireMutualPartner(uid, claimed, partner);

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
    // Only mutual pairs: a one-sided partnerId would otherwise start dashes
    // with (and push to) whoever it names.
    const partnerOf = new Map<string, string | undefined>();
    paired.forEach((doc) => partnerOf.set(doc.id, doc.data().partnerId as string | undefined));
    const couples = new Map<string, [string, string]>();
    for (const [uid, partnerId] of partnerOf) {
      if (!partnerId || partnerId === "skipped" || partnerOf.get(partnerId) !== uid) continue;
      couples.set(coupleKeyOf(uid, partnerId), [uid, partnerId]);
    }

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

// ─────────────────────────────────────────────────────────────
// Engagement nudges — hourly, one per user per day, local daytime only.
// The decision logic lives in nudges.ts (pure, node-testable); this is the
// data-loading shell around it. See that file for the rules.
// ─────────────────────────────────────────────────────────────
export const engagementNudges = onSchedule(
  { schedule: "0 * * * *", timeZone: "Etc/UTC", region: REGION },
  async () => {
    const nowMs = Date.now();
    const paired = await db.collection("users").where("partnerId", "!=", "skipped").get();

    // Cache per couple so both partners share the event/history reads.
    const releaseHistory = new Map<string, Promise<FirebaseFirestore.QuerySnapshot>>();
    const historyFor = (key: string) => {
      let p = releaseHistory.get(key);
      if (!p) {
        p = db.collection("doghouseEvents")
          .where("coupleKey", "==", key).where("isActive", "==", false)
          .orderBy("startedAt", "desc").limit(40).get();
        releaseHistory.set(key, p);
      }
      return p;
    };
    const activeEventFor = async (receiverId: string): Promise<ActiveEvent | undefined> => {
      const snap = await db.collection("doghouseEvents")
        .where("receiverId", "==", receiverId).where("isActive", "==", true).limit(1).get();
      const doc = snap.docs[0];
      if (!doc) return undefined;
      const startedAt = doc.data().startedAt as Timestamp | undefined;
      return { id: doc.id, startedAtMs: startedAt?.toMillis() ?? nowMs };
    };

    let sent = 0;
    for (const meDoc of paired.docs) {
      const uid = meDoc.id;
      const me = meDoc.data();
      const partnerId = me.partnerId as string | undefined;
      if (!partnerId || partnerId === "skipped") continue;

      try {
        const privRef = privateDataRef(uid);
        const priv = (await privRef.get()).data() ?? {};
        const markers = (priv.nudges ?? {}) as NudgeMarkers;
        const gateInput = {
          hasToken: typeof priv.fcmToken === "string" && priv.fcmToken.length > 0,
          remindersEnabled: priv.remindersEnabled as boolean | undefined,
          timeZone: priv.timeZone as string | undefined,
          markers,
        };
        if (preflight(gateInput, nowMs)) continue;

        const partnerDoc = await db.collection("users").doc(partnerId).get();
        const partner = partnerDoc.data();
        // Mutual only, or a one-sided partnerId would push a stranger's
        // name and doghouse status to whoever named them.
        if (!partner || partner.partnerId !== uid) continue;

        const key = coupleKeyOf(uid, partnerId);
        const [history, myActiveEvent, partnerActiveEvent, rubDoc] = await Promise.all([
          historyFor(key), activeEventFor(uid), activeEventFor(partnerId),
          db.collection("bellyRubs").doc(partnerId).get(),
        ]);

        // Mirrors DoghouseService.homeStartDate: last release, else account creation.
        const createdMs = (d: FirebaseFirestore.DocumentData | undefined) =>
          (d?.createdAt as Timestamp | undefined)?.toMillis() ?? nowMs;
        const lastReleaseMs = (receiverId: string) => history.docs
          .filter((d) => d.data().receiverId === receiverId)
          .map((d) => (d.data().endedAt as Timestamp | undefined)?.toMillis() ?? 0)
          .reduce((a, b) => Math.max(a, b), 0);
        const homeStartMs = lastReleaseMs(uid) || createdMs(me);
        const partnerHomeStartMs = lastReleaseMs(partnerId) || createdMs(partner);

        const rub = rubDoc.data();
        const lastBellyRubSentMs = rub?.fromUserId === uid
          ? (rub.sentAt as Timestamp | undefined)?.toMillis() : undefined;

        const result = pickNudge({
          name: (me.displayName as string | undefined) ?? "You",
          partnerName: (partner.displayName as string | undefined) ?? "Your partner",
          treats: (me.treats as number | undefined) ?? 100,
          ownedItemIds: (me.ownedItemIds as string[] | undefined) ?? [],
          homeStartMs, partnerHomeStartMs, myActiveEvent, partnerActiveEvent,
          lastTreatAwardMs: (me.lastTreatAward as Timestamp | undefined)?.toMillis(),
          lastBellyRubSentMs,
          pairedSinceMs: Math.max(createdMs(me), createdMs(partner)),
          lastActiveAtMs: (priv.lastActiveAt as Timestamp | undefined)?.toMillis(),
          ...gateInput,
          cosmeticPrices: COSMETIC_PRICES,
        }, nowMs);

        if (result.decision) {
          const { title, body, data, category } = result.decision;
          await notifyUser(uid, title, body, { data, category });
          sent += 1;
          logger.info(`[nudges] ${result.decision.kind} → ${uid}`);
        }
        if (Object.keys(result.markers).length > 0) {
          await privRef.set({ nudges: result.markers }, { merge: true });
        }
      } catch (err) {
        logger.error(`[nudges] Failed for ${uid}:`, err);
      }
    }
    logger.info(`[nudges] Tick done: ${sent} sent across ${paired.size} paired users`);
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

/**
 * Close a running jailbreak vote because one of its dogs was let out by
 * their partner. Status "cancelled" drops it from every client's active
 * listener and keeps resolveExpiredVotes (active only) away from it.
 */
async function cancelVoteForReleasedDog(
  voteId: string,
  releasedId: string,
  releasedBy: string
): Promise<void> {
  const ref = db.collection("voteEvents").doc(voteId);
  const vote = await db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    if (!data || data.status !== "active") return null;
    tx.update(ref, {
      status: "cancelled",
      cancelledBecause: "released",
      releasedUserId: releasedId,
      endedAt: Timestamp.now(),
    });
    return data;
  });
  if (!vote) return;

  const name =
    (vote.doghousedUserNames?.[releasedId] as string | undefined) ??
    (await displayName(releasedId));
  // The released dog and whoever released them already know.
  const audience = ((vote.audienceIds ?? []) as string[]).filter(
    (id) => id !== releasedId && id !== releasedBy
  );
  await notifyUsers(
    audience,
    "🏠 Jailbreak vote called off",
    `${name} got let out early, so the vote's over.`,
    { data: { type: "vote" } }
  );
  logger.info(`[jailbreakVote] Cancelled ${voteId}: ${releasedId} released by partner`);
}

/**
 * After two couples part ways, stop each from seeing the other's sendings.
 * Audiences are frozen into each post at creation, so without this the
 * "you'll stop seeing each other's public sendings" promise held only for
 * posts made after the removal.
 */
async function unshareFeedPosts(keyA: string, keyB: string): Promise<void> {
  const membersOf = (key: string) => key.split("_");
  const pairs: Array<[string, string[]]> = [
    [keyA, membersOf(keyB)],
    [keyB, membersOf(keyA)],
  ];
  for (const [ownerKey, strangers] of pairs) {
    const posts = await db.collection("feedPosts")
      .where("coupleKey", "==", ownerKey).get();
    await Promise.all(posts.docs.map((p) =>
      p.ref.update({ audienceIds: FieldValue.arrayRemove(...strangers) })));
  }
}

/**
 * A couple that splits takes its friendships with it: a link names the old
 * pair in memberIds/coupleKeys, and neither ex-partner can display a couple
 * they are no longer half of.
 */
async function dissolveCoupleFriendships(coupleKey: string): Promise<void> {
  const links = await db.collection("coupleFriendships")
    .where("coupleKeys", "array-contains", coupleKey).get();
  if (links.empty) return;
  await Promise.all(links.docs.map((d) => d.ref.delete()));
  logger.info(`[friends] Dissolved ${links.size} friendship(s) of split couple ${coupleKey}`);
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

  // Both couples must be real: each partner points back. A one-sided
  // partnerId would otherwise put a stranger into both couples' audiences.
  const [myPartnerDoc, themPartnerDoc] = await Promise.all([
    db.collection("users").doc(myPartner).get(),
    db.collection("users").doc(themPartner).get(),
  ]);
  if (myPartnerDoc.data()?.partnerId !== uid) {
    throw new HttpsError("failed-precondition", "Pair with your partner first.");
  }
  if (themPartnerDoc.data()?.partnerId !== themId) {
    throw new HttpsError("failed-precondition", "That user isn't paired yet.");
  }

  if (await anyBlockBetween([uid, myPartner], [themId, themPartner])) {
    throw new HttpsError("permission-denied", "That couple can't be added.");
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
    await unshareFeedPosts(myKey, otherKey);
  }
  return { ok: true };
});

// ═════════════════════════════════════════════════════════════
// MODERATION — reports and blocks (App Store Guideline 1.2).
//
// `reports/{id}` is create-only for the reporter; onReportCreated emails
// the developer so every report is looked at by a person. `blocks/{uid}`
// holds the uids this user has blocked. It is readable by its owner and
// written only here: blocking also severs the couple friendship between
// the two couples, and addCoupleFriend refuses to re-link while any block
// exists between any of the four people.
// ═════════════════════════════════════════════════════════════

/** True when anyone in `a` blocks anyone in `b`, or the reverse. */
async function anyBlockBetween(a: string[], b: string[]): Promise<boolean> {
  const ids = [...new Set([...a, ...b])];
  const docs = await Promise.all(ids.map((id) => db.collection("blocks").doc(id).get()));
  for (const d of docs) {
    const blocked = (d.data()?.blockedUserIds ?? []) as string[];
    const owner = d.id;
    const others = a.includes(owner) ? b : b.includes(owner) ? a : [];
    if (others.some((o) => blocked.includes(o))) return true;
  }
  return false;
}

export const onReportCreated = onDocumentCreated(
  { document: "reports/{reportId}", region: REGION, secrets: [gmailAppPassword] },
  async (event) => {
    const r = event.data?.data();
    if (!r) return;
    if (!(await withinEmailQuota(r.reporterId))) {
      logger.warn(`[report] Email quota exceeded for ${r.reporterId}; stored only`);
      return;
    }
    const reporter = await displayName(r.reporterId ?? "");
    const lines = [
      `Target: ${r.targetType ?? "?"} ${r.targetId ?? "?"}`,
      `Reported user: ${r.targetUserId ?? "-"}`,
      `Reason: ${r.reason ?? "?"}`,
      "",
      r.details ?? "",
      "",
      `— ${reporter} (uid: ${r.reporterId ?? "?"}), report ${event.params.reportId}`,
    ];
    try {
      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: { user: FEEDBACK_EMAIL, pass: gmailAppPassword.value() },
      });
      await transporter.sendMail({
        from: `"DogHouse App" <${FEEDBACK_EMAIL}>`,
        to: FEEDBACK_EMAIL,
        subject: `[DogHouse REPORT] ${r.targetType ?? "content"} — ${r.reason ?? ""}`,
        text: lines.join("\n"),
      });
      logger.info(`[report] Emailed report ${event.params.reportId}`);
    } catch (err) {
      logger.error("[report] Email failed (doc is still in Firestore):", err);
    }
  }
);

export const blockUser = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const target: string = (req.data?.userId ?? "").toString();
  if (!target || target === uid) throw new HttpsError("invalid-argument", "Pick someone to block.");

  const me = (await db.collection("users").doc(uid).get()).data();
  const myPartner: string | undefined = me?.partnerId;
  if (target === myPartner) {
    throw new HttpsError("failed-precondition", "To stop seeing your partner, un-pair from Profile.");
  }

  await db.collection("blocks").doc(uid).set({
    blockedUserIds: FieldValue.arrayUnion(target),
    updatedAt: Timestamp.now(),
  }, { merge: true });

  // Sever the couple friendship, if there is one, so neither couple keeps
  // seeing the other's sendings or landing in the same jailbreak votes.
  if (myPartner && myPartner !== "skipped") {
    const them = (await db.collection("users").doc(target).get()).data();
    const themPartner: string | undefined = them?.partnerId;
    if (themPartner && themPartner !== "skipped") {
      const myKey = coupleKeyOf(uid, myPartner);
      const themKey = coupleKeyOf(target, themPartner);
      const link = await db.collection("coupleFriendships")
        .doc(friendshipIdFor(myKey, themKey)).get();
      if (link.exists) {
        await link.ref.delete();
        await unshareFeedPosts(myKey, themKey);
      }
    }
  }
  logger.info(`[block] ${uid} blocked ${target}`);
  return { ok: true };
});

export const unblockUser = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const target: string = (req.data?.userId ?? "").toString();
  if (!target) throw new HttpsError("invalid-argument", "Missing user.");
  await db.collection("blocks").doc(uid).set({
    blockedUserIds: FieldValue.arrayRemove(target),
    updatedAt: Timestamp.now(),
  }, { merge: true });
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

    // Starter treats. Accounts created before 2026-09-22 carry no `treats`
    // field; every write now goes through treatsAfter(), so absent already
    // means STARTING_TREATS — this just makes the balance explicit so the
    // console and future queries see a number. Per-doc transaction so a claim
    // landing between the scan and the write is never overwritten. The user
    // base is small; a full scan is fine.
    let seeded = 0;
    const everyone = await db.collection("users").select("treats").get();
    for (const doc of everyone.docs) {
      if (doc.get("treats") !== undefined) continue;
      try {
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          if (fresh.exists && fresh.get("treats") === undefined) {
            tx.update(doc.ref, { treats: STARTING_TREATS });
            seeded += 1;
          }
        });
      } catch (err) {
        logger.error(`[backfill] Starter treats failed for ${doc.id}:`, err);
      }
    }
    if (seeded > 0) logger.info(`[backfill] Seeded starter treats on ${seeded} account(s)`);

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
/**
 * Prune the session history. Rows exist to answer "how often does this couple
 * come back?", which no question needs more than 90 days of — and an activity
 * trail is the kind of data that should age out rather than accumulate.
 */
export const cleanupSessions = onSchedule(
  { schedule: "0 4 * * *", timeZone: "Europe/Berlin", region: REGION },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - SESSION_RETENTION_DAYS * 24 * 3_600_000);
    let deleted = 0;

    // Bounded per run so one invocation cannot blow the memory limit. Deleting
    // the oldest first means no cursor is needed: each page is gone before the
    // next query runs.
    for (let i = 0; i < 10; i++) {
      const snap = await db.collection("sessions")
        .where("at", "<", cutoff).orderBy("at").limit(500).get();
      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < 500) break;
    }
    logger.info(`[cleanupSessions] Deleted ${deleted} session rows older than ${SESSION_RETENTION_DAYS}d`);
  }
);

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

    // Premium subscriptions are dispatched BEFORE anything treat-related, so
    // a subscription event can never credit treats. Routed on product id:
    // the legacy DogHouse+ products share the entitlement and must not grant.
    const premiumProduct = premiumProductOf(event);
    if (premiumProduct) {
      await handlePremiumEvent(event, premiumProduct, res);
      return;
    }
    if (typeof event.product_id === "string" && LEGACY_SUBSCRIPTION_PRODUCTS.has(event.product_id)) {
      logger.info("[revenuecatWebhook] Ignoring legacy subscription product", {
        type: event.type, productId: event.product_id,
      });
      res.status(200).send("legacy ignored");
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
    const amount = productId && Object.prototype.hasOwnProperty.call(TREAT_PRODUCTS, productId) ?
      TREAT_PRODUCTS[productId] : undefined;

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
          tx.update(meRef, { treats: treatsAfter(me.data(), amount) });
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

/**
 * Applies a premium subscription event to users/{uid}: premiumUntil,
 * premiumProductId, premiumUpdatedAt. Same auth (checked by the caller),
 * sandbox gate and uid resolution as the treat path.
 *
 * Exactly-once via once(uid, "premium_" + event.id), tagged kind "purchase"
 * so cleanupIdempotencyKeys keeps it as long as treat-pack keys. Ordering:
 * RevenueCat can deliver out of order, so an event older than the stored
 * premiumUpdatedAt is dropped inside the transaction.
 */
async function handlePremiumEvent(
  event: Record<string, unknown>,
  productId: string,
  res: { status: (code: number) => { send: (body: string) => unknown } }
): Promise<void> {
  const type = event.type;
  const skip = premiumSkipReason(event);
  if (skip) {
    if (skip !== "no change" && skip !== "ignored") {
      logger.warn("[revenuecatWebhook] Malformed premium event", { type, id: event.id, skip });
    }
    res.status(200).send(skip);
    return;
  }

  const environment = typeof event.environment === "string" ? event.environment : "UNKNOWN";
  if (environment === "SANDBOX" && !ALLOW_SANDBOX_PURCHASES) {
    logger.info("[revenuecatWebhook] Ignoring SANDBOX premium event");
    res.status(200).send("sandbox ignored");
    return;
  }

  const uid = await resolvePurchaseUid(event);
  if (!uid) {
    logger.error("[revenuecatWebhook] No user for premium event", {
      appUserId: event.app_user_id, id: event.id, type, productId,
    });
    res.status(200).send("no such user");
    return;
  }

  try {
    const result = await once(uid, `premium_${event.id as string}`, async () => {
      const applied = await db.runTransaction(async (tx) => {
        const meRef = db.collection("users").doc(uid);
        const me = await tx.get(meRef);
        if (!me.exists) throw new Error(`user ${uid} vanished before premium update`);
        const patch = premiumPatch(event, productId, me.get("premiumUpdatedAt"));
        if (patch === "stale") return undefined;
        tx.update(meRef, patch);
        return patch;
      });
      return applied ?
        { applied: true, type: type as string, productId, environment,
          premiumUntil: applied.premiumUntil } :
        { applied: false, type: type as string, productId, environment, reason: "stale" };
    }, "purchase");

    logger.info("[revenuecatWebhook] Premium event", { uid, id: event.id, ...result });
    res.status(200).send(result.applied ? "ok" : "stale");
  } catch (e) {
    logger.error("[revenuecatWebhook] Premium update failed", { uid, id: event.id, error: e });
    res.status(500).send("error");
  }
}
