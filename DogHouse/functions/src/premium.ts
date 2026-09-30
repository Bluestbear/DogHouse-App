// Premium (couple-shared subscription) — the pure decision logic, kept free of
// Firestore so it can be tested with plain node (see test-premium.mjs).
//
// Premium lives on users/{uid} as three server-only fields written by
// revenuecatWebhook: premiumUntil (ms), premiumProductId, premiumUpdatedAt
// (the RevenueCat event timestamp, ms). A couple is premium when EITHER
// partner's premiumUntil is in the future, so unpairing drops it for the
// non-payer without any extra write.

// Subscription products sold on the premium paywall. Only these reach the
// premium handler. The legacy DogHouse+ products (monthly/yearly/lifetime)
// share the entitlement but are never honoured, so routing is on product id,
// not entitlement id.
export const PREMIUM_PRODUCTS: ReadonlySet<string> = new Set([
  "premium_six_month",
  "premium_yearly",
]);

// Legacy DogHouse+ products still attached to the entitlement. Events for
// them are acknowledged and dropped: they must neither grant premium nor
// fall through to the treat-crediting path.
export const LEGACY_SUBSCRIPTION_PRODUCTS: ReadonlySet<string> = new Set([
  "monthly",
  "yearly",
  "lifetime",
]);

// Games a non-premium couple may create per calendar day (creator's time zone).
export const FREE_GAMES_PER_DAY = 1;

export const DEFAULT_TIME_ZONE = "Europe/Berlin";

/** The calendar day of `nowMs` in `timeZone` as "YYYY-MM-DD"; Berlin on a missing or invalid zone. */
export function dayKey(nowMs: number, timeZone?: string): string {
  const fmt = (tz: string) => new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
  });
  let f: Intl.DateTimeFormat;
  try {
    f = fmt(timeZone || DEFAULT_TIME_ZONE);
  } catch {
    f = fmt(DEFAULT_TIME_ZONE);
  }
  const parts: Record<string, string> = {};
  for (const p of f.formatToParts(new Date(nowMs))) parts[p.type] = p.value;
  return `${parts.year}-${parts.month}-${parts.day}`;
}

/**
 * The couple's game counter for the creator's `today`. The day only moves
 * FORWARD: partners in different time zones each use their own "today", and
 * resetting whenever the key merely differed would let them alternate
 * (Tokyo's Tuesday, then Berlin's Monday, then Tokyo's Tuesday again…) for
 * unlimited games. A day earlier than the stored one counts as the stored day,
 * so the couple's limit follows whichever partner's calendar is furthest ahead.
 * YYYY-MM-DD compares correctly as a string.
 */
export function gameDayCount(
  storedDay: unknown, storedCount: unknown, today: string
): { day: string; gamesToday: number } {
  if (typeof storedDay === "string" && storedDay >= today) {
    return { day: storedDay, gamesToday: typeof storedCount === "number" ? storedCount : 0 };
  }
  return { day: today, gamesToday: 0 };
}

type UserLike = { premiumUntil?: unknown } | undefined | null;

/** True when either partner's premiumUntil is later than now. */
export function isCouplePremium(a: UserLike, b: UserLike, nowMs: number): boolean {
  const active = (u: UserLike) => typeof u?.premiumUntil === "number" && u.premiumUntil > nowMs;
  return active(a) || active(b);
}

/** The premium product an event is about, or undefined when it is not a premium event. */
export function premiumProductOf(event: Record<string, unknown>): string | undefined {
  if (event.type === "PRODUCT_CHANGE" && typeof event.new_product_id === "string" &&
      PREMIUM_PRODUCTS.has(event.new_product_id)) {
    return event.new_product_id;
  }
  if (typeof event.product_id === "string" && PREMIUM_PRODUCTS.has(event.product_id)) {
    return event.product_id;
  }
  return undefined;
}

// Event types that set premiumUntil to the event's expiration_at_ms. A trial
// start arrives as INITIAL_PURCHASE with period_type TRIAL and is treated the
// same as a paid purchase. EXPIRATION writes an expiry in the past, and
// SUBSCRIPTION_EXTENDED (a store-side extension) moves it later.
const SETS_EXPIRY = new Set([
  "INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "EXPIRATION",
  "SUBSCRIPTION_EXTENDED",
]);

export type PremiumPatch = {
  premiumUntil: number;
  premiumProductId: string;
  premiumUpdatedAt: number;
};

/**
 * Checks a premium event's shape before any Firestore access. Returns the
 * reason to acknowledge-and-drop it, or undefined when it should be applied.
 * CANCELLATION is a deliberate no-op: access runs to expiry, and the
 * EXPIRATION that follows closes it.
 */
export function premiumSkipReason(event: Record<string, unknown>): string | undefined {
  const type = event.type;
  if (type === "CANCELLATION") return "no change";
  if (typeof type !== "string" || !SETS_EXPIRY.has(type)) return "ignored";
  if (typeof event.id !== "string" || !event.id) return "no event id";
  if (typeof event.expiration_at_ms !== "number") return "no expiration";
  if (typeof event.event_timestamp_ms !== "number") return "no timestamp";
  return undefined;
}

/**
 * The fields to write for a premium event, or "stale" when a newer event has
 * already been applied to this user (RevenueCat does not guarantee order).
 * Call only after premiumSkipReason returned undefined.
 */
export function premiumPatch(
  event: Record<string, unknown>,
  productId: string,
  storedUpdatedAt: unknown
): PremiumPatch | "stale" {
  const ts = event.event_timestamp_ms as number;
  if (typeof storedUpdatedAt === "number" && ts < storedUpdatedAt) return "stale";
  return {
    premiumUntil: event.expiration_at_ms as number,
    premiumProductId: productId,
    premiumUpdatedAt: ts,
  };
}
