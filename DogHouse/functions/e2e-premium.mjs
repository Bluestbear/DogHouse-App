// End-to-end check of the premium subscription against the REAL Cloud
// Functions running in the emulator: the free daily game limit in createGame,
// the couple-shared premium lift, and the premium branch of revenuecatWebhook
// (routing, trial, expiry, exactly-once, ordering, legacy products).
//
// Run from the project root (DogHouse/):
//   firebase emulators:exec --only firestore,functions --project doghouse-5e80e \
//     "node functions/e2e-premium.mjs"
//
// Or simply: `npm run e2e:premium` in functions/ (builds first).
// Needs functions/.secret.local with dummy GMAIL_APP_PASSWORD and
// REVENUECAT_WEBHOOK_SECRET lines (do not commit it); the webhook secret is
// read from there so the Authorization header matches.

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { dayKey } from "./lib/premium.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const PROJECT = "doghouse-5e80e";
const FN = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
const db = getFirestore(initializeApp({ projectId: PROJECT }));

// ── secret ─────────────────────────────────────────────────────
function loadSecret() {
  if (process.env.REVENUECAT_WEBHOOK_SECRET) return process.env.REVENUECAT_WEBHOOK_SECRET;
  const file = join(dirname(fileURLToPath(import.meta.url)), ".secret.local");
  try {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const m = line.match(/^\s*REVENUECAT_WEBHOOK_SECRET\s*=\s*(.*?)\s*$/);
      if (m) return m[1].replace(/^["']|["']$/g, "");
    }
  } catch {
    // fall through
  }
  throw new Error("REVENUECAT_WEBHOOK_SECRET not found in the environment or functions/.secret.local");
}
const SECRET = loadSecret();

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

// Unlike e2e-friends' helper, an explicit idempotencyKey wins (retry test)
// and the error's details are kept (the iOS client matches on them).
async function call(name, uid, data = {}) {
  const res = await fetch(`${FN}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token(uid)}` },
    body: JSON.stringify({ data: { idempotencyKey: randomUUID(), ...data } }),
  });
  const json = await res.json();
  if (json.error) {
    const err = new Error(`${name}: ${json.error.status} — ${json.error.message}`);
    err.status = json.error.status;
    err.serverMessage = json.error.message;
    err.details = json.error.details;
    throw err;
  }
  return json.result;
}

async function post(event) {
  const res = await fetch(`${FN}/revenuecatWebhook`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: SECRET },
    body: JSON.stringify({ event }),
  });
  return { status: res.status, text: await res.text() };
}

const game = (extra = {}) => ({
  kind: "preference", prompt: "Beach or mountains?", options: ["Beach", "Mountains"],
  answerIndex: 0, ...extra,
});
const createGame = (uid, extra) => call("createGame", uid, game(extra));

async function expectLimited(uid, what) {
  await assert.rejects(createGame(uid), (e) => {
    assert.equal(e.status, "RESOURCE_EXHAUSTED", what);
    assert.equal(e.serverMessage, "daily-game-limit", what);
    assert.deepEqual(e.details, { reason: "daily-game-limit" }, what);
    return true;
  });
}

const H = 3_600_000, D = 86_400_000;
let seq = 0;
function sub(overrides = {}) {
  const now = Date.now();
  return {
    type: "INITIAL_PURCHASE", id: `evt_${++seq}`, environment: "SANDBOX", store: "APP_STORE",
    app_user_id: U.B, aliases: [], product_id: "premium_yearly",
    entitlement_ids: ["DogHouse+"], period_type: "NORMAL",
    transaction_id: `txn_${seq}`, purchased_at_ms: now,
    expiration_at_ms: now + 365 * D, event_timestamp_ms: now,
    ...overrides,
  };
}

const docData = async (path) => (await db.doc(path).get()).data();
let step = 0;
const ok = (msg) => console.log(`  ✓ ${++step}. ${msg}`);

// ── fixtures ───────────────────────────────────────────────────
const U = { A: "uidA", B: "uidB" };
const KEY = [U.A, U.B].sort().join("_");
const TZ = "Pacific/Kiritimati"; // UTC+14: A's "today" differs from UTC/Berlin much of the day
const START = 100;

async function seed() {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  const user = (name, partnerId) => ({
    displayName: name, avatarId: "dog_1", partnerId, treats: START, graceCharges: 3,
    createdAt: Timestamp.now(),
  });
  await db.doc(`users/${U.A}`).set(user("A", U.B));
  await db.doc(`users/${U.B}`).set(user("B", U.A));
  await db.doc(`users/${U.A}/private/data`).set({ timeZone: TZ });
  // Existing scorecard: createGame must merge into it, never wipe it.
  await db.doc(`gameStats/${KEY}`).set({ wins: { [U.A]: 3 }, played: 7 });
}

async function assertTreatsUntouched() {
  assert.equal((await docData(`users/${U.A}`)).treats, START);
  assert.equal((await docData(`users/${U.B}`)).treats, START);
}

// ── the run ────────────────────────────────────────────────────
console.log("premium e2e");
await seed();

// 1. Free couple: first game ok, stats merged, second game limited.
const first = await createGame(U.A);
assert.ok(first.challengeId);
let stats = await docData(`gameStats/${KEY}`);
assert.equal(stats.lastGameDay, dayKey(Date.now(), TZ));
assert.equal(stats.gamesToday, 1);
assert.equal(stats.played, 7);
assert.deepEqual(stats.wins, { [U.A]: 3 });
await expectLimited(U.A, "A second game");
// B has no timeZone (Berlin), usually a calendar day behind A's UTC+14: the
// counter must not reset just because B's "today" is a different key.
await expectLimited(U.B, "B also limited (per couple, even from a zone behind A's)");
ok("free couple: 1st game ok (creator tz day, scorecard kept), 2nd → resource-exhausted daily-game-limit for either partner, across zones");

// 2. Answering is never limited.
const answered = await call("answerGame", U.B, { challengeId: first.challengeId, guessIndex: 0 });
assert.equal(answered.ok, true);
stats = await docData(`gameStats/${KEY}`);
assert.equal(stats.gamesToday, 1);
assert.equal(stats.lastGameDay, dayKey(Date.now(), TZ));
assert.equal(stats.played, 8);
ok("answerGame still works while limited; the counter survives answerGame's merge");

// 3. A retried createGame (same idempotency key) replays and does not count again.
await db.doc(`gameStats/${KEY}`).set({ lastGameDay: "2000-01-01", gamesToday: 9 }, { merge: true });
const retryKey = randomUUID();
const r1 = await createGame(U.A, { idempotencyKey: retryKey });
const r2 = await createGame(U.A, { idempotencyKey: retryKey });
assert.equal(r2.challengeId, r1.challengeId);
stats = await docData(`gameStats/${KEY}`);
assert.equal(stats.gamesToday, 1, "old day reset to 1, retry not counted");
assert.equal(stats.played, 8);
await expectLimited(U.A, "after reset + retry");
ok("new day resets the counter to 1; a retry with the same key replays without counting");

// 4. Legacy DogHouse+ product: acknowledged, grants nothing.
let r = await post(sub({ product_id: "yearly", id: "evt_legacy" }));
assert.equal(r.status, 200);
assert.equal(r.text, "legacy ignored");
assert.equal((await docData(`users/${U.B}`)).premiumUntil, undefined);
r = await post(sub({ type: "NON_RENEWING_PURCHASE", product_id: "lifetime", id: "evt_legacy2" }));
assert.equal(r.status, 200);
assert.equal(r.text, "legacy ignored");
await expectLimited(U.A, "legacy product must not lift the limit");
await assertTreatsUntouched();
ok("legacy yearly/lifetime (DogHouse+ entitlement) → 200 'legacy ignored', no premium, no treats");

// 5. INITIAL_PURCHASE (trial) for partner B lifts the limit for A.
const tBuy = Date.now();
const trialUntil = tBuy + 7 * D;
r = await post(sub({ id: "evt_trial", period_type: "TRIAL", event_timestamp_ms: tBuy,
  expiration_at_ms: trialUntil }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
let b = await docData(`users/${U.B}`);
assert.equal(b.premiumUntil, trialUntil);
assert.equal(b.premiumProductId, "premium_yearly");
assert.equal(b.premiumUpdatedAt, tBuy);
const key = await docData(`idempotencyKeys/${U.B}_premium_evt_trial`);
assert.equal(key.kind, "purchase");
assert.equal(key.status, "done");
await createGame(U.A);
await createGame(U.A);
await createGame(U.B);
await assertTreatsUntouched();
ok("INITIAL_PURCHASE (trial) for B → premiumUntil set, key kind=purchase; A and B create freely, treats untouched");

// 6. Duplicate event id does not double-apply (different payload, same id).
r = await post(sub({ id: "evt_trial", event_timestamp_ms: tBuy + 1000,
  expiration_at_ms: tBuy + 999 * D }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
b = await docData(`users/${U.B}`);
assert.equal(b.premiumUntil, trialUntil);
assert.equal(b.premiumUpdatedAt, tBuy);
ok("same event id redelivered with a different expiry → replayed, premiumUntil unchanged");

// 7. CANCELLATION changes nothing; access runs to expiry.
r = await post(sub({ type: "CANCELLATION", id: "evt_cancel", event_timestamp_ms: tBuy + 2000,
  expiration_at_ms: trialUntil }));
assert.equal(r.status, 200);
assert.equal(r.text, "no change");
b = await docData(`users/${U.B}`);
assert.equal(b.premiumUntil, trialUntil);
assert.equal(b.premiumUpdatedAt, tBuy);
await createGame(U.A);
ok("CANCELLATION → 200 'no change', still premium until expiry");

// 8. EXPIRATION → couple limited again (they already created games today).
const tExp = tBuy + 3000;
r = await post(sub({ type: "EXPIRATION", id: "evt_expire", event_timestamp_ms: tExp,
  expiration_at_ms: Date.now() - H }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
b = await docData(`users/${U.B}`);
assert.ok(b.premiumUntil < Date.now());
assert.equal(b.premiumUpdatedAt, tExp);
await expectLimited(U.A, "after EXPIRATION");
await expectLimited(U.B, "after EXPIRATION (payer)");
ok("EXPIRATION → premiumUntil in the past, couple limited again");

// 9. An older event arriving after a newer one is ignored.
r = await post(sub({ type: "RENEWAL", id: "evt_old_renewal", event_timestamp_ms: tBuy + 500,
  expiration_at_ms: Date.now() + 30 * D }));
assert.equal(r.status, 200);
assert.equal(r.text, "stale");
b = await docData(`users/${U.B}`);
assert.ok(b.premiumUntil < Date.now());
assert.equal(b.premiumUpdatedAt, tExp);
await expectLimited(U.A, "after stale RENEWAL");
ok("out-of-order RENEWAL older than the EXPIRATION → 'stale', still limited");

// 10. A newer renewal (six-month product, via PRODUCT_CHANGE) restores premium.
r = await post(sub({ type: "PRODUCT_CHANGE", id: "evt_change", product_id: "premium_yearly",
  new_product_id: "premium_six_month", event_timestamp_ms: tExp + 1000,
  expiration_at_ms: Date.now() + 180 * D }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
b = await docData(`users/${U.B}`);
assert.equal(b.premiumProductId, "premium_six_month");
await createGame(U.A);
await assertTreatsUntouched();
stats = await docData(`gameStats/${KEY}`);
assert.equal(stats.played, 8);
assert.equal(stats.wins[U.A], 3);
ok("newer PRODUCT_CHANGE → premium_six_month, unlimited again; scorecard and treats intact");

console.log(`\nAll ${step} premium checks passed.`);
process.exit(0);
