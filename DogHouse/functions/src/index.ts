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
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

const REGION = "europe-west1";

// ── Economy constants (mirror the Swift client) ──
const MAX_GRACE_CHARGES = 3;
const GRACE_RECHARGE_HOURS = 24;
const IMMUNITY_SECONDS = 3600;
const REDEMPTION_TREATS = 15;

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

async function notifyUser(
  userId: string,
  title: string,
  body: string,
  options: NotifyOptions = {}
): Promise<void> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (!fcmToken) {
      logger.warn(`[notifyUser] No FCM token for userId=${userId}`);
      return;
    }
    logger.info(`[notifyUser] Sending "${title}" to userId=${userId}, token=${fcmToken.substring(0, 20)}...`);

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

// ─────────────────────────────────────────────────────────────
// 4. Friendships — server-side friendIds bookkeeping + notifications.
//    Clients only ever write the `status` field; syncing both users'
//    friendIds arrays happens here with admin privileges (security
//    rules forbid users writing each other's documents).
// ─────────────────────────────────────────────────────────────
export const onFriendshipWritten = onDocumentWritten(
  { document: "friendships/{friendshipId}", region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const fromUserId: string = after.fromUserId;
    const toUserId: string = after.toUserId;

    // New pending request → notify the recipient
    if (!before && after.status === "pending") {
      const fromName = await displayName(fromUserId);
      await notifyUser(
        toUserId,
        "🐾 New friend request!",
        `${fromName} wants to be your friend on DogHouse`,
        { data: { type: "friends" } }
      );
      return;
    }

    // Accepted → link both users, notify the requester
    if (before?.status === "pending" && after.status === "accepted") {
      const batch = db.batch();
      batch.update(db.collection("users").doc(fromUserId), {
        friendIds: FieldValue.arrayUnion(toUserId),
      });
      batch.update(db.collection("users").doc(toUserId), {
        friendIds: FieldValue.arrayUnion(fromUserId),
      });
      await batch.commit();

      const toName = await displayName(toUserId);
      await notifyUser(
        fromUserId,
        "🎉 Friend request accepted!",
        `${toName} accepted your friend request`,
        { data: { type: "friends" } }
      );
      return;
    }

    // Removed → unlink both users
    if (before?.status !== "removed" && after.status === "removed") {
      const batch = db.batch();
      batch.update(db.collection("users").doc(fromUserId), {
        friendIds: FieldValue.arrayRemove(toUserId),
      });
      batch.update(db.collection("users").doc(toUserId), {
        friendIds: FieldValue.arrayRemove(fromUserId),
      });
      await batch.commit();
    }
  }
);

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
    // Is a FRIEND of the freshly doghoused user also publicly in the doghouse?
    const receiverDoc = await db.collection("users").doc(receiverId).get();
    const receiverFriendIds: string[] = receiverDoc.data()?.friendIds ?? [];
    if (receiverFriendIds.length === 0) return;

    const activePosts = await db
      .collection("feedPosts")
      .where("status", "==", "active")
      .get();

    const otherPost = activePosts.docs.find(
      (d) =>
        d.id !== postId &&
        d.data().receiverId !== receiverId &&
        receiverFriendIds.includes(d.data().receiverId)
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

      // Remove this user from everyone's friend lists
      const friendsOf = await db
        .collection("users")
        .where("friendIds", "array-contains", uid)
        .get();
      await Promise.all(
        friendsOf.docs.map((d) =>
          d.ref.update({ friendIds: FieldValue.arrayRemove(uid) })
        )
      );

      // Delete owned/related documents
      await deleteWhere("partnerCodes", "userId", uid);
      await deleteWhere("friendships", "fromUserId", uid);
      await deleteWhere("friendships", "toUserId", uid);
      await deleteWhere("feedPosts", "senderId", uid);
      await deleteWhere("feedPosts", "receiverId", uid);
      await deleteWhere("doghouseEvents", "senderId", uid);
      await deleteWhere("doghouseEvents", "receiverId", uid);
      await db.collection("bellyRubs").doc(uid).delete();
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

    // Quiz: resolve once both partners have answered
    if (
      after.type === "quiz" &&
      after.status === "active" &&
      participants.length === 2 &&
      participants.every((uid) => after.answers?.[uid]?.own && after.answers?.[uid]?.guess)
    ) {
      const [a, b] = participants;
      const aRight = after.answers[a].guess === after.answers[b].own;
      const bRight = after.answers[b].guess === after.answers[a].own;
      let winnerId: string | null = null;
      if (aRight && !bRight) winnerId = a;
      if (bRight && !aRight) winnerId = b;
      await ref.update({
        status: "completed",
        winnerId,
        completedAt: Timestamp.now(),
      });
      if (!winnerId) {
        const result = aRight
          ? "You BOTH know each other too well. It's a tie! 🤝"
          : "Neither of you guessed right... awkward 😅 It's a tie!";
        await notifyUsers(participants, "🧠 Quiz over!", result, {
          data: { type: "challenge" },
        });
      }
      return; // the update above re-triggers this function for the award
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
  const reason: string = (req.data?.reason ?? "").toString().slice(0, 500);
  const suggestion: string | null = req.data?.suggestion
    ? req.data.suggestion.toString().slice(0, 500) : null;
  const isPublic = req.data?.isPublic === true;
  if (!reason) throw new HttpsError("invalid-argument", "A reason is required.");

  const meRef = db.collection("users").doc(uid);
  const meSnap = await meRef.get();
  const me = meSnap.data();
  const partnerId: string | undefined = me?.partnerId;
  if (!partnerId || partnerId === "skipped") {
    throw new HttpsError("failed-precondition", "You have no partner.");
  }

  const partnerSnap = await db.collection("users").doc(partnerId).get();
  const partner = partnerSnap.data() ?? {};
  const immunity = partner.immunityUntil as Timestamp | undefined;
  if (immunity && immunity.toMillis() > Date.now()) {
    throw new HttpsError("failed-precondition",
      "Your partner has immunity! They can't be sent yet.");
  }

  const stored = (me?.graceCharges as number | undefined) ?? MAX_GRACE_CHARGES;
  const effective = effectiveGraceCharges(stored, me?.lastGraceRecharge as Timestamp | undefined);
  if (effective <= 0) {
    throw new HttpsError("resource-exhausted",
      "You're out of grace! Wait for it to recharge (1 per day).");
  }

  const now = Timestamp.now();
  const key = coupleKeyOf(uid, partnerId);
  const eventRef = db.collection("doghouseEvents").doc();
  const batch = db.batch();
  batch.set(eventRef, {
    senderId: uid, receiverId: partnerId, reason, suggestion,
    startedAt: now, endedAt: null, isActive: true, coupleKey: key,
  });
  batch.update(meRef, {
    graceCharges: effective - 1,
    lastGraceRecharge: now,
  });

  if (isPublic) {
    const audience = await audienceForCouple(uid, partnerId);
    const postRef = db.collection("feedPosts").doc();
    batch.set(postRef, {
      eventId: eventRef.id, senderId: uid, receiverId: partnerId,
      senderName: me?.displayName ?? "Someone",
      receiverName: partner.displayName ?? "their partner",
      senderAvatarId: me?.avatarId ?? "dog_1",
      receiverAvatarId: partner.avatarId ?? "dog_1",
      reason, createdAt: now, status: "active", audienceIds: audience,
      reactions: {}, coupleKey: key,
    });
  }
  await batch.commit();
  return { ok: true, graceRemaining: effective - 1 };
});

// Release partner (or confirm redemption) — grants immunity + reward server-side.
export const releasePartner = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const eventId: string = req.data?.eventId;
  const byRedemption = req.data?.byRedemption === true;
  if (!eventId) throw new HttpsError("invalid-argument", "Missing eventId.");

  const ref = db.collection("doghouseEvents").doc(eventId);
  const snap = await ref.get();
  const ev = snap.data();
  if (!ev || ev.senderId !== uid) {
    throw new HttpsError("permission-denied", "Only the sender can release.");
  }
  if (ev.isActive !== true) return { ok: true };

  const now = Timestamp.now();
  const receiverId: string = ev.receiverId;
  const batch = db.batch();
  batch.update(ref, {
    isActive: false, endedAt: now,
    releasedBy: byRedemption ? "redemption" : "sender",
  });
  // Grant the released dog immunity (was previously a client self-write)
  batch.update(db.collection("users").doc(receiverId), {
    immunityUntil: Timestamp.fromMillis(now.toMillis() + IMMUNITY_SECONDS * 1000),
    ...(byRedemption ? { treats: FieldValue.increment(REDEMPTION_TREATS) } : {}),
  });
  await batch.commit();

  // Close any public feed post for this sending
  const posts = await db.collection("feedPosts")
    .where("eventId", "==", eventId).where("status", "==", "active").get();
  await Promise.all(posts.docs.map((p) =>
    p.ref.update({ status: "released", endedAt: now })));
  return { ok: true };
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

// Purchase a cosmetic — for self or as a gift to the partner.
export const purchaseCosmetic = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const itemId: string = req.data?.itemId;
  const forPartner = req.data?.forPartner === true;
  const price = COSMETIC_PRICES[itemId];
  if (price === undefined) throw new HttpsError("invalid-argument", "Unknown item.");

  const meRef = db.collection("users").doc(uid);
  const me = (await meRef.get()).data() ?? {};
  const treats = (me.treats as number | undefined) ?? 100;
  if (treats < price) {
    throw new HttpsError("failed-precondition", "Not enough treats! Keep playing 🦴");
  }

  let targetId = uid;
  if (forPartner) {
    const partnerId = me.partnerId as string | undefined;
    if (!partnerId || partnerId === "skipped") {
      throw new HttpsError("failed-precondition", "You have no partner to gift to.");
    }
    targetId = partnerId;
  }

  const batch = db.batch();
  batch.update(meRef, { treats: FieldValue.increment(-price) });
  batch.update(db.collection("users").doc(targetId), {
    ownedItemIds: FieldValue.arrayUnion(itemId),
  });
  await batch.commit();

  if (forPartner) {
    await notifyUser(targetId, "🎁 A gift!",
      `${me.displayName ?? "Your partner"} bought you something for your dog. Go check the shop!`,
      { data: { type: "shop" } });
  }
  return { ok: true, treatsRemaining: treats - price };
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
  const meRef = db.collection("users").doc(uid);
  const me = (await meRef.get()).data() ?? {};

  // Guard: no award while currently in the doghouse
  const active = await db.collection("doghouseEvents")
    .where("receiverId", "==", uid).where("isActive", "==", true).limit(1).get();
  if (!active.empty) return { ok: true, awarded: 0 };

  const last = me.lastTreatAward as Timestamp | undefined;
  const sinceMs = last ? last.toMillis() : Date.now() - 3_600_000;
  const hours = Math.floor((Date.now() - sinceMs) / 3_600_000);
  if (hours < 1) return { ok: true, awarded: 0 };

  // Rate scales with room level (time since last release), matching the client.
  const rate = Math.max(1, Math.min(5, Number(req.data?.treatsPerHour ?? 1)));
  const amount = hours * rate;
  await meRef.update({
    treats: FieldValue.increment(amount),
    lastTreatAward: Timestamp.now(),
  });
  return { ok: true, awarded: amount };
});

// Redeem a "Whatever I Want" card — server checks and decrements the balance.
export const redeemWishCard = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const text: string = (req.data?.text ?? "").toString().slice(0, 300);
  if (!text) throw new HttpsError("invalid-argument", "Say what you want!");

  const meRef = db.collection("users").doc(uid);
  const me = (await meRef.get()).data() ?? {};
  const cards = (me.wishCards as number | undefined) ?? 0;
  const partnerId = me.partnerId as string | undefined;
  if (cards <= 0) throw new HttpsError("failed-precondition", "You have no cards to redeem.");
  if (!partnerId || partnerId === "skipped") {
    throw new HttpsError("failed-precondition", "You have no partner.");
  }

  const batch = db.batch();
  batch.set(db.collection("wishes").doc(), {
    fromUserId: uid, toUserId: partnerId,
    fromName: me.displayName ?? "Your partner", text, createdAt: Timestamp.now(),
  });
  batch.update(meRef, { wishCards: FieldValue.increment(-1) });
  await batch.commit();
  return { ok: true, cardsRemaining: cards - 1 };
});

// ─────────────────────────────────────────────────────────────
// 12. Random photo dash — the app itself starts these. Runs a few
//     times a day; each active couple has a small chance to get one.
//     First partner to send a photo wins a Whatever-I-Want card.
// ─────────────────────────────────────────────────────────────
const PHOTO_DASH_PROMPTS = [
  "First to send a selfie wins! 🤳",
  "First to send a pic of what you're doing right now 📸",
  "First to send a photo of something that reminds you of them ❤️",
  "First to send your best silly face 🤪",
  "First to send the view from where you are 🪟",
];

export const randomPhotoDash = onSchedule(
  { schedule: "0 11,15,19 * * *", timeZone: "Europe/Berlin", region: REGION },
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

    for (const [key, [a, b]] of couples) {
      // ~35% chance per tick, and never stack with an active dash
      if (Math.random() > 0.35) continue;
      const existing = await db.collection("challenges")
        .where("coupleKey", "==", key).where("type", "==", "photo")
        .where("status", "==", "active").limit(1).get();
      if (!existing.empty) continue;

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
