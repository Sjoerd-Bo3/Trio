# Fork feature plan — rebuilding on Trio 1.0

After the dev-based build crash-looped, we reset to the stable upstream **v1.0**
release and confirmed it runs clean. That proved the crash came from fork
changes, not upstream. This document tracks re-adding those changes
deliberately, one at a time, so each stays independently testable and
independently PR-able upstream.

## Branches

| Branch | Base | Purpose |
| --- | --- | --- |
| `build/dev` | upstream `v1.0` | Pristine reference build. Proven stable. |
| `build/altered` | `build/dev` @ 1.0.1 | Personal TestFlight build. Accumulates features **+** fork build glue. |
| `feat/*` | upstream `dev` | One feature each, clean, no fork glue. These are what we PR upstream. |

**Fork build glue never enters a `feat/*` branch.** It lives only on
`build/altered`:

- `com.apple.developer.usernotifications.critical-alerts` entitlement
  (required so the archive matches our provisioning profile)
- `APP_VERSION` / `APP_DEV_VERSION` = 1.0.1
- `MARKETING_VERSION` driven from `$(APP_VERSION)` for every target
  (upstream hardcodes `1.0` on the Watch app and extensions, which App Store
  Connect rejects as a `CFBundleShortVersionString` mismatch)

## Workflow per feature

1. Cut `feat/<name>` from upstream `dev`.
2. Re-apply the feature onto 1.0's structure. The old fork diffs will **not**
   apply as-is — upstream refactored Home, Adjustments and the alert system.
3. Clean to upstream quality: minimal diff, localized strings, tests kept,
   upstream code style.
4. Merge into `build/altered`, push, let Xcode Cloud build.
5. Install and test on device **before** starting the next feature. This is how
   we catch which feature reintroduces a crash.
6. When it is polished, open the upstream PR from the clean `feat/` branch.

## Features

### 1. Loop-ring animation — in progress

`feat/glass-borders`

1.0 replaced the old capsule loop pill with a **ring** that encodes the
automation mode (full / reductions-only / hypo-suspend-only / off) via gaps,
centre symbols and colour. The old `spinningCapsuleBorder` has nothing to wrap
anymore, so the animation was redesigned: while a cycle runs, a bright arc
sweeps around the ring path instead of showing a plain centre `ProgressView`.
The base ring is untouched, and the sweep is accessibility-hidden.

Deliberately implemented natively in SwiftUI rather than porting the fork's
UIKit `DashedSpinnerBorderView`, which was built for capsules and panels. That
keeps this a single-file change.

Still to tune on device: arc length, rotation period, gradient.

### 2. ProfilePresets — not started

The largest feature: a profile-preset switching module with its own Core Data
entity (`ProfilePresetRunStored`), Live Activity data, and an Adjustments tab.

**Prime crash suspect.** It touches persistence *and* the Live Activity
extension, which matches the "even iOS crashed" symptom. Investigate the cause
(Core Data migration, or the Live Activity payload) *before* re-adding it, then
test that build on its own.

### 3. Settings import/export — not started

Backup and restore: a JSON backup model, an import module, and an onboarding
import step.

**Depends on feature 2** — the backup serializes profile-preset data. So either
it goes upstream after ProfilePresets lands, or the upstream PR is scoped to
upstream's own presets (override / temp-target / meal) with profile presets
added later.

## Dropped

- **Per-alert severity overrides.** 1.0's Device Alarms (tiers, day/night
  windows, tone config) supersede it.
- **Contact-image background.** Upstream shipped its own version.
- **Quick-Pick Boluses**, **TDD backfill**, **xDrip sensor expiry**,
  **Add-Glucose autofocus**, **bolus-overlay watchdog**, **onboarding mmol
  import rounding** — not dropped, just not requested yet. Available to re-add
  later from the fork history.

## Upstream state

At the time of writing, upstream `dev` is `v1.0` plus a version bump only — the
two branches are code-identical, so `build/altered` is current with dev.
