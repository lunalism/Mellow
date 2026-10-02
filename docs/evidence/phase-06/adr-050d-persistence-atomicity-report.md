# ADR-050 Unit 050-D — Persistence Atomicity Probe (Exploratory)

**Status:** Exploratory Evidence.

이 문서는 Accepted Decision, Atomicity 보장, Storage Gate 완료 증거가 아니다.

ADR-050은 Proposed이며 어떤 Unit도 승인되지 않았다.

Raw Line은 같은 Directory의 `adr-050d-persistence-atomicity-raw.txt`에 있다.

## 1. 질문

Unit 050-B 측정에서 Repository `create` / `update` Save 하나가 WAL에 SQLite Commit Frame 2개를 쓰는 것이 관측되었다.

이 Probe는 두 Transaction이 각각 무엇을 바꾸는지, 그리고 Save와 Operation의 각 Commit 경계에서 Process가 멈췄을 때 다시 열린 Store가 어떤 Domain 상태를 보이는지 확인한다.

## 2. Evidence Contract Fields

| Field | Value |
| --- | --- |
| Production Commit | `0ef173b6b53615a7c9e664ca30559b523702ed08` |
| Temporary Harness | `MellowTests/ProjectRepositoryTests.swift`에 임시로 덧붙인 Test 전용 `ZZ050DAtomicityProbe`(+ `import SQLite3`), 측정 후 제거; Harness Source SHA-256 `a7766dbd5b07751320fea301ba663c3257908545990bc6a0e9cbf6ff4972e9dc`(한 버전만 실행); 복원된 Test File SHA-256 `037340de…e006`(측정 전과 같음) |
| Harness 보존 | 저장소에 넣지 않았다; 사본은 측정 Session의 임시 Scratch 영역에만 있다 |
| Device / OS | iPhone 12 (`iPhone13,2`), iOS 27.0.1 (24A446), SQLite 3.54.0; Serial 미기록 |
| Build | Debug, `build-for-testing` → `test-without-building` |
| Run Date | 2026-10-02 |
| Store | Run마다 새 격리 Directory `tmp/Step050D-<UUID>/`; 실제 `MellowModelContainer.makePersistentContainer(storeURL:)`와 Production 형태의 `SwiftDataProjectRepository(modelContext: container.mainContext)`; App의 실제 Store와 Media는 열지 않았다 |
| 입력 | 지어낸 Metadata(`.imported` Clip, Media File 없음, 고정 `createdAt`, Pending Row마다 다른 `deletedAt`) |
| Repetition | Scenario당 3 Run; 실패 0; 69개 경계 모두 SQLite `quick_check` = `ok` |

## 3. 방법

1. 측정할 Save 직전과 직후에 Live Store의 `-wal`을 읽기 전용으로 읽어 현재 Generation의 Frame(Page 번호, Commit 표시)을 얻는다. Checkpoint나 WAL 재시작이 있으면 그 Save를 판정 불가로 기록하도록 했다(발생하지 않았다).
2. **Commit 수를 세는 방법:** WAL Frame Header의 "Commit 뒤 Database 크기" Field가 0이 아닌 Frame을 Commit Frame으로 센다. 이것은 SQLite Transaction 경계의 직접 관측이다.
3. **각 Transaction의 내용:** Save 직후 상태의 복사본을 Checkpoint한 뒤 DB File의 모든 Table / Index B-tree를 Root Page에서 내부 Page의 Child Pointer를 따라 걸어 Page → 소유 B-tree 표를 만들고, 각 Transaction이 쓴 Page 번호를 그 표로 이름 붙인다. Overflow / Freelist Page는 "unmapped"로 표시하도록 했다(나타나지 않았다).
4. **Crash 경계 재구성:** 각 경계 X(Save 직전, 각 Commit Frame 직후, 마지막 Transaction의 중간)에 대해 별도 복사 Directory에 DB File 복사본과 "X까지 자른" WAL을 만든다. SQLite는 WAL을 열 때 마지막 유효 Commit까지만 반영하므로 이 복사본은 Process가 X에서 멈췄을 때 Crash Recovery가 보여 줄 Durable 상태의 모델이다(Crash 자체를 재현한 것은 아니다). Transaction 중간은 Transaction마다 한 지점(마지막 Transaction의 가운데)만 관측했다.
5. 각 복사본을 (a) SQLite 연결로 열어 `quick_check`, Table별 Row 수, `Z_PRIMARYKEY`를 읽고, (b) 다른 복사본을 Production `MellowModelContainer` + `SwiftDataProjectRepository`로 다시 열어 `recentProjects()`의 모든 Project에 대해 Identity, Active Clip 순서와 전체 Field, Pending-deleted Clip과 Deletion Record, Orientation을 기대 상태와 비교한다.
6. 판정: Save 전 상태와 같으면 `PRIOR`, 의도한 새 상태와 같으면 `NEW`, 다르면 `PARTIAL`, 열거나 읽지 못하면 `UNREADABLE`.

Live Store는 읽기만 했고 SQLite 연결은 복사본에만 열었다.

## 4. 결과

| Operation | Repository Save | Transaction 1 | Transaction 2 | Save 직전 | Txn 1 직후 | Txn 2 중간 | Txn 2 직후 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Select Clips 새 Project(create n = 3) | 1 | `Z_PRIMARYKEY` Page 1개 | Domain Row + Index + 영구 이력 Table + `Z_PRIMARYKEY` | PRIOR | PRIOR | PRIOR | NEW |
| Editor Add(D = 5 중 Pending 1, n = 2) | 1 | `Z_PRIMARYKEY` Page 1개 | 같음 | PRIOR | PRIOR | PRIOR | NEW |
| Editor Add(D = 50 중 Pending 10, n = 10) | 1 | `Z_PRIMARYKEY` Page 1개 | 같음(Clip Table Page 3개) | PRIOR | PRIOR | PRIOR | NEW |
| Editor Replace(D = 5 중 Pending 1) | 1 | `Z_PRIMARYKEY` Page 1개 | 같음 | PRIOR | PRIOR | PRIOR | NEW |
| `.replacingSaved` Save 1(create B n = 3) | 1 | `Z_PRIMARYKEY` Page 1개 | 같음 | PRIOR(A) | PRIOR(A) | PRIOR(A) | NEW(A + B) |
| `.replacingSaved` Save 2(delete A) | 1 | Domain Row + Index + 영구 이력 Table + `Z_PRIMARYKEY` | — | PRIOR(A + B) | NEW(B) | —(Transaction이 하나뿐; 그 중간: PRIOR(A + B)) | — |

모든 행은 3 Run에서 같았다.

### 직접 관측

- `create` / `update` Save의 Transaction 1은 매번 Page 8 하나만 썼고 그 Page는 `Z_PRIMARYKEY` Table의 B-tree였다. 그 직후 경계에서 `Z_PRIMARYKEY`의 `Z_MAX`만 새 Row 수만큼 커졌고(예: create n = 3에서 Clip 0 → 3, Project 0 → 1) 다른 모든 Table의 Row 수는 그대로였으며 Domain 판정은 `PRIOR`였다.
- Transaction 2는 `ZPERSISTEDVLOGPROJECT`, `ZPERSISTEDVLOGCLIP`, 그 Unique / Project Index, `ATRANSACTION` / `ACHANGE`와 그 Index, `Z_PRIMARYKEY`를 썼다. `ATRANSACTIONSTRING`은 각 Store의 첫 `create` Transaction 2에서만 쓰였고 Add / Replace / 이전 Project 삭제에서는 쓰이지 않았다. 그 직후 경계에서만 Domain 판정이 `NEW`였다.
- 마지막 Transaction의 중간에서 자른 WAL은 매번 직전 경계와 같은 Domain 상태(`PRIOR`)를 보였다.
- `deleteProject` Save는 Transaction 하나였다.
- 어떤 경계에서도 `PARTIAL`이나 `UNREADABLE`이 나오지 않았다.

### 추론(직접 관측이 아님)

- Transaction 1은 Core Data가 새 Object의 영구 ID를 위해 Primary Key 범위를 미리 할당하는 Bookkeeping으로 보인다. 근거는 바뀐 Page와 Field뿐이며 Framework 문서로 확인하지 않았다. 이 Transaction만 Durable해지면 남는 것은 사용되지 않는 Primary Key 간격이며 Domain 상태는 바뀌지 않는다(관측).
- `ATRANSACTION` / `ACHANGE`는 SwiftData / Core Data의 영구 이력(Persistent History) Table로 보인다; Domain Row와 같은 Transaction에서 쓰였다(관측).

## 5. 결론과 한계

### 이 Probe가 보인 것

- 측정한 네 Operation의 각 Repository Save에 대해, 관측한 모든 경계(Save 직전, 각 Commit 직후, Transaction당 한 개의 중간 지점)에서 재구성한 Domain 상태는 Save 전 상태 또는 완전한 새 상태 둘 중 하나였고 부분 상태는 없었다. 관측하지 않은 다른 중간 지점도 같을 것이라는 것은 SQLite WAL Recovery 설계에 근거한 추론이다. 즉 측정한 경우에 재구성한 DB / WAL 경계가 완전한 이전 상태 또는 새 상태로 다시 열렸다는 것이며, 실제 Process 강제 종료, 전원 손실, 모든 Save 오류에 대한 보장이 아니다.
- `.replacingSaved`는 Operation 전체로는 원자적이지 않다: Save 1과 Save 2 사이에서 멈추면 A와 B가 함께 Durable하게 남는다(관측). 이것은 부분 Project가 아니라 두 완전한 Project이다.

### 이 Probe가 보이지 않은 것

- **Process 안의 Save 실패:** 실제 Disk Full, I/O 오류, Fsync 오류로 Save가 오류를 던지는 경우는 주입하지 않았다. 기기 전체를 채우거나 실제 Store를 건드리지 않고 SQLite 쓰기 도중 실패를 안전하게 주입할 방법을 이 범위에서 쓰지 않았다. Save 전에 Throw하는 방식은 Save 도중 동작을 증명하지 않으므로 쓰지 않았다. SQLite 의미상 실패한 Transaction은 Durable 상태에 반영되지 않을 것으로 예상하지만 이 Probe의 관측은 아니다.
- **Save가 오류를 던졌지만 Transaction 2가 이미 Commit된 경우:** 예컨대 Commit 뒤의 Framework 처리에서 오류가 나는 경우가 가능한지, 가능하다면 Durable 상태가 `NEW`인 채 오류가 보고되는지는 확인되지 않았다. 따라서 "Save가 던지면 Commit되지 않았다"는 증명되지 않았다.
- **Save 성공이 전원 손실 뒤에도 Durable한지:** `synchronous` 설정을 얻지 못했다. WAL Mode에서 설정에 따라서는 마지막 Commit이 전원 손실 뒤 사라질 수 있다(이 경우에도 손상 없이 직전 상태로 돌아가는 것이 SQLite의 설계지만 이 Probe의 관측은 아니다). App Crash와 전원 손실은 다르며 이 Probe는 Process 정지만 재현한다.
- **Torn Write · Sector 손상:** 재현하지 않았다.
- **Checkpoint 도중 정지:** Operation 도중 Checkpoint가 없었으므로 다루지 않았다.
- **Framework 보장:** Apple 문서의 Save Atomicity 문구를 이 Probe에서 인용하거나 확인하지 않았다.
- **규모:** D ≤ 50, n ≤ 10, Store 최대 60 Clip Row.

### Media 보존 · 정리에 대한 의미

- Save가 성공했다면 그 Save의 Domain Row는 Durable하게 존재하므로(관측: Txn 2 직후 `NEW`) 그 Row가 참조하는 Media를 지우면 안 된다.
- Save가 오류를 던졌다면 Durable 상태는 관측으로 확정되지 않는다. 이는 ADR-050 050-D D1 / D4(Save 오류 = Pre-commit, Rollback)의 가정이 증명되지 않았음을 뜻하며, 가정이 틀리면 D4 Rollback이 Durable Row가 참조하는 Media를 옮기거나 지울 수 있다.
- **소유자 결정 후보(확립된 결론 아님):** Save 오류 뒤 Rollback 여부를 오류 자체가 아니라 새 Context로 다시 읽은 Durable 상태로 정하는 Gate — `PRIOR`면 Rollback, `NEW`면 보존(Commit된 것으로 처리), 다시 읽기 실패면 보존하고 다음 시작의 기존 Orphan Recovery(참조 없는 Media만 제거)에 맡김.
- `.replacingSaved`의 Save 1과 Save 2 사이 정지는 A와 B를 모두 남기며 두 Project의 Media는 모두 참조되므로 보존된다.

## 6. 재현 한계

- Harness Source가 저장소에 없고 SHA-256만 기록되었다. 이 Evidence는 저장소만으로 재현할 수 없다.
- 입력 UUID는 Seed가 없으므로 Byte 단위로 같은 Store를 다시 만들 수 없지만 3절의 방법과 4절의 입력 형태로 같은 실험을 다시 할 수 있다.
