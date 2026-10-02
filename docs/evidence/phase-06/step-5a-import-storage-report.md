# Phase 6 Step 5A — Import Storage Evidence (Exploratory)

**Status:** Exploratory Measurement Evidence.

이 문서는 Accepted Decision, Performance Acceptance Threshold, Storage Gate 완료 증거가 아니다.

Phase 6은 In Progress이며 Import Storage Estimate Formula와 Safety Reserve는 여전히 Pending이다(ROADMAP Phase 6 Pending Technical Gate, ADR-024, ADR-047 Still Pending).

이 Evidence를 근거로 한 제안은 `DECISIONS.md` ADR-050(Proposed)에 있다.

Raw Measurement Line은 같은 Directory의 `step-5a-import-storage-raw.txt`에 있다.

## 1. Evidence Contract Fields

| Field | Value |
| --- | --- |
| Production Commit | `0ef173b6b53615a7c9e664ca30559b523702ed08` (`phase/06-media-import-normalization`) |
| Temporary Harness | `MellowTests/WorkingMediaNormalizerTests.swift`에 임시로 덧붙인 Test 전용 `ZZStep5AStorageMeasurement` Class(+ `import SwiftData`), 측정 후 제거; Section B(전체 Matrix + Cleanup)에 쓴 최종 Harness Source SHA-256 `1b99fd1e1348914c7268035cf666e43aa7b61458c79749df129d000f254e968a`; Section A(IMG_0130 검증 3 Run)는 `statfs` 측정을 추가하기 전의 이전 Harness 버전으로 실행했으며 그 Hash는 기록하지 않았다; 복원된 Test File SHA-256은 측정 전 Snapshot과 같다(`cde00457…b790`) |
| Harness 보존 | 저장소에 넣지 않았다(AGENTS.md Spike and Experiment Rule: Experiment Code를 기본 경로로 `main`에 병합하지 않음); 사본은 측정 Session의 임시 Scratch 영역에만 있다; 따라서 이 Evidence는 저장소만으로 재현할 수 없다(7절) |
| Build / Configuration | Debug, `build-for-testing` → `test-without-building`, 새 DerivedData |
| Device | iPhone 12 (`iPhone13,2`), Primary Physical Test Device; Serial 미기록 |
| iOS | 27.0.1 (24A446) |
| Storage Context | Plain Free 약 27.0 GB(`volumeAvailableCapacity`), Important-usage Free 약 37.2 GB; Storage Pressure 없음 |
| Thermal / Power | 모든 Run 시작 · 종료 Thermal State Nominal(0); Low Power Mode Off |
| Run Date | 2026-10-02 |
| Project Shape | Run마다 새 Project 하나(Clip 1개 또는 Mixed 2개), Run별 격리 `tmp/Step5AMeasure-<UUID>` Root 안의 자체 `Mellow/` Media Root와 자체 On-disk SwiftData Store; App의 실제 Store / Media는 열지 않았다 |
| Repetition | Scenario당 3 Run(+ IMG_0130 Harness 검증 3 Run); 제외한 Run 없음 |

### 실행한 Production 구성요소(수정 없음)

- `ProjectMediaStore`: `beginWorkspace`, `adopt`, `materialize`, `discard`, `removeProjectMedia`
- `ImportSelectionPreflight` + `AVAssetImportSourceInspector`
- `WorkingMediaPlanBuilder`, `AVFoundationWorkingMediaNormalizer`
- `MellowModelContainer.makePersistentContainer(storeURL:)`, `SwiftDataProjectRepository.create` + Read-back

### 실행하지 않은 것

- System PhotosPicker와 `ReceivedVideoFile` 자체: Picker Transfer는 같은 `FileManager.copyItem` 호출을 쓰는 대체 단계로 측정했다.
- Provider File의 실제 위치 · Volume · Clone 동작.
- Coordinator / UI 연결, Thumbnail, App의 실제(더 큰) Store와 WAL.
- Low-storage 상태와 Runtime Disk Full.

## 2. Fixtures

| ID | 종류 | Bytes | SHA-256 | Duration | Raster | Video | Audio | Preflight 경로 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `IMG_0130.MOV` | 실제 iPhone 촬영본(소유자 승인) | 4,610,001 | `4fd24df2e24fea764ca626bac8adf2123e1048caa156909f676f1bfe9c4cee26`(측정 후 불변) | 2722/600 s | 1920×1080 Natural, Portrait Presentation | HEVC Main10 HLG Rec.2020 + Dolby Vision 신호, 29.98 fps | AAC 48 kHz Stereo | Normalize(HDR) → 1080×1920, 1/30, AAC Passthrough |
| `syn-readyNoise1080p30` | 합성 Random Noise | 37,191,620 | `59809b43ad11f9d3ef0be1d0d9ea1cde6a364439a3d61fea81e55263d6067f03` | 3000/600 s | 1080×1920 | H.264 SDR 30 fps | 없음 | Fast Path |
| `syn-noise4K30` | 합성 Random Noise | 149,619,684 | `e0b2eb0b2cc770580bb17ea39db584e034d5a188daa156e2f058be76ab299537` | 3000/600 s | 2160×3840 | H.264 SDR 30 fps | 없음 | Normalize(Raster) |
| `syn-pan4K30` | 합성 Scrolling Noise Texture | 53,075,852 | `6739a7b1c0883f06606e573c908d793032528d14c5f283bb19d787f4a3fe6ee6` | 3000/600 s | 2160×3840 | H.264 SDR 30 fps | 없음 | Normalize(Raster) |
| `syn-noise1080p60` | 합성 Random Noise | 69,366,347 | `54efe13b25b9c49f0186046933d88b690d1121727e938f899c28ea68a07b9beb` | 3000/600 s | 1080×1920 | H.264 SDR 60 fps | 없음 | Normalize(Frame Rate) |
| `syn-noiseHLG1080p30` | 합성 Random Noise | 48,698,186 | `f3343ec4f5018b317979e6399e9b287e1e5c7de39ca140e37b6cfd1765e0cf2b` | 3000/600 s | 1080×1920 | HEVC Main10 HLG 30 fps | 없음 | Normalize(HDR) |

합성 Fixture는 Harness가 기기에서 생성한 Encoder Stress 입력이며 Camera 촬영본이나 실제 사용자 Source를 대표하지 않는다.

합성 Fixture에는 Audio가 없으므로 그 출력 Byte는 Video만의 값이다.

## 3. 결과

O는 정규화 출력, N은 Adopt된 Source다.

Logical은 `fileSizeKey`, Allocated는 `totalFileAllocatedSizeKey`다.

| Scenario | 출력 Logical(Run별, B) | 출력 Allocated(B) | O / N | 출력 B/s | 표본 Peak Workspace Logical(B) | 정규화 시간 |
| --- | --- | --- | --- | --- | --- | --- |
| IMG_0130(Harness 검증) | 8,109,669 ×3 | 8,736,768–8,921,088 | 1.7591 | 1,787,583 | 12,719,670 | 1.73 s |
| IMG_0130 | 8,112,052 / 8,109,669 / 8,109,669 | 8,556,544–8,843,264 | 1.7591–1.7597 | 1,787,583–1,788,108 | 12,719,670–12,722,053 | 1.73–1.84 s |
| syn-readyNoise1080p30 | Fast Path, 출력 없음 | — | — | — | 37,191,620(Source만) | — |
| syn-noise4K30 | 18,020,073 / 16,701,837 / 18,126,901 | 17,682,432–18,333,696 | 0.1116–0.1212 | 3,340,367–3,625,380 | 166,321,521–167,746,585 | 2.40–2.42 s |
| syn-pan4K30 | 10,732,623 ×3 | 11,730,944–11,739,136 | 0.2022 | 2,146,524 | 63,808,475 | 1.48–1.49 s |
| syn-noise1080p60 | 36,017,434 ×3 | 36,950,016 | 0.5192 | 7,203,486 | 105,383,781 | 1.21 s |
| syn-noiseHLG1080p30 | 37,253,545 ×3 | 37,826,560–38,248,448 | 0.7650 | 7,450,709 | 85,951,731 | 1.25–1.27 s |
| Mixed(Ready + IMG_0130) | IMG 출력 8,109,669 ×3 | 9,007,104–9,023,488 | 1.7591 | 1,787,583 | 49,911,290 = 37,191,620 + 4,610,001 + 8,109,669 | 1.62–1.68 s |
| 취소 → Retry(IMG_0130) | Retry 출력 8,109,669 ×3 | 8,830,976–8,933,376 | 1.7591 | 1,787,583 | 실패 시도 8,483,506 / 8,483,506 / 8,385,801(Source 4,610,001 포함, Partial 3,873,505 / 3,873,505 / 3,775,800); Retry 12,719,670 | 1.67–1.73 s |

### Allocation과 Metadata

- 정규화 출력 24개의 Allocated − Logical은 203,031–1,006,513 B였다(최댓값 `syn-pan4K30` Run 2).
- Transfer 복사본의 Allocated − Logical은 60–3,509 B였다.
- Metadata Commit(27 Run 전부, 새 On-disk Store): Store Open이 `default.store` 86,016 B, `-shm` 32,768 B, 빈 `-wal`을 만들었고 `create` + Read-back이 WAL을 74,192 B Logical / 77,824 B Allocated 늘렸다.
- 이 WAL 증가량은 Clip 1개와 Clip 2개에서 같았다. 이 관측만으로 Clip당 WAL 증가율을 추론할 수 없다.
- 측정한 것은 새 빈 Store에 대한 `create`뿐이다. 기존 Project에 대한 `update`(Add / Replace는 기존 Durable Clip 전부를 다시 적용한다), `.replacingSaved`의 두 번째 Save, 기존의 큰 Store / WAL은 측정하지 않았다. Store Page 크기와 Auto-checkpoint 설정은 질의하지 않았다.
- Cleanup: 모든 Run이 `rootLogical=0`, 남은 Workspace Directory 없음으로 끝났고 Cleanup Test가 Fixture Directory를 제거했으며 tmp에 `Step5A*` 잔여물이 없었다.

### Encoder Level 교차 확인

- 이전에 보존한 IMG_0130 정규화 출력(같은 Normalizer, Step 4B 검증 Run)의 `avcC`는 High Profile(100), Level 4.0이다.
- 합성 출력의 Level은 기록하지 않았다.
- 따라서 이 Evidence는 Level 신호와 출력 Rate의 관계에 대해 어떤 결론도 내리지 않으며 Level 신호를 출력 크기의 상한으로 쓰지 않는다.

## 4. 관측된 File Lifetime

1. Picker Transfer 대체 단계: Transfer 복사본이 Provider File과 함께 존재한 뒤(Logical 2 × N) `adopt`가 같은 Volume Rename으로 Workspace에 옮긴다(이후 Transfer Directory는 비어 있음).
2. 모든 Adopt된 Source가 Preflight 전에 Workspace에 있다. Preflight는 아무것도 쓰지 않는다.
3. Fast Path: Adopt된 Source 자체가 Rename으로 Materialize된다. 추가 Byte가 없다.
4. 정규화: Source가 보존된 채 출력 File 하나가 옆에 생긴다. 20 ms Sampler는 모든 Run에서 Source와 출력 이름만 보았고(Intermediate 없음) Workspace Peak는 N + O와 정확히 같았다.
5. Materialize가 출력을 `Projects/…/Media/`로 옮긴다. 정규화 항목의 Source는 `discard`까지 Workspace에 남는다.
6. Metadata Commit이 WAL Byte를 더한다(위).
7. `discard`가 보존된 Source를 제거한다.
8. 취소: Normalizer가 Throw 전에 자기 Partial Output을 제거했고(이후 Workspace에는 Source만 있음) Retry는 보존된 Source로 실행되었다. 실패한 Partial과 Retry 출력은 순차적이어서 겹치지 않았다.

## 5. Capacity 관측과 한계

- tmp, Test Root, Application Support는 Test-runner Process에서 같은 `volumeUUIDString` / `volumeIdentifier`를 보고했다. 실제 PhotosPicker Provider 위치는 관측하지 않았다.
- `volumeAvailableCapacity`(`capPlain`)는 306개 측정 전부에서 26,992,640,000 B였고 한 번도 변하지 않았다.
- `statfs` 여유 공간(`statfsFree`, Section B에만 있음)은 273개 측정 가운데 243개가 26,992,640,000 B, 30개가 26,951,680,000 B(−40,960,000 B)였다. 30개는 모두 `syn-noise1080p60`과 `syn-noiseHLG1080p30` Run의 정규화 이후 Snapshot(S4–S7)이며 Cleanup 뒤 원래 값으로 돌아왔다. 8–18 MB 출력에서는 변하지 않았다.
- `volumeAvailableCapacityForImportantUsage`(`capImportant`)는 어떤 Run 안에서도 변하지 않았고(최대 167,746,585 B Workspace와 36–38 MB 출력 Run 포함) Run 사이에서만 네 값을 보였다: 37,230,774,904(Section A Run 1–2), 37,271,734,904(Section A Run 3), 37,281,000,672(Section B 초반), 37,240,040,672(Section B 후반). 변화량은 +40,960,000, +9,265,768, −40,960,000 B였다.
- 값이 변하지 않은 것은 Caching, 갱신 단위, Purgeable 공간 계산 중 무엇 때문인지 알 수 없으며 신선도의 증거도 아니다. 이 값으로 Byte를 Operation에 귀속할 수 없고 Important-usage 값과 Plain 값의 차이(약 10.2–10.3 GB)가 무엇을 포함하는지도 이 Evidence로 알 수 없다.
- 150 MB 4K Fixture를 Provider / Transfer 위치로 복사해도 Free-space 단계가 바뀌지 않았다(APFS Clone과 일치). 그런데 `totalFileAllocatedSize`는 전체 크기를 보고했다. 따라서 File별 Allocated 크기는 Clone의 물리 사용량을 과대 표시하고 Block 소유를 증명하지 않는다. 실제 Picker Transfer가 Clone되는지는 알 수 없다.
- Peak는 정규화 동안에만 약 20 ms 간격으로 표본 추출했고(Run당 32–98 Sample: 4K30 Noise 95–98, 취소 시도 32–33) 다른 단계는 단일 Snapshot이다. 표본 구간 밖의 Peak와 아래 Formula Peak는 File Lifetime에서 추론한 값이다.
- Free Space가 부족에 가까운 적이 없어 Runtime Disk Full은 실행되지 않았다.
- 합성 Noise는 최악의 경우도 아니다: 4K Noise는 축소가 Noise를 평균하여 1080p Noise보다 낮은 Rate를 냈다. 가장 큰 표본에서 보편적 출력 크기 상한을 추론하지 않는다.
- Normalizer는 `AVVideoAverageBitRateKey`를 설정하지 않는다(H.264 High AutoLevel만). Average Bitrate 요청이라도 File 크기 보장이 아니다.

## 6. Lifetime에서 추론한 Peak Additional Storage 모델

Accepted Set의 Source N₁…Nₙ 가운데 정규화 부분집합이 출력 Oⱼ를 만든다고 하면:

- Transfer 단계(Preflight 전): 이미 Adopt된 Σ Nᵢ + 전송 중인 항목의 Transfer 복사본 Nₖ(Clone이 아니라고 보면). Provider File은 Mellow 검사 시점에 이미 존재한다.
- Accepted Set 검사 시점: Σ Nᵢ는 이미 Disk에 있어 Capacity 값에 반영되어 있다. 남은 추가량은 Σ Oⱼ(모든 출력이 Materialize까지 공존) + Metadata 증가 + 취소 / Retry 과도분(Partial Output 최대 하나, Retry 출력과 누적되지 않음)이다.
- Materialize와 Discard는 Storage를 더하지 않는다. Commit된 Media는 다시 계산하지 않는다(ADR-024).
- Oⱼ에는 증명 가능한 상한이 없다.

## 7. 재현 절차

**재현 한계:** 이 Evidence는 저장소만으로 재현할 수 없다.

- Harness Source가 저장소에 없고 최종 버전의 SHA-256만 기록되었다; Hash는 동일성 확인 수단일 뿐 Source를 제공하지 않는다. Section A의 이전 버전은 Hash도 없다.
- 합성 Fixture는 Seed 없는 System 난수(`arc4random_buf`)로 생성했으므로 같은 Byte로 다시 만들 수 없고 위 Fixture Hash를 다시 맞출 수 없다. 생성 Parameter(Raster, Codec, Frame Duration, Frame 수, Pan 이동량)는 2절 표가 일부만 기록한다.
- `IMG_0130.MOV`는 소유자가 보관하는 비공개 실제 촬영본이며 저장소에 없다.
- 아래 절차는 Harness를 가진 사람을 위한 개요이며 실행 가능한 재현 절차가 아니다.

1. Commit `0ef173b`에서 Harness Source(위 SHA-256)를 `MellowTests/WorkingMediaNormalizerTests.swift` 끝에 덧붙이고 `import SwiftData`를 추가한 뒤 Fixture Directory UUID를 치환한다.
2. 소유자 승인 Fixture `IMG_0130.MOV`를 `xcrun devicectl device copy to --domain-type appDataContainer --domain-identifier com.mellow.Mellow --destination tmp/Step5AFixtures-<UUID>/IMG_0130.MOV`로 복사한다.
3. iPhone 12 Destination으로 `build-for-testing` 후 `test-without-building -only-testing:MellowTests/ZZStep5AStorageMeasurement/<test>`를 실행한다(`testZZ5A_0_fixtures`가 합성 Fixture를 만들고, `_1`–`_8`이 Scenario, `_9`가 Fixture Directory를 지운다).
4. Log에서 `S5A|` Line을 추출한다.
5. Test File을 Snapshot에서 Byte 단위로 복원하고 SHA-256과 Production Source Checksum을 비교한다.
6. Uninstall 없이 일반 Debug App을 Over-install하고 Container를 확인한다.
