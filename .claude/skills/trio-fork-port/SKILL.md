---
name: trio-fork-port
description: >-
  Port an upstream nightscout/Trio change (a PR, a commit, or dev) into the
  Sjoerd-Bo3/Trio "Build-Experiment" fork and verify it via the fork's
  compile-check CI. Use whenever the user asks to "merge <PR#>", "bring in
  <feature> from upstream", "sync dev", or bump submodules/version into their
  build. Encodes the fork's constraints: no upstream backlinks, CI-only build
  verification, pbxproj registration, and fork-specific code gotchas.
---

# Porting upstream Trio changes into Build-Experiment

The target is always **`Sjoerd-Bo3/Trio`**, branch **`Build-Experiment`**. Work on a
short feature branch off `origin/Build-Experiment` and open a PR into `Build-Experiment`.

## Hard rules

1. **Never reference the upstream source in anything pushed to GitHub.** No upstream PR
   number, author, or URL in commit messages, branch names, PR titles, or PR bodies.
   GitHub auto-creates cross-reference backlinks on the upstream PR otherwise, and the
   user does not want that. Describe changes *functionally* instead (e.g. "Add bolus
   initiating state", not "Port #1211").
2. **You cannot build locally.** No Xcode, and the org egress proxy blocks
   `nightscout`/`loopandlearn` repos (403), so submodules can't be fetched. The **only**
   build signal is the `compile_check` GitHub Actions workflow. Verify there, not locally.
3. **The user often merges PRs before CI finishes.** After pushing/PR-ing, schedule a
   check-in to confirm `compile_check` went green. If a merged PR's build is red,
   **fix-forward on a new branch** off `Build-Experiment` — never reopen a merged PR.

## Fetching upstream code (the proxy blocks git)

`git fetch` of nightscout/loopandlearn fails (403). Fetch PR patches over HTTPS instead —
`github.com/.../pull/N.patch` 302-redirects to `patch-diff`, so hit that host directly:

```bash
curl -sSL "https://patch-diff.githubusercontent.com/raw/nightscout/Trio/pull/<N>.patch" -o pr.patch   # mailbox, splits commits
curl -sSL "https://patch-diff.githubusercontent.com/raw/nightscout/Trio/pull/<N>.diff" -o pr.diff      # net diff
```

Retry on transient 502s. To read a value from an upstream tree (e.g. a submodule pin),
`WebFetch` on `https://github.com/nightscout/Trio/tree/<branch>` works where `curl` 403s.

Build-Experiment has **diverged** from upstream `dev` (NSFetchedResultsController Home
refactor, the reusable border component, the reworked bolus card, Quick Bolus). Expect
upstream hunks to conflict; apply with `git apply --3way`/`--reject` and integrate the
rejects by hand rather than forcing a verbatim apply.

## Workflow

```bash
git fetch origin Build-Experiment
git checkout -B feat/<short-name> origin/Build-Experiment
# ... apply/adapt the change ...
# add the branch to compile_check triggers (see below)
git add -A && git commit -m "<functional description, no upstream ref>"
git push -u origin feat/<short-name>
# open a PR into Build-Experiment (no upstream ref); then verify compile_check
```

### Enable CI for the branch

`compile_check.yml` only runs on branches in its `push:` list. Add each working branch:

```yaml
# .github/workflows/compile_check.yml
on:
  push:
    branches:
      - ...
      - feat/<short-name>   # add this
```

The job runs on `macos-26`, selects Xcode, checks out `submodules: recursive` (works on the
GitHub runner — outside the org proxy), and runs
`xcodebuild build-for-testing -scheme "Trio Tests" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
Docs-only branches are skipped (`paths-ignore` covers `**.md`), so a skill/README change
needs no trigger entry.

### Registering a new Swift file in the Xcode project

Any new `.swift` file needs **four** entries in `Trio.xcodeproj/project.pbxproj`, or CI
fails with "Build input file cannot be found". Mirror a sibling file in the same group:

1. `PBXBuildFile` section — `<BUILD_GUID> /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = <FILE_GUID> /* Foo.swift */; };`
2. `PBXFileReference` section — `<FILE_GUID> /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };`
3. The owning `PBXGroup`'s `children` list — `<FILE_GUID> /* Foo.swift */,`
4. The main app target's `PBXSourcesBuildPhase` `files` list — `<BUILD_GUID> /* Foo.swift in Sources */,`

Use two fresh 24-hex-uppercase GUIDs; `grep` the file first to confirm they're unused. Keep
tabs intact (pbxproj is tab-indented). Verify counts afterward: FILE_GUID ×3, BUILD_GUID ×2.

### Bumping submodules (can't fetch the objects locally)

Set the gitlink directly; CI fetches the actual commit:

```bash
git update-index --cacheinfo 160000,<new_sha>,<SubmodulePath>
```

**Never touch `CGMBLEKit`** — it is intentionally pinned at loopandlearn `26ad721`.

## Fork-specific code gotchas

- **`NotificationCenter` is shadowed.** Trio declares its own `NotificationCenter` protocol,
  so `NotificationCenter.default` fails to resolve — and it compiles for the simulator but
  **breaks the archive/release build**. Always use `Foundation.NotificationCenter.default`.
- **Home uses NSFetchedResultsController.** `HomeStateModel` was refactored to NSFRC
  (diverged from upstream's `coreDataPublisher`). Use a per-method
  `let context = CoreDataStack.shared.newTaskContext()`, not a shared `self.context`/
  `backgroundContext` (those don't exist here and cause "cannot find in scope").
- **Reusable spinning/progress border** lives in `Trio/Sources/Views/SpinningCapsuleBorder.swift`:
  - `.spinningCapsuleBorder(isActive:color:)` / `.spinningRoundedBorder(isActive:color:cornerRadius:)`
    — indeterminate rotating dashed border (loop pill, pump reservoir pill).
  - `.progressRoundedBorder(progress:color:cornerRadius:)` — determinate fill; top and
    bottom edges fill left→right symmetrically over a faint track.
  - It animates a `CAShapeLayer` on the render server (off the main thread) to avoid the
    micro-lag that animating a SwiftUI `StrokeStyle.dashPhase` causes. Prefer reusing this
    over a `ProgressView()` spinner.
- **iOS deployment target is 17.0** — `symbolEffect`, `.task(id:)`, ViewBuilder `let`
  bindings, `.sensoryFeedback` are all available.
- **Localization**: this fork does not maintain the `.xcstrings` catalog for ported
  strings; `String(localized: "…")` falls back to the literal, which is acceptable. Don't
  hand-merge xcstrings hunks.

## GitHub access

The GitHub MCP tools are scoped to `sjoerd-bo3/trio` only. Use them for PRs, CI status
(`actions_list` → `compile_check.yml`), and comments. `actions_list` output can be huge —
parse the saved tool-result file rather than reading it inline.
