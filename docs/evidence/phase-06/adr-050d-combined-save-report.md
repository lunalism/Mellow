# ADR-050 Unit 050-D — `.replacingSaved` Combined-Save Experiment (Exploratory)

**Status:** Exploratory Evidence.

이 문서는 OD-14의 결정, 050-D의 승인, Atomicity 보장, Storage Gate 완료 증거가 아니다.

Raw Line은 같은 Directory의 `adr-050d-combined-save-raw.txt`에 있다.

## 1. 질문

Select Clips `.replacingSaved`에서 새 Project B의 삽입과 이전 Project A의 삭제를 하나의 `ModelContext`에 쌓고 `save()`를 한 번 호출하면, 그 Save가 SQLite에 어떤 Commit을 쓰는지, 그리고 각 Commit 경계와 Transaction 중간에서 다시 연 Store가 어떤 상태인지 확인한다(ADR-050 050-D D8.6a, OD-14의 결정 입력).

## 2. Evidence Contract Fields

| Field | Value |
| --- | --- |
| Production Commit | `800e3ec9f023eb24c1013c5f47f7f75b342c1532`(Production 코드 변경 없음) |
| Temporary Harness | `MellowTests/ProjectRepositoryTests.swift`에 임시로 덧붙인 Test 전용 `ZZ050DCombinedSaveProbe`(+ `import SQLite3`), 측정 후 제거; Harness Source SHA-256 `da1edcf11189708eafa9f7938e40746cd84dda06dab0b4e22dc479c14aa6acd1`(한 버전만 실행); 복원된 Test File SHA-256 `037340de…e006`(측정 전과 같음) |
| Harness 보존 | 저장소에 넣지 않았다; 사본은 측정 Session의 임시 Scratch 영역에만 있다 |
| Device / OS | iPhone 12 (`iPhone13,2`), iOS 27.0.1 (24A446), SQLite 3.54.0; Serial 미기록 |
| Build | Debug, `build-for-testing` → `test-without-building` |
| Run Date | 2026-10-02 |
| Store | Run마다 새 격리 Directory `tmp/Step050C-<UUID>/`; 실제 `MellowModelContainer.makePersistentContainer(storeURL:)`; App의 실제 Store와 Media는 열지 않았다 |
| 입력 | 지어낸 Metadata(`.imported` Clip, Media File 없음); A는 Production Repository `create`로 준비(측정 밖) |
| Case | Small: A 5 Clip(그중 Pending 1) → B 3 Clip; Large: A 50 Clip(그중 Pending 10) → B 10 Clip; 각 3 Run |
| 결과 | 6 Run, 실패 0; 24개 경계 모두 SQLite `quick_check` = `ok` |

## 3. 방법

1. Production Repository로 A를 만든 뒤, 같은 Container에서 새 `ModelContext`를 만들고 `autosaveEnabled = false`로 설정했다(기록: 실험 Context `false`, Production 형태의 `mainContext`는 `true`). 이 실험은 제안된 `replaceProject` API나 Autosave가 켜진 `mainContext`와의 상호작용을 시험하지 않는다. 임시 Store Directory 이름 `Step050C-<UUID>`는 Harness 내부 표지일 뿐이다.
2. 그 Context에서 A Row를 Fetch하고, `insert(PersistedVlogProject(project: B))`, `delete(A)`, `save()`를 중단 지점 없이 순서대로 실행했다. 명시적 Save는 한 번이다.
3. Save 전후에 Live WAL을 읽기 전용으로 읽어 Commit Frame을 세고, 각 Transaction의 Page를 Checkpoint된 복사본의 B-tree 소유자로 이름 붙였다(050-D Atomicity Probe와 같은 방법).
4. 각 경계(Save 직전, 각 Commit 직후, 마지막 Transaction의 중간 한 지점)마다 DB File 복사본과 그 지점까지 자른 WAL로 별도 복사본을 만들고, SQLite로 `quick_check` · Table별 Row 수 · `ZPROJECT IS NULL`인 Clip Row 수 · `Z_PRIMARYKEY`를 읽고, 다른 복사본을 Production Repository로 다시 열어 모든 Project의 Identity, Active Clip 순서와 전체 Field, Pending-deleted Clip과 Deletion Record, Orientation을 비교했다.
5. 판정: `A_ONLY`(A와 정확히 같음), `B_ONLY`(B와 정확히 같음), `BOTH`, `NEITHER`, `PARTIAL`, `UNREADABLE`.

## 4. 결과

| Case | 명시적 Save | SQLite Commit | Transaction 1 | Transaction 2 | Save 직전 | Txn 1 직후 | Txn 2 중간 | Txn 2 직후 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Small(A 5 / Pending 1 → B 3) | 1 | 2 | `Z_PRIMARYKEY` Page 하나 | B 삽입, A와 그 Clip Row 삭제, Index, 영구 이력 Table, `Z_PRIMARYKEY` | A_ONLY | A_ONLY | A_ONLY | B_ONLY |
| Large(A 50 / Pending 10 → B 10) | 1 | 2 | `Z_PRIMARYKEY` Page 하나 | 같은 Table들 + `sqlite_master`(Page 1)와 B-tree 소유자를 찾지 못한 Page 4개(2, 22, 23, 24; 해석하지 않음 — Page 증가일 수 있으나 확인하지 않음) | A_ONLY | A_ONLY | A_ONLY | B_ONLY |

모든 행은 3 Run에서 같았다.

### 직접 관측

- Transaction 1은 매번 Page 8 하나(`Z_PRIMARYKEY`)만 썼다. 그 직후 `Z_MAX`만 커졌고(Small: Clip 5 → 8, Project 1 → 2; Large: Clip 50 → 60, Project 1 → 2) 모든 Domain Table의 Row 수는 그대로였으며 상태는 `A_ONLY`였다.
- Transaction 2 직후 `ZPERSISTEDVLOGPROJECT` = 1, `ZPERSISTEDVLOGCLIP` = B의 Clip 수(3 또는 10)였고 상태는 `B_ONLY`였다. A의 Active와 Pending-deleted Clip Row는 모두 사라졌고 `ZPROJECT IS NULL`인 Clip Row는 0이었다. B의 Clip은 순서 · Field · 소유가 B와 정확히 같았다.
- 마지막 Transaction의 중간에서 자른 WAL은 매번 `A_ONLY`였다.
- `BOTH`, `NEITHER`, `PARTIAL`, `UNREADABLE`은 어떤 경계에서도 나오지 않았다.
- WAL 증가: Small 65,920 B(16 Frame), Large 86,520 B(21 Frame), 3 Run 모두 같음.

### 추론(직접 관측이 아님)

- 여러 SQLite Commit 가운데 Domain Row를 바꾼 Commit은 하나였으므로, 측정한 경우에 "A 삭제"와 "B 삽입"은 같은 SQLite Transaction에 있었다. 관측하지 않은 다른 중간 지점도 같을 것이라는 것은 SQLite WAL Recovery 설계에 근거한 추론이다.

## 5. 050-B Metadata Estimate와의 비교

- Accepted 050-B는 `.replacingSaved`를 Save 2회로 계산한다: `(196,608 + 512 × n) + (196,608 + 512 × D_replaced)`.
- Small: Estimate 397,312 B, 관측 WAL 증가 65,920 B(0.1659배). Large: Estimate 423,936 B, 관측 86,520 B(0.2041배).
- 참고로 050-B Evidence의 두 Save 측정(A 50 Row 중 Pending 10, B 10)에서 두 Save의 WAL 증가 합은 148,320–160,680 B였다(다른 Run, 같은 형태).
- 이 비교는 Accepted 상수를 바꾸지 않으며 상한을 증명하지 않는다.

## 6. 한계

- 재구성한 DB / WAL 경계는 Crash Recovery의 모델이며, 실제 Process 강제 종료, 전원 손실, 모든 Process 안 Save 오류 동작을 증명하지 않는다.
- Transaction 중간은 Transaction마다 한 지점만 관측했다.
- 규모는 A ≤ 50 Clip, B ≤ 10 Clip이며 그 밖으로 외삽하지 않는다.
- Save 오류 경로, Disk Full, Checkpoint 도중 정지, 동시 Reader는 다루지 않았다.
- `mainContext.autosaveEnabled = true`는 이 Test Process에서 읽은 값이다.

## 7. 재현 한계

- Harness Source가 저장소에 없고 SHA-256만 기록되었다. 이 Evidence는 저장소만으로 재현할 수 없다.
- 입력 UUID는 Seed가 없으므로 Byte 단위로 같은 Store를 다시 만들 수 없지만 3절의 방법과 2절의 입력 형태로 같은 실험을 다시 할 수 있다.
