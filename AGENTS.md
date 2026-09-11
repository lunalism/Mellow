# AGENTS.md

## Purpose

This file is the execution entry point for AI coding agents working on Mellow.

Mellow is an iPhone-first Mini Vlog application, and all implementation work must follow the product, design, architecture, decision, roadmap, and development-rule documents in this repository.

This file does not replace those documents.

Its purpose is to tell the agent what to read, how to decide what it is allowed to do, how to execute work, and when it must stop and ask for a decision.

---

## Repository Context

Project name: `Mellow`

Primary platform: iPhone

Primary language: Swift

Primary UI framework: SwiftUI

Minimum deployment target: iOS 18.0

Official device quality baseline: iPhone 12 and later

Primary physical test device: iPhone 12

MVP video standard: 1080p / 30 fps

Mellow is a Mini Vlog app for recording short everyday moments as multiple video clips, lightly arranging and trimming them, previewing the combined result, and exporting a finished video.

Mellow is not a professional video editor.

Mellow is not a photo camera or photo editing app in the MVP.

---

## Required Documents

Before implementing Mellow, read the relevant repository documents.

The core documents are:

- `docs/PRODUCT.md`
- `docs/FEATURES.md`
- `docs/DESIGN.md`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`
- `docs/ROADMAP.md`
- `RULES.md`

`RULES.md` contains the always-on development rules.

`docs/ROADMAP.md` defines the implementation order and Phase gates.

`docs/DECISIONS.md` records accepted and pending decisions.

Do not rely on memory of these documents when the current repository versions are available.

Read the current files before making implementation decisions.

---

## Source of Truth

For product and implementation requirements, use the following order:

1. `docs/PRODUCT.md`
2. `docs/FEATURES.md`
3. `docs/DESIGN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/DECISIONS.md`
6. `docs/ROADMAP.md`
7. `RULES.md`
8. Existing code

`AGENTS.md` defines agent execution behavior but does not silently override product requirements in the source-of-truth documents.

If existing code conflicts with the documents, do not assume the code is correct.

If two source-of-truth documents appear to conflict, stop and report the conflict instead of choosing one silently.

---

## Mandatory Preflight

Before changing files for a development task, perform the following checks.

1. Read `RULES.md`.
2. Read the relevant section of `docs/ROADMAP.md`.
3. Identify the current Phase.
4. Read the relevant sections of `docs/PRODUCT.md`, `docs/FEATURES.md`, `docs/DESIGN.md`, `docs/ARCHITECTURE.md`, and `docs/DECISIONS.md`.
5. Check `git status`.
6. Check the current branch.
7. Confirm that the requested work belongs to the current Phase.
8. Check whether the Phase has an unresolved Decision Gate.
9. Identify the tests required for the requested change.
10. Identify whether iPhone 12 physical-device validation is required.

Do not begin implementation when an unresolved Decision Gate blocks the task.

---

## Current Phase Rule

Work only within the current Phase defined by `docs/ROADMAP.md`.

Do not implement future Phase functionality early.

Do not combine multiple Phases into one implementation task unless the user explicitly changes the Roadmap.

Small structural preparation for the current Phase is allowed only when it is necessary for the current work.

Do not build speculative infrastructure for hypothetical future features.

---

## Scope Rule

Implement only what is required by the current task and current Phase.

Do not add extra features because they are easy, conventional, interesting, or potentially useful later.

Do not silently add options, settings, screens, gestures, permissions, analytics, dependencies, or editing capabilities that are not approved.

When a useful idea falls outside the current MVP or Phase, report it as a possible backlog item instead of implementing it.

---

## Decision Rule

The agent is an implementation agent, not the product decision maker.

Do not silently decide unresolved product, UX, architecture, storage, codec, HDR, camera, export, or scope questions.

Use the blocking-decision criteria in `RULES.md` section 3 for the current Phase or change set.

A decision blocks the current scope when it affects required implementation structure, correctness, media/data/user safety, acceptance, a required gate already due, source-of-truth consistency, or a current unresolved dependency needed to safely perform the next mandatory work immediately after merge.

When a required decision blocks the current Phase or change set, stop the affected implementation and report:

- the exact decision required
- why it is required now
- the current Phase
- the affected requirements
- the available options
- the benefits and drawbacks of each option
- the recommended option
- the expected implementation impact

Continue the affected implementation only after the user approves the decision.

Future Phase-only pending decisions do not block current work, completion, or merge when none of the blocking criteria apply and their required gates have not been reached.

Keep those decisions visible in the appropriate source-of-truth document and linked to their owning Phase or Decision Gate, and resolve them before the required gate is reached.

Do not decide, delete, hide, ignore, or silently defer a pending decision merely to enable merge, and do not use a future label to bypass a current blocker.

Determine whether a decision blocks current work from the source-of-truth documents and Roadmap gates; if it remains unclear, stop the affected work and report the ambiguity instead of guessing.

If new evidence introduces a blocking decision during a Phase, stop the affected implementation and follow the existing Exception and Replanning Protocol.

---

## Replanning Rule

If real implementation evidence shows that the current plan should change, do not force the existing plan and do not branch into a new direction silently.

Follow the Exception and Replanning Protocol in `docs/ROADMAP.md`.

A valid reason for replanning may include:

- an Apple framework limitation
- a reproducible iPhone 12 performance problem
- a data-loss risk
- a draft-corruption risk
- a preview/export parity problem
- a repeated crash
- a confirmed product or UX change from the user

A new library or a more interesting implementation idea is not by itself a reason to replan.

---

## Spike and Experiment Rule

Use `spike/<topic>` or `experiment/<topic>` only when a technical question cannot be answered responsibly without a small prototype or measurement.

A spike must answer a narrow question.

A spike must not become an unapproved product feature.

Keep spike code minimal.

Record measurable results when applicable.

Do not treat successful spike code as production-ready code automatically.

Do not merge experiment code directly into `main` as the default path.

After the experiment, report the result and obtain the required decision before changing production architecture.

---

## Confirmed MVP Guardrails

The following guardrails must not be changed without an approved decision and corresponding documentation update.

- Mellow is iPhone-first.
- The minimum deployment target is iOS 18.0.
- The official quality baseline is iPhone 12 and later.
- The primary physical test device is iPhone 12.
- The MVP standard video profile is 1080p / 30 fps.
- Portrait projects use 9:16.
- Landscape projects use 16:9.
- Project orientation remains fixed for the life of the project.
- Device rotation does not silently change project orientation.
- Rear and front cameras are supported.
- Camera switching is allowed only when not recording.
- Directly recorded clips may be recorded freely up to 10 seconds.
- Recording automatically stops at 10 seconds.
- There are no fixed 1-second, 3-second, or 5-second recording presets in the MVP.
- Imported source videos may be longer than 10 seconds.
- A Mellow project clip may use at most a 10-second segment.
- Photos original media must not be modified or deleted by Mellow.
- Multiple local drafts are supported.
- Drafts do not automatically expire.
- Export does not delete the draft.
- The project has no arbitrary fixed total-duration limit.
- The project has no arbitrary fixed clip-count limit.
- Photo capture and photo editing are outside the MVP.
- 4K export is outside the MVP.
- 60 fps export is outside the MVP.
- Advanced professional editing is outside the MVP.

---

## Architecture Guardrails

Follow `docs/ARCHITECTURE.md` as the implementation architecture.

In particular:

- SwiftUI views must not directly own infrastructure responsibilities.
- `AVCaptureSession` lifecycle must not be implemented directly in SwiftUI views.
- Large video binaries must not be stored as SwiftData blobs.
- Project metadata and media files must remain separated.
- Media references persisted in metadata must use relative paths rather than container-specific absolute paths.
- Media file operations must be isolated behind the media-storage boundary.
- Preview and export must share the same composition definition as far as practical.
- Heavy AVFoundation and file work must not block the Main Actor.
- Media workflows must remain local-first for the MVP.
- Third-party dependencies require explicit approval.
- Do not introduce an over-engineered module or Clean Architecture structure that is not justified by the current MVP.

---

## Media Safety Rule

User media safety has higher priority than implementation speed.

Never knowingly create a flow where a successful recording or import can disappear because of ordinary navigation or view recreation.

Do not create valid clip metadata before the associated media has been successfully created and validated.

Do not delete the Photos source when a Mellow clip or project is deleted.

Do not overwrite the Photos source during trim, crop, normalization, or export.

Do not allow one missing or corrupted clip to crash the entire application or destroy unrelated drafts.

Use staging and safe-finalization flows for new media.

Treat interrupted writes and temporary-file cleanup as part of feature correctness.

---

## Non-destructive Editing Rule

Trim and framing should remain metadata-driven and non-destructive unless an approved architecture decision says otherwise.

Do not repeatedly re-encode project media for ordinary trim or framing changes.

Do not alter source media as the user adjusts an edit.

Apply edit metadata through the shared preview/export composition path.

---

## Main Thread Rule

Do not perform expensive video, file, thumbnail, import, composition-building, or export preparation work on the Main Actor.

UI-facing state updates belong on the Main Actor.

Camera-session mutations must use an appropriate serialized execution context.

Do not assume AVFoundation objects are safe to access from arbitrary concurrency contexts.

Do not suppress concurrency problems with broad `@unchecked Sendable` usage.

---

## Performance Rule

The primary performance reference is iPhone 12.

Do not optimize only for current Pro devices.

Avoid structures that load all video frames or all full-resolution media into memory at once.

Avoid rebuilding the capture session because SwiftUI reevaluates a view.

Avoid rendering an entire preview movie every time the user wants to preview a project.

Avoid copying or decoding long 4K media unnecessarily.

Use Instruments or measurable evidence before introducing complex optimization layers.

---

## Testing Rule

Implementation and tests belong together.

Domain rules should have unit tests.

Media-pipeline behavior should have integration tests where practical.

User-flow behavior should have UI tests where appropriate.

Hardware-specific camera behavior cannot be considered complete based only on Simulator tests.

Do not claim that a test passed if it was not actually run.

Do not claim physical-device validation if the user has not performed it or supplied the result.

---

## iPhone 12 Device Gate

The following areas require iPhone 12 validation when they are implemented or materially changed:

- rear camera preview
- front camera preview
- camera switching
- video recording
- 10-second automatic stop
- microphone audio
- project/device orientation behavior
- haptics
- Photos video import
- 4K source import
- trim interaction
- framing interaction
- multi-clip preview
- export
- Photos save
- Share Sheet
- camera interruptions
- background and foreground camera lifecycle
- meaningful storage-pressure behavior

If implementation is complete but this validation remains, report the Phase or task as `Needs Device Test`, not `Completed`.

---

## Build and Verification Rule

Before reporting a development task complete, run the checks that apply to that task.

At minimum, normally check:

- Xcode build
- relevant unit tests
- relevant integration tests
- relevant UI tests
- compiler warnings
- `git diff --check`
- `git status`
- unexpected file changes

If a required check cannot be run, explicitly state that it was not run and why.

---

## Git Safety Rule

Do not perform destructive or remote Git operations unless explicitly requested.

Do not run `git push` unless the user asked for a push.

Do not merge branches unless the user asked for a merge.

Do not delete branches unless the user asked for branch deletion.

Do not force push.

Do not rewrite shared history.

Do not rebase, squash, or amend existing commits unless explicitly requested.

Do not stage unrelated changes.

Do not discard user changes to make the working tree cleaner.

Always inspect the working tree before making broad changes.

---

## Commit Rule

Keep commits focused and reviewable.

Prefer one clear purpose per commit.

Do not mix documentation cleanup, unrelated refactoring, and feature implementation in the same commit.

Use descriptive commit messages such as:

- `feat: add vlog project domain models`
- `feat: implement camera preview`
- `feat: enforce ten second recording limit`
- `fix: preserve clip after recording interruption`
- `test: cover clip duration policy`
- `docs: record export codec decision`

Avoid meaningless commit messages such as `update`, `changes`, `misc`, or `fix stuff`.

---

## File Modification Rule

Modify only files required for the current task.

Do not reformat unrelated files.

Do not rename large groups of files without an explicit reason and approval.

Do not change product documentation merely to make existing code appear compliant.

Do not create new architectural layers unless the task requires them.

When the user requests one specific document change, do not modify other documents unless the user explicitly asks or a required documentation-sync rule applies.

---

## Markdown Rule

When editing Mellow Markdown documents, keep a single sentence on a single line.

Do not insert manual line breaks inside one sentence.

Normal blank lines between paragraphs are allowed.

Headings, lists, tables, and code blocks may use their normal Markdown structure.

Do not add document version labels during initial drafting.

After the baseline is established, versioning may be introduced only when substantive document changes justify it.

---

## Dependency Rule

Do not add a third-party package, SDK, framework, analytics system, backend service, or build tool without explicit approval.

If a dependency is proposed, explain:

- why Apple-native APIs are insufficient
- what problem the dependency solves
- maintenance health
- license
- privacy impact
- security impact
- binary-size impact
- lock-in risk
- replacement strategy

Important dependency decisions belong in `docs/DECISIONS.md`.

---

## Permission and Privacy Rule

Request permissions contextually when the relevant feature needs them.

Do not ask for broad permissions at launch without a requirement.

Prefer system Photos Picker behavior for video import where possible.

Do not add tracking or analytics without approval.

Do not upload user video or audio to a server as part of the MVP.

Do not log user video frames or audio content.

Avoid logging unnecessary full local file paths or personal-media metadata.

---

## Error Rule

Do not expose raw AVFoundation, SwiftData, FileManager, Photos, or other framework error strings directly to users.

Map infrastructure failures to typed application errors.

Preserve useful technical details for development logging without leaking unnecessary media information.

Failure handling is part of feature completion, especially when media could be lost.

---

## No Fake Completion

Do not report a feature as complete merely because a screen renders.

Do not report a feature as complete merely because the project builds.

Do not report camera or media work as complete merely because a mock or Simulator path works.

Do not silently leave acceptance-critical TODOs behind.

Do not substitute placeholder behavior for production behavior while calling the Phase complete.

If production implementation is done but device validation is outstanding, say so explicitly.

---

## Completion Report

For a substantial implementation task or Phase, report at least:

### Implemented

State what was actually implemented.

### Changed Files

List the files changed and why.

### Tests Run

State exactly which tests and checks were executed.

### Results

Separate passed, failed, and not-run checks.

### Physical Device

State whether iPhone 12 validation is required and whether it has been completed.

### Open Issues

State remaining defects or risks.

### Open Decisions

State any decisions still required.

### Scope Check

Confirm whether the work remained inside the requested Phase and task.

### Next Gate

State whether the current work is ready for review, device testing, commit, merge, or the next Phase.

---

## Phase Completion Rule

A Phase is complete only when the Acceptance Criteria and Exit Criteria in `docs/ROADMAP.md` are satisfied.

Completion and merge also require the current Phase/change set's due Decision Gates to be resolved, no unresolved blocking decision under `RULES.md` section 3, and no source-of-truth contradiction related to the current change.

Future Phase-only pending decisions may remain recorded and linked to their owning gates without blocking current completion or merge; this does not waive required evidence or allow entry into a future Phase whose required gate is unresolved.

If a Phase requires iPhone 12 validation, user confirmation of that validation is part of the gate.

Do not advance automatically to the next Phase.

After a Phase is ready, present the result for review and wait for the appropriate user instruction before merge, push, or beginning the next Phase.

---

## Final Operating Principle

Protect the Mellow product direction from accidental complexity.

Protect user media from loss.

Prefer clear, native, testable implementations over speculative abstractions.

Respect the current Phase.

Respect unresolved decisions.

Use evidence when a plan needs to change.

Do not let implementation convenience silently redefine the product.
