<!-- Thanks for the pull request. Please fill in what applies and delete what doesn't. -->

## What this changes

<!-- The behaviour that is different after this merges, and why it needed doing. -->

## How it was tested

<!-- Which of these ran, and on what. Device results carry more weight than simulator
     results for anything involving the keyboard, search, or reminders. -->

- [ ] `swift run coreverify` (52/52 green)
- [ ] `swift test`
- [ ] `xcodebuild test` on a simulator
- [ ] Checked on a physical device

## Non-negotiables

<!-- These are the constraints from README.md and CONTRIBUTING.md. A pull request that
     breaks one of them cannot be merged whatever else it does. Tick to confirm, or
     say below which one this touches and why. -->

- [ ] No analytics, no telemetry, no off-device data transmission
- [ ] Zero-knowledge and encryption-always-on still hold
- [ ] `kSecAttrSynchronizable: false` on every Keychain item
- [ ] No changes to the frozen crypto contract bytes in `Sources/CatchlightCore/Crypto/`
- [ ] No new third-party dependencies

## Anything else

<!-- Screenshots for UI changes, linked issues, follow-up work you deliberately left out. -->
