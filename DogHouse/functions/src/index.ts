import { initializeApp, getApp, App } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions/v2";
import {
  onDocumentWritten,
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

const REGION = "europe-west1";

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

async function notifyUser(
  userId: string,
  title: string,
  body: string
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
      apns: {
        headers: {
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        payload: {
          aps: { sound: "default", badge: 1 },
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
  body: string
): Promise<void> {
  await Promise.all([...new Set(userIds)].map((id) => notifyUser(id, title, body)));
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
        `${senderName}: "${reason}"`
      );
      return;
    }

    if (before?.isActive === true && after.isActive === false) {
      if (after.releasedBy === "vote") {
        await notifyUser(
          receiverId,
          "🗳️ The people have spoken!",
          "Your friends voted you out of the DogHouse. You're FREE! 🎉"
        );
      } else {
        await notifyUser(
          receiverId,
          "🏠 You've been released!",
          `${senderName} let you out! Welcome home 🎉`
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
      `${fromName} gave you a belly rub ❤️`
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
      "Who Let The Dogs Out? Tap to cast your vote!"
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
        `${fromName} wants to be your friend on DogHouse`
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
        `${toName} accepted your friend request`
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
      `${senderName} sent ${receiverName} to the DogHouse: "${post.reason}"`
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
      `${dogNames[dogs[0]]} and ${dogNames[dogs[1]]} are BOTH in the DogHouse. Vote who goes free! 🗳️`
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
          `${reactorName} supports sending ${after.receiverName} to the DogHouse`
        );
      } else if (reaction === "dog" && uid !== after.receiverId) {
        await notifyUser(
          after.receiverId,
          "🐶 Someone's on your side!",
          `${reactorName} thinks you don't belong in the DogHouse`
        );
      }
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
        }
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
      // Winners get their own richer push from onDoghouseEvent
      audience = audience.filter((id) => !winners.includes(id));

      if (winners.length === 0) {
        await notifyUsers(
          audience,
          "🗳️ The vote is over",
          "No votes were cast... nobody goes free 😬"
        );
      } else if (winners.length === 1) {
        await notifyUsers(
          audience,
          "🗳️ The people have spoken!",
          `${releasedNames[0]} has been voted out of the DogHouse! 🎉`
        );
      } else {
        await notifyUsers(
          audience,
          "🤝 It's a tie!",
          `${releasedNames.join(" and ")} both go free! JAILBREAK! 🎉`
        );
      }
      logger.info(
        `[resolveVotes] Resolved ${voteDoc.id}: winners=${winners.join(",") || "none"}`
      );
    }
  }
);
