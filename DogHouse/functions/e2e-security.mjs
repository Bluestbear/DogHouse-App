// End-to-end check of the 2026-09-23 security fixes against the REAL Cloud
// Functions in the emulator: code-checked pairing,
// mutual-partner checks, challenge card provenance, the redemption reward
// gate and the createdAt clamp.
//
// Run: `npm run e2e:security` in functions/ (builds first). Needs the Auth
// emulator too, because the createdAt clamp reads the Auth account. Like the
// other e2e scripts it needs functions/.secret.local with dummy secrets.

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
const PROJECT = "doghouse-5e80e";
const FN = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
const app = initializeApp({ projectId: PROJECT });
const db = getFirestore(app);
const auth = getAuth(app);

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

async function rejects(promise, status) {
  try {
    await promise;
  } catch (err) {
    assert.equal(err.status, status, err.message);
    return;
  }
  assert.fail(`expected ${status}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const user = async (uid) => (await db.collection("users").doc(uid).get()).data();

async function waitFor(check, what, ms = 10_000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    if (await check()) return;
    await sleep(250);
  }
  assert.fail(`timed out waiting for ${what}`);
}

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

// ── fixtures ───────────────────────────────────────────────────
const A = "secA", B = "secB", C = "secC", D = "secD";
for (const uid of [A, B, C, D]) {
  await auth.createUser({ uid }).catch(() => undefined);
  await db.collection("users").doc(uid).set({
    displayName: uid, createdAt: Timestamp.now(), graceCharges: 3,
  });
}
await db.collection("partnerCodes").doc("BBBBBB").set({ userId: B });
await db.collection("partnerCodes").doc("CCCCCC").set({ userId: C });

console.log("security e2e");

await test("pairWithCode links both halves atomically", async () => {
  const r = await call("pairWithCode", A, { code: "bbbbbb" });
  assert.equal(r.partnerId, B);
  assert.equal((await user(A)).partnerId, B);
  assert.equal((await user(B)).partnerId, A);
});

await test("pairWithCode refuses a taken partner, a bad code, and yourself", async () => {
  await rejects(call("pairWithCode", C, { code: "BBBBBB" }), "FAILED_PRECONDITION");
  await rejects(call("pairWithCode", C, { code: "ZZZZZZ" }), "NOT_FOUND");
  await rejects(call("pairWithCode", C, { code: "CCCCCC" }), "INVALID_ARGUMENT");
  assert.equal((await user(B)).partnerId, A);
});

await test("a one-sided partnerId buys no partner actions", async () => {
  // C names A, who is paired with B (the trigger refuses to steal A).
  await db.collection("users").doc(C).update({ partnerId: A });
  await sleep(1500);
  assert.equal((await user(A)).partnerId, B);
  await rejects(call("sendToDoghouse", C, { reason: "because" }), "FAILED_PRECONDITION");
  await rejects(call("sendRoses", C), "FAILED_PRECONDITION");
  await rejects(call("purchaseCosmetic", C, { itemId: "hat_party", forPartner: true }),
    "FAILED_PRECONDITION");
  await rejects(call("equipCosmetic", C, { category: "hat", itemId: null, forPartner: true }),
    "PERMISSION_DENIED");
  await db.collection("users").doc(C).update({ wishCards: 1 });
  await rejects(call("redeemWishCard", C, { text: "anything" }), "FAILED_PRECONDITION");
  assert.equal((await user(C)).wishCards, 1);
});

const key = [A, B].sort().join("_");

await test("a forged completed challenge pays no card", async () => {
  await db.collection("challenges").doc("forged1").set({
    coupleKey: key, type: "quiz", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
  await db.collection("challenges").doc("forged2").set({
    coupleKey: key, type: "photo", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
  await sleep(3000);
  assert.equal((await user(A)).wishCards, undefined);
});

await test("a real photo dash pays exactly one card", async () => {
  const ref = db.collection("challenges").doc("dash1");
  await ref.set({
    coupleKey: key, type: "photo", participants: [A, B], createdBy: "system",
    status: "active",
  });
  await ref.update({ status: "completed", winnerId: B, photoData: "aGk=" });
  await waitFor(async () => (await user(B)).wishCards === 1, "the card");
  await ref.update({ touchedAgain: true });
  await sleep(2000);
  assert.equal((await user(B)).wishCards, 1);
  assert.equal((await ref.get()).data().cardAwarded, true);
});

await test("a photo dash claimed without a photo pays nothing", async () => {
  const ref = db.collection("challenges").doc("dash2");
  await ref.set({
    coupleKey: key, type: "photo", participants: [A, B], createdBy: "system",
    status: "active",
  });
  await ref.update({ status: "completed", winnerId: B, photoData: "" });
  await sleep(2500);
  assert.equal((await user(B)).wishCards, 1);
  assert.notEqual((await ref.get()).data().cardAwarded, true);
});

await test("the anniversary race pays once, only at this year's id, only on the day", async () => {
  const year = new Date().getUTCFullYear();
  const meta = db.collection("coupleMeta").doc(key);
  // Anniversary set, but six weeks away.
  await meta.set({ userIds: [A, B], anniversary: Timestamp.fromMillis(Date.now() + 42 * 86_400_000) });
  await db.collection("challenges").doc(`anniv_${key}_${year + 7}`).set({
    coupleKey: key, type: "anniversary", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
  const race = db.collection("challenges").doc(`anniv_${key}_${year}`);
  await race.set({
    coupleKey: key, type: "anniversary", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
  await sleep(2500);
  assert.equal((await user(A)).wishCards, undefined);

  // Today it is (stored as local midnight, so a few hours back still counts).
  await meta.set({ userIds: [A, B], anniversary: Timestamp.fromMillis(Date.now() - 20 * 3_600_000) });
  await race.update({ nudge: true });
  await waitFor(async () => (await user(A)).wishCards === 1, "the anniversary card");
  await sleep(1500);
  assert.equal((await user(A)).wishCards, 1);
});

await test("redemption treats need a redemption request", async () => {
  await call("sendToDoghouse", A, { reason: "milk" });
  const ev = (await db.collection("doghouseEvents")
    .where("senderId", "==", A).where("isActive", "==", true).get()).docs[0];
  await call("releasePartner", A, { eventId: ev.id, byRedemption: true });
  const after = (await ev.ref.get()).data();
  assert.equal(after.isActive, false);
  assert.equal(after.releasedBy, "sender");
  assert.equal((await user(B)).treats, undefined);

  // The release granted an hour of immunity; lift it for the second round.
  await db.collection("users").doc(B).update({ immunityUntil: null });
  await call("sendToDoghouse", A, { reason: "milk again" });
  const ev2 = (await db.collection("doghouseEvents")
    .where("senderId", "==", A).where("isActive", "==", true).get()).docs[0];
  await call("requestRedemption", B, { eventId: ev2.id });
  await call("releasePartner", A, { eventId: ev2.id, byRedemption: true });
  assert.equal((await ev2.ref.get()).data().releasedBy, "redemption");
  assert.equal((await user(B)).treats, 115);
});

await test("a backdated createdAt does not buy the top treat rate", async () => {
  // D's Auth account is minutes old; the profile claims 100 days.
  await db.collection("users").doc(D).update({
    createdAt: Timestamp.fromMillis(Date.now() - 100 * 86_400_000),
  });
  const r = await call("claimHomeTreats", D);
  assert.equal(r.awarded, 1); // 1 hour × rate 1, not × 5
});

const E = "secE";
const privateDoc = (uid) => db.collection("users").doc(uid).collection("private").doc("data");
const codeOf = async (uid) => (await privateDoc(uid).get()).data()?.partnerCode;
const codeExists = async (code) => (await db.collection("partnerCodes").doc(code).get()).exists;

await test("code guessing is rate limited per account", async () => {
  await auth.createUser({ uid: E }).catch(() => undefined);
  await db.collection("users").doc(E).set({ displayName: E, createdAt: Timestamp.now() });
  for (let i = 0; i < 10; i++) {
    await rejects(call("pairWithCode", E, { code: `ZZZZZ${i}` }), "NOT_FOUND");
  }
  await rejects(call("pairWithCode", E, { code: "ZZZZZ0" }), "RESOURCE_EXHAUSTED");
  // The same budget covers couple codes.
  await rejects(call("addCoupleFriend", E, { code: "ZZZZZ0" }), "FAILED_PRECONDITION");
});

await test("a removed couple cannot add itself back with the unchanged code", async () => {
  // C is still pointing one-sidedly at A from above; clear that, then pair C with D.
  await db.collection("users").doc(C).update({ partnerId: FieldValue.delete() });
  await sleep(1500);
  await call("pairWithCode", D, { code: "CCCCCC" });
  assert.equal((await user(C)).partnerId, D);
  await privateDoc(A).set({ partnerCode: "AAAAAA" }, { merge: true });
  await db.collection("partnerCodes").doc("AAAAAA").set({ userId: A });

  const keyCD = [C, D].sort().join("_");
  const linkId = [key, keyCD].sort().join("__");
  await call("addCoupleFriend", A, { code: "CCCCCC" });
  assert.equal((await db.collection("coupleFriendships").doc(linkId).get()).exists, true);

  // C's couple removes A's couple; A cannot come back...
  await call("removeCoupleFriend", C, { coupleKey: key });
  assert.equal((await db.collection("coupleFriendships").doc(linkId).get()).exists, false);
  await rejects(call("addCoupleFriend", A, { code: "CCCCCC" }), "PERMISSION_DENIED");
  // ...but the couple that removed can.
  await call("addCoupleFriend", C, { code: "AAAAAA" });
  assert.equal((await db.collection("coupleFriendships").doc(linkId).get()).exists, true);
  assert.equal((await db.collection("friendRemovals").doc(linkId).get()).exists, false);
  await call("removeCoupleFriend", C, { coupleKey: key });
});

await test("a build that clears its own partnerId still splits both halves and retires both codes", async () => {
  assert.equal(await codeOf(C), undefined);
  await privateDoc(C).set({ partnerCode: "CCCCCC" }, { merge: true });
  await db.collection("users").doc(C).update({ partnerId: FieldValue.delete() });
  await waitFor(async () => (await user(D)).partnerId === undefined, "D to be unpaired by the trigger");
  await waitFor(async () => !(await codeExists("CCCCCC")), "C's old code to be retired");
  const newC = await codeOf(C), newD = await codeOf(D);
  assert.match(newC, /^[A-Z2-9]{6}$/);
  assert.match(newD, /^[A-Z2-9]{6}$/);
  assert.equal(await codeExists(newC), true);
  assert.equal(await codeExists(newD), true);
  await rejects(call("pairWithCode", D, { code: "CCCCCC" }), "NOT_FOUND");
});

await test("unpairPartner clears both halves and retires both codes; the ex cannot return", async () => {
  // Every real account carries its code on the private document; the
  // fixture only wrote the lookup side.
  await privateDoc(B).set({ partnerCode: "BBBBBB" }, { merge: true });
  await call("unpairPartner", A);
  assert.equal((await user(A)).partnerId, undefined);
  assert.equal((await user(B)).partnerId, undefined);
  assert.equal(await codeExists("AAAAAA"), false);
  assert.equal(await codeExists("BBBBBB"), false);
  const newA = await codeOf(A);
  assert.match(newA, /^[A-Z2-9]{6}$/);
  assert.equal((await db.collection("partnerCodes").doc(newA).get()).data().userId, A);
  // The retained code is dead; a freshly shared one works.
  await rejects(call("pairWithCode", B, { code: "AAAAAA" }), "NOT_FOUND");
  await call("pairWithCode", B, { code: newA });
  assert.equal((await user(A)).partnerId, B);
  assert.equal((await user(B)).partnerId, A);
  // Idempotent with no partner.
  await call("unpairPartner", C);
});

console.log(`\n${passed} passed`);
process.exit(0);
