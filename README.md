# DogHouse

An iOS app for couples. When your partner annoys you, you put them in the doghouse, and
they have to make it up to you before you let them out. The app keeps that short and
light, and it is built so there is never anything to gain from being petty.

Native SwiftUI on iOS 26, Firebase for the backend, RevenueCat for in-app purchases.

## Demo

<!-- TODO: demo video link -->

<!-- TODO: screenshots (Home all-clear, doghouse scene, send sheet, release animation, Shop / Treat Store, friends feed) -->

## How it works

**The loop is send, make up, release.**

1. **Send.** Your partner does something annoying: doesn't text back all day, leaves the
   kitchen a mess. You send them to the doghouse. You write why, and you can say what
   they have to do to get out. They get a notification.
2. **Make up.** Their room turns into a rainy kennel. It looks worse the longer they stay:
   there are 8 visual stages, from 1 hour to 7 days. They can ask to be let out once
   they've done the thing.
3. **Release.** You let them out. A released partner gets an hour of immunity. If they
   asked for release and you confirm it, they get treats.

The rules are there to calm things down. They are enforced on the server:

- **Sends are scarce.** You have 3 sends. One comes back every 24 hours. That keeps a send
  a gesture, not a weapon.
- **Sending costs you too.** A stay in the doghouse resets their room level, and nobody
  earns treats while either partner is in. Being trigger-happy never pays.
- **Making up pays.** The fight has a scripted way out, and taking it earns treats.

There is no running tally of who has been worse. Every stay in the doghouse ends.

**Social layer.** Couples can befriend other couples. When you send your partner to the
doghouse you can post it to your friends, who can take your side or roast them. If
someone from each of two friend couples is in the doghouse at the same time, a 30-minute
jailbreak vote opens among the linked couples. The winner walks free with an hour of
immunity.

**Between sends** there are quizzes, photo dashes, an anniversary race, roses and
cosmetics for your dog. Treats buy the cosmetics.

## Architecture

```
DogHouse/                      Xcode project, firebase.json, firestore.rules
  DogHouse/                    App target
    DogHouseApp.swift          Entry point, root navigation
    AppDelegate.swift          Firebase setup, FCM, the -useEmulator switch
    Services/                  @MainActor ObservableObject singletons (Firestore listeners)
    Views/  Models/
  DogHouseWidget/              Widget extension; shares state through an App Group
  DogHouseTests/               Unit tests (pure logic)
  DogHouseUITests/             XCUITest walkthroughs in demo mode
  functions/src/index.ts       All Cloud Functions (v2, Node 22, TypeScript)
  functions/src/nudges.ts      Engagement-nudge rules (pure, unit-tested)
  functions/e2e-*.mjs          End-to-end checks against the emulator
  firestore.rules              Security rules
  firestore-tests/             Rules test suite (vitest + @firebase/rules-unit-testing)
  public/                      Firebase Hosting: privacy policy, terms, pairing links
scripts/                       Headless build and test wrappers
```

**Client.** SwiftUI only. Dependencies come from Swift Package Manager: Firebase iOS SDK
(Auth, Firestore, Functions, Messaging, Crashlytics, Analytics without IDFA),
GoogleSignIn and RevenueCat `purchases-ios`. Each feature has a service in
`DogHouse/DogHouse/Services/`, for example `DoghouseService`, `FriendService`,
`FeedService`, `ChallengeService` and `PurchaseService`. Each one holds its own Firestore
listeners and publishes state to the views. Every callable goes through `CloudFunctions`,
which pins the region and retries transient errors with backoff. The rooms, doghouses,
avatars and cosmetics are drawn in code with SwiftUI shapes. The only raster images are
the app icon, the launch-screen images and one boot illustration.

**Backend.** Firebase Auth (email, Sign in with Apple, Google), Firestore, Cloud Messaging
and Cloud Functions v2 in `europe-west1`. Every function is in
`DogHouse/functions/src/index.ts`. They fall into four groups:

- **Callables:** the only way to change the economy or link two accounts.
  `sendToDoghouse`, `releasePartner`, `requestRedemption`, `sendRoses`,
  `purchaseCosmetic`, `equipCosmetic`, `claimHomeTreats`, `redeemWishCard`,
  `pairWithCode`, `addCoupleFriend`, `removeCoupleFriend`, `blockUser`, `unblockUser`.
- **Firestore triggers:** push notifications, feed and vote handling, challenge results,
  pairing, account deletion, feedback and report emails.
- **Scheduled jobs:** expire jailbreak votes, anniversary check, random photo dash,
  engagement nudges, idempotency-key and session cleanup.
- **One HTTPS endpoint:** `revenuecatWebhook`.

### Security model

`firestore.rules` and the functions together enforce these rules:

- **The client never writes economy fields.** The rules reject any client write to
  `users/{uid}` that touches `treats`, `graceCharges`, `immunityUntil`, `wishCards`,
  `ownedItemIds`, `lastTreatAward` or `lastGraceRecharge`. Only callables change them,
  through the Admin SDK.
- **Spending callables are idempotent and transactional.** Each one runs
  `runTransaction` inside `once(uid, idempotencyKey, ...)`. `once()` claims an
  `idempotencyKeys/{uid}_{key}` document with an atomic `create()`, replays the stored
  result on a retry, and releases the key only if the operation threw before committing.
  This is why it is safe for the client to retry.
- **Secrets live in a private subdocument.** The pairing code and the FCM token are
  stored at `users/{uid}/private/data`, which only the owner can read. The rules reject
  any write that puts them back on the public profile.
- **No enumeration.** `/users` and `partnerCodes` deny `list`. The client only fetches
  profiles by a uid it already knows.
- **Partner checks are mutual.** Rules only let a client clear its `partnerId` or name
  someone who already points back, so pairing always goes through the `pairWithCode`
  callable, and every partner-scoped callable still checks that the partner's document
  points back (`requireMutualPartner`).

The comments in `DogHouse/firestore.rules` give the reason behind each rule.

## RevenueCat: treat packs

Treats are the in-app currency. You earn them by keeping your room nice and by making
up. You can also buy three consumable packs through RevenueCat:

| Product id | Treats |
|---|---|
| `com.Harrison.DogHouse.treats.small` | 250 |
| `com.Harrison.DogHouse.treats.medium` | 900 |
| `com.Harrison.DogHouse.treats.large` | 1600 |

- **Client** (`DogHouse/DogHouse/Services/PurchaseService.swift`,
  `Views/Shop/TreatPackSheet.swift`). The app reads the `default` offering and buys a
  package through the RevenueCat SDK. It **never credits treats itself**. After a
  purchase, the sheet watches the user's Firestore document until the balance goes up.
  After a 20-second watchdog it re-enables the packs and tells the user the treats are on
  the way.
- **Server** (`revenuecatWebhook` in `functions/src/index.ts`). Only the webhook credits
  treats:
  - It checks the `Authorization` header against the `REVENUECAT_WEBHOOK_SECRET` secret.
  - It maps `product_id` to an amount (`TREAT_PRODUCTS`).
  - It credits inside `once(uid, "treatpack_<transaction_id>")` plus a transaction, so a
    webhook RevenueCat delivers twice credits only once. If `transaction_id` is missing,
    it falls back to the event id.
  - Purchase idempotency keys are kept for 180 days, while other keys are pruned after
    24 hours. That retention window is the replay guard.
  - Refunds and cancellations are logged, not clawed back.
  - `ALLOW_SANDBOX_PURCHASES` controls whether `SANDBOX` events are credited.
- **Keys are split by build.** Debug uses a RevenueCat **Test Store** key (`test_...`),
  so purchases can be faked on the simulator. Release uses the App Store key
  (`appl_...`). `PurchaseService.isUsableKey` refuses placeholders and refuses a `test_`
  key in Release. With a placeholder key, the Shop hides the store. `PurchaseKeyTests`
  covers this.
- **Tests.** `cd DogHouse/functions && npm run e2e:purchases` sends fake RevenueCat
  payloads to the emulated webhook. It covers a bad auth header, a credit, an exact
  replay, an unmapped product, anonymous ids, an ignored `CANCELLATION` and the event-id
  fallback.

Sandbox (TestFlight) purchases are ignored by the webhook unless `ALLOW_SANDBOX_PURCHASES`
in `functions/src/index.ts` is flipped on for a pre-launch test.

## Building

**Requirements:**

- macOS with Xcode 26 or later (developed on Xcode 27.0) and an iOS 26.x simulator. The
  deployment target is iOS 26.0.
- Node 22 and `firebase-tools` for functions and the emulator.
- A Java runtime (JDK 21) for the Firestore emulator.

Run these from the repository root:

```sh
scripts/build.sh            # Debug build for the simulator, prints errors/warnings only
scripts/test.sh             # unit tests (DogHouseTests)
scripts/test.sh ui          # UI tests (DogHouseUITests, demo mode, no backend needed)
scripts/functions-check.sh  # tsc --noEmit on functions/
```

The scripts target `iPhone 17, OS=26.5` by default. To use another simulator, override it,
e.g. `SIM_DEST="platform=iOS Simulator,name=iPhone 16,OS=26.0" scripts/build.sh`.

Backend tests:

```sh
cd DogHouse/firestore-tests && npm ci && npm test   # rules suite; starts its own emulator
cd DogHouse/functions && npm ci
npm run test:nudges                                # pure nudge logic
npm run e2e:security                               # security fixes, against emulators
npm run e2e:purchases                              # RevenueCat webhook
npm run e2e:friends                                # couple friendships
```

The `e2e:*` scripts need `functions/.secret.local` with both dummy secrets (see
Configuration, step 5) and Java on `PATH`. They start the emulators with
`--project doghouse-5e80e`. Change that in `functions/package.json` to your own project
id.

## Configuration

To build and run the app, you need your own Firebase project and your own
`GoogleService-Info.plist`. The app connects to whichever project that file names.

1. **Firebase project.** Create one and enable Firestore, Authentication (Email/Password,
   plus Apple and Google if you want them) and Cloud Messaging. Functions need the Blaze
   plan to deploy. The emulator does not.
2. **`GoogleService-Info.plist`.** Register an iOS app with your bundle id, download the
   file, and put it at `DogHouse/DogHouse/GoogleService-Info.plist`. The path is
   gitignored. The Crashlytics symbol-upload build phase also reads it from there.
3. **Identifiers.** Replace these with your own:
   - The bundle id `com.Harrison.DogHouse`, the widget and test bundle ids, and the
     development team: Xcode target settings.
   - The App Group `group.com.harrisonkrampe.doghouse`: both `.entitlements` files,
     `AuthService.swift`, `HomeView.swift` and `DogHouseWidget/WidgetState.swift`.
   - The Google Sign-In URL scheme: `DogHouse/DogHouse/Info.plist`, `CFBundleURLTypes`.
     Set it to your `REVERSED_CLIENT_ID`.
   - The Firebase project id: `.firebaserc` and `DogHouse/.firebaserc`.
   - The feedback recipient: `FEEDBACK_EMAIL` in `functions/src/index.ts`.
   - The support address: `Legal.supportEmail` in `DogHouse/DogHouse/Models/Legal.swift`.
   - The App Store link and app id in `DogHouse/public/`.
4. **RevenueCat (optional).** Paste your public SDK keys into
   `DogHouse/DogHouse/Services/PurchaseService.swift`: the `test_` key in the `#if DEBUG`
   branch and the `appl_` key in the `#else` branch. These are RevenueCat's
   *publishable* app keys, not secret keys. Without them, the app runs with the store
   hidden.
5. **Function secrets.** Both are declared with `defineSecret`:

   | Secret | Used by |
   |---|---|
   | `REVENUECAT_WEBHOOK_SECRET` | `revenuecatWebhook`: the webhook's `Authorization` header value |
   | `GMAIL_APP_PASSWORD` | `onFeedbackCreated` / `onReportCreated`: nodemailer email to the moderator |

   In production, set them with `firebase functions:secrets:set <NAME>`. For the emulator,
   create `DogHouse/functions/.secret.local` (gitignored) with a dummy value for **both**
   secrets, otherwise the functions emulator will not load:

   ```
   REVENUECAT_WEBHOOK_SECRET=local-dummy
   GMAIL_APP_PASSWORD=local-dummy
   ```

6. **Deploying your own copy.** From `DogHouse/`:
   - `firebase deploy --only firestore:indexes`
   - then `--only functions`
   - then `--only firestore:rules`

## Running the core journey locally (emulator, two simulators)

Debug builds can point Auth, Firestore and Functions at the local Firebase emulator suite,
so two test accounts can pair and play without touching a real backend.

1. **Start the emulators.** In a terminal:

   ```sh
   cd DogHouse/functions && npm ci && npm run build   # the emulator loads lib/index.js
   cd .. && firebase emulators:start --project <your-project-id>
   ```

   - The emulator ports are in `DogHouse/firebase.json`: Auth 9099, Firestore 8080,
     Functions 5001, and the emulator UI at http://127.0.0.1:4000.
   - `singleProjectMode` is on, so `<your-project-id>` must match `PROJECT_ID` in your
     `GoogleService-Info.plist`.
   - Java must be on `PATH`.
2. **Run the app on two iOS 26 simulators with `-useEmulator`.** In Xcode, open
   Product > Scheme > Edit Scheme > Run > Arguments and add `-useEmulator`. Run on
   simulator A, switch the destination, and run on simulator B. `AppDelegate.swift` saves
   the choice in `UserDefaults` (`dh.useEmulator`), so later launches from the icon stay on
   the emulator. Running on B from Xcode stops the app on A, so relaunch A from its
   home-screen icon. Launch once with `-useProduction` to clear the setting. The switch
   exists only in Debug builds.
3. **Sign up and pair.** On each simulator, sign up with email and password, e.g.
   `a@doghouse.test` and `b@doghouse.test`. The accounts exist only in the Auth emulator.
   Go through onboarding. On A, copy the pairing code. On B, enter it. Pairing runs
   through the `pairWithCode` callable.
4. **Play the loop.**
   - On A, swipe Home to your partner's page and send B to the doghouse with a reason.
   - B's home turns into the kennel through the Firestore listener.
   - On B, request redemption. On A, release B, and B gets treats plus an hour of
     immunity.
   - Watch the documents change in the emulator UI.

Limitations of the local setup:

- Simulators get no FCM pushes, so notifications are not delivered. The state arrives
  through listeners anyway.
- Scheduled functions don't run in the emulator.
- The simulator keychain survives an app uninstall. For a clean start, run
  `xcrun simctl keychain <udid> reset`.
- Email sign-up is the path tested against the emulator.

### Demo mode (no backend at all)

The `-demo*` launch arguments work only in Debug builds. `-demoOnboarding` runs
without an account and keeps everything local, so nothing reaches Firebase. On its own it
walks through onboarding and the tour. Add `-demoHome` or one of the tab arguments below
to start on a paired, onboarded profile. The UI tests use the same mode.

| Arguments | Opens on |
|---|---|
| `-demoOnboarding` | onboarding and the live tour with fake data |
| `-demoOnboarding -demoHome` | Home, all clear |
| `-demoOnboarding -demoDoghouseHours 30` | the doghouse scene, 30 hours into a stay |
| `-demoOnboarding -demoHome -demoKick` | the send ("boot kick") animation |
| `-demoOnboarding -demoShop` | Shop and Treat Store, with fake packs and simulated purchases |
| `-demoOnboarding -demoFriends` | Friends tab with a mock feed and jailbreak banner |
| `-holdSplash` | keeps the launch splash on screen |

## License

The source code is released under the [GNU AGPL v3](LICENSE): you may use, study and
modify it, and anything built from it, including a hosted service, must be published
under the same licence.

The DogHouse name, logo, app icon, dog characters and image assets are **not** covered
by the licence. [NOTICE](NOTICE) lists exactly what is reserved.
