// Plain-node tests for the pure nudge decision logic (no emulator needed).
// Run from functions/: npm run build && node test-nudges.mjs
import assert from "node:assert/strict";
import { pickNudge, preflight, roomLevel, localHour } from "./lib/nudges.js";

const H = 3_600_000, D = 86_400_000;
// A Tuesday, 14:00 in Berlin (12:00 UTC).
const NOW = Date.UTC(2026, 8, 8, 12, 0, 0);
const PRICES = { hat_beanie: 70, hat_wizard: 180, necklace_red: 50 };

const base = () => ({
  name: "Harrison", partnerName: "Lena", treats: 20, ownedItemIds: [],
  homeStartMs: NOW - 2 * D, partnerHomeStartMs: NOW - 2 * D,
  pairedSinceMs: NOW - 30 * D, lastActiveAtMs: NOW - 2 * D, timeZone: "Europe/Berlin",
  hasToken: true, markers: {}, cosmeticPrices: PRICES,
});
let n = 0;
const ok = (msg) => console.log(`  ✓ ${++n}. ${msg}`);

// Gates
assert.equal(preflight({ hasToken: false, markers: {} }, NOW), "no token");
assert.equal(preflight({ hasToken: true, remindersEnabled: false, markers: {} }, NOW), "reminders off");
assert.equal(preflight({ hasToken: true, timeZone: "America/Los_Angeles", markers: {} }, NOW), "quiet hours"); // 05:00 there
assert.equal(preflight({ hasToken: true, timeZone: "Nope/Zone", markers: {} }, NOW), undefined); // bad zone → Berlin
assert.equal(preflight({ hasToken: true, markers: { lastSentAt: NOW - 5 * H } }, NOW), "daily cap");
assert.equal(localHour(NOW, "Asia/Tokyo"), 21);
ok("preflight: token, toggle, local quiet hours, bad zone fallback, daily cap");

// First run initialises markers without sending, even for an inactive user
// (no lastTreatAward → the claim would pay one hour, below the minimum).
{
  const r = pickNudge({ ...base(), lastActiveAtMs: NOW - 3 * D }, NOW);
  assert.equal(r.decision, undefined);
  assert.equal(r.markers.roomLevel, roomLevel(2 * D));
  assert.equal(r.markers.streakStart, NOW - 2 * D);
  assert.equal(r.markers.shopTreats, 20);
  assert.equal(r.markers.bellyRubAt, NOW);
  ok("first run: silent marker init (level, streak, shop floor, belly rub clock)");
}

// Active user gets nothing except escalation.
{
  const s = { ...base(), lastActiveAtMs: NOW - 1 * H, markers: { roomLevel: 1, streakStart: NOW - 2 * D, streakMilestone: 0, shopTreats: 0 } };
  assert.equal(pickNudge(s, NOW).reason, "active");
  const r = pickNudge({ ...s, partnerActiveEvent: { id: "e1", startedAtMs: NOW - 3.5 * D } }, NOW);
  assert.equal(r.decision.kind, "escalation");
  assert.match(r.decision.body, /Three days/);
  assert.equal(r.markers.escalation.e1, 2);
  assert.equal(r.markers.lastSentAt, NOW);
  ok("active user: only escalation fires (sender copy, stage 2)");
}

// Escalation does not repeat a stage, and moves on to the next one.
{
  const s = { ...base(), myActiveEvent: { id: "e2", startedAtMs: NOW - 8 * D }, markers: { escalation: { e2: 3 } } };
  assert.notEqual(pickNudge(s, NOW).decision?.kind, "escalation");
  const r = pickNudge({ ...s, markers: { escalation: { e2: 2 } } }, NOW);
  assert.equal(r.decision.kind, "escalation");
  assert.match(r.decision.body, /week in the cold/);
  ok("escalation: idempotent per stage, receiver copy at stage 3");
}

// Treats waiting beats everything else for a quiet user.
{
  const m = { roomLevel: 4, streakStart: NOW - 2 * D, streakMilestone: 0, shopTreats: 20 };
  const r = pickNudge({ ...base(), lastTreatAwardMs: NOW - 10 * H, markers: m }, NOW);
  assert.equal(r.decision.kind, "treats");
  assert.match(r.decision.body, /earned 20 treats/); // 10h × 2/hr at level 4
  assert.equal(r.markers.treatsAt, NOW);
  const tooSmall = pickNudge({ ...base(), lastTreatAwardMs: NOW - 3 * H, markers: m }, NOW);
  assert.notEqual(tooSmall.decision?.kind, "treats");
  const recent = pickNudge({ ...base(), lastTreatAwardMs: NOW - 10 * H, markers: { ...m, treatsAt: NOW - 10 * H } }, NOW);
  assert.notEqual(recent.decision?.kind, "treats");
  ok("treats: amount from level rate, minimum, 48h gap");
}

// Streak milestone at 3 days, once, and reset on a new streak.
{
  const s = { ...base(), homeStartMs: NOW - 3 * D, partnerHomeStartMs: NOW - 10 * D, lastTreatAwardMs: NOW - 1 * H,
    markers: { roomLevel: 5, streakStart: NOW - 3 * D, streakMilestone: 0, shopTreats: 20, bellyRubAt: NOW } };
  const r = pickNudge(s, NOW);
  assert.equal(r.decision.kind, "streak");
  assert.match(r.decision.title, /3 days of peace/);
  assert.equal(r.markers.streakMilestone, 3);
  const again = pickNudge({ ...s, markers: { ...s.markers, streakMilestone: 3 } }, NOW);
  assert.notEqual(again.decision?.kind, "streak");
  const newStreak = pickNudge({ ...s, markers: { ...s.markers, streakStart: NOW - 40 * D, streakMilestone: 30 } }, NOW);
  assert.equal(newStreak.decision.kind, "streak");
  assert.equal(newStreak.markers.streakStart, NOW - 3 * D);
  ok("streak: milestone once per streak, reset after a release");
}

// Level-up says the perk only.
{
  const s = { ...base(), homeStartMs: NOW - 4 * D, partnerHomeStartMs: NOW - 4 * D, lastTreatAwardMs: NOW - 1 * H,
    markers: { roomLevel: 4, streakStart: NOW - 4 * D, streakMilestone: 3, shopTreats: 20, bellyRubAt: NOW } };
  const r = pickNudge(s, NOW);
  assert.equal(r.decision.kind, "level");
  assert.equal(r.decision.body, "The fireplace is lit.");
  assert.equal(r.markers.roomLevel, 5);
  ok("level-up: perk-only copy, marker advances");
}

// Belly rub reminder after 5 days, then shop when something became affordable.
{
  const s = { ...base(), lastTreatAwardMs: NOW - 1 * H, lastBellyRubSentMs: NOW - 6 * D,
    markers: { roomLevel: 4, streakStart: NOW - 2 * D, streakMilestone: 0, shopTreats: 20, bellyRubAt: NOW - 6 * D } };
  const r = pickNudge(s, NOW);
  assert.equal(r.decision.kind, "bellyRub");
  assert.equal(r.decision.category, "BELLY_RUB_NUDGE");
  const shop = pickNudge({ ...s, lastBellyRubSentMs: NOW - 1 * D, treats: 200 }, NOW);
  assert.equal(shop.decision.kind, "shop");
  assert.match(shop.decision.body, /Wizard Hat/);
  assert.equal(shop.markers.shopTreats, 200);
  const owned = pickNudge({ ...s, lastBellyRubSentMs: NOW - 1 * D, treats: 200, ownedItemIds: ["hat_wizard", "hat_beanie", "necklace_red"] }, NOW);
  assert.equal(owned.decision, undefined);
  ok("belly rub after 5 days; shop picks the priciest newly affordable, skips owned");
}

console.log(`\nAll ${n} nudge checks passed.`);
