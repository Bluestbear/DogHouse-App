// Plain-node tests for the pure premium logic (no emulator needed).
// Run from functions/: npm run test:premium (builds first).
import assert from "node:assert/strict";
import {
  dayKey, gameDayCount, isCouplePremium, premiumProductOf, premiumSkipReason, premiumPatch,
  PREMIUM_PRODUCTS, LEGACY_SUBSCRIPTION_PRODUCTS, FREE_GAMES_PER_DAY,
} from "./lib/premium.js";

let n = 0;
const ok = (msg) => console.log(`  ✓ ${++n}. ${msg}`);
const H = 3_600_000;

// dayKey
{
  // 2026-09-29 22:30 UTC: already the 30th in Berlin (UTC+2) and Tokyo, still the 29th in LA.
  const t = Date.UTC(2026, 8, 29, 22, 30);
  assert.equal(dayKey(t, "UTC"), "2026-09-29");
  assert.equal(dayKey(t, "Europe/Berlin"), "2026-09-30");
  assert.equal(dayKey(t, "Asia/Tokyo"), "2026-09-30");
  assert.equal(dayKey(t, "America/Los_Angeles"), "2026-09-29");
  assert.equal(dayKey(t, undefined), "2026-09-30");
  assert.equal(dayKey(t, ""), "2026-09-30");
  assert.equal(dayKey(t, "Nope/Zone"), "2026-09-30");
  assert.equal(dayKey(Date.UTC(2026, 0, 5, 12), "UTC"), "2026-01-05"); // zero-padded
  ok("dayKey: per-zone calendar day, YYYY-MM-DD, Berlin fallback on missing/invalid zone");
}

// gameDayCount
{
  assert.deepEqual(gameDayCount(undefined, undefined, "2026-09-29"), { day: "2026-09-29", gamesToday: 0 });
  assert.deepEqual(gameDayCount("2026-09-29", 1, "2026-09-29"), { day: "2026-09-29", gamesToday: 1 });
  assert.deepEqual(gameDayCount("2026-09-28", 5, "2026-09-29"), { day: "2026-09-29", gamesToday: 0 });
  // A partner whose calendar is behind does not get a fresh day.
  assert.deepEqual(gameDayCount("2026-09-30", 1, "2026-09-29"), { day: "2026-09-30", gamesToday: 1 });
  assert.deepEqual(gameDayCount("2026-09-29", "x", "2026-09-29"), { day: "2026-09-29", gamesToday: 0 });
  assert.deepEqual(gameDayCount("2025-12-31", 1, "2026-01-01"), { day: "2026-01-01", gamesToday: 0 });
  ok("gameDayCount: same day keeps the count, a later day resets, an earlier day never resets");
}

// isCouplePremium
{
  const now = Date.UTC(2026, 8, 29, 12);
  assert.equal(isCouplePremium({}, {}, now), false);
  assert.equal(isCouplePremium(undefined, undefined, now), false);
  assert.equal(isCouplePremium({ premiumUntil: now + H }, {}, now), true);
  assert.equal(isCouplePremium({}, { premiumUntil: now + H }, now), true);
  assert.equal(isCouplePremium({ premiumUntil: now }, {}, now), false); // must be strictly later
  assert.equal(isCouplePremium({ premiumUntil: now - H }, { premiumUntil: now - 1 }, now), false);
  assert.equal(isCouplePremium({ premiumUntil: String(now + H) }, {}, now), false); // numbers only
  ok("isCouplePremium: either partner, strictly future, numeric only");
}

// Routing
{
  assert.deepEqual([...PREMIUM_PRODUCTS].sort(), ["premium_six_month", "premium_yearly"]);
  assert.equal(FREE_GAMES_PER_DAY, 1);
  assert.equal(premiumProductOf({ type: "INITIAL_PURCHASE", product_id: "premium_yearly" }), "premium_yearly");
  assert.equal(premiumProductOf({ type: "RENEWAL", product_id: "premium_six_month" }), "premium_six_month");
  for (const legacy of LEGACY_SUBSCRIPTION_PRODUCTS) {
    assert.equal(premiumProductOf({ type: "INITIAL_PURCHASE", product_id: legacy,
      entitlement_ids: ["DogHouse+"] }), undefined, legacy);
  }
  assert.equal(premiumProductOf({ type: "NON_RENEWING_PURCHASE",
    product_id: "com.Harrison.DogHouse.treats.small" }), undefined);
  assert.equal(premiumProductOf({ type: "PRODUCT_CHANGE", product_id: "premium_six_month",
    new_product_id: "premium_yearly" }), "premium_yearly");
  assert.equal(premiumProductOf({ type: "PRODUCT_CHANGE", product_id: "yearly",
    new_product_id: "premium_yearly" }), "premium_yearly");
  // new_product_id only counts on PRODUCT_CHANGE
  assert.equal(premiumProductOf({ type: "RENEWAL", product_id: "yearly",
    new_product_id: "premium_yearly" }), undefined);
  ok("routing: premium products only; legacy DogHouse+ products and treat packs are not premium");
}

// Event shape
{
  const ev = (o = {}) => ({ type: "INITIAL_PURCHASE", id: "e1", expiration_at_ms: 2, event_timestamp_ms: 1, ...o });
  for (const t of ["INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "EXPIRATION"]) {
    assert.equal(premiumSkipReason(ev({ type: t })), undefined, t);
  }
  assert.equal(premiumSkipReason(ev({ period_type: "TRIAL" })), undefined);
  assert.equal(premiumSkipReason(ev({ type: "CANCELLATION" })), "no change");
  assert.equal(premiumSkipReason(ev({ type: "BILLING_ISSUE" })), "ignored");
  assert.equal(premiumSkipReason(ev({ id: undefined })), "no event id");
  assert.equal(premiumSkipReason(ev({ expiration_at_ms: null })), "no expiration");
  assert.equal(premiumSkipReason(ev({ event_timestamp_ms: undefined })), "no timestamp");
  ok("shape: the five expiry-setting types (incl. trial) apply; CANCELLATION no-op; malformed skipped");
}

// Ordering
{
  const ev = { type: "RENEWAL", id: "e", expiration_at_ms: 500, event_timestamp_ms: 100 };
  assert.deepEqual(premiumPatch(ev, "premium_yearly", undefined),
    { premiumUntil: 500, premiumProductId: "premium_yearly", premiumUpdatedAt: 100 });
  assert.deepEqual(premiumPatch(ev, "premium_yearly", 100),
    { premiumUntil: 500, premiumProductId: "premium_yearly", premiumUpdatedAt: 100 }); // equal applies
  assert.equal(premiumPatch(ev, "premium_yearly", 101), "stale");
  ok("ordering: applies when event_timestamp_ms >= premiumUpdatedAt, else stale");
}

console.log(`\nAll ${n} premium checks passed.`);
