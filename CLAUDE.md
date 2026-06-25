# Repository guidance for Claude

## TestFlight "What to Test" notes (Xcode Cloud)

`ci_scripts/ci_post_xcodebuild.sh` runs after every Xcode Cloud archive and
generates `TestFlight/WhatToTest.en-US.txt`, which Xcode Cloud uses as the
build's **"What to Test"** notes. The change list is built automatically from
the branch's **first-parent commit subjects** since its base branch (default
`dev`), with merge subjects tidied (e.g. `Merge nightscout/Trio PR #1203 (...)`
→ `PR #1203 — ...`).

**Because the notes are auto-generated from commit/merge subjects, write clear,
user-facing subject lines:**

- Feature/fix commits: a short imperative summary of the user-visible change,
  e.g. `Allow override percentage down to 10%`, not `wip` / `fixup`.
- When merging a branch or PR, give the merge commit a descriptive subject,
  e.g. `Merge: <what it adds>` or keep the upstream `PR #NNNN (<summary>)` form.
- Avoid noisy internal merges in the first-parent history where possible
  (e.g. repeated `Merge branch 'dev'` syncs) — the script filters the obvious
  ones, but clean history keeps the notes readable.

**Manual note for a specific build:** put text in
`ci_scripts/whattotest_message.txt`; it is prepended above the auto change list.
The generated `TestFlight/` folder is git-ignored.

To change the base branch the notes diff against, set `WHATTOTEST_BASE_BRANCH`
(default `dev`) as an Xcode Cloud environment variable.
