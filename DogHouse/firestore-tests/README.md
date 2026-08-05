# Firestore rules tests

`firestore.rules` is the whole authorization model for DogHouse. It is edited
by hand, it is not type-checked, and a mistake there fails *open* — no other
layer will catch it. These tests are the guard.

## Running

Requires a Java runtime (the Firestore emulator is a Java process):

```bash
brew install --cask temurin
```

Then, from this directory:

```bash
npm install
npm test
```

`npm test` starts the emulator, loads `../firestore.rules`, runs the suite, and
shuts the emulator down. No credentials and no network access to the real
project are involved.

The hook timeout is raised to 60s because the emulator's first start on a busy
machine can take much longer than vitest's 10s default. That failure looks
alarming but is not a rules problem: it reports "Hook timed out" with all tests
*skipped* rather than failed.

Fixture uids must not contain an underscore — see the note at the top of
`rules.test.js`.

## What is covered

| Area | Property under test |
|---|---|
| `users` | single-document reads allowed, **collection enumeration denied** |
| `users` | economy fields (treats, grace, immunity, cards) not client-writable |
| `users` | relocated secrets cannot be written back onto the public document |
| `users/{uid}/private` | unreadable by anyone but the owner — including the partner |
| `doghouseEvents` | clients cannot create events or release themselves |
| `bellyRubs` | sender identity cannot be spoofed |
| `coupleTasks`/`coupleMeta` | the other half of the key must really be your partner |
| `feedPosts` | reactions and roasts confined to your own key |
| `challenges` | a partner's quiz answer cannot be rewritten |
| `idempotencyKeys` | entirely server-side |

## Adding a case

Every new rule needs at least one *denied* test. A rule with only positive
tests will pass even if it grants far more than intended — the enumeration
hole these tests were written for looked correct from the allowed side.
