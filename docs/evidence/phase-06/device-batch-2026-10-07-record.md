# Phase 6 Device Batch 2026-10-07 — Evidence Record, Pre-F4 Rebaseline, F4, F6, F7, Replace (R) and K1 Results

**Status:** Reconstructed record (D0 … F3), a fresh read-only baseline (snap-21), the F4 result (snap-22-S12-F4), the F6 result (snap-24-S14-F6) the F7 result (snap-26-S15-F7, snap-27-S16-F7-reopen) the Editor Replace results (snap-28 … snap-37) and the K1 result (snap-39 / snap-40).

This document is not a Phase 6 Gate completion claim; Phase 6 remains In Progress and Needs Device Test.

## 1. Context

| Field | Value |
| --- | --- |
| Device | LunaTestphone, iPhone 12 (`iPhone13,2`, `00008101-001825E03E10001E`) |
| Installed build | Debug `3ce5d45` (`phase/06-media-import-normalization`), in-place install |
| Projects | DP (disposable) `6986CA3E-EE49-4524-A796-E072127EBC6F`; preserved `B8A7FB31-7EC3-4DC4-B330-3B6D25E31DB0` |
| Rebaseline taken | 2026-10-07T09:59:41Z (18:59 KST), read-only `devicectl copy from` / `info files` only |
| Durable evidence root (outside git) | `/Volumes/Data/dev/Mellow-device-evidence/phase-06/device-batch-2026-10-07/` |
| In-repo evidence | this record and `device-batch-2026-10-07-pre-f4-manifest.txt` (snap-21 baseline, then S12 after F4, S16 after F7, S22 after R2f and S23 after K1, plus the K1 source checksum) |

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

F4, F6, F7, the Replace steps and K1 are recorded in sections 9 to 13 with evidence that is still inspectable.

F5 is postponed by owner decision: its `+ 새 프로젝트 시작` flow replaces the current saved Project, which is DP, so it waits for a separately seeded disposable replacement target; the Select Clips C1 device check stays open.

Not run: F5 (postponed).

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

Phase 6 remains In Progress and Needs Device Test.
