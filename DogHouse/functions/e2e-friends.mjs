// End-to-end check of the friends feature against the REAL Cloud Functions
// running in the emulator: couple linking, public sendings, jailbreak vote
// creation/resolution/cancellation, un-friending, un-pairing, deletion.
//
// Run from the project root (DogHouse/):
//   firebase emulators:exec --only firestore,functions --project doghouse-5e80e \
//     "node functions/e2e-friends.mjs"
//
// Or simply: `npm run e2e:friends` in functions/ (builds first).
// The functions emulator wants every declared secret to resolve; create
// functions/.secret.local with dummy GMAIL_APP_PASSWORD and
// REVENUECAT_WEBHOOK_SECRET lines for the run (do not commit it).

import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const PROJECT = "doghouse-5e80e";
const FN = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
const db = getFirestore(initializeApp({ projectId: PROJECT }));

// ── helpers ────────────────────────────────────────────────────
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const token = (uid) => {
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: "none", typ: "JWT" })}.${b64({
    sub: uid, user_id: uid, aud: PROJECT, iat: now, exp: now + 3600,
    iss: `https://securetoken.google.com/${PROJECT}`,
    firebase: { identities: {}, sign_in_provider: "custom" },
  })}.`;
};

async function call(name, uid, data = {}) {
  const res = await fetch(`${FN}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token(uid)}` },
    body: JSON.stringify({ data: { ...data, idempotencyKey: randomUUID() } }),
  });
  const json = await res.json();
  if (json.error) {
    const err = new Error(`${name}: ${json.error.status} — ${json.error.message}`);
    err.status = json.error.status;
    throw err;
  }
  return json.result;
}

// The emulator does not expose v2 scheduled functions over HTTP, so the
// resolver's handler is invoked in-process (v2 functions expose `.run`).
// The compiled module initialises its own admin app: ensureApp() falls back
// to getApp() because this script already created the default app.
process.env.GCLOUD_PROJECT ??= PROJECT;
const fns = await import("./lib/index.js");
async function trigger(name) {
  await fns[name].run({ scheduleTime: new Date().toISOString(), jobName: name });
}

async function until(desc, probe, ms = 20000) {
  const deadline = Date.now() + ms;
  for (;;) {
    const value = await probe();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for: ${desc}`);
    await new Promise((r) => setTimeout(r, 250));
  }
}
const settle = (ms = 2500) => new Promise((r) => setTimeout(r, ms));

const key = (a, b) => [a, b].sort().join("_");
const docData = async (path) => (await db.doc(path).get()).data();
const activeVotes = async () =>
  (await db.collection("voteEvents").where("status", "==", "active").get()).docs;
const postFor = async (dog) =>
  (await db.collection("feedPosts").where("receiverId", "==", dog).get()).docs
    .sort((x, y) => y.data().createdAt.toMillis() - x.data().createdAt.toMillis())[0];

let step = 0;
const ok = (msg) => console.log(`  ✓ ${++step}. ${msg}`);

// ── fixtures ───────────────────────────────────────────────────
// Four couples. Friendships: AB↔CD, CD↔EF, AB↔GH (added during the test).
const U = {
  A: "uidA", B: "uidB", C: "uidC", D: "uidD",
  E: "uidE", F: "uidF", G: "uidG", H: "uidH",
};
const partnerOf = { A: "B", B: "A", C: "D", D: "C", E: "F", F: "E", G: "H", H: "G" };
const codeOf = (n) => `CODE${n}${n}`;

async function seed() {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  const batch = db.batch();
  for (const [n, uid] of Object.entries(U)) {
    batch.set(db.doc(`users/${uid}`), {
      displayName: n, avatarId: "dog_1", partnerId: U[partnerOf[n]],
      treats: 100, graceCharges: 3, createdAt: Timestamp.now(),
    });
    batch.set(db.doc(`users/${uid}/private/data`), { partnerCode: codeOf(n) });
    batch.set(db.doc(`partnerCodes/${codeOf(n)}`), { userId: uid });
  }
  await batch.commit();
}

// ── the run ────────────────────────────────────────────────────
console.log("friends e2e");
await seed();
await settle(1000); // let onUserPaired see the seeded docs settle

// 1. Connecting
await call("addCoupleFriend", U.A, { code: codeOf("C") });
let link = await docData(`coupleFriendships/${[key(U.A, U.B), key(U.C, U.D)].sort().join("__")}`);
assert.ok(link, "AB↔CD link exists");
assert.deepEqual(new Set(link.memberIds), new Set([U.A, U.B, U.C, U.D]));
ok("A links with C's couple by C's code — all four are members");

await call("addCoupleFriend", U.B, { code: codeOf("D") });
assert.equal((await db.collection("coupleFriendships").get()).size, 1);
ok("adding the same couple again (other partner, other code) is a no-op");

await assert.rejects(call("addCoupleFriend", U.A, { code: codeOf("B") }), /own couple/);
await assert.rejects(call("addCoupleFriend", U.A, { code: "NOPE00" }), /No couple/);
ok("own code and unknown code are rejected");

await call("addCoupleFriend", U.C, { code: codeOf("E") });
ok("C links with E's couple (AB and EF are NOT friends)");

// 2. Posting to friends
await call("sendToDoghouse", U.A, { reason: "left the milk out", isPublic: true });
let postB = await until("A's public post", () => postFor(U.B));
assert.deepEqual(new Set(postB.data().audienceIds), new Set([U.A, U.B, U.C, U.D]));
assert.equal(postB.data().coupleKey, key(U.A, U.B));
ok("A's public sending reaches exactly AB + CD");
await settle();
assert.equal((await activeVotes()).length, 0);
ok("one dog in — no vote");

await call("sendToDoghouse", U.E, { reason: "private thing", isPublic: false });
await settle();
assert.equal((await postFor(U.F)), undefined);
ok("a private sending makes no feed post");

// 3. Jailbreak vote across two friended couples
await call("sendToDoghouse", U.C, { reason: "snored", isPublic: true });
let postD = await until("C's public post", () => postFor(U.D));
assert.deepEqual(new Set(postD.data().audienceIds), new Set([U.A, U.B, U.C, U.D, U.E, U.F]));
let vote = await until("jailbreak vote", async () => (await activeVotes())[0]);
assert.deepEqual(new Set(vote.data().doghousedUserIds), new Set([U.B, U.D]));
assert.deepEqual(new Set(vote.data().audienceIds), new Set(Object.values(U).filter((u) => ![U.G, U.H].includes(u))));
assert.equal(vote.id, `joint_${[postB.id, postD.id].sort().join("_")}`);
await until("posts tagged with vote", async () =>
  (await postFor(U.B)).data().voteEventId === vote.id && (await postFor(U.D)).data().voteEventId === vote.id);
ok("B and D both in → one vote, audience is the union of both couples' friends, posts tagged");

// F is already in the doghouse privately; G sends H publicly with no friends
await call("sendToDoghouse", U.G, { reason: "no friends yet", isPublic: true });
await settle();
assert.equal((await activeVotes()).length, 1);
ok("a dog with no friended couples in the doghouse starts no vote");

// 4. Voting + resolution
await db.doc(`voteEvents/${vote.id}`).update({
  [`votes.${U.A}`]: U.B, [`votes.${U.C}`]: U.D, [`votes.${U.E}`]: U.D,
  [`votes.${U.F}`]: "uidIntruder", // would be refused by rules; resolver must ignore it too
  endsAt: Timestamp.fromMillis(Date.now() - 1000),
});
await trigger("resolveExpiredVotes");
const settled = await until("vote resolved", async () => {
  const v = await docData(`voteEvents/${vote.id}`);
  return v.status === "completed" ? v : null;
});
assert.deepEqual(settled.winnerIds, [U.D]);
assert.equal(settled.winnerId, U.D);
const evD = (await db.collection("doghouseEvents").where("receiverId", "==", U.D).get()).docs[0].data();
assert.equal(evD.isActive, false);
assert.equal(evD.releasedBy, "vote");
const userD = await docData(`users/${U.D}`);
assert.ok(userD.immunityUntil.toMillis() > Date.now(), "D got immunity");
assert.ok(userD.lastTreatAward, "D's treat clock reset");
assert.ok((await docData(`users/${U.C}`)).lastTreatAward, "C's treat clock reset");
assert.equal((await postFor(U.D)).data().status, "released");
assert.equal((await postFor(U.D)).data().releasedByVote, true);
assert.equal((await postFor(U.B)).data().status, "active");
ok("D wins 2–1 (bogus vote ignored): released by vote, immunity + treat clocks, B stays in");

// 5. Third couple joins; a new vote starts with the dog still inside
await call("addCoupleFriend", U.G, { code: codeOf("A") });
await call("releasePartner", U.G, { eventId: (await db.collection("doghouseEvents").where("receiverId", "==", U.H).get()).docs[0].id });
await db.doc(`users/${U.H}`).update({ immunityUntil: FieldValue.delete() });
await call("sendToDoghouse", U.G, { reason: "again", isPublic: true });
const postH = await until("G's second post", async () => {
  const p = await postFor(U.H);
  return p?.data().status === "active" ? p : null;
});
assert.deepEqual(new Set(postH.data().audienceIds), new Set([U.G, U.H, U.A, U.B]));
const vote2 = await until("second vote", async () => (await activeVotes())[0]);
assert.deepEqual(new Set(vote2.data().doghousedUserIds), new Set([U.B, U.H]));
ok("GH befriends AB; H in → new vote pairs H with B (whose earlier vote is over)");

// 6. Partner releases mid-vote → vote cancelled
const evB = (await db.collection("doghouseEvents").where("receiverId", "==", U.B).where("isActive", "==", true).get()).docs[0];
await call("releasePartner", U.A, { eventId: evB.id });
const cancelled = await docData(`voteEvents/${vote2.id}`);
assert.equal(cancelled.status, "cancelled");
assert.equal(cancelled.releasedUserId, U.B);
assert.equal((await activeVotes()).length, 0);
await db.doc(`voteEvents/${vote2.id}`).update({ endsAt: Timestamp.fromMillis(Date.now() - 1000) });
await trigger("resolveExpiredVotes");
await settle(1500);
assert.equal((await docData(`voteEvents/${vote2.id}`)).status, "cancelled");
const evH = (await db.collection("doghouseEvents").where("receiverId", "==", U.H).where("isActive", "==", true).get()).docs;
assert.equal(evH.length, 1, "H is still in — the resolver left the cancelled vote alone");
ok("A lets B out early → vote cancelled, resolver ignores it, H stays in");

// 7. Un-friending trims audiences both ways
await call("removeCoupleFriend", U.A, { coupleKey: key(U.G, U.H) });
assert.equal((await db.doc(`coupleFriendships/${[key(U.A, U.B), key(U.G, U.H)].sort().join("__")}`).get()).exists, false);
assert.ok(!(await postFor(U.H)).data().audienceIds.some((u) => [U.A, U.B].includes(u)), "AB dropped from GH's post");
assert.ok(!(await postFor(U.B)).data().audienceIds.some((u) => [U.G, U.H].includes(u)), "GH dropped from AB's post");
assert.ok((await postFor(U.B)).data().audienceIds.includes(U.C), "CD still see AB's post");
ok("removing a couple deletes the link and un-shares both couples' posts");

// 7b. Blocking severs the friendship and stops re-linking
await call("blockUser", U.D, { userId: U.A });
assert.deepEqual((await docData(`blocks/${U.D}`)).blockedUserIds, [U.A]);
await until("AB↔CD link severed by block", async () =>
  !(await db.doc(`coupleFriendships/${[key(U.A, U.B), key(U.C, U.D)].sort().join("__")}`).get()).exists);
for (const p of (await db.collection("feedPosts").where("coupleKey", "==", key(U.A, U.B)).get()).docs) {
  assert.ok(!p.data().audienceIds.includes(U.C) && !p.data().audienceIds.includes(U.D),
    "AB's posts no longer reach C or D");
}
await assert.rejects(call("addCoupleFriend", U.A, { code: codeOf("C") }), /can't be added/);
await assert.rejects(call("addCoupleFriend", U.C, { code: codeOf("B") }), /can't be added/);
await assert.rejects(call("blockUser", U.C, { userId: U.D }), /un-pair/);
ok("D blocks A → link gone, posts unshared, neither couple can re-add, partner can't be blocked");

await call("unblockUser", U.D, { userId: U.A });
assert.deepEqual((await docData(`blocks/${U.D}`)).blockedUserIds, []);
await call("addCoupleFriend", U.A, { code: codeOf("C") });
assert.ok(await docData(`coupleFriendships/${[key(U.A, U.B), key(U.C, U.D)].sort().join("__")}`));
ok("unblock → the couples can link again");

// 8. Un-pairing dissolves the couple's friendships
await db.doc(`users/${U.A}`).update({ partnerId: FieldValue.delete() });
await until("AB↔CD link dissolved", async () =>
  !(await db.doc(`coupleFriendships/${[key(U.A, U.B), key(U.C, U.D)].sort().join("__")}`).get()).exists);
assert.equal((await db.collection("coupleFriendships").get()).size, 1, "CD↔EF survives");
ok("A un-pairs → AB's friendships are gone, CD↔EF untouched");

// 9. Account deletion leaves other couples' votes alone
await db.doc(`deletionRequests/${U.E}`).set({ requestedAt: Timestamp.now() });
await until("E removed from vote audience", async () => {
  const v = await docData(`voteEvents/${vote.id}`);
  return v && !v.audienceIds.includes(U.E);
});
assert.ok(await docData(`voteEvents/${vote.id}`), "the vote itself survives");
await until("E's user doc gone", async () => !(await db.doc(`users/${U.E}`).get()).exists);
assert.equal((await db.collection("coupleFriendships").get()).size, 0, "CD↔EF dissolved with E");
ok("deleting E drops E from the audience without deleting the vote; EF's link goes");

console.log(`\nAll ${step} friends checks passed.`);
process.exit(0);
