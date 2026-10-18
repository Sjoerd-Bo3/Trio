# Backup & Restore

Settings > Backup & Restore saves Trio's configuration to a JSON file and restores it again, and, in builds
with the iCloud capability, keeps automatic and named backups in the user's private iCloud database.

## What a backup holds

A backup is one versioned snapshot (schema 6; schemas 2 to 5 and the earlier settings export format are still
readable). It holds therapy and algorithm settings, basal rates, insulin sensitivities, carb ratios, glucose
targets, delivery limits, the CGM type and plugin, saved override, temp target and meal presets, app and alert
configuration, and Dynamic ISF summaries from the last ten days. A configuration fingerprint detects changes
and tampering.

It never holds pump or CGM pairing state, sign-in details, active overrides or temp targets, or treatment
history. Those travel only in opt-in tiers (see Protected data).

## File backup

Export Backup File and Import Backup File work on every build, with or without iCloud. Files are written
atomically to a temporary location and handed to the share sheet. A file is opened by looking at its content,
not its extension, and is limited to 8 MiB.

## Restoring

Restoring replaces the current configuration after validation and always ends in Open Loop; it never switches
Trio back to Closed Loop. Before anything is written Trio checks that

- no pump is paired,
- no override or temp target is running,
- no earlier restore is still unresolved.

Guarded values are clamped to the limits of the settings screens, and the confirmation screen lists, per
category, which values change. A refused restore changes nothing.

The restore runs as a transaction: a rollback journal records the previous files, presets, alert settings and
Dynamic ISF rows before the first write. The result is verified by reading everything back. If anything fails
the previous state is restored. If Trio is killed in the middle, recovery runs at the next launch before any
therapy service starts. Recovery never blocks startup: if the journal cannot be replayed, Trio forces Open Loop,
holds back closed-loop dosing, and shows a notice in Backup & Restore.

After a restore, Backup & Restore shows a review notice until the user confirms they checked the restored
settings. Automatic iCloud backups pause until then.

### File protection

Therapy files and the journal are written with the default file protection class, exactly like the rest of
Trio's settings, through one helper (`TherapyFileWriter`). Never use complete file protection for them: the loop
reads these files while the phone is locked and would silently fall back to built-in defaults.

## Onboarding

The onboarding flow has a Restore Backup step with Restore From Backup File (and Restore From iCloud when
available) and Start Fresh. A chosen backup is applied once through the same engine, and the onboarding screens
are prefilled from the restored settings so every value is reviewed. Values onboarding has no screen for stay as
restored. The Nightscout steps are unchanged.

## iCloud backups

iCloud backups are optional at build time. `ENABLE_ICLOUD_BACKUP` in `Config.xcconfig` is `NO` by default. Setting
it to `YES` (for example in `ConfigOverride.xcconfig`) selects `Trio-iCloud.entitlements` and defines the
`TRIO_ICLOUD_BACKUP` compilation condition. The App ID and provisioning profile then need the iCloud capability
with the container `iCloud.<bundle identifier>`. Without it, Trio builds and signs as before and the screen shows
file backup only.

- Backups live in a dedicated record zone of the private database. Every backup field is stored in the record's
  encrypted values; no asset is ever used. A payload must fit in 750,000 bytes.
- Trio compares the configuration once per 24 hours (on launch or when it becomes active). A changed
  configuration queues a snapshot; queued snapshots survive restarts and retry later.
- Named manual backups can be made at any time. Manual and automatic backups have separate retention limits
  (3, 5, 10 or 15) and the oldest are removed first.
- Initialize the development CloudKit schema once and deploy it to production before shipping; TestFlight uses
  production. Upload failures are shown in Configuration and never raise alerts.

## Protected data

When exporting a file or making a named iCloud backup, the user can opt in to Nightscout and remote control
sign-in details and to pump and CGM pairing. They are sealed with a passphrase (PBKDF2-HMAC-SHA256, at least
200,000 iterations, then AES-256-GCM; the header and the backup id are authenticated) and are never written in the
clear. The passphrase is never stored or uploaded, so automatic backups never include this tier, and a forgotten
passphrase loses only this tier. Older plain export files with sign-in details can still be read.

Sign-in details are written after the core restore has committed; a failure is only a warning. Remote commands stay
off until the user opens Settings > Services. Pairing is restored only during onboarding, only on a phone without a
pump, only for Medtrum, Omnipod Eros and Medtronic, and only after two confirmations: that the old phone no longer
runs Trio, and a final dialog naming the pump. Omnipod DASH, Dana and unknown pumps are never adopted. Trio stays
in Open Loop and sends no pump command during the restore.

## Implementation

- `TrioSettingsBackup.swift`, `SettingsBackupValidator.swift`, `SettingsBackupDynamicISF.swift`: snapshot,
  normalization, integrity.
- `SettingsBackupRestore.swift`, `SettingsBackupRestoreTransaction.swift`, `SettingsBackupRestorePresets.swift`,
  `SettingsBackupRestoreHistory.swift`: the restore engine.
- `SettingsImportApplier.swift`, `SettingsBackupGuardrails.swift`: guardrails and the change overview.
- `LegacySettingsBackupV1.swift`, `LegacyBackupAdapter.swift`: the earlier export format.
- `BackupService.swift`: capture, export and restore for the running app.
- `CloudKitBackupStore.swift`, `TrioCloudBackupCoordinator.swift`: iCloud storage and scheduling.
- `SealedSensitiveBlob.swift`, `SensitiveRestore.swift`: the protected tier, its envelope and the pump adoption gate.
