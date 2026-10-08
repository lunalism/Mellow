# Phase 6 Device Batch 2026-10-07 — Evidence Record, Pre-F4 Rebaseline, F4, F6, F7, Replace (R), K1, F5 and Select Clips Duration (SC) Results

**Status:** Reconstructed record (D0 … F3), a fresh read-only baseline (snap-21), the F4 result (snap-22-S12-F4), the F6 result (snap-24-S14-F6) the F7 result (snap-26-S15-F7, snap-27-S16-F7-reopen) the Editor Replace results (snap-28 … snap-37) the K1 result (snap-39 / snap-40) the seed setup with the F5 result (snap-42 … snap-44) and the Select Clips duration checks (snap-45 … snap-50).

This document is not a Phase 6 Gate completion claim; Phase 6 remains In Progress and Needs Device Test.

## 1. Context

| Field | Value |
| --- | --- |
| Device | LunaTestphone, iPhone 12 (`iPhone13,2`, `00008101-001825E03E10001E`) |
| Installed build | Debug `3ce5d45` (`phase/06-media-import-normalization`), in-place install |
| Projects | DP (disposable) `6986CA3E-EE49-4524-A796-E072127EBC6F`; preserved `B8A7FB31-7EC3-4DC4-B330-3B6D25E31DB0` |
| Rebaseline taken | 2026-10-07T09:59:41Z (18:59 KST), read-only `devicectl copy from` / `info files` only |
| Durable evidence root (outside git) | `/Volumes/Data/dev/Mellow-device-evidence/phase-06/device-batch-2026-10-07/` |
| In-repo evidence | this record and `device-batch-2026-10-07-pre-f4-manifest.txt` (snap-21 baseline, then S12 after F4, S16 after F7, S22 after R2f, S23 after K1 S-2 after SEED / F5 and SC-S4 after the Select Clips checks, plus the K1 source checksum) |

Raw device databases (`default.store*`), media copies and session-transcript extracts stay in the durable root and are never added to git.

## 2. Evidence Loss

The original batch working directory (session scratchpad `/private/tmp/claude-501/…/f760ed17-…/scratchpad`) no longer exists.

Lost with it: the original run sheet file, snapshots snap-00 … snap-20 (store copies, listings, per-snapshot DP hash files), the B8A7FB31 media backups (`dev-base-20261007/media`), the D1-4c workspace copies (`ws-15-S-delay-pre-relaunch`), the F2 / F3 console logs (`f2-console.log`, `f3-console.log`), the synthetic fixture files and their generator, and the original tools.

None of the lost snapshots can be re-inspected.

Everything in section 6 that cites them is a historical report, not evidence still available for inspection.

## 3. Recovery (bounded search)

Searched: the two Claude Code session transcripts that ran the batch (`f760ed17…`, `202b5bc7…`) and `/private/tmp/claude-501/`.

| Item | Result | Where |
| --- | --- | --- |
| Run sheet revision 2 (03:42:50Z) + all five result-log appends | Recovered verbatim | `recovered/RUNSHEET-reconstructed.md` |
| Owner messages (observations as reported) | Recovered verbatim (25) | `recovered/owner-messages-verbatim.txt` |
| Every device-related tool call with its printed output | Recovered (143 calls) | `recovered/transcript-device-ops.txt` |
| `snap.sh`, `verify-b8.sh`, `hash-dp.sh`, `probe.swift` sources | Recovered as printed; rebuilt as new tools | `tools/` |
| B8A7FB31 full SHA-256 (both files) | Recovered: printed in full at backup time (03:24Z) and at every `verify-b8.sh` run through snap-20 | transcript |
| DP full SHA-256 for A14A4519 (F1) and 7AF61025 (F3) | Recovered: printed in full as diff lines at snap-18 / snap-20 | transcript |
| DP full SHA-256 for the other 11 files | **Not recoverable**: only the verdict `DP-MEDIA-IDENTICAL` was printed; the hash files were lost | — |
| Full store dumps of snap-20 | **Not recoverable** in full; only diffs and truncated row lists were printed | — |
| F2 / F3 console logs | **Lost**; only the excerpts quoted in the run-sheet result logs survive | run sheet |

## 4. Fresh Baseline — snap-21-pre-F4-rebaseline

Mellow process at snapshot time: **running, pid 7510**.

Observation gap: snap-20 recorded Mellow not running after F3 (pid 7454, terminated 18:42:58), so pid 7510 was started afterwards by a launch not recorded in this batch; its launch arguments and cause are unknown and are not inferred.

The F4 launch (`--terminate-existing`) ended pid 7510 at 19:06:36 KST; nothing else about that process was observed.

Projects: exactly 2 — `6986CA3E-EE49-4524-A796-E072127EBC6F` (portrait9x16) and `B8A7FB31-7EC3-4DC4-B330-3B6D25E31DB0` (portrait9x16).

DP clip rows (all `imported`, trim = source, not deleted, path `Projects/6986CA3E-…/Media/<clip>.mov`):

| Order | Clip | Duration | Note (from history) |
| --- | --- | --- | --- |
| 0 | `74ACCEBA-B1D8-45A3-A8F2-DE942C7E0BD3` | 3000/600 | M02 exact 5.0 s |
| 1 | `C9C53E23-E67E-435E-80F5-AE4C172A0FAF` | 2761/600 | S1 (D1-1d) |
| 2 | `65EDDD05-F930-4B0B-8261-82BEDF7AD533` | 600/600 | M01 exact 1.0 s (moved in D1-5) |
| 3 | `AB163D20-A682-4645-82A7-3BF10240BDC7` | 1800/600 | M05 60FPS |
| 4 | `D74FCDC9-6A0D-4866-8D7C-25D278D317CC` | 1800/600 | M08 4K SDR |
| 5 | `D47D2BE1-1392-4D3F-AAC2-5652995777BE` | 2341/600 | H1 (D1-2) |
| 6 | `BFB501AA-21B3-41ED-B1BD-462FF0F9FDD2` | 2341/600 | H2 (D1-2) |
| 7 | `4899F476-D07B-4FAA-BF5E-BCB10027121E` | 2262/600 | H3 (D1-2) |
| 8 | `0E9BA7E9-FE44-4041-9313-759D4DFA8077` | 2341/600 | D1-4a commit |
| 9 | `53E3FEDB-3825-4F0B-ABAA-84D9D7297D7A` | 2341/600 | D1-4a commit |
| 10 | `634440FB-B35A-445A-9831-0B516ABB0838` | 2262/600 | D1-4a commit |
| 11 | `A14A4519-FD8C-49A3-9A5A-E35598A93895` | 2341/600 | F1 (H1) |
| 12 | `7AF61025-80E3-4CC2-846A-53B716540BD7` | 2262/600 | F3 (H3) |

B8A7FB31 clip rows: 0 `D987C395-4937-4939-B8D9-FF247B30CDDC` 2681/600; 1 `E2F56144-9DD7-40A4-9F11-094F2A6CBD60` 1766/600.

Counts match the expectation: DP 13, B8A7FB31 2.

Media: 15 files under `Projects/`, each referenced by exactly one row, no unreferenced file; full SHA-256 of every file is in `device-batch-2026-10-07-pre-f4-manifest.txt`.

Workspace / staging: `ProjectWorkspace` empty (mtime 10/7 18:42), `CaptureStaging` empty (mtime 9/18).

tmp: 1959 entries, all pre-existing test-host residue (profraw, `MellowTestFixtures-*`, `CameraModelTests-*`, dated 10/2 or earlier) except two empty directories touched 10/7 18:42 (`ProjectMediaTransfer`, `TemporaryItems`, 64 bytes each); no file was found that an import left behind.

## 5. Continuity Since F3 (what the fresh baseline can and cannot show)

Full-hash continuity (a full SHA-256 recorded at the time equals the snap-21 full SHA-256):

- B8A7FB31 `D987C395…` = `237e55c4bdca73da2f6204ba11d92232a0e70e7530a31c17daec714c5ae75a55` (backup 03:24Z, every verify through snap-20, snap-21).
- B8A7FB31 `E2F56144…` = `29f50685b7a5b5fc44f4b4696632f937ce38c49b7cea6017282c2db21b19a7d6` (same).
- DP `A14A4519…` = `7c30ee3d3c746c0fcc77c5d91fe9dcde560b92e08cb7a7591bc334104b3e5dba` (snap-18, snap-21).
- DP `7AF61025…` = `24864e429e4172ef22a0ec851914552d60acad6833ee5349c6c75c89127a0a9b` (snap-20, snap-21).

The B8 backup files themselves are lost, so this continuity rests on the full hashes printed in the transcript, not on a re-comparison against the backup bytes.

The other 11 DP media files have no recoverable earlier full hash: snap-21 establishes their baseline but cannot independently prove they are unchanged since F3; earlier identity rests on the historical `DP-MEDIA-IDENTICAL` reports only.

Store rows: no full earlier dump is recoverable; snap-21's 15 rows are consistent with the reported history (S2 order, D1-5 move to index 2, F1 and F3 appends) but cannot be byte-compared with snap-20.

Matching hash prefixes from earlier snapshots are not treated as proof of byte identity anywhere in this record.

## 6. Completed Test Record (historical reports)

Sources: owner messages (`recovered/owner-messages-verbatim.txt`), run-sheet result logs (`recovered/RUNSHEET-reconstructed.md`), snapshot outputs printed in the transcript; the snapshots themselves are lost unless marked otherwise.

| Step | Owner report (as given) | Recorded snapshot result (historical) |
| --- | --- | --- |
| D0 | D0-4 PASS: DP opened as an empty Editor | DP created; 2 projects |
| D1-1a | PASS: exact 1.0 s and 5.0 s added | S2: 600/600 and 3000/600 |
| D1-1b | Short-video alert observed; count / duration not separately reported | — |
| D1-1c | Long-video alert and clip preservation; the two attempts not reported separately | — |
| D1-1d | Existing two clips remained, only S1 added, exclusion alert appeared | S2: S1 = `C9C53E23` 2761/600, stored as `hvc1` (not normalized) |
| D1-1e | Long-video exclusion alert; three clips remained | — |
| D1-1f | Preparation message and exclusion alert; only 60FPS added | S2: 1800/600 |
| D1-1g | Five clips, landscape excluded, an alert; wording and sheet not confirmed | S2: 5 clips |
| D1-2 | ~2–3 s per video, no Back during preparation, edge swipe blocked, Undo / Redo worked; drag was only after completion (correction) | S3: 8 clips |
| D1-3 | Sheet closed on Cancel, no alert, 8 clips, + worked; counter at cancel not confirmed | S4: 8 clips, no leftovers |
| D1-4a | Killed at 2/3 | S5: 11 clips — all three committed before the kill; **INCONCLUSIVE** for kill-during-preparation |
| D1-4b | Relaunch: 11 clips, no sheet / resume / alert | S6: identical to S5 |
| D1-5 | Snap-back seen; order persisted; not an overall PASS | snap-10: order saved |
| D1-5 retest (3ce5d45) | No snap-back both directions; Undo / Redo / reopen correct; Back stayed visible (pending interval not measured) | snap-13: order saved, media identical |
| D1-4c | Sheet paused ~8 s; killed at 2/3; relaunch 11 clips, no sheet / resume / alert | snap-15: workspace held 3 source copies + item-1 output, store unchanged; snap-16: workspace swept, store unchanged; preparation-phase only, not mid-write |
| D1-6a/b | PASS as expected; DP 11 | snap-17: unchanged |
| F1 | Failure alert (wording not transcribed); Retry added H1; Undo / Redo correct | snap-18: +1 row `A14A4519` + 1 file; no logs captured |
| F2 | PASS with exact copy; Cancel closed quietly; DP 12 | snap-19: unchanged; console excerpt in run sheet (log file lost) |
| F3 | PASS; failure alert, then CR shortage alert, then Retry added; DP 13 | snap-20: +1 row `7AF61025` + 1 file; console excerpt in run sheet (log file lost) |

F4, F6, F7, the Replace steps, K1, F5 and the Select Clips checks are recorded in sections 9 to 15 with evidence that is still inspectable.

F5 was postponed by owner decision because its `+ 새 프로젝트 시작` flow replaces the current saved Project, which was DP; it ran later against a separately seeded disposable replacement target (section 14).

## 7. S1 Source Correction and Fast-Path Check

The run sheet's prerequisite listed S1 and S2 as ~3 s, 1080p 30, HDR off camera clips; only S1 was recorded (S2 was a checkpoint name, not a source), and F4 / F6 / F7 must use S1.

S1's facts come from its committed DP copy `C9C53E23`, probed again at snap-21: QuickTime `.mov`, video `hvc1` (HEVC, not H.264), `hvcC` general_profile_idc 1 (Main), 8 bits per component, Rec.709 primaries / transfer / matrix, encoded 1920×1080 with a 90° transform (presentation 1080×1920, portrait), nominal 29.978 fps (min frame duration 20/600), duration 2761/600 s, AAC 48 kHz stereo, no Dolby Vision atom.

A ready item is materialized by moving the picker-transferred file unchanged, so this copy carries the source's facts.

Against `ImportPreflightClassifier` at `3ce5d45` (no `MellowApp/Core` change since `71279e6`): HEVC is a supported family; portrait; 1.0 ≤ 4.60 ≤ 5.0 s; no HDR signal (Rec.709, 8-bit, Main profile, no DV); 29.978 ≤ 30.5; 1080×1920 does not exceed the 1080p class; AAC passes through — no normalization reason, so `readyFastPath`.

D1-1d already imported S1 as `hvc1`, which is direct evidence it took the fast path on this device (any normalized output is H.264).

The fast path skips only preparation: the C1 admission check runs before it for every first attempt, and the requirement always includes the 256 MiB Import Safety Reserve, so a simulated 0 usable bytes refuses even a ready-only set.

## 8. Corrected F4 Plan (as issued before launch)

| Field | Value |
| --- | --- |
| Launch | `devicectl device process launch --terminate-existing --console` with `OS_ACTIVITY_DT_MODE=enable`, only `-uiTestImportCapacityShortage=c1:1` |
| Target | DP `6986CA3E…`, Editor Add |
| Source | **S1** (HEVC Main 8-bit Rec.709, 2761/600) |

| Step | Action | Expected |
| --- | --- | --- |
| F4-0 | Launch | Console: `UI-test device import controls active: normalizer=false capacity=true` |
| F4-1 | Add → S1 | No preparation sheet. Console: `UI-test capacity override boundary=c1BeforePreparation usable=0 (simulated)` then `Import attempt admission refused … boundary=c1BeforePreparation`. Alert `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` with no `다시 시도`. DP stays 13 clips. |
| F4-2 | Add → S1 again, same launch | No override line; no preparation sheet; S1 is appended once → DP 14, new last row `imported` 2761/600, exactly +1 media file (`hvc1`). No success log line is expected. Then terminate Mellow. **[S12]** |

At S12 expect: the 13 prior rows and their 15 media hashes equal snap-21; ProjectWorkspace empty; B8A7FB31 unchanged.

The same alert copy is also produced by the C0 pre-copy admission during the picker transfer, so only the `boundary=c1BeforePreparation` console line proves C1.

The C1 count is consumed only after the picker transfer and preflight; a cancelled picker or an excluded source leaves it unconsumed.

This is a simulated capacity-check outcome, not disk exhaustion or an out-of-space write.

## 9. F4 Result — simulated C1 (first-attempt admission) shortage, Editor Add of S1

Classification: a SIMULATED C1 capacity-check outcome (`usable=0` reported by the Debug control), not actual disk exhaustion or an out-of-space write.

| Field | Value |
| --- | --- |
| Build | Debug `3ce5d45`, installed in place (unchanged since D1-5 retest) |
| Launch | 2026-10-07 19:06:36 KST, `devicectl device process launch --terminate-existing --console` with `OS_ACTIVITY_DT_MODE=enable`, only `-uiTestImportCapacityShortage=c1:1`; pid 7513 |
| Target / source | DP `6986CA3E…`, Editor Add; S1 twice |
| Console log | `logs/f4-console.log` in the durable root (110 lines) |
| Snapshots | before: snap-21-pre-F4-rebaseline; after: snap-22-S12-F4 (Mellow not running) |

Owner observations (as reported):

- F4-1: the alert title was `저장 공간이 부족해요` and the message `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.`, with one button, `확인`.
- Neither F4 attempt showed a preparation sheet.
- F4-2 finished with 14 clips.
- The exit at 19:07:17 was the owner's manual App Switcher swipe-away.

Captured console (`[app]` lines, KST):

- 19:06:36.930 `UI-test device import controls active: normalizer=false capacity=true`.
- 19:06:37.145 `Recovery complete dirsRemoved=0 mediaRemoved=0 referenced=15 noncanonical=0 failures=0 skippedLive=0 emptyStoreGuard=0 rowsUnreadable=0`.
- 19:06:54.448 `Project editor loaded 6986CA3E-… clips=13 total=47.4s`.
- 19:07:00.664 `UI-test capacity override boundary=c1BeforePreparation usable=0 (simulated)`.
- 19:07:00.664 `Import attempt admission refused project=6986CA3E boundary=c1BeforePreparation`.
- No later import line (the success path does not log); 19:07:17 `The app terminated with the exit code 0.` (the owner's swipe-away).

The `boundary=c1BeforePreparation` line is what attributes the alert to C1; the same copy can also come from the C0 pre-copy admission during the picker transfer.

S12 snapshot (snap-22-S12-F4) versus snap-21:

- Store: exactly +1 row — DP order 13 `1FCE13D8-699F-47CD-92B9-0AE5140F6A4E`, `imported`, src = trim = 2761/600, not deleted. DP 14, B8A7FB31 2, 2 projects.
- Media: exactly +1 file, `Projects/6986CA3E-…/Media/1FCE13D8-….mov`, referenced by that row; every row references an existing file and no file is unreferenced.
- The prior 15 media files' full SHA-256 are identical to snap-21 (full manifest comparison).
- The new file's SHA-256 `9b4fd2124be9835e386fecad570df61337423e3af64db2081eba8e8f0f26485c` equals S1's earlier copy `C9C53E23` — the ready item was materialized byte-for-byte; probe: `hvc1` Main 8-bit Rec.709, presentation 1080×1920, 2761/600, AAC 48 kHz stereo.
- ProjectWorkspace empty (mtime 19:07, used and cleaned); CaptureStaging empty; tmp entry names identical to snap-21.

Verdict: F4 PASS — owner-observed UI plus captured C1 injection log plus snapshot.

Limitations: one C1 refusal on a ready-only set via the Editor Add route; Select Clips C1 (F5) is not yet run; the 11 DP files without recovered earlier full hashes are compared only from snap-21 onward.

## 10. F6 Result — Editor Add with every Editor save failing (`-uiTestEditorSaveFailure`)

Classification: a Debug repository seam whose `update` always throws; this exercises the Retry-failure path only, not Retry success.

| Field | Value |
| --- | --- |
| Build | Debug `3ce5d45` (unchanged) |
| Launch | 2026-10-07 19:15:56 KST, `devicectl device process launch --terminate-existing --console` with `OS_ACTIVITY_DT_MODE=enable`, `com.mellow.Mellow -- -uiTestEditorSaveFailure`; pid 7518 |
| Target / source | DP `6986CA3E…` (14 clips), Editor Add; S1 |
| Console log | `logs/f6-console.log` in the durable root |
| Snapshots | before: snap-23-pre-F6 (store and 16 media hashes identical to snap-22-S12-F4); after: snap-24-S14-F6 (Mellow not running) |

Launch notes:

- A first launch attempt failed with devicectl exit 64 because devicectl parsed `-uiTestEditorSaveFailure` as its own options; nothing was launched, and the error output is kept as `logs/f6-attempt1-argparse-error.log`. App arguments without `=value` must follow `--`.
- Observation gap: Mellow was running as pid 7517 before the launch, started after F4 by a launch not recorded in this batch; its options and cause are unknown and not inferred, and `--terminate-existing` ended it.
- This seam writes no activation log line and devicectl does not report process arguments, so activation is established by the save-failure log lines below; the console had no `controls active` line (no normalizer or capacity control).

Owner observations (as reported):

- The initial attempt and the Retry both showed the title `영상을 준비하지 못했어요`, the message `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.` and the buttons `다시 시도` / `취소`.
- No preparation sheet appeared.
- The owner tapped `다시 시도` once, then `취소` on the repeated alert; DP still showed 14 clips afterwards.
- The exit at 19:16:54 was the owner's manual App Switcher swipe-away.

Captured console (`[app]` lines, KST):

- 19:15:57.460 `Recovery complete dirsRemoved=0 mediaRemoved=0 referenced=16 noncanonical=0 failures=0 skippedLive=0 emptyStoreGuard=0 rowsUnreadable=0`.
- 19:16:42.098 `Project editor loaded 6986CA3E-… clips=14 total=52.0s`.
- 19:16:45.526 `Import attempt save failed project=6986CA3E: domain=Mellow.(unknown context …).UpdateFailingProjectRepository.SaveFailure, code=1` (initial attempt).
- 19:16:49.622 the same line again (the one Retry).
- No further import line; 19:16:54 `The app terminated with the exit code 0.` (the owner's swipe-away).

S14 snapshot (snap-24-S14-F6) versus snap-23-pre-F6:

- Store rows identical (DP 14, B8A7FB31 2, 2 projects).
- All 16 media files' full SHA-256 identical; listing paths identical, so no media was added or left behind.
- ProjectWorkspace empty (mtime 19:16, used and cleaned); CaptureStaging empty; tmp entry names identical.

Verdict: F6 PASS — owner-observed UI plus two captured save-failure log lines plus snapshot.

Limitations: Retry success after a save failure is not reachable with this seam; the Retry was exercised once.

## 11. F7 Result — Editor Add whose save lands but cannot be verified (`-uiTestEditorSaveUnverified`), then normal reopen

Classification: a Debug repository seam that forwards every save but makes the post-save observation unreadable, producing the U1 (save unverified) reconciliation lock; U2 is not reachable with this seam.

| Field | Value |
| --- | --- |
| Build | Debug `3ce5d45` (unchanged) |
| Launch A | 2026-10-07 19:20:52 KST, `devicectl device process launch --terminate-existing --console` with `OS_ACTIVITY_DT_MODE=enable`, `com.mellow.Mellow -- -uiTestEditorSaveUnverified`; pid 7521; Mellow was not running before it |
| Launch B | owner's normal Home Screen launch, no options, no console; pid 7525 |
| Target / source | DP `6986CA3E…` (14 clips), Editor Add; S1 |
| Console log | `logs/f7-console.log` in the durable root (launch A only) |
| Snapshots | before: snap-25-pre-F7 (store and 16 media hashes identical to snap-24-S14-F6); after launch A: snap-26-S15-F7 (Mellow not running); after launch B: snap-27-S16-F7-reopen (Mellow running) |

The seam writes no activation log line; the console had no `controls active` line, and activation is established by the save-unverified log lines below.

Owner observations (as reported):

- F7-1: the alert title was `저장 확인이 필요해요` and the message `변경사항은 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 열어 확인해주세요.`, matching the expected wording exactly.
- F7-2: `프로젝트 화면으로` returned to the Projects screen; the exit at 19:21:30 was the owner's manual App Switcher swipe-away.
- Whether a preparation sheet appeared during the Add was not separately reported.
- F7-3: after a normal Home Screen relaunch and reopening the project, DP showed 15 clips with S1 last, and no lock, alert or preparation sheet appeared.

Captured console, launch A (`[app]` lines, KST):

- 19:20:52.624 `Recovery complete dirsRemoved=0 mediaRemoved=0 referenced=16 noncanonical=0 failures=0 skippedLive=0 emptyStoreGuard=0 rowsUnreadable=0`.
- 19:21:20.373 `Project editor loaded 6986CA3E-… clips=14 total=52.0s`.
- 19:21:24.405 `Import attempt save unverified project=6986CA3E reason=unreadable; media preserved`.
- 19:21:24.406 `Project editor import save uncertain; media preserved`.
- 19:21:28.182 `Projects entry saved project: 6986CA3E-…` (back on the Projects screen).
- 19:21:30 `The app terminated with the exit code 0.` (the owner's swipe-away).

Launch B has no console capture (Home Screen launch).

S15 snapshot (snap-26-S15-F7) versus snap-25-pre-F7:

- Store: exactly +1 row — DP order 14 `C8846E32-10C8-41EE-B54D-9A72E0B5786D`, `imported`, src = trim = 2761/600, not deleted. DP 15, B8A7FB31 2, 2 projects.
- Media: exactly +1 file, `Projects/6986CA3E-…/Media/C8846E32-….mov`, referenced by that row; every row references an existing file and no file is unreferenced.
- The prior 16 media files' full SHA-256 are identical to snap-25.
- The new file's SHA-256 equals S1's (`9b4fd2124be9835e386fecad570df61337423e3af64db2081eba8e8f0f26485c`); probe: `hvc1` Main 8-bit Rec.709, presentation 1080×1920, 2761/600, AAC 48 kHz stereo.
- ProjectWorkspace empty (mtime 19:21, used and cleaned); CaptureStaging empty; tmp entry names identical.

S16 snapshot (snap-27-S16-F7-reopen) versus S15:

- Store rows and order identical; all 17 media files' full SHA-256 identical, including both B8A7FB31 files; listing paths identical.
- ProjectWorkspace and CaptureStaging empty; tmp entry names identical.

Verdict: F7 PASS — the save landed exactly once while the Editor reported U1, media was preserved, and a normal reopen showed the committed state without a lock; based on owner-observed UI, captured log lines and two snapshots.

Limitations: preparation-sheet absence during F7's Add was not separately observed; U2 (save indeterminate) remains unit-tested only; launch B has no console.

## 12. Editor Replace (R) — unavailable-clip Replace, rejections, cancellation and completion

All R steps target DP; B8A7FB31 is never a target. Each media removal was separately approved by the owner and scoped by `-uiTestRemoveActiveClipMedia=<clip>` plus `-uiTestRemoveActiveClipMediaProject=<DP>` (the app refuses unless the clip is an active Clip of the named Project at its canonical path); before each removal the target file was backed up twice in the durable root, write-protected and reverified by full SHA-256.

### 12.1 R1 — make X = `C8846E32-10C8-41EE-B54D-9A72E0B5786D` (slot 15, the F7 clip) unavailable

- Backups: snap-27 and snap-28 copies, `9b4fd2124be9835e386fecad570df61337423e3af64db2081eba8e8f0f26485c` (equal to the S16 manifest).
- Launch: 19:29:21 KST, pid 7529, `-- -uiTestRemoveActiveClipMedia=C8846E32-… -uiTestRemoveActiveClipMediaProject=6986CA3E-…`; it ended the owner's F7-3 process pid 7525.
- Console: `UI-test unavailable fixture applied: clip=C8846E32 media removed, metadata kept active`; recovery referenced DP 14 + B8 2, removed 0, failures 0.
- Owner: tapping the last clip showed `클립을 사용할 수 없어요` / `파일을 찾을 수 없어요.` with the button reported as `클립교체` (source string `클립 교체`; the spacing on screen was not separately confirmed); the other clips looked normal; nothing was changed; exit by owner swipe-away.
- S17 (snap-29, confirmed by snap-30) versus snap-28: store identical (X active); the only media / listing difference is X's missing file; the other 16 full SHA-256 identical; workspace, staging and tmp clean.

### 12.2 R2a–R2d — invalid replacements of X (owner's normal launch, no console)

Owner observations, as transcribed (spelling and spacing differences from the source strings are not treated as verified UI defects):

| Step | Source | Owner-reported alert | Sheet | Result |
| --- | --- | --- | --- | --- |
| R2a | M04 (5.5 s) | `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요` / `확인` | none | X stayed unavailable |
| R2b | M03 (0.8 s) | `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.` / `확인` | none | X stayed unavailable |
| R2c | M07 (landscape) | `지원하지 않는 영상이예요` / `세로영상을 선택해주세요.` / `확인` | none | X stayed unavailable |
| R2d | M06 (MP4) | `영상을 추가할 수 없어요.` / `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.` / `확인` | not reported | X stayed unavailable |

Source strings at `3ce5d45` for reference: `5초 이하의 영상을 선택해주세요.`, `지원하지 않는 영상이에요`, `세로 영상을 선택해주세요.`, `영상을 추가할 수 없어요`.

S18 (snap-31) versus S17: store, 16 media full SHA-256 and listing paths identical; workspace used at 19:37 and empty; staging empty; tmp names identical.

Owner verdict: PASS for invalid-input rejection and preservation of the unavailable target, supported by the reported alerts and the unchanged S18 snapshot; preparation-sheet appearance was not separately reported for R2d.

### 12.3 R2e — first cancellation attempt missed (normal launch, no console)

The owner reports that the Replace preparation finished before `취소` could be tapped, so no cancellation was exercised and no PASS is recorded.

S19 (snap-32, owner's process pid 7538 running) versus S18: X's row was soft-deleted (deletedAt 19:42:10 KST, kept for session Undo); new active row `588C39AD-E9BA-4AFB-B54C-F6E7EF7AFFA7` at order 14 (slot 15), 2341/600 (H1); +1 file `3a769474fbc7e18b60b5e06872bc515f17d3e8e954fd4e603960c28d5d135f88` (H.264 High 1080×1920, AAC stereo); the other 14 active rows, 16 media hashes and B8A7FB31 unchanged; workspace empty.

### 12.4 R2e′ first try — blocked on a valid clip

- Launch: 19:47:30 KST, pid 7548, `-- -uiTestNormalizerDelay=8000`; console `controls active: normalizer=true capacity=false`; startup cleanup finalized X's soft-deleted row (`Cleanup file already absent clip=C8846E32`, `Cleanup metadata finalized clip=C8846E32`, `finalized=1 removed=0 deferred=0`).
- Owner: the valid slot-15 clip `588C39AD` offered no `클립 교체`; nothing was attempted (its console shows no import line; the process was later ended by the R1′ launch, signal 9).
- Cause, by design at `3ce5d45`: `ProjectEditorModel.canReplaceSelectedClip` requires the selected Clip to be derived-unavailable (ADR-040: healthy Clips never expose Replace), and `클립 교체` exists only in the unavailable-clip shell; the plan had wrongly targeted a valid clip.

### 12.5 R1′ — revised setup: make `588C39AD` unavailable

- Backups: snap-32 and snap-33 copies, write-protected, 7,365,844 bytes, `3a769474…5f88`, reverified against both manifests.
- Pre-launch baseline snap-34: identical to snap-33 except X's row is gone (finalized above); DP 15 active rows, 17 media.
- Launch: 19:52:04 KST, pid 7550, `-- -uiTestRemoveActiveClipMedia=588C39AD-… -uiTestRemoveActiveClipMediaProject=6986CA3E-…`; console `UI-test unavailable fixture applied: clip=588C39AD media removed, metadata kept active`; recovery DP 14 + B8 2, removed 0, failures 0.
- Owner: slot 15 showed `클립을 사용할 수 없어요` / `파일을 찾을 수 없어요.` / `클립 교체`; DP 15, other clips normal; no replacement attempted; exit by owner swipe-away.
- S20 (snap-35) versus snap-34: store identical (`588C39AD` active); the only media / listing difference is `588C39AD`'s missing file; the other 16 full SHA-256 identical (B8A7FB31 equal to its recorded full hashes); workspace, staging and tmp clean.

### 12.6 R2e′ — delayed cancellation during the pre-conversion Debug delay

- Launch: 19:54:49 KST, pid 7552, `-- -uiTestNormalizerDelay=8000`; console `controls active: normalizer=true capacity=false`; recovery DP 14 + B8 2, removed 0; 19:55:05 Editor loaded DP 15; no import, normalizer or cancel line afterwards; 19:55:41 app terminated (exit 0).
- Owner observations (reported in the coordination chat; recorded here after the first version of this section wrongly listed them as missing): the preparation sheet appeared and no counter was seen; the owner tapped `취소` immediately during the initial pause; the sheet closed without an alert; DP remained at 15 clips; the last clip remained unavailable; the owner then swiped Mellow away manually and had not reopened it when asked about pid 7556.
- S21 (snap-36) versus S20: store, 16 media full SHA-256 and listing paths identical; ProjectWorkspace empty but modified at 19:55 (used and cleaned during this launch); tmp names identical.
- Observation gap: at S21 Mellow was running as pid 7556, a launch after pid 7552 ended that this batch did not perform; the owner reports having swiped Mellow away and not having reopened it at that time; its options and cause are not inferred.
- Verdict: PASS for Replace cancellation during the Debug delay before conversion (owner UI plus S21 showing no row or media change and an empty workspace); it does not cover cancellation during an active file write.

### 12.7 R2f — successful Replace of unavailable `588C39AD` with H3, Undo / Redo, reopen

- Launch: the owner reports a Home Screen open; there is no console, and because pid 7556's origin is unknown, a no-option execution is not verified.
- Owner: H3 replaced the unavailable last clip and finished; DP stayed 15 and the replacement played; Undo restored the unavailable clip; Redo restored the replacement; leaving and reopening kept 15 clips and the replacement; then swiped away.
- S22 (snap-37, Mellow not running) versus S21:
  - Order 14: the `588C39AD` row is no longer in the store (no deleted row remains); new active row `71CDF383-9A80-4413-A612-8773EED4A664`, `imported`, src = trim = 2262/600 (H3).
  - +1 file `71CDF383-….mov`, SHA-256 `01ab75b8d5f5d6580c2ca07086065faba794744706f34552b19e24d53dbf86b2`: H.264 High 1080×1920, 2262/600, 30 fps, AAC stereo (normalized H3); `588C39AD`'s bytes survive only in the write-protected backups.
  - The other 14 DP rows and 16 media full SHA-256 identical; B8A7FB31's 2 rows and recorded full hashes unchanged; DP 15 active; ProjectWorkspace empty (modified 20:00); CaptureStaging empty; tmp names identical.
- When the `588C39AD` row was removed (Editor exit or startup cleanup within the unrecorded process) is not observable without a console.

Verdicts: R1 and R1′ PASS (owner UI plus captured removal logs plus snapshots); R2a–R2d PASS by owner verdict (expected rejection for each source with X left unavailable, wording as transcribed; S18 shows no state change; R2d sheet appearance not reported); R2f PASS as reported by the owner ("all requested UI checks passed") plus snapshot, without a console; R2e not exercised; R2e′ PASS for cancellation during the pre-conversion Debug delay (owner UI plus S21).

Limitations: cancellation was exercised only during the pre-normalization Debug delay, not during an active file write; the replacement flow ran without a console; F5 (Select Clips C1) remains postponed.

## 13. K1 — real-camera 4K HDR (Dolby Vision HLG) Editor Add, no Debug options

| Field | Value |
| --- | --- |
| Build | Debug `3ce5d45` (unchanged) |
| Launch | 2026-10-07 20:07:53 KST, `devicectl device process launch --terminate-existing --console` with `OS_ACTIVITY_DT_MODE=enable`, `com.mellow.Mellow` with no app arguments; pid 7605; Mellow was not running before it |
| Target / source | DP `6986CA3E…` (15 clips), Editor Add; K1 |
| Console log | `logs/k1-console.log` in the durable root |
| Snapshots | before: snap-38-pre-K1 (identical to snap-37-S22-R2f); after: snap-39-S23-K1, confirmed by snap-40-S23-confirm (Mellow not running, no launch in between) |
| Source copy | `sources/K1/K1-IMG_0163-2.MOV` in the durable root, write-protected, SHA-256 `b52519c8757d97e85f9a27aada06f2cce338b1fb057330dbd6cef67ac233294c`, 12,006,666 bytes |

The console had no `controls active` or `UI-test` line, so this run is verified free of Debug controls.

Owner observations (as reported):

- K1 was recorded in portrait at 4K30 with HDR Video ON.
- The video was added successfully; a preparation screen appeared with wording about adding the video (exact text not transcribed); no counter was visible.
- The final clip count was 16.
- The owner swiped Mellow away afterwards.

Captured console (`[app]` lines, KST): 20:07:53 `Recovery complete dirsRemoved=0 mediaRemoved=0 referenced=17 noncanonical=0 failures=0 …`; 20:08:07 `Project editor loaded 6986CA3E-… clips=15 total=55.8s`; no import or error line (the success path does not log); 20:08:24 `The app terminated with the exit code 0.` (the owner's swipe-away).

S23 snapshot (snap-39-S23-K1) versus snap-38:

- Store: exactly +1 row — DP order 15 (slot 16) `46757A52-8CAD-454D-8E04-ADF5FA334ED7`, `imported`, src = trim = 2260/600, not deleted; DP 16, B8A7FB31 2.
- Media: exactly +1 file referenced by that row, SHA-256 `e33a59ba995c6f083e37d739d9ccac2aa4871a6923e3fccad4b067f21c785dea`, 6,834,570 bytes; the 17 prior full SHA-256 identical (B8A7FB31 equal to its recorded full hashes); every row references an existing file.
- ProjectWorkspace empty (mtime 20:08, used and cleaned); CaptureStaging empty; tmp entry names identical.

Source (independently inspected from the owner-provided original; the only recent video file in Downloads, `IMG_0163 2.MOV`, mtime 20:05:34 KST):

- Video `hvc1`, HEVC Main 10 (`general_profile_idc` 2), 10 bits per component, Dolby Vision configuration (`dvvC`) alongside `hvcC`.
- BT.2020 primaries, HLG transfer (`ITU_R_2100_HLG`), BT.2020 matrix.
- Encoded 3840×2160 with a 90° transform: presentation 2160×3840, portrait.
- 113 frames, every frame 20/600 (constant 30 fps), duration 2260/600; ~25.3 Mbit/s.
- Audio AAC 48 kHz stereo, ~136 kbit/s, audio track 2259/600.

Output (`46757A52`):

- Video `avc1`, H.264 High (profile 100), encoded and displayed 1080×1920 (identity transform), Rec.709 primaries / transfer / matrix (SDR).
- 113 frames, every frame 20/600 (constant 30 fps), first PTS 0, duration 2260/600; ~14.4 Mbit/s.
- Audio AAC 48 kHz stereo, ~136 kbit/s, audio track 2259/600 (the same as the source, consistent with AAC pass-through).

Correspondence: the frame count, frame timing, duration, audio rate and audio track length match the source exactly, and 2160×3840 scaled by `min(1.0, 1080 / 2160, 1920 / 3840)` = 0.5 gives exactly 1080×1920, never upscaled; the HDR (HLG / BT.2020 / 10-bit / Main 10 / Dolby Vision) and raster reasons were both present in the source, and the output is tone-mapped SDR.

Verdict: K1 PASS — owner-observed successful Add (16 clips), a console-verified run without Debug controls, a snapshot showing exactly one committed clip with prior media preserved, and an independently inspected source whose facts the output matches.

Limitations: the preparation screen's exact text was not transcribed and no counter was seen; the link between the Downloads file and the Photos asset rests on the owner's identification, the filename and the exact timing correspondence, not on an asset identifier; the audio track is 2259/600 in both source and output (observation only).

## 14. Disposable Seed and F5 — simulated C1 shortage on Select Clips

### 14.1 Why a seed

`+ 새 프로젝트 시작` › `새 프로젝트 만들기` replaces the current saved Project (`.replacingSaved`), and the current saved Project is `repository.recentProjects().first` (newest `updatedAt`, then `createdAt`, then id; `ProjectCompositionCoordinator.lastSavedProject`).

Before seeding that was DP, so F5 was postponed by the owner to avoid any chance of replacing DP.

The owner approved creating one empty disposable Project with the existing create-only `-uiTestSeedPortrait` control (`AppEnvironment.seedUITestProjects`, which only calls `repository.create`) so that it, not DP, becomes the replacement target.

Consequence accepted by the owner: `기존 프로젝트 불러오기` now opens the seed; DP and B8A7FB31 stay stored and unchanged but are not reachable from the Projects screen; no project is deleted and no timestamp is altered to restore DP.

### 14.2 SEED

| Field | Value |
| --- | --- |
| Baseline | snap-42-S0-pre-SEED, identical to snap-41 (store equal to S23; 18 media full SHA-256 equal to the committed S23 manifest); Mellow was running as pid 7612, a launch after K1 that this batch did not perform (observation gap; options and cause not inferred), ended by `--terminate-existing` |
| Launch | 2026-10-07 20:21:56 KST, pid 7686, `com.mellow.Mellow -- -uiTestSeedPortrait`, console captured (`logs/seed-console.log`) |

- Console: no `controls active` or `UI-test` line; `Cleanup startup reconciliation projects=3`; recovery referenced 18, removed 0, failures 0; 20:22:20.746 `Projects entry saved project: F0D95E9E-64A4-4A96-A51A-694A4CD69CD7`.
- Owner: opened the Projects screen only, then swiped Mellow away (exit 20:22:26).
- S-1 (snap-43-S1-post-SEED) versus S-0: exactly one new Project `F0D95E9E-64A4-4A96-A51A-694A4CD69CD7`, `portrait9x16`, created = updated 2026-10-07 20:21:56 KST, 0 clips; DP's 16 and B8A7FB31's 2 rows identical; 18 media full SHA-256 and listing paths identical (the empty seed has no project directory); workspace, staging and tmp clean.

### 14.3 F5 — simulated C1 (first-attempt admission) shortage on Select Clips replacing the seed

Classification: a SIMULATED C1 capacity-check outcome (`usable=0` from the Debug control), not real disk exhaustion or an out-of-space write.

| Field | Value |
| --- | --- |
| Launch | 2026-10-07 20:25:30 KST, pid 7689, `com.mellow.Mellow -- -uiTestImportCapacityShortage=c1:1`, console captured (`logs/f5-console.log`); Mellow was not running since S-1 |
| Target / source | Select Clips replacing the current saved Project = seed `F0D95E9E…`; M01 (`EXACT 1.0s`, ready) |
| Snapshots | before: snap-43-S1-post-SEED; after: snap-44-S2-F5 (Mellow not running, no launch since) |

Target verification: the owner opened the Projects screen and stopped; the console showed 20:26:56.224 `Projects entry saved project: F0D95E9E-64A4-4A96-A51A-694A4CD69CD7`, an exact match, before the selection step was authorized.

Owner observations (as transcribed; spacing is reported wording, not a verified copy defect):

- The alert was `저장공간이 부족해요` / `영상을 추가하려면 기기의 저장공간을 확보한 후 다시 시도해주세요.` with one button, `확인` (source strings `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.`).
- No preparation sheet appeared before the alert.
- `확인` returned to the Projects screen.
- The owner then swiped Mellow away without another import attempt.

Captured console (`[app]` lines, KST):

- 20:25:30.994 `UI-test device import controls active: normalizer=false capacity=true`.
- 20:27:47.065 `UI-test capacity override boundary=c1BeforePreparation usable=0 (simulated)`.
- 20:27:47.065 `Import attempt admission refused project=2FD0B4C0 boundary=c1BeforePreparation` (`2FD0B4C0` is the would-be replacement Project's id; it was never stored).
- No further import line; 20:28:18 `The app terminated with the exit code 0.` (the owner's swipe-away).

S-2 snapshot (snap-44-S2-F5) versus S-1:

- Store identical: 3 Projects; the seed still has 0 clips with `updatedAt` 20:21:56 and is still the current saved Project; DP 16 and B8A7FB31 2 rows unchanged; `2FD0B4C0` appears nowhere.
- 18 media full SHA-256 and listing paths identical; no media added.
- ProjectWorkspace empty (mtime 20:27, used and cleaned); CaptureStaging empty; tmp entry names identical.

Verdict: F5 PASS for the simulated Select Clips C1 rejection — owner-observed alert and no sheet, captured C1 override and refusal logs, and an unchanged S-2 snapshot.

Limitations: simulated capacity only (not real disk exhaustion); one ready source; the seed then served as the first replacement target for the Select Clips checks (section 15).

## 15. Select Clips Duration Checks (SC) — seed → P2 → P3 → (SC4x: Px) → P4

The owner approved SC1–SC4, including replacement and cleanup of only the successive disposable Projects; the owner later separately authorized replacing the unplanned Project Px.

All steps ran in one console-attached launch with no app options: pid 7735, 2026-10-07 21:17:09 KST, `com.mellow.Mellow` with no arguments (0 `controls active` / `UI-test` lines; recovery 3 Projects, 18 referenced, removed 0); `logs/sc-console.log` in the durable root.

Before the launch Mellow was running as pid 7718, a launch after F5 that this batch did not perform (observation gap; options and cause not inferred); snap-45-pre-SC was identical to S-2.

Before every `새 프로젝트 만들기` the owner left and re-entered the Projects screen and stopped, and a fresh `Projects entry saved project:` line was checked against the expected disposable Project; DP and B8A7FB31 were never the target.

All sources (M01 1.0 s, M02 5.0 s, M03 0.8 s, M04 5.5 s) are ready synthetic fixtures; every committed file is a byte-identical fast-path copy (M01 `9e68d6e6…ba30`, M02 `8cfee24c…f1e`, equal to DP's earlier copies).

| Step | Target (verified line) | Selection | Owner observation (as transcribed) | Snapshot result |
| --- | --- | --- | --- | --- |
| SC1 | seed `F0D95E9E-64A4-4A96-A51A-694A4CD69CD7` (21:17:41) | M03 | `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.` / `확인`; alert directly, no sheet; Projects screen remained | SC-S1 (snap-46): no change; seed still current with 0 clips |
| SC2 | seed (21:21:51) | M01, M03 | `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요` / `확인`; no sheet; one 1-second clip; screen behind the notice not reported | SC-S2 (snap-47): seed row gone (it had no media or folder); P2 `3D051BDE-3FC6-40DD-829A-6F10548CEB83` with 1 clip `64F12DC8-…` 600/600, +1 file = M01 |
| SC3 | P2 (21:31:00) | M02, M04 | `긴 영상이 제외되었어요.` / `5초를 초과한 영상은 추가할 수 없어요.` / `확인`; Editor showed only the 5.0 s clip; no sheet | SC-S3 (snap-48): P2 row, clip, file and folder gone; P3 `02EED3C9-2127-414C-BFD2-4C55C64FF0F2` with 1 clip `EE98CD0A-…` 3000/600, +1 file = M02 |
| SC4 (corrected) | Px (22:18:18) | exactly M01, M03, M04 | `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.` / `확인`; no sheet; Editor showed exactly one clip, M01 (1.0 s) | SC-S4 (snap-50): Px row, both clips, both files and folder gone; P4 `995A1AAF-200E-42C8-8AE2-C6155D54F70A` with 1 clip `7CC09E8E-1A73-4C1F-B701-940CAD27E9A9` 600/600, +1 file = M01 |

Spelling and punctuation differences between the transcriptions and the source strings (for example the SC2 message without its final period and the SC3 title with an extra period) are recorded as reported wording, not verified copy defects.

### 15.1 SC4x — unplanned selection, not an SC4 result

- Target verified as P3 (22:08:49, 22:08:52), but the owner accidentally included M02: the selection was M01, M02, M03 and M04 instead of the prescribed M01, M03, M04.
- Owner: `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.` / `확인`; no sheet; the Editor showed two clips, M01 and M02; the owner asked that this not be recorded as an SC4 PASS.
- snap-49-SC4x-actual versus SC-S3: P3's row, clip, file and folder gone; new Project Px `877ECA15-FD66-4735-A680-230D1F6A55C7` (22:13:37) with clips `DD22B9A1-…` 600/600 (= M01) and `27346AC2-…` 3000/600 (= M02); DP, B8A7FB31 and their 18 hashes unchanged; workspace clean.
- This state became the baseline for the corrected SC4; the owner explicitly authorized replacing Px, including its two clip rows, two media files and folder.

### 15.2 Preservation and cleanup across SC

- DP's 16 and B8A7FB31's 2 clip rows and their 18 media full SHA-256 at SC-S4 are identical to snap-45-pre-SC.
- After every step ProjectWorkspace was empty again (used at 21:18, 21:22, 21:38, 22:13, 22:18), CaptureStaging empty and tmp entry names unchanged, and every row referenced an existing file with no unreferenced file.
- Final state: 3 Projects (P4 current with 1 clip, DP 16, B8A7FB31 2) and 19 media files; Mellow left running as pid 7735.

Verdicts: SC1, SC2, SC3 and the corrected SC4 PASS — owner-observed alerts, the console-verified target before each confirmation and the snapshots; SC4x is recorded only as an unplanned run.

Limitations: synthetic ready fixtures only; the screen on which the SC2 notice appeared was not reported; the console does not log successful imports, so each commit is established by the snapshot and the next `saved project` line.

Phase 6 remains In Progress and Needs Device Test.

## 16. AF — Aspect-mismatch Framing Preservation (Editor Add into P4), 2026-10-08

Purpose: the Physical Device Test item "Source / Project Aspect Mismatch의 Framing 영역 보존" — a 3:4 portrait source added to a 9:16 project keeps its whole presentation frame and aspect ratio in the working file, with no Project crop baked in and `framing = nil` (ROADMAP Phase 6 Scope / Acceptance; ADR-022; ADR-047 and Revision 1).

The owner authorized Editor Add of A1 and A2 into the disposable Project P4 `995A1AAF-200E-42C8-8AE2-C6155D54F70A` only, preserving its M01 clip, DP and B8A7FB31; Select Clips and Project replacement were not used.

A3 (a Photos-cropped real source) was deferred, and baseline performance measurement is kept separate from this functional check.

### 16.1 Fixtures and offline tools

The fixtures and tools were created 2026-10-08 in the durable root (outside git): `tools/makefixture` and `tools/edgecheck` (with `.swift` sources), `sources/AF/` (fixtures, `FIXTURES.md`, `AF-manifest.sha256`, source edgecheck frames).

Each frame is mid-grey with 16 px edge stripes (top red, bottom green, left blue, right yellow), 32 px corner squares (TL white, TR cyan, BL magenta, BR orange), a large `A1` / `A2` label, the raster text and a frame counter.

`edgecheck` decodes every frame and measures each stripe's width on three sample lines per edge, counts non-stripe and near-black pixels on the outermost rows and columns (corners excluded) and classifies the four corners.

| ID | File | SHA-256 | Source-file facts (`tools/probe`) | Expected classification (code reading) |
| --- | --- | --- | --- | --- |
| A1 | `A1-3x4-1080x1440.mov`, 75,986 B | `81bf19d29d0129ade1f327417844895c019c9429603d91bdc73f9d9ebe88fef0` | QuickTime, avc1 High, 1080×1440, identity transform, 90 frames at 20/600, 1800/600, Rec.709, no audio | ready fast path (byte copy) |
| A2 | `A2-3x4-1440x1920.mov`, 98,236 B | `e3c58a93073a946df6c32369807f97641d05274d1bf892d986bbff8ff9a83d03` | same, 1440×1920 | normalization (raster reason), full aperture, built-in path; ADR-047 output 1080×1440 |

Source baseline over all 90 frames of each fixture: stripe widths top 16, left 16, right 16, bottom 17 (the green/grey boundary pixel decodes nearer green), 0 non-stripe and 0 near-black pixels on every outermost line, corners correct in 90/90 frames.

Negative control: the same checker on DP media `0E9BA7E9…` (no markers) reports stripe widths 0 and up to 1824 non-stripe outermost pixels.

The owner AirDropped both files to LunaTestphone, saved them to Photos and confirmed the labels and 3-second durations before Mellow was opened.

### 16.2 Pre-state and launch

- snap-51-pre-AF (00:55:40Z): store, media SHA-256 and tmp identical to snap-50 (SC-S4); DP 16 active, B8A7FB31 2, P4 1 clip (`7CC09E8E`, M01, framing NULL) and P4 newest `updatedAt`; ProjectWorkspace empty.
- Mellow was already running as pid 7823, a launch this batch did not perform (observation gap; options and cause not inferred; the owner had not opened Mellow); state was unchanged.
- Launch: 2026-10-08 09:57:06 KST, pid 8041, `--terminate-existing --console` with `OS_ACTIVITY_DT_MODE` and no app arguments (`logs/af-launch-command.txt`, `logs/af-console.log`); no `controls active` or injection lines; recovery preserved DP 16, P4 1, B8A7FB31 2, removed 0, failures 0.
- Target: `Projects entry saved project: 995A1AAF-200E-42C8-8AE2-C6155D54F70A` at 09:58:11, checked before the owner opened `기존 프로젝트 불러오기`; `Project editor loaded 995A1AAF… clips=1 total=1.0s` at 09:58:57.

### 16.3 Results

| Step | Owner observation | Committed clip / file | Output facts | Decoded edges (all 90 frames) | Metadata |
| --- | --- | --- | --- | --- | --- |
| A1 (snap-52-AF-A1) | no sheet, no alert; timeline 1.0 s, 3.0 s | +1 row `77BA7C31-AB17-465C-8E6B-E87425444EF8` order 1, +1 file 75,986 B, SHA-256 `81bf19d2…88fef0` = A1 source | avc1 High 1080×1440, identity, 20/600, 1800/600, Rec.709, no audio | stripes 16 / 16 / 16 / 17 (= source), outermost non-stripe 0, near-black 0, corners 90/90 | `imported`, trimStart 0, trimDuration = sourceDuration = 1800/600, framing X / Y / scale NULL |
| A2 (snap-53-AF-A2) | a preparation sheet appeared and dismissed itself; no alert; timeline 1.0 s, 3.0 s, 3.0 s | +1 row `B7FDADAB-06B9-43ED-B6F4-AE402687D6E7` order 2, +1 file 89,691 B, SHA-256 `3f50cf85413bccde5f024c36742015634877e014988c88778bb7ba2dab054978` | avc1 High 1080×1440 (scale 0.75, no upscale), identity, 90 samples all 20/600 from 0, ends 1800/600, Rec.709, no audio | stripes 12 / 12 / 12 / 12 (16 × 0.75), outermost non-stripe 0, near-black 0, corners 90/90 | `imported`, trimStart 0, trimDuration = sourceDuration = 1800/600, framing X / Y / scale NULL |

Evidence sources: the "Owner observation" column is the owner's report as given; every other column comes from inspection of the snapshot's file copies (`tools/probe`, `tools/edgecheck`, `tools/frametiming`, SHA-256) and store copy (SQLite on a scratch copy); console lines are quoted from `logs/af-console.log`.

Edge widths: the fixture design draws 16 px stripes, but the decoded source baseline is 16 px on the top, left and right edges and 17 px on the bottom edge (one boundary pixel decodes nearer green); A1 reproduces that baseline exactly, and A2's decoded output is 12 px on all four edges — the nominal 16 × 0.75, with the bottom going from 17 decoded source pixels to 12 output pixels.

Source file versus delivered representation: A1's committed file is byte-identical to the source file, so PhotosPicker delivered the original bytes for A1 on this AirDrop → Photos → PhotosPicker route; this is not a claim that Photos always preserves original bytes.

For A2 the delivered representation is not directly observable, because the normalizer reads a temporary copy that is cleaned up and its output is a re-encode by design; the 1080×1440 output and A1's byte identity on the same route are consistent with original delivery, which is recorded as an inference.

The console does not log successful imports; the only A2-window lines are the system AVC / HEVC encoder registration at 10:02:52, indirect evidence that an encode ran.

The Editor thumbnails (Aspect Fill cells) were not used as evidence of preserved or missing source area.

### 16.4 Persistence, Photos sources and cleanup

- AF-3: the owner went Back to Projects and reopened P4; the console shows `Projects entry saved project: 995A1AAF…` (10:06:23) and `Project editor loaded 995A1AAF… clips=3 total=7.0s` with active clips `7CC09E8E`, `77BA7C31`, `B7FDADAB` (10:06:26); the owner saw M01, A1, A2 (1.0 s, 3.0 s, 3.0 s).
- The owner swipe-closed Mellow at about 10:06 KST; the console recorded `App terminated due to signal 9` at 10:06:33.
- Photos: the owner saw A1 and A2 unchanged (labels, coloured borders, raster text, 3-second durations); this is a visual observation, not a byte-level verification of the Photos assets.
- snap-54-AF-final (01:08:13Z, Mellow not running): store, media SHA-256 and tmp identical to snap-53; P4 3 / 3 active, DP 16 / 16, B8A7FB31 2 / 2, no clip with non-NULL framing; 21 media files for 21 active rows; ProjectWorkspace (last used 10:02) and CaptureStaging empty; `ProjectMediaTransfer` and `TemporaryItems` in tmp touched at 09:59 and 10:02 and empty.
- DP's 16 and B8A7FB31's 2 rows and their 18 media full SHA-256 are identical from snap-51 to snap-54; M01 `7CC09E8E` is unchanged; the Mac-side fixtures still match `AF-manifest.sha256`.

### 16.5 Verdict and open gaps

Verdict: AF PASS for framing-area preservation — for the fast path (A1) and the normalization path (A2) the working file holds the full 3:4 presentation frame (all four edge stripes at the expected width and all corners present in every frame, no padding or black border), the aspect ratio and orientation are kept, no Project crop is baked in, and `framing` is NULL with trim equal to the full source.

Scope: synthetic H.264 SDR 30 fps fixtures through AirDrop → Photos → PhotosPicker on LunaTestphone, Editor Add only, installed Debug `3ce5d45` (same app bundle container as the rest of the batch; HEAD `96e4202` differs from it only under `docs/`); not HDR, not a real-camera or Photos-edited source (A3 deferred), not Select Clips or Replace.

Open, not closed by AF:
- Exact preparation-sheet copy: the owner could not transcribe the title or subtitle (an uncertain recollection, "영상이 준비되고 있어요", is not recorded as copy) and no progress text was captured; the sheet-copy and progress gate stays open.
- Unexplained launch: Mellow was running as pid 7823 before the AF launch, and its origin and launch options are unknown (observation gap, as with pids 7510, 7517, 7556, 7612 and 7718).
- Portrait Aspect Mismatch baseline measurement (elapsed, memory, peak storage, thermal) remains a separate open item.
- AF is a bounded synthetic H.264 SDR Editor Add check and closes no other Phase 6 gate (mid-write kill, import during delete / replacement, runtime disk full, peak storage, baseline measurement, accessibility, Select Clips mixed exclusion, ADR-050 Integration Gate items remain open).
- Phase 7 Fill + Crop and drag framing are not implemented; AF shows only that the source area they need is preserved.

Phase 6 remains In Progress and Needs Device Test.

## 17. PS — Preparation Sheet Copy and `2/5` Position (Editor Add of five normalization items into P4), 2026-10-08

Purpose: the open observation gap for the Preparation Sheet's exact rendered copy and its multi-item `2/5` position (ROADMAP Phase 6 Physical Device Test; ADR-042 Revision 4 §1: `영상을 준비하고 있어요` / `잠시만 기다려주세요.`, visible progress, `2/5` when several items need preparation, `취소`).

The owner authorized one successful Editor Add of H1, H2, H3, M05 and M08 into P4 `995A1AAF-200E-42C8-8AE2-C6155D54F70A`, preserving its three clips, DP and B8A7FB31, with only `-uiTestNormalizerDelay=15000`.

### 17.1 Expected behaviour from the implementation (`96e4202` code = installed `3ce5d45`)

- Copy constants: `ImportPreparationCopy.title` `영상을 준비하고 있어요`, `.message` `잠시만 기다려주세요.`, `.cancelAction` `취소`.
- `ImportPreparationProgress.positionLabel` is `N/M` only when M > 1, where M counts normalization-required items only (ready items do not count) and N is the 1-based ordinal of the item being normalized.
- The bar is a 260 pt track whose fill is `aggregate = (completed items + current item's real normalizer fraction) / M`; it shows no numeric text (the percentage exists only as the accessibility value, outside this check).
- `ImportAttemptCoordinator` emits `normalizationStarted` for an item before calling the normalizer, and the Debug `UITestScriptedNormalizer` sleeps for `-uiTestNormalizerDelay` inside that call before running the real normalizer, so each item's hold shows `N/M` with the bar at `(N − 1) / M`.

Debug pacing limitation: the 15 s hold before each item is a Debug control; during a hold the bar stands still at its true value, so this run does not show production timing or production bar motion; the copy, layout and progress model are the production view's.

### 17.2 Selection, pre-state and launch

- Selection: H1, H2, H3 (camera HDR, D1-2 sources), M05 `60FPS 3.0s` and M08 `4K SDR 3.0s` — five normalization-required items (HDR, frame rate, resolution), all previously normalized on this device; no ready item was included.
- snap-55-pre-PS (01:17:23Z): store, media SHA-256 and tmp identical to snap-54; workspace empty.
- Mellow was already running as pid 8086 (not running at snap-54 01:08:13Z), a launch this batch did not perform (observation gap; origin and options unknown); it was ended by `--terminate-existing`.
- Launch: 2026-10-08 10:18:48 KST, pid 8120, `--terminate-existing --console` with `OS_ACTIVITY_DT_MODE` and the single app argument `-uiTestNormalizerDelay=15000` (`logs/ps-launch-command.txt`, `logs/ps-console.log`); console `UI-test device import controls active: normalizer=true capacity=false`; recovery preserved DP 16, P4 3, B8A7FB31 2, removed 0, failures 0.
- Target: `Projects entry saved project: 995A1AAF-200E-42C8-8AE2-C6155D54F70A` at 10:22:52, checked before the owner opened `기존 프로젝트 불러오기`; `Project editor loaded 995A1AAF… clips=3 total=7.0s` at 10:27:36.

### 17.3 Captured sheet (owner screenshots)

The owner took two screenshots during the run and AirDropped them to the Mac; copies are preserved write-protected in the durable root at `screenshots/PS/`.

Evidence sources: the rendered text and bar fill come from the screenshot images (read and pixel-measured on the Mac); "Owner" lines are the owner's report as given; rows, files, output facts and cleanup come from snapshot inspection; console lines are quoted from `logs/ps-console.log`.

| File | Captured (EXIF) | SHA-256 | Rendered content |
| --- | --- | --- | --- |
| `IMG_0166.PNG` (1170×2532) | 2026-10-08 10:28:26 | `b2e2101dc30cbd104ce3e9a29d27b3787068d67bf117beb25ae701a6ebf20d2d` | title `영상을 준비하고 있어요`, subtitle `잠시만 기다려주세요.`, position `1/5`, button `취소`; bar fill 0 of 780 px (0.000) |
| `IMG_0167.PNG` (1170×2532) | 2026-10-08 10:28:45 | `b5abbb5a5d8a994ef72de882b592b34f04dfb41e69d06bca589b2a54448789f1` | same title, subtitle and button; position `2/5`; bar fill 156 of 780 px (0.200) |

- The text in both images matches the code constants character for character, including the subtitle's final period; the owner's own reading of the screenshots reports the same title, subtitle and button and no numeric percentage.
- The bar was measured on the image pixels with `screenshots/PS/barfill` (source, invocation, method and expected output in `screenshots/PS/README.md`; track 780 px = 260 pt × 3): 0.000 at `1/5` and 0.200 at `2/5`, equal to `(1 completed + 0) / 5` during item 2's hold — the model's real value, not a fabricated one; the measurement covers only these two captured frames, not bar motion between them.
- Both screenshots show the Editor navigation bar with the title `Project` and Undo / Redo, no Back button, and the status bar's `◀ 사진` back-link; the back-link is recorded as seen, without inferring its cause.
- `3/5`, `4/5`, `5/5` and the dismissal were not captured or reported and are not claimed.

### 17.4 Result

- Owner: no alert; after preparation the timeline showed exactly 8 clips.
- snap-56-PS (01:32:13Z, pid 8120 running) versus snap-55: exactly +5 rows in P4 at orders 3–7 and +5 files; M01, A1 and A2 unchanged at orders 0–2.

| Order | Clip | src = trim | Source (evidence) | File SHA-256 | Output facts |
| --- | --- | --- | --- | --- | --- |
| 3 | `642C8513-119E-4107-A7AF-4446BD511FEF` | 2341/600 | H1 — decoded first frame pixel-identical to DP's H1 output `D47D2BE1` | `99fca42375e2fedec1f9f2cc75d093400305dbc35fc901bdf980118eb9e25e83` | avc1 1080×1920, Rec.709, 117 samples at 20/600 + a final 1/600 sample ending at 2341/600, AAC 48 kHz stereo |
| 4 | `35FC6A16-D8BA-4722-B89A-6985DC3ADC8F` | 2341/600 | H2 — first frame identical to DP's H2 output `BFB501AA` | `5cdac8cf9ba83fb770cf33ed2846bacf4dcbe8d37fb406e7bda5750894006363` | same profile and sample pattern as H1, AAC 48 kHz stereo |
| 5 | `5BA780F5-2FB1-4F64-BC51-DC4C585FD9F8` | 2262/600 | H3 — the only selected source with 2262/600 | `372007d1e7476f0c7d46bc0fd079f16012ff9fe3c3929fadf13672312fa3a801` | avc1 1080×1920, Rec.709, 114 samples all 20/600, track range 2262/600, AAC 48 kHz stereo |
| 6 | `D574295F-175F-4B4F-B3F1-B275BA613654` | 1800/600 | M05 — first frame identical to DP's M05 output `AB163D20` | `ae8870abf6b5bcdba794fafce1908be8426d2230e4dff9adba55b050cbde7f56` | avc1 1080×1920, Rec.709, 90 samples all 20/600, no audio |
| 7 | `F212B6FC-3CE3-4757-8FCE-C13D8C40BC5A` | 1800/600 | M08 — first frame identical to DP's M08 output `D74FCDC9` | `732bcfc1525891fce985e5e402851b61123d4cd7333a459d88264ead561cd3c2` | avc1 1080×1920, Rec.709, 90 samples all 20/600, no audio |

- The committed order equals the selection order (H1, H2, H3, M05, M08).
- All five rows are `imported`, trimStart 0, trimDuration = sourceDuration, framing X / Y / scale NULL, not deleted.
- Unevaluated observation: the H1 / H2 outputs end with a 1/600 final sample after 117 samples at 20/600, and H3's samples extend to 2280/600 within a 2262/600 track range; these match the same sources' earlier DP outputs and are recorded as observed only — this run does not evaluate or resolve cadence compliance (ADR-048 Revisions 1 / 2) for these sources.
  - Later note (2026-10-08, after PS): this observation stayed unevaluated within PS; a separate read-only review of the inspected outputs is recorded in §18.
- Console: no Mellow error lines in the run; the system AVC / HEVC encoder registered at 10:28:40 (about 15 s after the run began, consistent with item 1's hold); the console does not log sheet text or successful imports.

### 17.5 Preservation and cleanup

- DP's 16 and B8A7FB31's 2 rows and their 18 media SHA-256, and P4's three earlier files, are identical to snap-55 (21 prior hashes); 26 media files for 26 active rows (DP 16, P4 8, B8A7FB31 2).
- ProjectWorkspace (last used 10:29) and CaptureStaging empty; `ProjectMediaTransfer` and `TemporaryItems` in tmp touched at 10:28 and empty; no other tmp change.
- Mellow was left running as pid 8120 at snap-56.

### 17.6 Verdict and open gaps

Verdict: PS PASS, bounded to the captured Preparation Sheet copy and the `1/5` → `2/5` positions on Editor Add with the Debug delay enabled — the two screenshots show exactly `영상을 준비하고 있어요` / `잠시만 기다려주세요.` / `1/5`, then `2/5` / `취소`, and the measured fill at `2/5` equals the model's real 0.200; the owner reported no alert and 8 clips, and snapshot inspection shows the five items committed together in selection order with nothing else changed.

Not verified by PS: production timing, smooth or continuous bar progress, `3/5`–`5/5`, automatic dismissal, failure-path atomicity, and H1 / H2 / H3 cadence compliance.

Scope: one successful Editor Add of five normalization-required camera-HDR and synthetic sources, Debug build with `-uiTestNormalizerDelay=15000`, Dark appearance as captured, LunaTestphone.

Open, not closed by PS:
- Debug pacing: production timing and bar motion without the hold are not shown; `3/5`–`5/5` and automatic dismissal were not captured.
- Unexplained launch: Mellow was running as pid 8086 before the PS launch (observation gap, as with pid 7823 and the earlier pids).
- The sheet's accessibility (VoiceOver label / percentage value, Dynamic Type, contrast, Reduce Motion) belongs to the UI Accessibility Verification gate.
- Select Clips and Replace sheets were not captured in this run; cancellation and failure paths were covered earlier (D1-3, F1–F3, R2e′) and were not repeated.
- PS closes no other Phase 6 gate (mid-write kill, import during delete / replacement, runtime disk full, peak storage, baseline measurement, Select Clips mixed exclusion, ADR-050 Integration Gate items remain open).

Phase 6 remains In Progress and Needs Device Test.

## 18. Follow-up — Cadence Review of the Normalized H1–H3 Outputs (read-only), 2026-10-08

Purpose: evaluate the short final sample observed in §17 (left unevaluated there) against the documented output-cadence and duration contract; this is an offline review of existing snapshot copies with no app launch, device import or code change.

### 18.1 Governing requirements

- ADR-048 Revision 1 (Cadence Grid): with `d = outputFrameDuration` and `E` the exact normalization session end, the video output has exactly one frame at every `t_k = k × d` with `t_k < E`; the writer session ends at `E`, so the last encoded sample's terminal duration may be shorter than `d`, and the output is not extended to fill the last interval.
- ADR-048 Revision 2 (takes precedence): the exact rational presentation-time grid is the authoritative cadence evidence — the grid starts at 0, every adjacent interval is exactly `d`, and only the last sample may be shorter, ending at `E`; average or metadata rates (`nominalFrameRate`, `sampleCount / duration`) may exceed 30 because of that sample and are diagnostic only, never a rejection reason; skipping the short last sample or ending the session early is forbidden.
- ADR-045 §7: `source duration <= output duration <= source duration + 1/30 s`; for a normalized item, `sourceDuration` is the validated output's actual duration, `trimStart = 0`, `trimDuration` is the validated Accepted Source Duration, and the output must cover the whole trim.
- Implementation reference (code reading at `64692dd`, unchanged from installed `3ce5d45` outside `docs/`): `AVFoundationWorkingMediaNormalizer` ends the writer session at `plan.sourceDuration`, and `WorkingMediaOutputValidator` requires every interval to equal `d` and `last < E <= last + d` with `E = plan.sourceDuration`.

### 18.2 Inspected outputs and findings

The inputs were snapshot copies, verified by SHA-256 against each snapshot's `media.sha256`. The tool is `analysis/cadence-2026-10-08/gridcheck` in the durable root; its source, invocation, inputs, saved output and hashes are kept there with a README and `cadence-manifest.sha256`. The output frame duration `d` is 20/600 throughout.

| Output | Source | Snapshot | Total (asset = track) | Presentation grid | Final sample (stored duration) | Edit list | Clip metadata |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `642C8513-119E-4107-A7AF-4446BD511FEF` (`99fca423…5e83`) | H1 | snap-56-PS | 2341/600 | 118 samples at 0 … 2340, 0 off-grid, every gap 20, 0 duplicates | at 2340, stored 1/600; stored durations sum to 2341 | media 0+2341 → track 0+2341 | src 2341 = trim 2341, trimStart 0 |
| `35FC6A16-D8BA-4722-B89A-6985DC3ADC8F` (`5cdac8cf…6363`) | H2 | snap-56-PS | 2341/600 | same as H1 | at 2340, stored 1/600; sum 2341 | media 0+2341 → track 0+2341 | src 2341 = trim 2341, trimStart 0 |
| `5BA780F5-2FB1-4F64-BC51-DC4C585FD9F8` (`372007d1…a801`) | H3 | snap-56-PS | 2262/600 | 114 samples at 0 … 2260, 0 off-grid, every gap 20, 0 duplicates | at 2260, stored 20/600; sum 2280 | media 0+2262 → track 0+2262 (presents the last frame for 2/600) | src 2262 = trim 2262, trimStart 0 |
| `D47D2BE1-1392-4D3F-AAC2-5652995777BE` (`9e0cc015…b761`) | H1 (D1-2) | snap-54-AF-final | 2341/600 | same as `642C8513` | stored 1/600; sum 2341 | media 0+2341 → track 0+2341 | src 2341 = trim 2341 |
| `BFB501AA-21B3-41ED-B1BD-462FF0F9FDD2` (`a7c22adc…b180`) | H2 (D1-2) | snap-54-AF-final | 2341/600 | same as `642C8513` | stored 1/600; sum 2341 | media 0+2341 → track 0+2341 | src 2341 = trim 2341 |
| `4899F476-D07B-4FAA-BF5E-BCB10027121E` (`8c5e1467…bdbc`) | H3 (D1-2) | snap-54-AF-final | 2262/600 | same as `5BA780F5` | stored 20/600; sum 2280 | media 0+2262 → track 0+2262 | src 2262 = trim 2262 |

Three quantities are kept distinct:

- Presentation spacing: every adjacent interval is exactly 20/600 in all six outputs.
- Stored sample duration: only the final sample differs. H1 and H2 store 1/600. H3 stores 20/600, and its edit list ends the track at 2262.
- Total duration: equals `E` exactly in all six outputs.

The H1 / H2 `nominalFrameRate` of 30.243486 and `minFrameDuration` of 1/600 reported earlier by `tools/probe` follow from the short final sample; Revision 2 classes them as diagnostic only.

### 18.3 Result

All six inspected outputs comply with ADR-048 Revisions 1 and 2 and with ADR-045 §7:

- Frame count: `E` = 2341/600 requires targets k = 0…117 (118 frames), and `E` = 2262/600 requires k = 0…113 (114 frames). Both counts are exact, with no missing, duplicate or off-grid timestamp and no `2d` interval.
- End of the last frame: the final frame is presented for `E − t_last` (1/600 for H1 / H2, 2/600 for H3), so `last < E <= last + d` holds.
- Total duration: the output equals the Accepted Source Duration recorded as `trimDuration`, which lies within `[source, source + 1/30 s]`, and the trim covers the whole output.

The short final sample is the contract's prescribed form, not a defect, and no contract ambiguity was found for presentation timing or total duration.

Limits:

- The original H1–H3 camera files were never captured. Their own frame timing and bytes are unknown, and the only source-side fact is the Accepted Source Duration, as measured by the app on the delivered file and recorded as `trimDuration`. Compliance is judged on the outputs, which is what the contract governs.
- The two end-storage forms play back the same (a shortened final sample duration for H1 / H2; a full-length final sample cut by the edit list for H3), but the reason the writer produced different forms is unknown and is not inferred. The contract constrains presentation times and total duration, not the container representation.
- The device evidence for the cadence rule itself remains `IMG_0130.MOV` (ADR-048 Revision 2). This review covers only the six outputs above. It does not certify other sources, and it closes no other Phase 6 gate.

Phase 6 remains In Progress and Needs Device Test.
