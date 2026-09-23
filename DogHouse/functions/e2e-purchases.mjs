// End-to-end check of the RevenueCat webhook against the REAL Cloud Function
// running in the emulator: auth, crediting, exactly-once replay, unmapped
// products, anonymous ids and aliases, refund-shaped events.
//
// Run from the project root (DogHouse/):
//   firebase emulators:exec --only firestore,functions --project doghouse-5e80e \
//     "node functions/e2e-purchases.mjs"
//
// Or simply: `npm run e2e:purchases` in functions/ (builds first).
// The functions emulator wants every declared secret to resolve; create
// functions/.secret.local with dummy GMAIL_APP_PASSWORD and
// REVENUECAT_WEBHOOK_SECRET lines for the run (do not commit it). This script
// reads the same value so the Authorization header matches.
//
// Not covered here: the ALLOW_SANDBOX_PURCHASES=false branch. It is a
// compile-time constant in src/index.ts, so it is verified by the manual
// step in TREAT_PACKS_SETUP.md instead (one Test Store purchase must be
// ignored after the flag is flipped and redeployed).

import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

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
    // fall through to the error below
  }
  throw new Error(
    "REVENUECAT_WEBHOOK_SECRET not found in the environment or functions/.secret.local"
  );
}
const SECRET = loadSecret();

// ── helpers ────────────────────────────────────────────────────
async function post(event, auth = SECRET) {
  const res = await fetch(`${FN}/revenuecatWebhook`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: auth },
    body: JSON.stringify(event === undefined ? {} : { event }),
  });
  return { status: res.status, text: await res.text() };
}

// Shape follows RevenueCat's NON_RENEWING_PURCHASE payload; only the fields
// the function reads are filled in.
let eventSeq = 0;
function purchase(overrides = {}) {
  return {
    type: "NON_RENEWING_PURCHASE",
    id: `evt_${++eventSeq}`,
    environment: "SANDBOX",
    store: "APP_STORE",
    app_user_id: U.P,
    aliases: [],
    product_id: PRODUCT.small,
    transaction_id: `txn_${eventSeq}`,
    purchased_at_ms: Date.now(),
    ...overrides,
  };
}

const docData = async (path) => (await db.doc(path).get()).data();
const treatsOf = async (uid) => (await docData(`users/${uid}`)).treats;

let step = 0;
const ok = (msg) => console.log(`  ✓ ${++step}. ${msg}`);

// ── fixtures ───────────────────────────────────────────────────
const U = { P: "uidP" };
const PRODUCT = {
  small: "com.Harrison.DogHouse.treats.small",
  medium: "com.Harrison.DogHouse.treats.medium",
  large: "com.Harrison.DogHouse.treats.large",
};
const START = 100;

async function seed() {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  await db.doc(`users/${U.P}`).set({
    displayName: "P", avatarId: "dog_1", partnerId: null,
    treats: START, graceCharges: 3, createdAt: Timestamp.now(),
  });
}

// ── the run ────────────────────────────────────────────────────
console.log("purchases e2e");
await seed();

// 1. Auth
let r = await post(purchase(), "not-the-secret");
assert.equal(r.status, 401);
assert.equal(await treatsOf(U.P), START);
ok("wrong Authorization header → 401, nothing credited");

// 2. A real purchase credits the mapped amount and leaves a purchase record
r = await post(purchase({ transaction_id: "txn_first" }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
assert.equal(await treatsOf(U.P), START + 250);
const record = await docData(`idempotencyKeys/${U.P}_treatpack_txn_first`);
assert.ok(record, "purchase key doc exists");
assert.equal(record.kind, "purchase");
assert.equal(record.status, "done");
assert.equal(record.result.credited, 250);
assert.equal(record.result.productId, PRODUCT.small);
assert.equal(record.result.environment, "SANDBOX");
ok("NON_RENEWING_PURCHASE small pack → +250, key doc tagged kind=purchase");

// 3. Exactly-once: the same transaction delivered again does nothing
r = await post(purchase({ transaction_id: "txn_first" }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
assert.equal(await treatsOf(U.P), START + 250);
ok("same transaction_id redelivered → 200, balance unchanged");

// 4. Unmapped product
r = await post(purchase({ product_id: "com.Harrison.DogHouse.treats.huge", transaction_id: "txn_huge" }));
assert.equal(r.status, 200);
assert.equal(r.text, "nothing to credit");
assert.equal(await treatsOf(U.P), START + 250);
ok("unmapped product_id → 'nothing to credit', balance unchanged");

// 5. Anonymous app_user_id with no aliases has nobody to credit
r = await post(purchase({ app_user_id: "$RCAnonymousID:abc", aliases: [], transaction_id: "txn_anon" }));
assert.equal(r.status, 200);
assert.equal(r.text, "no such user");
assert.equal(await treatsOf(U.P), START + 250);
ok("$RCAnonymousID with no aliases → 'no such user', balance unchanged");

// 6. Anonymous app_user_id resolved through aliases
r = await post(purchase({
  app_user_id: "$RCAnonymousID:abc", aliases: ["$RCAnonymousID:abc", U.P],
  product_id: PRODUCT.medium, transaction_id: "txn_alias",
}));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
assert.equal(await treatsOf(U.P), START + 250 + 900);
ok("anonymous id with the uid in aliases → medium pack +900");

// 7. Refund-shaped events are acknowledged but never move treats
r = await post(purchase({ type: "CANCELLATION", transaction_id: "txn_first" }));
assert.equal(r.status, 200);
assert.equal(r.text, "ignored");
assert.equal(await treatsOf(U.P), START + 250 + 900);
ok("CANCELLATION → 'ignored', balance unchanged (log-only by design)");

// 8. Missing transaction_id falls back to the event id
r = await post(purchase({ transaction_id: undefined, id: "evt_fallback", product_id: PRODUCT.large }));
assert.equal(r.status, 200);
assert.equal(r.text, "ok");
assert.equal(await treatsOf(U.P), START + 250 + 900 + 1600);
assert.ok(await docData(`idempotencyKeys/${U.P}_treatpack_evt_fallback`), "keyed on event id");
ok("no transaction_id → keyed on event.id, large pack +1600");

// 9. Body without an event
r = await post(undefined);
assert.equal(r.status, 200);
assert.equal(r.text, "no event");
ok("body without `event` → 'no event'");

// 10. Unknown user id that is not anonymous
r = await post(purchase({ app_user_id: "uidNobody", transaction_id: "txn_nobody" }));
assert.equal(r.status, 200);
assert.equal(r.text, "no such user");
assert.equal(await treatsOf(U.P), START + 250 + 900 + 1600);
ok("uid with no users/ doc → 'no such user'");

console.log(`\nAll ${step} purchase checks passed.`);
process.exit(0);
