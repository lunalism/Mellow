# Phase 6 Device Batch 2026-10-07 — Evidence Record, Pre-F4 Rebaseline and F4 Result

**Status:** Reconstructed record (D0 … F3), a fresh read-only baseline (snap-21) and the F4 result (snap-22-S12-F4).

This document is not a Phase 6 Gate completion claim; Phase 6 remains In Progress and Needs Device Test.

## 1. Context

| Field | Value |
| --- | --- |
| Device | LunaTestphone, iPhone 12 (`iPhone13,2`, `00008101-001825E03E10001E`) |
| Installed build | Debug `3ce5d45` (`phase/06-media-import-normalization`), in-place install |
| Projects | DP (disposable) `6986CA3E-EE49-4524-A796-E072127EBC6F`; preserved `B8A7FB31-7EC3-4DC4-B330-3B6D25E31DB0` |
| Rebaseline taken | 2026-10-07T09:59:41Z (18:59 KST), read-only `devicectl copy from` / `info files` only |
| Durable evidence root (outside git) | `/Volumes/Data/dev/Mellow-device-evidence/phase-06/device-batch-2026-10-07/` |
| In-repo evidence | this record and `device-batch-2026-10-07-pre-f4-manifest.txt` |

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

F4 is recorded in section 9 with evidence that is still inspectable.

Not run yet: F5 … F7, R0 … R2f.

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

Phase 6 remains In Progress and Needs Device Test.
