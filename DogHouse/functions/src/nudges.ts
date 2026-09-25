// Engagement nudges — the decision logic, kept pure so it can be tested with
// plain node (no emulator) and reasoned about without Firestore in the way.
//
// One nudge per user per day at most, only between 09:00 and 21:00 in the
// user's own time zone, and most kinds only for users who have not opened the
// app for a while. Doghouse escalation is the exception: it fires for active
// users too, because it is about the couple's state, not about coming back.
//
// Every kind records a marker on users/{uid}/private/data.nudges so a rerun
// (or the same hour tick on two instances) can never send the same nudge
// twice. Markers are compared before sending and written back after.

export const NUDGE_HOUR_START = 9;   // inclusive, local time
export const NUDGE_HOUR_END = 21;    // exclusive
export const NUDGE_MIN_GAP_MS = 20 * 3_600_000;      // "one per day", tolerant of hourly jitter
export const NUDGE_QUIET_MS = 12 * 3_600_000;         // no app open for this long → "quiet" user
export const TREATS_NUDGE_MIN = 8;                    // don't nudge for pocket change
export const TREATS_NUDGE_QUIET_MS = 24 * 3_600_000;
export const TREATS_NUDGE_GAP_MS = 48 * 3_600_000;
export const BELLY_RUB_NUDGE_MS = 5 * 86_400_000;
export const STREAK_MILESTONE_DAYS = [3, 7, 14, 30];
export const ESCALATION_DAYS = [1, 3, 7];

const HOUR = 3_600_000;
const DAY = 86_400_000;

// Mirrors RoomLevel in Swift: seconds at home → level, treats/hour, and the
// perk each level adds (the push says only what you got, not the numbers).
const ROOM_THRESHOLDS_MS = [0, 1, 6, 24, 72, 168, 336, 720, 1440, 2160].map((h) => h * HOUR);
const ROOM_TREATS_PER_HOUR = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5];
const ROOM_PERKS: Record<number, string> = {
  2: "A chair just appeared in your room.",
  3: "Your dog got a cozy blanket.",
  4: "A pillow and a rug moved in.",
  5: "The fireplace is lit.",
  6: "A TV and some wall art arrived.",
  7: "Plants and a bookshelf. Living the dream.",
  8: "Full luxury. VIP status.",
  9: "Penthouse: aquarium and sunset views.",
  10: "It's a Dog Palace now. Pure royalty.",
};

export function roomLevel(homeMs: number): number {
  let level = 1;
  ROOM_THRESHOLDS_MS.forEach((t, i) => { if (homeMs >= t) level = i + 1; });
  return level;
}

export function treatsPerHour(level: number): number {
  return ROOM_TREATS_PER_HOUR[Math.max(1, Math.min(10, level)) - 1];
}

// Mirrors CosmeticItem.catalog in Swift (names only; prices live in index.ts).
export const COSMETIC_NAMES: Record<string, string> = {
  necklace_red: "Ruby", necklace_blue: "Sapphire", necklace_green: "Emerald",
  necklace_purple: "Amethyst", necklace_pink: "Rose Quartz", necklace_gold: "Gold Chain",
  necklace_bone: "Bone Charm", necklace_heart: "Heart Locket", necklace_rainbow: "Rainbow",
  necklace_diamond: "Diamond",
  hat_beanie: "Cozy Beanie", hat_party: "Party Hat", hat_cowboy: "Cowboy Hat",
  hat_chef: "Chef's Hat", hat_wizard: "Wizard Hat", hat_halo: "Halo", hat_crown: "Crown",
  hat_top: "Top Hat",
  glasses_cool: "Cool Shades", glasses_round: "Round Specs", glasses_heart: "Heart Frames",
  glasses_ski: "Ski Goggles", glasses_star: "Star Frames", glasses_pixel: "Pixel Shades",
};

/** What the scheduler has already done for this user. Stored under private/data.nudges. */
export interface NudgeMarkers {
  lastSentAt?: number;
  /** Highest room level already announced. */
  roomLevel?: number;
  /** The both-home streak the milestone refers to (its start, epoch ms). */
  streakStart?: number;
  streakMilestone?: number;
  /** Escalation stage already sent, per doghouse event id. */
  escalation?: Record<string, number>;
  treatsAt?: number;
  /** Treat balance at the last shop nudge; only items above it are "newly affordable". */
  shopTreats?: number;
  bellyRubAt?: number;
}

export interface ActiveEvent { id: string; startedAtMs: number }

export interface NudgeInput {
  name: string;
  partnerName: string;
  treats: number;
  ownedItemIds: string[];
  /** When my current stay at home began (last release, else account creation). */
  homeStartMs: number;
  partnerHomeStartMs: number;
  myActiveEvent?: ActiveEvent;        // I am in the doghouse
  partnerActiveEvent?: ActiveEvent;   // I sent my partner there
  lastTreatAwardMs?: number;
  /** When I last sent my partner a belly rub, if ever. */
  lastBellyRubSentMs?: number;
  /** Newest of the two account creation dates — the earliest we can be sure they were paired. */
  pairedSinceMs: number;
  lastActiveAtMs?: number;
  timeZone?: string;
  remindersEnabled?: boolean;
  hasToken: boolean;
  markers: NudgeMarkers;
  cosmeticPrices: Record<string, number>;
}

export interface NudgeDecision {
  kind: "escalation" | "treats" | "streak" | "level" | "bellyRub" | "shop";
  title: string;
  body: string;
  data: Record<string, string>;
  category?: string;
}

export interface NudgeResult {
  decision?: NudgeDecision;
  /** Marker fields to persist (init or post-send), possibly without a decision. */
  markers: Partial<NudgeMarkers>;
  reason: string;
}

/** Hour of day (0–23) in the user's zone; falls back to Berlin on a bad zone. */
export function localHour(nowMs: number, timeZone?: string): number {
  const zone = timeZone || "Europe/Berlin";
  const fmt = (tz: string) => new Intl.DateTimeFormat("en-US", {
    hour: "numeric", hourCycle: "h23", timeZone: tz,
  }).formatToParts(new Date(nowMs)).find((p) => p.type === "hour")?.value;
  let hour: string | undefined;
  try { hour = fmt(zone); } catch { hour = fmt("Europe/Berlin"); }
  return Number(hour ?? 12);
}

/**
 * Cheap gate that needs only the private document. The scheduler runs this
 * before loading anything else so the hourly sweep stays inexpensive.
 */
export function preflight(
  p: { hasToken: boolean; remindersEnabled?: boolean; timeZone?: string; markers: NudgeMarkers },
  nowMs: number
): string | undefined {
  if (!p.hasToken) return "no token";
  if (p.remindersEnabled === false) return "reminders off";
  const hour = localHour(nowMs, p.timeZone);
  if (hour < NUDGE_HOUR_START || hour >= NUDGE_HOUR_END) return "quiet hours";
  if (p.markers.lastSentAt && nowMs - p.markers.lastSentAt < NUDGE_MIN_GAP_MS) return "daily cap";
  return undefined;
}

function plural(n: number, unit: string): string {
  return `${n} ${unit}${n === 1 ? "" : "s"}`;
}

function escalationCopy(stage: number, partner: string, iAmSender: boolean): { title: string; body: string } {
  if (iAmSender) {
    switch (stage) {
      case 1: return { title: "🐕 Still in the doghouse", body: `${partner} has been in the doghouse for a day. Ready to let them out?` };
      case 2: return { title: "🌧️ It's raining in the doghouse", body: `Three days now, and it's raining in there. Time to let ${partner} out?` };
      default: return { title: "🥶 It's freezing in the doghouse", body: `A whole week. ${partner}'s dog is freezing. Let them out?` };
    }
  }
  switch (stage) {
    case 1: return { title: "🐕 Still in the doghouse", body: `A day in the doghouse. Make it up to ${partner} to get out.` };
    case 2: return { title: "🌧️ It's raining in the doghouse", body: `It's raining in the doghouse. Time to make it up to ${partner}.` };
    default: return { title: "🥶 It's freezing in the doghouse", body: `A week in the cold. Your dog needs you to make things right with ${partner}.` };
  }
}

export function pickNudge(s: NudgeInput, nowMs: number): NudgeResult {
  const markers: Partial<NudgeMarkers> = {};
  const gate = preflight(s, nowMs);
  if (gate) return { markers, reason: gate };

  // "Quiet" needs a known last-open time: a client that never wrote one is
  // too old to have shipped this feature, and may well be opened daily.
  const quiet = s.lastActiveAtMs !== undefined && nowMs - s.lastActiveAtMs >= NUDGE_QUIET_MS;
  const send = (decision: NudgeDecision, extra: Partial<NudgeMarkers>): NudgeResult =>
    ({ decision, markers: { ...markers, ...extra, lastSentAt: nowMs }, reason: decision.kind });

  // 1. Doghouse escalation — both sides, regardless of activity.
  const escalation = { ...(s.markers.escalation ?? {}) };
  for (const [event, iAmSender] of [
    [s.partnerActiveEvent, true],
    [s.myActiveEvent, false],
  ] as Array<[ActiveEvent | undefined, boolean]>) {
    if (!event) continue;
    const days = (nowMs - event.startedAtMs) / DAY;
    let stage = 0;
    ESCALATION_DAYS.forEach((d, i) => { if (days >= d) stage = i + 1; });
    if (stage === 0 || stage <= (escalation[event.id] ?? 0)) continue;
    escalation[event.id] = stage;
    const copy = escalationCopy(stage, s.partnerName, iAmSender);
    return send({ kind: "escalation", ...copy, data: { type: "doghouse" } }, { escalation });
  }

  const bothHome = !s.myActiveEvent && !s.partnerActiveEvent;
  const homeMs = nowMs - s.homeStartMs;
  const level = roomLevel(homeMs);

  // Level marker: initialise silently, and follow the level down after a
  // doghouse stint so the next climb is announced again.
  if (s.markers.roomLevel === undefined || level < s.markers.roomLevel) markers.roomLevel = level;

  // Streak marker: a new streak (different start) resets the milestone.
  const streakStart = bothHome ? Math.max(s.homeStartMs, s.partnerHomeStartMs) : undefined;
  const streakDays = streakStart !== undefined ? Math.floor((nowMs - streakStart) / DAY) : 0;
  let milestone = 0;
  STREAK_MILESTONE_DAYS.forEach((d) => { if (streakDays >= d) milestone = d; });
  let priorMilestone = s.markers.streakMilestone ?? 0;
  if (streakStart !== undefined && s.markers.streakStart === undefined) {
    // First sight of this user: don't replay milestones they already lived.
    markers.streakStart = streakStart;
    markers.streakMilestone = milestone;
    priorMilestone = milestone;
  } else if (streakStart !== undefined && s.markers.streakStart !== streakStart) {
    markers.streakStart = streakStart;
    markers.streakMilestone = 0;
    priorMilestone = 0;
  }

  // Shop marker: initialise to the current balance so nobody gets a
  // "newly affordable" push for things they could already buy.
  if (s.markers.shopTreats === undefined) markers.shopTreats = s.treats;
  // Belly rub marker: start the clock now, so rollout day is not a flurry of
  // reminders to everyone who hasn't rubbed a belly lately.
  if (s.markers.bellyRubAt === undefined) markers.bellyRubAt = nowMs;

  if (!quiet) return { markers, reason: "active" };

  // 2. Treats waiting at home.
  if (bothHome && nowMs - (s.lastActiveAtMs ?? 0) >= TREATS_NUDGE_QUIET_MS
      && nowMs - (s.markers.treatsAt ?? 0) >= TREATS_NUDGE_GAP_MS) {
    // claimHomeTreats pays hours since lastTreatAward, and only one hour when
    // that was never set — so promise exactly what the claim will deliver.
    const since = s.lastTreatAwardMs ?? nowMs - HOUR;
    const hours = Math.floor((nowMs - since) / HOUR);
    const amount = hours * treatsPerHour(level);
    if (amount >= TREATS_NUDGE_MIN) {
      return send({
        kind: "treats", title: "🦴 Treats are waiting",
        body: `Your room earned ${amount} treats while you were away. Come collect them.`,
        data: { type: "treats" },
      }, { treatsAt: nowMs });
    }
  }

  // 3. Peace streak milestone.
  if (streakStart !== undefined && milestone > priorMilestone) {
    return send({
      kind: "streak", title: `🕊️ ${plural(milestone, "day")} of peace`,
      body: `Nobody's been in the doghouse for ${plural(milestone, "day")}. The room's only getting cozier.`,
      data: { type: "streak" },
    }, { streakStart, streakMilestone: milestone });
  }

  // 4. Room level-up: say what the room got, nothing else.
  const announced = markers.roomLevel ?? s.markers.roomLevel ?? level;
  if (level > announced && ROOM_PERKS[level]) {
    return send({
      kind: "level", title: `🛋️ Room level ${level}!`,
      body: ROOM_PERKS[level],
      data: { type: "level" },
    }, { roomLevel: level });
  }

  // 5. A belly rub is free, and wakes the partner too.
  const lastRub = s.lastBellyRubSentMs ?? s.pairedSinceMs;
  if (nowMs - lastRub >= BELLY_RUB_NUDGE_MS && nowMs - (s.markers.bellyRubAt ?? nowMs) >= BELLY_RUB_NUDGE_MS) {
    return send({
      kind: "bellyRub", title: "🐾 Belly rub time",
      body: `${s.partnerName} could use a belly rub. It's free, and their dog will love it.`,
      data: { type: "belly_rub_nudge" }, category: "BELLY_RUB_NUDGE",
    }, { bellyRubAt: nowMs });
  }

  // 6. Something in the shop became affordable since the last shop nudge.
  const floor = markers.shopTreats ?? s.markers.shopTreats ?? 0;
  const owned = new Set(s.ownedItemIds);
  const newlyAffordable = Object.entries(s.cosmeticPrices)
    .filter(([id, price]) => !owned.has(id) && price <= s.treats && price > floor)
    .sort((a, b) => b[1] - a[1])[0];
  if (newlyAffordable) {
    const [id] = newlyAffordable;
    return send({
      kind: "shop", title: "🛍️ New in budget",
      body: `You can now afford the ${COSMETIC_NAMES[id] ?? id}. ${s.treats} treats in the jar.`,
      data: { type: "shop" },
    }, { shopTreats: s.treats });
  }

  return { markers, reason: "nothing due" };
}
