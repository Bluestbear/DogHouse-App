/**
 * Firestore security rules tests.
 *
 * These run against the emulator with rules enforced. Every case here is a
 * property the app depends on for correctness or privacy; the "denied" cases
 * are the ones that matter, since a rule that is too permissive fails open
 * and nothing else in the stack will catch it.
 *
 * Run: npm test   (requires a Java runtime for the Firestore emulator)
 */

import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, deleteField,
  query, where,
} from "firebase/firestore";
import { beforeAll, afterAll, beforeEach, describe, test } from "vitest";

const HERE = dirname(fileURLToPath(import.meta.url));

// Fixture uids must not contain underscores. A coupleKey is two uids joined
// with "_", and isMyCoupleKey splits on it to recover the halves — so an
// underscore inside a uid makes parts.size() != 2 and denies every
// couple-scoped rule. Firebase Auth uids are alphanumeric, so uids like
// these match production; the earlier "uid_alice" fixtures did not, and made
// the couple-key rules look broken when they were not.
const ALICE = "uidAlice";        // paired with BOB
const BOB = "uidBob";            // paired with ALICE
const MALLORY = "uidMallory";    // unrelated third party
const COUPLE_KEY = [ALICE, BOB].sort().join("_");

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "doghouse-test",
    firestore: {
      rules: readFileSync(resolve(HERE, "../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => { await testEnv?.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  // Seed with rules disabled so fixtures don't depend on the rules under test.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", ALICE), {
      displayName: "Alice", partnerId: BOB, treats: 100, graceCharges: 3,
    });
    await setDoc(doc(db, "users", BOB), {
      displayName: "Bob", partnerId: ALICE, treats: 100, graceCharges: 3,
    });
    await setDoc(doc(db, "users", MALLORY), {
      displayName: "Mallory", treats: 100,
    });
    await setDoc(doc(db, "users", ALICE, "private", "data"), {
      partnerCode: "ABC123", fcmToken: "alice-device-token",
    });
    await setDoc(doc(db, "doghouseEvents", "evt1"), {
      senderId: ALICE, receiverId: BOB, isActive: true, reason: "left the milk out",
    });
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

// ───────────────────────── user documents ─────────────────────────

describe("users", () => {
  test("signed-in user can read a single profile by id", async () => {
    await assertSucceeds(getDoc(doc(as(MALLORY), "users", ALICE)));
  });

  test("NOBODY can enumerate the user table", async () => {
    // This is the regression guard for the pairing-code harvest: `list` would
    // hand every account's document to any signed-in user.
    await assertFails(getDocs(collection(as(MALLORY), "users")));
  });

  test("anonymous users cannot read profiles", async () => {
    await assertFails(getDoc(doc(anon(), "users", ALICE)));
  });

  test("owner cannot grant themselves treats", async () => {
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { treats: 99999 }));
  });

  test("owner cannot grant themselves immunity or grace", async () => {
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { graceCharges: 99 }));
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { wishCards: 99 }));
  });

  test("owner can change a non-economy field", async () => {
    await assertSucceeds(updateDoc(doc(as(ALICE), "users", ALICE), { avatarId: "dog_4" }));
  });

  test("a stranger cannot write to someone else's profile", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "users", ALICE), { displayName: "pwned" }));
  });

  test("secrets cannot be written back onto the public document", async () => {
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { fcmToken: "leak" }));
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { partnerCode: "LEAK01" }));
  });

  // The exact shape AuthService.bootstrapProfileIfNeeded writes (1.1 (5)).
  const bootstrap = (uid) => ({
    id: uid, displayName: "Newbie", friendIds: [], createdAt: new Date(),
    graceCharges: 3, lastGraceRecharge: new Date(),
    tourComplete: false, onboardingComplete: false,
  });

  test("a new account can create its profile in the shape the app writes", async () => {
    await assertSucceeds(setDoc(doc(as("uidNew"), "users", "uidNew"), bootstrap("uidNew")));
  });

  test("a new profile cannot be born holding economy fields or a partner", async () => {
    for (const extra of [
      { treats: 99999 }, { wishCards: 50 }, { immunityUntil: new Date(Date.now() + 1e10) },
      { ownedItemIds: ["hat_crown"] }, { lastTreatAward: new Date(0) }, { graceCharges: 99 },
      { partnerId: ALICE }, { fcmToken: "t" }, { partnerCode: "ABC123" },
    ]) {
      await assertFails(setDoc(doc(as("uidNew"), "users", "uidNew"),
        { ...bootstrap("uidNew"), ...extra }));
    }
  });

  test("owner cannot backdate createdAt to buy a higher treat rate", async () => {
    await assertFails(updateDoc(doc(as(ALICE), "users", ALICE), { createdAt: new Date(0) }));
  });

  test("owner can still set the fields the app updates", async () => {
    await assertSucceeds(updateDoc(doc(as(ALICE), "users", ALICE), {
      displayName: "Al", tourComplete: true, onboardingComplete: true,
      termsAcceptedVersion: "1", termsAcceptedAt: new Date(),
    }));
    await assertSucceeds(updateDoc(doc(as(ALICE), "users", ALICE), { partnerId: deleteField() }));
  });

  test("the migration may REMOVE legacy secrets", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "users", ALICE), {
        fcmToken: "legacy", partnerCode: "OLD123",
      });
    });
    await assertSucceeds(updateDoc(doc(as(ALICE), "users", ALICE), {
      fcmToken: deleteField(), partnerCode: deleteField(),
    }));
  });
});

// ───────────────────────── private subdocument ─────────────────────────

describe("users/{uid}/private/data", () => {
  test("owner can read their own pairing code and token", async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), "users", ALICE, "private", "data")));
  });

  test("a PARTNER cannot read the private document", async () => {
    await assertFails(getDoc(doc(as(BOB), "users", ALICE, "private", "data")));
  });

  test("a stranger cannot read the private document", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "users", ALICE, "private", "data")));
  });

  test("owner can rotate their push token", async () => {
    await assertSucceeds(updateDoc(
      doc(as(ALICE), "users", ALICE, "private", "data"), { fcmToken: "new-token" }));
  });

  test("pairing code is immutable once issued", async () => {
    await assertFails(updateDoc(
      doc(as(ALICE), "users", ALICE, "private", "data"), { partnerCode: "ZZZ999" }));
  });
});

// ───────────────────────── pairing codes ─────────────────────────

describe("partnerCodes", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "partnerCodes", "ABC123"), { userId: ALICE });
    });
  });

  test("a code can be looked up by id (pairing in 1.1 (5))", async () => {
    await assertSucceeds(getDoc(doc(as(MALLORY), "partnerCodes", "ABC123")));
  });

  test("NOBODY can list the codes — that is every code plus its uid", async () => {
    await assertFails(getDocs(collection(as(MALLORY), "partnerCodes")));
  });

  test("a code can only be claimed for yourself", async () => {
    await assertSucceeds(setDoc(doc(as(MALLORY), "partnerCodes", "MAL234"), { userId: MALLORY }));
    await assertFails(setDoc(doc(as(MALLORY), "partnerCodes", "MAL345"), { userId: ALICE }));
  });
});

// ───────────────────────── doghouse events ─────────────────────────

describe("doghouseEvents", () => {
  test("participants can read their own event", async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), "doghouseEvents", "evt1")));
    await assertSucceeds(getDoc(doc(as(BOB), "doghouseEvents", "evt1")));
  });

  test("an outsider cannot read a couple's event", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "doghouseEvents", "evt1")));
  });

  test("clients cannot create events directly", async () => {
    // Creation must go through sendToDoghouse, which spends a grace charge.
    await assertFails(setDoc(doc(as(ALICE), "doghouseEvents", "forged"), {
      senderId: ALICE, receiverId: BOB, isActive: true, reason: "free sending",
    }));
  });

  test("the dog cannot release themselves by editing the event", async () => {
    await assertFails(updateDoc(doc(as(BOB), "doghouseEvents", "evt1"), { isActive: false }));
  });
});

// ───────────────────────── belly rubs ─────────────────────────

describe("bellyRubs", () => {
  test("partner can send a rub stamped with their own uid", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "bellyRubs", BOB), {
      fromUserId: ALICE, fromDisplayName: "Alice", sentAt: new Date(),
    }));
  });

  test("partner cannot spoof who the rub came from", async () => {
    await assertFails(setDoc(doc(as(ALICE), "bellyRubs", BOB), {
      fromUserId: MALLORY, fromDisplayName: "Someone Else", sentAt: new Date(),
    }));
  });

  test("a stranger cannot send a rub", async () => {
    await assertFails(setDoc(doc(as(MALLORY), "bellyRubs", BOB), {
      fromUserId: MALLORY, fromDisplayName: "Mallory", sentAt: new Date(),
    }));
  });

  test("only the receiver reads their rub doc", async () => {
    await assertSucceeds(getDoc(doc(as(BOB), "bellyRubs", BOB)));
    await assertFails(getDoc(doc(as(MALLORY), "bellyRubs", BOB)));
  });
});

// ───────────────────────── couple-scoped docs ─────────────────────────

describe("coupleTasks / coupleMeta", () => {
  test("real partners can use their couple document", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "coupleMeta", COUPLE_KEY),
      { anniversary: new Date() }));
  });

  test("a stranger cannot fabricate a couple doc keyed to someone else", async () => {
    // Previously the rule only checked that the caller's uid appeared in the
    // key, so anyone could pair themselves to a stranger in this namespace.
    const forged = [MALLORY, ALICE].sort().join("_");
    await assertFails(setDoc(doc(as(MALLORY), "coupleMeta", forged),
      { anniversary: new Date() }));
  });

  test("an outsider cannot read a couple's tasks", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "coupleTasks", COUPLE_KEY)));
  });
});

describe("achievements", () => {
  test("a partner can unlock a badge and bump a counter", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "achievements", COUPLE_KEY),
      { unlocked: { firstOffence: new Date() }, counters: { roses: 1 } }, { merge: true }));
  });

  test("the other partner reads it", async () => {
    await assertSucceeds(getDoc(doc(as(BOB), "achievements", COUPLE_KEY)));
  });

  test("a stranger can neither read nor forge the couple's badges", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "achievements", COUPLE_KEY)));
    await assertFails(setDoc(doc(as(MALLORY), "achievements", COUPLE_KEY),
      { unlocked: { dogPalace: new Date() } }, { merge: true }));
  });
});

// ───────────────────────── onboarding tasks ─────────────────────────

describe("onboardingTasks", () => {
  test("a partner can attach a listener BEFORE the doc exists", async () => {
    // OnboardingService attaches its snapshot listener in init — before
    // either partner has submitted, so before the document exists. A rule
    // that reaches into resource.data denies the read on a missing document
    // and Firestore then tears the listener down for good: neither partner
    // ever sees the other's submission and both sit on "waiting for your
    // partner" forever.
    await assertSucceeds(getDoc(doc(as(ALICE), "onboardingTasks", COUPLE_KEY)));
  });

  test("both partners can write their own half, in either order", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "onboardingTasks", COUPLE_KEY),
      { coupleId: COUPLE_KEY, user1Submitted: true }, { merge: true }));
    await assertSucceeds(setDoc(doc(as(BOB), "onboardingTasks", COUPLE_KEY),
      { user2Submitted: true }, { merge: true }));
    await assertSucceeds(getDoc(doc(as(BOB), "onboardingTasks", COUPLE_KEY)));
  });

  // user1 is the lower uid (OnboardingService.sortedIds): here ALICE.
  const ob = () => doc(as(ALICE), "onboardingTasks", COUPLE_KEY);
  const obBob = () => doc(as(BOB), "onboardingTasks", COUPLE_KEY);
  const header = { id: COUPLE_KEY, coupleId: COUPLE_KEY, user1Id: ALICE, user2Id: BOB };
  const finalTasks = [{ id: "t1", title: "Dishes", suggestedBy: ALICE, isAppSuggestion: false }];

  test("the whole negotiation, as the app writes it, succeeds", async () => {
    const tasks = [{ id: "t1", title: "Dishes" }];
    await assertSucceeds(setDoc(ob(), { ...header, user1Tasks: tasks, user1Submitted: true }, { merge: true }));
    await assertSucceeds(setDoc(obBob(), { ...header, user2Tasks: tasks, user2Submitted: true }, { merge: true }));
    await assertSucceeds(setDoc(ob(), { ...header, user1Strikes: [], user1ReviewComplete: true }, { merge: true }));
    await assertSucceeds(setDoc(obBob(), { ...header, user2Strikes: [], user2ReviewComplete: true }, { merge: true }));
    await assertSucceeds(setDoc(ob(), { ...header, finalTasks }, { merge: true }));
    // The partner computes the identical list; rewriting the same bytes is fine.
    await assertSucceeds(setDoc(obBob(), { ...header, finalTasks }, { merge: true }));
    await assertSucceeds(setDoc(ob(), { ...header, user1Confirmed: true }, { merge: true }));
    await assertSucceeds(setDoc(obBob(), { ...header, user2Confirmed: true }, { merge: true }));
  });

  test("a partner cannot submit or confirm for the other half", async () => {
    await assertFails(setDoc(obBob(), { ...header, user1Confirmed: true }, { merge: true }));
    await assertFails(setDoc(obBob(), { ...header, user1Submitted: true, user1Tasks: [] }, { merge: true }));
    await assertFails(setDoc(ob(), { ...header, user2Confirmed: true }, { merge: true }));
  });

  test("the final list needs both reviews and is write-once", async () => {
    await assertFails(setDoc(ob(), { ...header, finalTasks }, { merge: true }));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "onboardingTasks", COUPLE_KEY), {
        ...header, user1ReviewComplete: true, user2ReviewComplete: true, finalTasks,
      });
    });
    await assertFails(setDoc(obBob(), {
      ...header, finalTasks: [{ id: "x", title: "Alice does everything", suggestedBy: "app", isAppSuggestion: true }],
    }, { merge: true }));
  });

  test("the header must name this couple", async () => {
    await assertFails(setDoc(ob(), { ...header, user1Id: MALLORY }, { merge: true }));
  });

  test("an outsider cannot read or fabricate a couple's task doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "onboardingTasks", COUPLE_KEY), {
        coupleId: COUPLE_KEY, user1Id: ALICE, user2Id: BOB,
      });
    });
    await assertFails(getDoc(doc(as(MALLORY), "onboardingTasks", COUPLE_KEY)));

    // Mallory is unpaired, so no key containing her uid is hers to write.
    const forged = [MALLORY, ALICE].sort().join("_");
    await assertFails(setDoc(doc(as(MALLORY), "onboardingTasks", forged),
      { user1Submitted: true }));
  });
});

// ───────────────────────── couple friendships ─────────────────────────

describe("coupleFriendships", () => {
  const THEM_A = "uidCarol";
  const THEM_B = "uidDave";
  const THEIR_KEY = [THEM_A, THEM_B].sort().join("_");
  const LINK_ID = [COUPLE_KEY, THEIR_KEY].sort().join("__");

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users", THEM_A), { displayName: "Carol", partnerId: THEM_B });
      await setDoc(doc(db, "users", THEM_B), { displayName: "Dave", partnerId: THEM_A });
      // Written by the addCoupleFriend callable, which runs as admin.
      await setDoc(doc(db, "coupleFriendships", LINK_ID), {
        coupleKeys: [COUPLE_KEY, THEIR_KEY],
        memberIds: [ALICE, BOB, THEM_A, THEM_B],
        createdAt: new Date(),
      });
    });
  });

  test("a member can run the exact query FriendService listens with", async () => {
    const q = query(
      collection(as(ALICE), "coupleFriendships"),
      where("memberIds", "array-contains", ALICE)
    );
    await assertSucceeds(getDocs(q));
  });

  test("a member can read the linked couple's profiles", async () => {
    // rebuildCouples splits the other coupleKey and fetches both profiles
    // one document at a time, because `list` on /users is denied.
    await assertSucceeds(getDoc(doc(as(ALICE), "users", THEM_A)));
    await assertSucceeds(getDoc(doc(as(ALICE), "users", THEM_B)));
  });

  test("a non-member cannot read the link, even with the same query shape", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "coupleFriendships", LINK_ID)));
    const q = query(
      collection(as(MALLORY), "coupleFriendships"),
      where("memberIds", "array-contains", ALICE)
    );
    await assertFails(getDocs(q));
  });

  test("clients cannot forge a friendship", async () => {
    await assertFails(setDoc(doc(as(MALLORY), "coupleFriendships", "forged"), {
      coupleKeys: [COUPLE_KEY, THEIR_KEY],
      memberIds: [MALLORY, ALICE, BOB, THEM_A],
    }));
  });
});

// ───────────────────────── feed posts ─────────────────────────

describe("feedPosts", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "feedPosts", "post1"), {
        senderId: ALICE, receiverId: BOB, audienceIds: [ALICE, BOB, MALLORY],
        reactions: {}, roasts: {}, status: "active",
      });
    });
  });

  test("audience member may add their own reaction", async () => {
    await assertSucceeds(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`reactions.${MALLORY}`]: "dog" }));
  });

  test("audience member cannot react on someone else's behalf", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`reactions.${ALICE}`]: "dog" }));
  });

  test("a canned roast can be set and cleared", async () => {
    await assertSucceeds(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`roasts.${MALLORY}`]: "Guilty as charged 🐕‍🦺" }));
    await assertSucceeds(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`roasts.${MALLORY}`]: deleteField() }));
  });

  test("a roast cannot carry an essay onto the dog's lock screen", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`roasts.${MALLORY}`]: "x".repeat(61) }));
    await assertFails(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`roasts.${MALLORY}`]: { nested: true } }));
  });

  test("a reaction is one of the two kinds; toggling off is allowed", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`reactions.${MALLORY}`]: "anything else" }));
    await assertSucceeds(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`reactions.${MALLORY}`]: "back" }));
    await assertSucceeds(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { [`reactions.${MALLORY}`]: deleteField() }));
  });

  test("audience member cannot rewrite the post itself", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "feedPosts", "post1"),
      { reason: "something else entirely" }));
  });

  test("clients cannot create feed posts directly", async () => {
    await assertFails(setDoc(doc(as(ALICE), "feedPosts", "forged"), {
      senderId: ALICE, receiverId: BOB, audienceIds: [ALICE],
    }));
  });
});

// ───────────────────────── jailbreak votes ─────────────────────────

describe("voteEvents", () => {
  const CAROL = "uidCarol"; // the other couple's dog, in the doghouse too
  const OUTSIDER = "uidEve";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      // Written by onFeedPostCreated (admin). BOB and CAROL are the dogs;
      // ALICE, MALLORY and CAROL's couple make up the audience.
      await setDoc(doc(db, "voteEvents", "vote1"), {
        type: "joint_doghouse", status: "active",
        doghousedUserIds: [BOB, CAROL],
        audienceIds: [ALICE, BOB, MALLORY, CAROL],
        votes: {}, startedAt: new Date(), endsAt: new Date(Date.now() + 1800_000),
      });
      await setDoc(doc(db, "voteEvents", "vote2"), {
        type: "joint_doghouse", status: "completed",
        doghousedUserIds: [BOB, CAROL], audienceIds: [ALICE, BOB, MALLORY, CAROL],
        votes: {}, startedAt: new Date(), endsAt: new Date(),
      });
    });
  });

  test("an audience member can run the exact query VoteService listens with", async () => {
    const q = query(
      collection(as(MALLORY), "voteEvents"),
      where("audienceIds", "array-contains", MALLORY),
      where("status", "==", "active")
    );
    await assertSucceeds(getDocs(q));
  });

  test("an outsider cannot read the vote, even with the same query shape", async () => {
    await assertFails(getDoc(doc(as(OUTSIDER), "voteEvents", "vote1")));
    const q = query(
      collection(as(OUTSIDER), "voteEvents"),
      where("audienceIds", "array-contains", MALLORY),
      where("status", "==", "active")
    );
    await assertFails(getDocs(q));
  });

  test("an audience member may vote for one of the dogs", async () => {
    await assertSucceeds(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${MALLORY}`]: CAROL }));
  });

  test("a dog may vote in their own jailbreak", async () => {
    await assertSucceeds(updateDoc(doc(as(BOB), "voteEvents", "vote1"),
      { [`votes.${BOB}`]: BOB }));
  });

  test("a vote must name a dog in THIS vote — no voting yourself free", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${MALLORY}`]: MALLORY }));
    await assertFails(updateDoc(doc(as(ALICE), "voteEvents", "vote1"),
      { [`votes.${ALICE}`]: ALICE }));
  });

  test("nobody can vote on someone else's behalf", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${ALICE}`]: CAROL }));
  });

  test("an outsider cannot vote", async () => {
    await assertFails(updateDoc(doc(as(OUTSIDER), "voteEvents", "vote1"),
      { [`votes.${OUTSIDER}`]: CAROL }));
  });

  test("clients cannot settle the vote themselves", async () => {
    await assertFails(updateDoc(doc(as(ALICE), "voteEvents", "vote1"),
      { status: "completed", winnerId: BOB }));
    await assertFails(updateDoc(doc(as(ALICE), "voteEvents", "vote1"),
      { endsAt: new Date() }));
  });

  test("a vote cannot be changed once cast", async () => {
    await assertSucceeds(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${MALLORY}`]: CAROL }));
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${MALLORY}`]: BOB }));
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote1"),
      { [`votes.${MALLORY}`]: deleteField() }));
  });

  test("no votes after endsAt, even before the resolver has run", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "voteEvents", "vote3"), {
        type: "joint_doghouse", status: "active",
        doghousedUserIds: [BOB, CAROL], audienceIds: [ALICE, BOB, MALLORY, CAROL],
        votes: {}, startedAt: new Date(), endsAt: new Date(Date.now() - 1000),
      });
    });
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote3"),
      { [`votes.${MALLORY}`]: CAROL }));
  });

  test("no votes once the vote has closed", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "voteEvents", "vote2"),
      { [`votes.${MALLORY}`]: CAROL }));
  });

  test("clients cannot start a vote", async () => {
    await assertFails(setDoc(doc(as(ALICE), "voteEvents", "forged"), {
      type: "joint_doghouse", status: "active", doghousedUserIds: [BOB],
      audienceIds: [ALICE], votes: {},
    }));
  });
});

// ───────────────────────── challenges ─────────────────────────

describe("challenges", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "challenges", "quiz1"), {
        coupleKey: COUPLE_KEY, type: "quiz", participants: [ALICE, BOB],
        status: "active", createdBy: ALICE, answers: { [ALICE]: { own: "Italy" } },
      });
    });
  });

  test("participant may submit their own answer", async () => {
    await assertSucceeds(updateDoc(doc(as(BOB), "challenges", "quiz1"),
      { [`answers.${BOB}`]: { own: "Italy" } }));
  });

  test("participant cannot rewrite their partner's answer to force a match", async () => {
    await assertFails(updateDoc(doc(as(BOB), "challenges", "quiz1"),
      { [`answers.${ALICE}`]: { own: "Sweden" } }));
  });

  test("a participant cannot award themselves a card", async () => {
    await assertFails(updateDoc(doc(as(BOB), "challenges", "quiz1"), { cardAwarded: true }));
  });

  test("an outsider cannot read the challenge", async () => {
    await assertFails(getDoc(doc(as(MALLORY), "challenges", "quiz1")));
  });

  // The anniversary race gets this year's deterministic doc before creating
  // it. A rule that dereferences resource.data denies that get on a missing
  // doc, which made the race unwinnable (QA-055, 2026-09-22).
  test("a participant can check whether this year's anniversary race exists yet", async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), "challenges", `anniv_${COUPLE_KEY}_2026`)));
  });

  const YEAR = new Date().getUTCFullYear();
  // The exact shape ChallengeService.wishHappyAnniversary writes.
  const race = {
    coupleKey: COUPLE_KEY, type: "anniversary", title: `Anniversary Race ${YEAR}`,
    prompt: "First to wish a happy anniversary wins!", participants: [ALICE, BOB],
    status: "completed", createdBy: ALICE, winnerId: ALICE,
    createdAt: new Date(), completedAt: new Date(),
  };

  test("first tap creates the anniversary race; an outsider cannot", async () => {
    await assertFails(setDoc(doc(as(MALLORY), "challenges", "anniv_x"),
      { ...race, createdBy: MALLORY }));
    await assertSucceeds(setDoc(doc(as(ALICE), "challenges", `anniv_${COUPLE_KEY}_${YEAR}`), race));
  });

  test("the race can't be minted again under another id or year", async () => {
    await assertFails(setDoc(doc(as(ALICE), "challenges", "anniv_whatever"), race));
    await assertFails(setDoc(doc(as(ALICE), "challenges", `anniv_${COUPLE_KEY}_${YEAR + 5}`), race));
    await assertFails(setDoc(doc(as(ALICE), "challenges", `anniv_${COUPLE_KEY}_${YEAR}`),
      { ...race, winnerId: BOB }));
  });

  test("a quiz can be created in the shape the app writes", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "challenges", "quiz2"), {
      coupleKey: COUPLE_KEY, type: "quiz", title: "Couple Quiz", prompt: "Where to?",
      options: ["Italy", "Sweden"], createdBy: ALICE, participants: [ALICE, BOB],
      status: "active", answers: { [ALICE]: { own: "Italy" } }, createdAt: new Date(),
    }));
  });

  test("nobody can create a challenge that is already won (card minting)", async () => {
    for (const type of ["quiz", "photo", "anything"]) {
      await assertFails(setDoc(doc(as(ALICE), "challenges", `forged_${type}`), {
        coupleKey: COUPLE_KEY, type, participants: [ALICE, BOB],
        status: "completed", createdBy: ALICE, winnerId: ALICE,
      }));
    }
    // Nor start a photo dash — only the scheduler does that.
    await assertFails(setDoc(doc(as(ALICE), "challenges", "photo_forged"), {
      coupleKey: COUPLE_KEY, type: "photo", participants: [ALICE, BOB],
      status: "active", createdBy: ALICE,
    }));
  });

  test("a challenge must belong to my own couple", async () => {
    const strangers = [MALLORY, ALICE].sort().join("_");
    await assertFails(setDoc(doc(as(MALLORY), "challenges", "quiz3"), {
      coupleKey: strangers, type: "quiz", participants: [MALLORY, ALICE],
      status: "active", createdBy: MALLORY, answers: {},
    }));
    // Mismatched key and participants.
    await assertFails(setDoc(doc(as(ALICE), "challenges", "quiz4"), {
      coupleKey: COUPLE_KEY, type: "quiz", participants: [ALICE, MALLORY],
      status: "active", createdBy: ALICE, answers: {},
    }));
  });

  test("a quiz cannot be completed or won by a client", async () => {
    await assertFails(updateDoc(doc(as(BOB), "challenges", "quiz1"),
      { status: "completed", winnerId: BOB }));
    await assertFails(updateDoc(doc(as(BOB), "challenges", "quiz1"),
      { [`answers.${BOB}`]: { own: "Italy" }, winnerId: BOB }));
  });

  test("a photo dash is claimed by its sender, for themselves only", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "challenges", "dash1"), {
        coupleKey: COUPLE_KEY, type: "photo", participants: [ALICE, BOB],
        status: "active", createdBy: "system", createdAt: new Date(),
      });
    });
    const claim = { status: "completed", photoData: "aGVsbG8=", completedAt: new Date() };
    await assertFails(updateDoc(doc(as(BOB), "challenges", "dash1"), { ...claim, winnerId: ALICE }));
    await assertFails(updateDoc(doc(as(BOB), "challenges", "dash1"),
      { ...claim, winnerId: BOB, cardAwarded: true }));
    await assertFails(updateDoc(doc(as(MALLORY), "challenges", "dash1"), { ...claim, winnerId: MALLORY }));
    await assertSucceeds(updateDoc(doc(as(BOB), "challenges", "dash1"), { ...claim, winnerId: BOB }));
    // Completed is final: the partner cannot re-claim it.
    await assertFails(updateDoc(doc(as(ALICE), "challenges", "dash1"), { ...claim, winnerId: ALICE }));
  });
});

// ───────────────────────── server-only collections ─────────────────────────

describe("wishes", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "wishes", "w1"),
        { fromUserId: ALICE, toUserId: BOB, text: "breakfast in bed" });
    });
  });

  test("sender and receiver can read a wish; a stranger cannot", async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), "wishes", "w1")));
    await assertSucceeds(getDoc(doc(as(BOB), "wishes", "w1")));
    await assertFails(getDoc(doc(as(MALLORY), "wishes", "w1")));
  });

  test("a wish can NOT be created by a client — only redeemWishCard may", async () => {
    // A direct create used to skip the card-balance check entirely.
    await assertFails(setDoc(doc(as(ALICE), "wishes", "w2"),
      { fromUserId: ALICE, toUserId: BOB, text: "free wish" }));
  });

  test("only the receiver may mark a wish fulfilled, and nothing else", async () => {
    await assertSucceeds(updateDoc(doc(as(BOB), "wishes", "w1"), { fulfilled: true }));
    await assertFails(updateDoc(doc(as(ALICE), "wishes", "w1"), { fulfilled: true }));
    await assertFails(updateDoc(doc(as(BOB), "wishes", "w1"), { text: "rewritten" }));
  });
});

describe("reports and blocks", () => {
  test("a user can file a report as themselves, within limits", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "reports", "r1"), {
      reporterId: ALICE, targetType: "feedPost", targetId: "post1",
      targetUserId: MALLORY, reason: "harassment", details: "rude", createdAt: new Date(),
    }));
    await assertFails(setDoc(doc(as(ALICE), "reports", "r2"), {
      reporterId: BOB, targetType: "feedPost", targetId: "post1", reason: "spoofed",
    }));
    await assertFails(setDoc(doc(as(ALICE), "reports", "r3"), {
      reporterId: ALICE, targetType: "everything", targetId: "x", reason: "bad type",
    }));
    await assertFails(setDoc(doc(as(ALICE), "reports", "r4"), {
      reporterId: ALICE, targetType: "user", targetId: MALLORY, reason: "x".repeat(101),
    }));
  });

  test("reports are never readable by clients", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "reports", "r1"),
        { reporterId: ALICE, targetType: "user", targetId: MALLORY, reason: "spam" });
    });
    await assertFails(getDoc(doc(as(ALICE), "reports", "r1")));
    await assertFails(getDocs(collection(as(MALLORY), "reports")));
  });

  test("a block list is readable by its owner only and never client-writable", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "blocks", ALICE), { blockedUserIds: [MALLORY] });
    });
    await assertSucceeds(getDoc(doc(as(ALICE), "blocks", ALICE)));
    await assertFails(getDoc(doc(as(MALLORY), "blocks", ALICE)));
    await assertFails(updateDoc(doc(as(ALICE), "blocks", ALICE), { blockedUserIds: [] }));
    await assertFails(setDoc(doc(as(BOB), "blocks", BOB), { blockedUserIds: [ALICE] }));
  });
});

describe("server-only collections", () => {
  test("idempotency keys are completely inaccessible to clients", async () => {
    await assertFails(getDoc(doc(as(ALICE), "idempotencyKeys", `${ALICE}_key1`)));
    await assertFails(setDoc(doc(as(ALICE), "idempotencyKeys", `${ALICE}_key1`), { status: "done" }));
  });

  test("a user may request their own deletion but not someone else's", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "deletionRequests", ALICE), { requestedAt: new Date() }));
    await assertFails(setDoc(doc(as(MALLORY), "deletionRequests", ALICE), { requestedAt: new Date() }));
  });

  test("feedback must be attributed to the sender", async () => {
    await assertSucceeds(setDoc(doc(as(ALICE), "feedback", "f1"),
      { fromUserId: ALICE, text: "great app" }));
    // The exact shape InputTabView writes.
    await assertSucceeds(setDoc(doc(as(ALICE), "feedback", "f3"), {
      fromUserId: ALICE, fromName: "Alice", type: "suggestion",
      text: "x".repeat(2000), createdAt: new Date(),
    }));
    await assertFails(setDoc(doc(as(ALICE), "feedback", "f4"),
      { fromUserId: ALICE, text: "x".repeat(2001) }));
    await assertFails(setDoc(doc(as(ALICE), "feedback", "f5"),
      { fromUserId: ALICE, text: "hi", attachment: "x".repeat(500000) }));
    await assertFails(setDoc(doc(as(ALICE), "feedback", "f2"),
      { fromUserId: BOB, text: "impersonated" }));
  });

  test("nothing in the database may be deleted by a client", async () => {
    await assertFails(deleteDoc(doc(as(ALICE), "users", ALICE)));
    await assertFails(deleteDoc(doc(as(ALICE), "doghouseEvents", "evt1")));
  });
});

// ───────────────────────── staged: partnerId lockdown ─────────────────────────
//
// Enable together with the STAGED rule under /users (and the isMyCoupleKey
// clause) once no build older than 1.1 (6) is in use. Until then 1.1 (5)
// pairs by writing partnerId directly and these would fail by design.
describe.skip("staged partnerId lockdown", () => {
  test("nobody can point partnerId at a stranger", async () => {
    await assertFails(updateDoc(doc(as(MALLORY), "users", MALLORY), { partnerId: ALICE }));
  });

  test("unpairing and skipping stay open", async () => {
    await assertSucceeds(updateDoc(doc(as(MALLORY), "users", MALLORY), { partnerId: "skipped" }));
    await assertSucceeds(updateDoc(doc(as(ALICE), "users", ALICE), { partnerId: deleteField() }));
  });

  test("an ex who re-points at me cannot reach our old couple docs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "coupleMeta", COUPLE_KEY), { anniversary: new Date() });
      await updateDoc(doc(ctx.firestore(), "users", BOB), { partnerId: deleteField() });
    });
    await assertFails(getDoc(doc(as(ALICE), "coupleMeta", COUPLE_KEY)));
  });
});
