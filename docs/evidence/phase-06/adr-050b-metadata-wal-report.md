# ADR-050 Unit 050-B — Metadata / WAL Evidence (Exploratory)

**Status:** Exploratory Measurement Evidence.

이 문서는 Accepted Decision, 증명된 상한, Performance Acceptance Threshold, Storage Gate 완료 증거가 아니다.

ADR-050은 Proposed이며 Unit 050-B를 포함한 어떤 Unit도 승인되지 않았다.

Raw Measurement Line은 같은 Directory의 `adr-050b-metadata-wal-raw.txt`에 있다.

## 1. Evidence Contract Fields

| Field | Value |
| --- | --- |
| Production Commit | `0ef173b6b53615a7c9e664ca30559b523702ed08` (`phase/06-media-import-normalization`) |
| Temporary Harness | `MellowTests/ProjectRepositoryTests.swift`에 임시로 덧붙인 Test 전용 `ZZ050BMetadataMeasurement` Class(+ `import SQLite3`), 측정 후 제거; Section B(사용한 측정)의 최종 Harness Source SHA-256 `cb22bec04b3dc2934c5f2aeb366cb834f3dc66d17a7456f15194a77043d57311`; Section A는 Pending-deleted Row의 `deletedAt`이 모두 같던 이전 버전이며 그 Hash는 기록하지 않았다; 복원된 Test File SHA-256은 측정 전 Snapshot과 같다(`037340de…e006`) |
| Harness 보존 | 저장소에 넣지 않았다(AGENTS.md Spike and Experiment Rule); 사본은 측정 Session의 임시 Scratch 영역에만 있다 |
| Build / Configuration | Debug, `build-for-testing` → `test-without-building`, 새 DerivedData |
| Device | iPhone 12 (`iPhone13,2`); Serial 미기록 |
| iOS | 27.0.1 (24A446) |
| Thermal / Power | 시작 Thermal State Nominal(0); Low Power Mode Off |
| Run Date | 2026-10-02 |
| Store | Run마다 새 격리 Directory `tmp/Step050B-<UUID>/default.store`; 실제 `MellowModelContainer.makePersistentContainer(storeURL:)`와 Production 형태의 `SwiftDataProjectRepository(modelContext: container.mainContext)`; App의 실제 Store와 Media는 열지 않았다 |
| 입력 | 지어낸 Metadata만 사용: Clip은 `.imported`, `RelativeMediaPath` 문자열만 있고 Media File은 없다, 고정 `createdAt`, Duration 3 s; Pending-deleted Row는 메모리에서 `deleteClip`으로 만들고 Row마다 서로 다른 `deletedAt`을 준다 |
| Repetition | Scenario당 3 Run; Section A는 아래 4절의 이유로 Estimate에 쓰지 않았지만 Raw에 보존했다 |

## 2. 방법

- 각 측정 단계는 Production과 같은 Repository 호출 순서를 따른다.
  - Select Clips 새 Project: `create(B)`(Save 1회) + `project(id:)` Read-back(Fetch, Save 없음).
  - Editor Add: `appendClips` → `update`(Save 1회) + Read-back 비교.
  - Editor Replace: `replaceClip`(기존 Clip은 Pending-deleted, 새 Clip이 같은 위치) → `update`(Save 1회) + Read-back 비교.
  - Select Clips `.replacingSaved`: `create(B)`(Save 1) + Read-back, 그 뒤 `deleteProject(A)`(Save 2, Cascade). 두 Save를 따로 측정했다.
- 기존 Project 크기 `D`는 0 / 10 / 50 / 200이며 D ≥ 10이면 그중 20%가 Pending-deleted Row다(10 → 2, 50 → 10, 200 → 40). 비교용으로 Pending Row 없는 D = 50 Add 1을 한 번 측정했다. 이 값들은 측정점이며 Product 상한이 아니다.
- **Fresh:** 새 Store를 열고 `recentProjects()` 한 번 뒤 Scenario Setup(`create`)만 실행한 상태.
- **Warm:** 같은 열린 Container에서 먼저 관계없는 고정 작업(50-Clip Project W 생성 + W에 Clip 1개 Add `update` 20회)을 실행한 상태. 측정 시작 시 WAL은 1,495,592–1,503,832 B(363–365 Frame, Commit Frame 42개)였고 Checkpoint는 일어나지 않았다.
- 관측 방법은 측정 대상 Store에 SQLite 연결을 열지 않는다.
  - `stat()`으로 DB / `-wal` / `-shm`의 Logical · Allocated 크기를 단계 전후에 기록했다.
  - 각 단계 동안 Background Thread가 약 0.2 ms 간격으로 `stat()`하여 Peak를 기록했다.
  - WAL Header(Page 크기, Checkpoint Sequence, Salt)와 현재 Generation의 Frame Header(Salt 일치)를 읽기 전용으로 읽어 쓰인 Frame 수와 Commit Frame 수(SQLite Transaction 수)를 셌다. Checkpoint 뒤 WAL 재시작은 Salt / Sequence 변화로 판정한다.
  - DB Header(Page 크기, Write / Read Version, Change Counter, Page 수)를 읽기 전용으로 읽었다.
  - Durable Row 수는 별도 `ModelContext`의 `fetchCount`로 셌다.
- SQLite 설정: 측정 Run과 별도의 Store에서 측정 뒤 Store File(DB / WAL / SHM)을 복사하고 그 **복사본**에 읽기 전용 연결로 Pragma를 질의했다.

## 3. 결과(Section B, 3 Run씩)

WAL 증가 = 단계 전후 `-wal` Logical 크기 차이. 각 행은 별도 표시가 없으면 3 Run이다. Frame = 그 단계에서 WAL에 쓰인 Frame 수(Frame = 24 B Header + 4,096 B Page = 4,120 B). Commit = 그 단계의 SQLite Commit Frame 수.

| 상태 | 단계 | 쓰인 Durable Clip Row | WAL 증가(B) | Frame | Commit | 단계 후 Row(Project / Clip / Pending) |
| --- | --- | --- | --- | --- | --- | --- |
| Fresh | create n = 1 | 1 | 74,192 | 18 | 2 | 1 / 1 / 0 |
| Fresh | create n = 10 | 10 | 74,192 | 18 | 2 | 1 / 10 / 0 |
| Fresh | create n = 50 | 50 | 90,672 | 22 | 2 | 1 / 50 / 0 |
| Fresh | create n = 200 | 200 | 123,632–127,752 | 30–31 | 2 | 1 / 200 / 0 |
| Fresh | Add D = 0, n = 1 | 1 | 61,800 | 15 | 2 | 1 / 1 / 0 |
| Fresh | Add D = 0, n = 10 | 10 | 61,800 | 15 | 2 | 1 / 10 / 0 |
| Fresh | Add D = 10, n = 1 | 11 | 61,800 | 15 | 2 | 1 / 11 / 2 |
| Fresh | Add D = 10, n = 10 | 20 | 61,800 | 15 | 2 | 1 / 20 / 2 |
| Fresh | Add D = 50, n = 1 | 51 | 70,040 | 17 | 2 | 1 / 51 / 10 |
| Fresh | Add D = 50, n = 10 | 60 | 70,040–82,400 | 17–20 | 2 | 1 / 60 / 10 |
| Fresh | Add D = 50(Pending 없음), n = 1 | 51 | 65,920–82,400 | 16–20 | 2 | 1 / 51 / 0 |
| Fresh | Add D = 200, n = 1 | 201 | 98,880 | 24 | 2 | 1 / 201 / 40 |
| Fresh | Add D = 200, n = 10 | 210 | 103,000 | 25 | 2 | 1 / 210 / 40 |
| Fresh | Replace D = 10 | 11 | 61,800 | 15 | 2 | 1 / 11 / 3 |
| Fresh | Replace D = 50 | 51 | 70,040–82,400 | 17–20 | 2 | 1 / 51 / 11 |
| Fresh | Replace D = 200 | 201 | 94,760–115,360 | 23–28 | 2 | 1 / 201 / 41 |
| Fresh | `.replacingSaved` create B n = 10(A: D = 10) | 10 | 65,920 | 16 | 2 | 2 / 20 / 2 |
| Fresh | `.replacingSaved` delete A D = 10 | 10(삭제) | 61,800 | 15 | 1 | 1 / 10 / 0 |
| Fresh | `.replacingSaved` create B n = 10(A: D = 50) | 10 | 65,920–78,280 | 16–19 | 2 | 2 / 60 / 10 |
| Fresh | `.replacingSaved` delete A D = 50 | 50(삭제) | 82,400 | 20 | 1 | 1 / 10 / 0 |
| Fresh | `.replacingSaved` create B n = 10(A: D = 200) | 10 | 90,640–94,760 | 22–23 | 2 | 2 / 210 / 40 |
| Fresh | `.replacingSaved` delete A D = 200(B n = 10과 n = 1 두 Scenario, 6 Run) | 200(삭제) | 115,360–123,600 | 28–30 | 1 | 1 / 10 / 0 또는 1 / 1 / 0 |
| Fresh | `.replacingSaved` create B n = 1(A: D = 200) | 1 | 65,920–70,040 | 16–17 | 2 | 2 / 201 / 40 |
| Warm | create n = 10 | 10 | 86,520–90,640 | 21–22 | 2 | 2 / 80 / 0 |
| Warm | Add D = 50, n = 1 | 51 | 70,040–74,160 | 17–18 | 2 | 2 / 121 / 10 |
| Warm | Add D = 50, n = 10 | 60 | 86,520 | 21 | 2 | 2 / 130 / 10 |
| Warm | Replace D = 50 | 51 | 70,040 | 17 | 2 | 2 / 121 / 11 |
| Warm | `.replacingSaved` create B n = 10(A: D = 50) | 10 | 86,520–90,640 | 21–22 | 2 | 3 / 130 / 10 |
| Warm | `.replacingSaved` delete A D = 50 | 50(삭제) | 86,520 | 21 | 1 | 2 / 80 / 0 |

### 관측

- **Save 경계와 Transaction:** `create`와 `update` Save는 모두 SQLite Commit Frame 2개, `deleteProject` Save는 1개를 썼다. Repository Save 하나는 SQLite Transaction 하나가 아니다. `.replacingSaved`는 Repository Save 2회, SQLite Transaction 3개로 이루어진 Operation이다. 어느 Transaction에 어떤 Row가 들어갔는지는 Page 내용을 해석하지 않았으므로 알 수 없다.
- **Read-back:** Read-back 단계는 WAL에 아무것도 쓰지 않았다(각 단계의 Commit 수가 Save 수와만 일치).
- **Whole-project Rewrite:** Add / Replace의 WAL 증가는 새 Clip 수가 아니라 기존 Project 크기를 따라 커졌다(Add n = 1: D = 0 → 61,800 B, D = 200 → 98,880 B).
- **Cascade 삭제:** `.replacingSaved`의 이전 Project 삭제는 삭제되는 Clip Row 수에 따라 커졌다(D = 10 → 61,800 B, D = 200 → 115,360–123,600 B).
- **Store 크기 효과:** 같은 n = 10 `create`도 Store에 이미 Row가 많으면 더 커졌다(Fresh 빈 Store 74,192 B, A가 200 Row일 때 90,640–94,760 B, Warm 86,520–90,640 B). 이 효과는 210 Clip Row까지만 관측되었다.
- **Page 단위 변동:** 같은 Scenario의 Run 간 차이는 0–5 Frame(0–20,600 B)이었다.
- **Net WAL 증가 = 쓰인 Byte:** 측정된 모든 단계에서 WAL 재시작이나 Checkpoint가 없었으므로 WAL 증가는 그 단계가 WAL에 쓴 Frame Byte와 같았다. 단계 안의 Peak WAL 크기는 단계 후 크기와 같았다(WAL은 단계 중에 줄지 않았다). `-shm`은 항상 32,768 B였다. 단계 중 DB File은 변하지 않았다(21 Page).
- **Checkpoint:** 측정 단계 안에서는 Checkpoint가 관측되지 않았다(Warm 최대 약 1.77 MB WAL, 약 430 Frame 포함). Container를 닫을 때 WAL이 DB로 Checkpoint되어 `-wal`이 0 B가 되고 DB File이 86,016 B에서 최대 139,264 B로 커졌다(최대 +53,248 B).
- **WAL 무한 증가 위험:** 동시 Reader로 인한 Checkpoint 지연과 Auto-checkpoint 임계값을 넘는 경우는 측정하지 않았다.

### SQLite 설정(복사본에서 얻은 값)

| 항목 | 값 | 출처 |
| --- | --- | --- |
| `page_size` | 4,096 | 복사본 Pragma와 DB / WAL Header가 일치 |
| `journal_mode` | `wal` | 복사본 Pragma; DB Header Write / Read Version 2 / 2 |
| `auto_vacuum` | 2(Incremental) | 복사본 Pragma |
| `encoding` | UTF-8 | 복사본 Pragma |
| `wal_autocheckpoint` | **얻지 못함** | 연결별 설정이며 Database File에 저장되지 않으므로 복사본 연결은 SwiftData 연결의 값을 보고하지 않는다 |
| `synchronous` | **얻지 못함** | 위와 같은 이유 |

## 4. Section A(대체됨)

- 첫 Run은 Harness 검증(create)이었고 결과는 Section B와 같았다.
- 두 번째 Run은 Pending-deleted Row의 `deletedAt`을 모두 같은 값으로 만들었다. `VlogProject`는 `deletedClips`를 `deletedAt`으로 정렬하므로 같은 값끼리의 순서가 Fetch 순서에 따라 달라졌고, Harness의 Read-back 동등성 검사 32개가 실패했다. Save 자체는 검사 전에 완료되었고 Row 수도 기대와 같았다.
- 이것은 지어낸 입력에서 생긴 Harness 결함이므로 Row마다 다른 `deletedAt`을 주도록 고친 뒤 전체 Matrix를 다시 측정했다(Section B). Section A는 Estimate에 쓰지 않는다.
- 참고 관찰: Production에서도 두 Pending-deleted Clip의 `deletedAt`이 정확히 같으면 같은 순서 문제가 생길 수 있다. 이 저장소에서 그런 경우가 실제로 생기는지는 확인하지 않았다.

## 5. 해석의 한계

- 관측값은 측정점(D ≤ 200, n ≤ 10, Store 최대 210 Clip Row) 안의 표본이며 그 밖으로의 외삽이나 상한이 아니다.
- Checkpoint가 Operation 도중에 일어나는 경우, Auto-checkpoint 임계값, 동시 Reader, 큰 기존 Store / 큰 WAL(App의 실제 WAL은 약 1 MB였다), Disk Full 중 Save는 측정하지 않았다.
- SQLite Transaction 내용은 해석하지 않았다.

## 6. 재현 한계

- Harness Source가 저장소에 없고 최종 버전의 SHA-256만 기록되었다. Section A의 이전 버전은 Hash도 없다. 이 Evidence는 저장소만으로 재현할 수 없다.
- 입력 Metadata는 Seed 없는 UUID를 쓰므로 Byte 단위로 같은 Store를 다시 만들 수 없다. 2절의 구성 규칙은 같은 형태의 입력을 다시 만드는 데 충분하다.
- 실제 Media나 비공개 Fixture는 쓰지 않았다.
