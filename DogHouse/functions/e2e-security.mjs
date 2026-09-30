// End-to-end check of the 2026-09-23 security fixes against the REAL Cloud
// Functions in the emulator: code-checked pairing,
// mutual-partner checks, challenge card provenance, the redemption reward
// gate and the createdAt clamp.
//
// Run: `npm run e2e:security` in functions/ (builds first). Needs the Auth
// emulator too, because the createdAt clamp reads the Auth account. Like the
// other e2e scripts it needs functions/.secret.local with dummy secrets.

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
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
    "FAILED_PRECONDITION");
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

await test("the anniversary race pays once, only at this year's id", async () => {
  const year = new Date().getUTCFullYear();
  await db.collection("challenges").doc(`anniv_${key}_${year + 7}`).set({
    coupleKey: key, type: "anniversary", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
  await db.collection("challenges").doc(`anniv_${key}_${year}`).set({
    coupleKey: key, type: "anniversary", participants: [A, B], createdBy: A,
    status: "completed", winnerId: A,
  });
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

console.log(`\n${passed} passed`);
process.exit(0);
