# Mellow — Development Roadmap

## 1. Document Purpose

이 문서는 Mellow MVP를 처음부터 TestFlight 준비 상태까지 구현하기 위한 실행 계획을 정의한다.

`PRODUCT.md`, `FEATURES.md`, `DESIGN.md`, `ARCHITECTURE.md`, `DECISIONS.md`를 실제 개발 순서로 연결하며, Codex가 중간에 범위를 임의로 확장하거나 다른 방향으로 분기하지 않도록 단계별 목표와 완료 조건을 고정한다.

이 문서는 구현 순서, 검증 방법, Phase 진입 조건, Phase 종료 조건, Git 운영 방식의 기준으로 사용한다.

현재 Phase가 완료되지 않은 상태에서는 다음 Phase의 구현을 시작하지 않는다.

새로운 아이디어가 발생하더라도 현재 Phase에 즉시 추가하지 않고 Backlog 또는 별도 Decision 대상으로 이동한다.

---

## 2. Source of Truth Order

구현 중 요구사항 충돌이 발생하면 다음 순서로 기준을 해석한다.

1. `PRODUCT.md`
2. `FEATURES.md`
3. `DESIGN.md`
4. `ARCHITECTURE.md`
5. `DECISIONS.md`
6. `ROADMAP.md`
7. 실제 코드

코드가 문서와 충돌하는 경우 코드가 기준이 아니라 문서가 기준이다.

문서 간 실제 충돌이 발견되면 Codex는 임의로 해석하지 않고 작업을 중단한 뒤 충돌 내용을 보고해야 한다.

---

## 3. Global Development Rules

### 3.1 Phase Gate

현재 Phase의 Exit Criteria를 모두 충족하기 전에는 다음 Phase를 시작하지 않는다.

### 3.2 No Scope Expansion

현재 Phase에서 요구하지 않은 기능을 발견하거나 아이디어가 생겨도 즉시 구현하지 않는다.

새 기능은 Backlog로 기록하거나 사용자의 승인을 받아 이후 Phase로 배치한다.

### 3.3 No Silent Product Decisions

Open Decision을 구현 중 발견하면 Codex가 임의로 결정하지 않는다.

Codex는 다음 내용을 보고한다.

- 결정이 필요한 항목
- 현재 작업에 미치는 영향
- 가능한 선택지
- 각 선택지의 장단점
- 추천안

사용자 승인 전에는 해당 결정에 의존하는 구현을 진행하지 않는다.

현재 Phase / Change Set에 Blocking인지는 `RULES.md` 3절의 기준으로 판단하며 필요한 구현 구조, Correctness, Media / Data / User Safety, Acceptance Criteria, 이미 도달했어야 하는 Gate, 현재 변경 관련 문서 모순과 현재 범위의 필수 후속 작업 Dependency를 포함한다.

진행 중 새로운 Evidence로 Blocking Decision이 발생하면 해당 구현을 중단하고 4절의 Exception and Replanning Protocol을 따르며 Blocking 여부가 불명확해도 추측으로 진행하지 않고 보고한다.

Future Phase-only Pending은 현재 Blocking 조건에 해당하지 않을 때 현재 작업을 차단하지 않지만 적절한 Source of Truth에 기록하고 Owning Phase / Gate와 연결하여 Required Gate에 도달하기 전에 해결한다.

Merge를 위해 Pending을 임의 확정·삭제·숨김·무시하거나 조용히 연기하지 않으며 Future라는 표시만으로 현재 Blocking Dependency를 회피하지 않는다.

### 3.4 Architecture Change Gate

`ARCHITECTURE.md`의 Confirmed Technical Decisions 또는 Architecture Invariants를 변경해야 한다면 구현을 중단한다.

변경 이유를 설명하고 필요한 경우 `DECISIONS.md`에 새로운 ADR을 추가한 뒤 승인 후 진행한다.

### 3.5 Physical Device Gate

Camera, Recording, Orientation, Import, Preview, Export, Storage, Haptic과 관련된 Phase는 iPhone 12 실기기 검증을 완료하기 전까지 완료 처리하지 않는다.

### 3.6 Build Quality Gate

각 Phase 종료 전 최소한 다음을 수행한다.

- Xcode Build
- Unit Tests
- 해당 Phase 관련 Integration Tests
- Compiler Warning 확인
- `git diff --check`
- Git Working Tree 상태 확인

### 3.7 Small Reviewable Changes

한 번에 여러 Phase를 구현하지 않는다.

한 Commit은 가능한 한 하나의 명확한 목적을 가져야 한다.

### 3.8 No Premature Optimization

실제 측정 없이 복잡한 최적화를 먼저 도입하지 않는다.

다만 Media 전체를 Memory에 올리는 것처럼 Architecture 문서에서 금지한 명백한 위험 구조는 처음부터 피한다.

### 3.9 Native First

MVP에서는 승인 없이 Third-party Dependency를 추가하지 않는다.

### 3.10 Documentation Sync

구현 과정에서 확정된 중요 Decision이 기존 문서에 영향을 주면 관련 문서를 같은 작업 범위에서 업데이트한다.


### 3.11 Definition of Ready

각 Phase는 구현을 시작하기 전에 최소한 다음 조건을 만족해야 한다.

- 이전 Phase의 Exit Criteria가 완료되었다.
- 현재 Phase에 필요한 Product, Feature, Design, Architecture Decision이 확정되어 있다.
- 해당 Phase의 Decision Gate가 있다면 모두 해결되었다.
- 필요한 Test Strategy가 정의되어 있다.
- Physical Device Test가 필요한 경우 테스트 방법과 대상 기기가 준비되어 있다.
- 해당 Phase의 Scope와 Explicitly Excluded 항목이 명확하다.
- 현재 Branch와 `main`의 상태가 깨끗하다.

이 조건을 만족하지 못하면 Codex는 Phase 구현을 시작하지 않는다.

Phase 진입에 필요한 Structural / Product / Technical Decision Gate는 모두 해결되어야 하며 이미 Required Gate에 도달한 Pending은 해당 Phase의 구현 시작과 완료를 막는다.

#### Structural UX Readiness

UI를 포함하는 Phase는 해당 구현 구조에 영향을 주는 UX Decision이 unresolved 상태이면 구현을 시작할 수 없다.

화면의 핵심 Layout, 주요 Control Placement / Hierarchy, List / Grid, 주요 Interaction / Gesture, Navigation과 Progress / Completion 구조는 해당 UI를 필요로 하는 가장 이른 Phase 이전에 사용자 승인으로 결정한다.

Pending UX Decision 자체는 허용하지만 현재 Phase의 구조적 선행조건을 UI 구현 뒤나 Phase 12로 미루지 않는다.

Future Phase에만 영향을 주는 Pending UX Decision은 그 미래 Phase의 Gate로 유지하며 현재 Phase의 Definition of Ready를 불필요하게 차단하지 않는다.

현재 Blocking Decision과 미도래 Future Pending의 범위 구분은 Phase Entry뿐 아니라 Exit / Merge에도 동일하게 적용하며 현재 Phase에 필요한 UX Gate를 구현 뒤나 Phase 12로 미루는 근거가 되지 않는다.

이미 Accepted된 동작은 다시 Open으로 만들지 않고 미정인 표현과 구조만 결정하며 `DESIGN.md` 37절의 Structural / Polish 분류를 따른다.

Spacing, Visual Balance, 비구조적인 Typography / Corner Radius / Motion 조정은 Phase 12까지 가능하지만 구현 구조나 기존 Accessibility 기준에 영향을 주면 해당 UI Phase 이전 Gate에서 해결한다.

#### Accessibility in Every UI Phase

Accessibility는 Phase 12에서 처음 도입하지 않으며 `DESIGN.md` 33절의 기존 요구사항을 각 관련 UI Phase에서 구현하고 검증한다.

- 충분한 Touch Target을 확인한다.
- 주요 Control의 VoiceOver Label과 식별 가능 여부를 확인한다.
- Dynamic Type을 고려하고 해당 화면의 핵심 Flow와 Layout을 검증한다.
- Color만으로 상태를 전달하지 않는지와 충분한 Contrast를 확인한다.
- 해당 Motion이 있으면 Reduce Motion 대응을 검토·검증한다.

각 UI Phase의 Implementation Tasks, Acceptance Criteria와 Exit Criteria에 이 검증을 연결하고 적용 범위, 실행한 결과 및 미해결 사항을 보고한다.

UI 자동 검증과 수동 확인을 해당 화면에 맞게 사용하며 기존 Physical Device Gate가 필요한 영역은 실제 iPhone 12 결과 없이 완료로 처리하지 않는다.

이 규칙은 새로운 수치 Threshold나 접근성 기능을 추가하지 않으며 Phase 12는 이미 적용된 접근성의 종합 Regression / Hardening과 화면 간 일관성 검증을 담당한다.

### 3.12 Traceability Rule

각 구현 작업은 가능한 한 `FEATURES.md`의 Feature ID와 연결한다.

예를 들어 `F-MVP-015`에 대한 구현, Test, Bug Fix는 Commit 또는 Review 설명에서 해당 Feature ID를 참조할 수 있다.

기능이 어느 Phase에서 구현되는지 불명확하면 Roadmap을 먼저 수정하고 구현한다.

### 3.13 Evidence-based Completion

Phase 완료 판단은 설명이 아니라 증거를 기준으로 한다.

가능한 증거는 다음과 같다.

- Build 성공 결과
- Unit Test 결과
- Integration Test 결과
- UI Test 결과
- iPhone 12 Physical Device Test 결과
- 실제 Export File Metadata
- Screenshot 또는 Screen Recording
- Instruments Measurement
- Git Diff 및 Commit History

Codex가 실행하지 못한 검증을 실행한 것처럼 보고하지 않는다.


---

## 4. Exception and Replanning Protocol

Roadmap은 기본 실행 경로를 고정하지만 새로운 기술적 증거, 실제 Device Test 결과, Apple Framework 제약, Data Loss Risk 또는 명확한 Product 문제로 인해 기존 계획을 변경해야 할 수 있다.

이 경우 Roadmap을 억지로 유지하거나 Codex가 임의로 새로운 방향으로 분기하지 않고 다음 절차를 사용한다.

### 4.1 Replanning Trigger

다음 상황은 Replanning을 검토할 수 있는 합리적인 Trigger다.

- 현재 Architecture로 핵심 Requirement를 안정적으로 구현할 수 없다는 증거가 확인된 경우
- iPhone 12에서 반복적인 Crash, Memory Pressure, 과도한 Thermal Issue 또는 심각한 성능 문제가 발생한 경우
- Preview와 Export Parity를 현재 설계로 유지하기 어렵다는 사실이 확인된 경우
- Media Loss 또는 Draft Corruption Risk가 발견된 경우
- Apple Framework의 실제 제약으로 Confirmed Decision을 그대로 구현할 수 없는 경우
- TestFlight 또는 실제 Device 환경에서 Simulator와 다른 핵심 문제가 확인된 경우
- 사용자가 Product 또는 UX 방향 변경을 명시적으로 승인한 경우

단순히 다른 구현 방식이 더 흥미롭거나 새로운 Library가 편해 보인다는 이유만으로 Replanning하지 않는다.

### 4.2 Stop and Stabilize

분기가 필요하다고 판단되면 현재 작업을 즉시 다음 안전한 상태로 만든다.

1. 현재 변경사항을 확인한다.
2. 실행 가능한 범위에서 Build와 Test를 수행한다.
3. 작업 중인 미완성 코드와 정상 코드의 상태를 구분한다.
4. 필요하면 현재 상태를 WIP 또는 Checkpoint Commit으로 남긴다.
5. `main`에는 검증되지 않은 변경을 Merge하지 않는다.

### 4.3 Replanning Report

Codex는 방향 변경 전에 다음 내용을 보고한다.

- 현재 Phase
- 문제가 발견된 정확한 지점
- 기존 Decision 또는 Architecture
- 발견된 증거
- 사용자에게 미치는 영향
- 기술적 영향
- 가능한 선택지
- 각 선택지의 장점
- 각 선택지의 단점
- 예상 변경 범위
- Roadmap에 미치는 영향
- 추천안

사용자 승인 전에는 기존 Decision을 변경하지 않는다.

### 4.4 Change Classification

변경은 영향 범위에 따라 다음 수준으로 분류한다.

#### Level 1 — Implementation Adjustment

제품, 기능, UX, Architecture 계약을 변경하지 않는 내부 구현 조정이다.

예:

- 동일한 Protocol 아래 내부 Class 분리
- Performance 개선
- Bug Fix
- Test Helper 변경

Level 1은 새로운 ADR 없이 현재 Phase에서 처리할 수 있다.

#### Level 2 — Architecture Adjustment

제품 기능은 유지하지만 `ARCHITECTURE.md`의 구현 기준 또는 Technical Decision이 변경되는 경우다.

예:

- Recording Pipeline 교체
- Persistence Strategy 변경
- Export Engine 변경

Level 2는 사용자 승인과 `ARCHITECTURE.md` 업데이트가 필요하며 중요 변경은 새로운 ADR로 기록한다.

#### Level 3 — Product or UX Change

`PRODUCT.md`, `FEATURES.md`, `DESIGN.md`의 확정 요구사항을 변경하는 경우다.

예:

- Clip 최대 길이 변경
- 9:16 / 16:9 정책 변경
- MVP 기능 추가 또는 제거
- Export Workflow 변경

Level 3은 사용자 승인 후 관련 Source of Truth 문서와 `DECISIONS.md`, `ROADMAP.md`를 함께 업데이트한다.

### 4.5 Experiment and Spike Branch

기술적으로 어느 선택이 맞는지 문서만으로 판단할 수 없는 경우 짧은 Experiment 또는 Spike를 수행할 수 있다.

권장 Branch Naming은 다음과 같다.

- `spike/<topic>`
- `experiment/<topic>`

Spike는 다음 규칙을 따른다.

- 질문 하나를 검증하는 데 집중한다.
- Product Feature를 완성하려고 하지 않는다.
- 가능한 한 작은 코드로 검증한다.
- Test 결과와 측정값을 남긴다.
- 성공했다고 자동으로 Production Code에 채택하지 않는다.
- 실험 결과를 사용자에게 보고한 후 Decision을 확정한다.
- 실험 Branch의 코드를 그대로 `main`에 Merge하는 것을 기본으로 하지 않는다.
- 채택된 아이디어는 정식 Phase Branch에서 Architecture 기준에 맞게 구현한다.

### 4.6 ADR Superseding Rule

기존 Accepted Decision이 변경되면 과거 기록을 삭제하지 않는다.

새로운 ADR을 추가하고 이전 ADR의 Status를 `Superseded`로 변경한다.

새 ADR은 최소한 다음을 기록한다.

- 어떤 ADR을 대체하는가
- 왜 변경했는가
- 어떤 증거가 있었는가
- 어떤 Trade-off를 수용했는가
- 어떤 문서와 Phase가 영향을 받는가

### 4.7 Documentation Update Order

Level 2 또는 Level 3 변경이 승인되면 다음 순서로 문서를 갱신한다.

1. `PRODUCT.md` — 제품 목적이 변경된 경우
2. `FEATURES.md` — 기능 Scope가 변경된 경우
3. `DESIGN.md` — UX가 변경된 경우
4. `ARCHITECTURE.md` — 기술 구조가 변경된 경우
5. `DECISIONS.md` — ADR 추가 또는 상태 변경
6. `ROADMAP.md` — Phase 또는 Gate 재계획

문서를 갱신한 뒤 새로운 Baseline Commit을 생성하고 구현을 재개한다.

### 4.8 Roadmap Re-entry

Replanning이 끝나면 현재 Roadmap에서 다시 시작할 지점을 명시한다.

가능한 결과는 다음과 같다.

- 현재 Phase 계속 진행
- 현재 Phase 일부 재작업
- 이전 Phase로 돌아가 수정
- 새로운 Intermediate Phase 삽입
- 이후 Phase 순서 변경

Phase 번호 변경이 필요한 경우 기존 History를 이해할 수 있도록 이유를 기록한다.

### 4.9 Emergency Fix Exception

Data Loss, Repeated Crash, Security 또는 Build Blocker처럼 즉시 수정이 필요한 문제는 현재 Phase 밖이라도 Emergency Fix를 허용할 수 있다.

Emergency Fix는 최소 범위로 수행하고 이후 관련 문서와 Test를 보완한다.

새로운 Feature를 Emergency Fix로 위장하여 Scope에 추가하지 않는다.

---

## 5. Git Strategy

### Main Branch

`main`은 항상 Build 가능한 기준 Branch로 유지한다.

### Feature Branch

각 Phase는 별도의 Branch에서 작업하는 것을 기본으로 한다.

권장 Branch Naming은 다음과 같다.

- `phase/00-bootstrap`
- `phase/01-domain-persistence`
- `phase/02-home-vlog-creation`
- `phase/03-camera-foundation`
- `phase/04-video-recording`
- `phase/05-clip-management`
- `phase/06-video-import`
- `phase/07-trim-framing`
- `phase/08-vlog-preview`
- `phase/09-export-share`
- `phase/10-draft-storage-recovery`
- `phase/11-permissions-errors`
- `phase/12-ui-polish-accessibility`
- `phase/13-performance-hardening`
- `phase/14-mvp-qa`
- `phase/15-testflight-readiness`

### Merge Rule

각 Phase의 Exit Criteria를 충족한 후 Review를 거쳐 `main`에 Merge한다.

현재 Phase의 Acceptance Criteria와 필수 Test / Device Evidence를 충족하고 진입·종료 및 현재 Change Set에 필요한 Decision Gate를 해결해야 하며 `RULES.md` 3절의 Unresolved Blocking Decision이나 현재 변경 관련 Source of Truth 모순이 남아 있으면 완료·Merge할 수 없다.

현재 범위에 영향을 주지 않는 Future Phase-only Pending은 Source of Truth에 기록하고 Owning Phase / Gate와 연결한 상태로 유지할 수 있으며 그 존재만으로 현재 Merge를 차단하지 않는다.

예를 들어 Phase 2의 구현·안전성·Acceptance에 영향을 주지 않는 Phase 9 Export Codec Pending은 Phase 2 Merge를 막지 않지만 Phase 6 Working Media Codec이나 Phase 7 Trim / Framing Structural UX가 해당 Required Gate에서 미해결이면 각 Phase의 구현을 시작할 수 없다.

이 범위 구분은 기존 Gate 시점, 사용자 승인, Scope 및 `RULES.md` 28절의 나머지 Merge 검증 요건을 변경하지 않는다.

### Commit Rule

작업 Commit Message는 목적이 명확해야 한다.

예시는 다음과 같다.

- `feat: add vlog project domain models`
- `feat: implement camera preview`
- `feat: enforce ten second recording limit`
- `test: cover clip duration policy`
- `fix: preserve recording after interruption`
- `docs: record import media decision`

---

## 6. Phase Status Model

각 Phase는 다음 상태 중 하나로 관리한다.

- `Not Started`
- `Ready`
- `In Progress`
- `Blocked`
- `Needs Decision`
- `Needs Device Test`
- `In Review`
- `Completed`

Codex는 Exit Criteria가 충족되지 않았는데 `Completed` 상태로 보고하지 않는다.

`Blocked` 또는 `Needs Decision` 상태에서는 다음 Phase로 넘어가지 않는다.

Decision으로 인한 현재 Phase의 `Needs Decision` / `Blocked` 판단은 현재 Blocking 범위를 기준으로 하며 미도래 Future Phase-only Pending의 존재만으로 현재 Phase를 이 상태로 처리하지 않는다.

---

## 7. Phase Review Checklist

각 Phase 종료 시 다음 Checklist를 사용한다.

### Scope

- 계획된 기능만 구현했는가?
- Explicitly Excluded 기능을 추가하지 않았는가?
- 새로운 Product Decision을 임의로 만들지 않았는가?

### Architecture

- Architecture Invariant를 유지했는가?
- 새로운 Dependency가 추가되었다면 승인되었는가?
- Media Safety와 Original Preservation이 유지되는가?

### Quality

- Build가 성공하는가?
- Unit Tests가 통과하는가?
- Integration Tests가 통과하는가?
- UI Tests가 필요한 경우 통과하는가?
- Compiler Warning이 없는가?
- `git diff --check`가 통과하는가?

### Device

- Physical Device Test가 필요한가?
- 필요한 경우 iPhone 12에서 검증했는가?
- Simulator 결과만으로 완료 처리하지 않았는가?

### Documentation

- 관련 문서와 코드가 일치하는가?
- 새로운 Decision이 있다면 ADR이 기록되었는가?
- 현재 Phase 진입·종료 및 현재 변경에 필요한 Decision Gate가 해결되고 Blocking Decision과 관련 Source of Truth 모순이 없는가?
- Future Pending이 Source of Truth에 기록되고 Owning Phase / Required Gate와 연결되어 있는가?

다음 Phase의 Gate 확인은 필요한 Decision과 해결 시점을 식별하는 것이며 현재 범위와 무관한 Future Decision을 현재 Merge 전에 모두 확정하라는 의미가 아니다.

다음 Phase 진입 시에는 해당 Required Gate가 실제로 해결되어 있어야 한다.

---

## 8. Issue and Bug Handling

구현 중 발견된 Issue는 다음 중 하나로 분류한다.

### Current Phase Bug

현재 Phase의 Acceptance Criteria 또는 기존 완료 기능을 깨뜨리는 문제다.

현재 Phase에서 해결한다.

### Regression

이전 Phase에서 정상 동작하던 기능이 깨진 문제다.

새로운 Feature보다 우선하여 수정한다.

### Future Enhancement

MVP Requirement가 아니며 있으면 좋은 개선 사항이다.

현재 Phase에 넣지 않고 Post-MVP Backlog로 이동한다.

### Architecture Risk

향후 Data Loss, Crash, Export Mismatch, Storage 문제로 이어질 수 있는 구조적 위험이다.

필요하면 Replanning Protocol을 사용한다.

Issue를 분류하지 않은 채 구현 Scope를 확대하지 않는다.

---

## 9. Rollback and Recovery Policy

Phase 구현이 실패하거나 변경이 잘못된 방향으로 진행된 경우 Git History를 파괴하지 않는다.

다음 원칙을 사용한다.

- `main`에 대한 Force Push를 사용하지 않는다.
- 이미 공유된 Commit History를 임의로 Rewrite하지 않는다.
- 실패한 Feature Branch는 보존하거나 폐기할 수 있다.
- 필요하면 마지막 검증된 Baseline에서 새로운 Branch를 만든다.
- Revert가 필요한 경우 이유가 명확한 Revert Commit을 사용한다.
- 사용자 Media 또는 Test Fixture를 Git Reset으로 복구 가능한 데이터처럼 취급하지 않는다.

---

## 10. Feature-to-Phase Traceability

MVP Feature 구현은 대략 다음 Phase에 연결한다.

| Feature Area | Primary Phase |
| --- | --- |
| Vlog Project / Orientation | Phase 1–2 |
| Multiple Drafts / Autosave | Phase 1–2, Phase 10 |
| Camera Preview / Switching | Phase 3 |
| 10-second Recording / Audio | Phase 4 |
| Clip List / Reorder / Delete / Undo | Phase 5 |
| Photos Video Import | Phase 6 |
| Imported Video 10-second Selection | Phase 6–7 |
| Trim | Phase 7 |
| Fill + Crop / Framing | Phase 7 |
| Full Vlog Preview | Phase 8 |
| Export / Save / Share | Phase 9 |
| Draft Recovery / Storage Safety | Phase 10 |
| Permissions / Error Handling | Phase 11 |
| Accessibility / Haptics / Visual Polish | Phase 12 (Recording Haptics 구현: Phase 4, 승인된 정책의 Polish: Phase 12) |
| iPhone 12 Performance Validation | Phase 13 |
| End-to-End MVP Verification | Phase 14 |
| TestFlight | Phase 15 |

세부 Feature ID의 정확한 연결이 필요한 경우 구현 시작 전에 현재 `FEATURES.md`를 기준으로 Phase 작업 계획에 명시한다.

---

# Phase 0 — Project Bootstrap

## Goal

빈 Repository를 실제 iOS 개발이 가능한 최소 Xcode Project로 전환한다.

이 Phase에서는 사용자 기능을 구현하지 않는다.

## Included

- Xcode Project 생성
- SwiftUI App Target 생성
- Unit Test Target 생성
- UI Test Target 생성
- iOS 18.0 Deployment Target 적용
- iPhone 전용 Target 정책 적용
- 기본 Folder Structure 생성
- App Environment Skeleton 생성
- Design System Skeleton 생성
- Logging Skeleton 생성
- Git ignore 확인

## Explicitly Excluded

- 실제 Home UI
- Camera
- Video Recording
- SwiftData Model
- Video Import
- Preview
- Export
- Third-party Dependencies

## Implementation Tasks

1. Xcode에서 Mellow App Project를 생성한다.
2. Bundle Identifier는 실제 App Store 준비 전 변경 가능한 값으로 사용하되 임의의 Company 정보는 만들지 않는다.
3. Minimum Deployment Target을 iOS 18.0으로 설정한다.
4. Supported Device Family를 iPhone 중심으로 구성한다.
5. `MellowApp`, `MellowTests`, `MellowUITests` Target을 확인한다.
6. `ARCHITECTURE.md`의 Initial Project Structure를 기준으로 Folder Structure를 생성한다.
7. `MellowApp.swift`는 App Entry Point만 담당하도록 유지한다.
8. `AppEnvironment`의 빈 Dependency Container Skeleton을 생성한다.
9. `AppRouter`는 필요한 최소 구조만 생성하고 실제 Navigation은 구현하지 않는다.
10. `DesignSystem` Folder와 기본 Placeholder File을 생성한다.
11. OSLog Category를 위한 Logging Skeleton을 생성한다.
12. 프로젝트가 Clean Build 되는지 확인한다.

## Tests

- 기본 Unit Test Target 실행
- 기본 UI Test Target 실행
- App Launch Test 확인

## Physical Device Test

- iPhone 12에서 App 설치
- iPhone 12에서 App Launch
- 빈 기본 화면이 정상적으로 표시되는지 확인

## Acceptance Criteria

- Xcode Project가 iOS 18.0 기준으로 Build 된다.
- iPhone Simulator에서 App이 Launch 된다.
- iPhone 12에 설치 및 Launch 된다.
- Third-party Dependency가 없다.
- Folder Structure가 Architecture 문서와 일치한다.
- Compiler Warning이 없다.

## Exit Criteria

모든 Acceptance Criteria를 만족하고 `main`에 Merge 가능한 상태여야 한다.

---

# Phase 1 — Domain and Persistence Foundation

## Goal

실제 UI와 Media 기능을 만들기 전에 Mellow의 Project 및 Clip Domain과 Draft Metadata Persistence 기반을 구현한다.

## Included

- `VlogProject`
- `VlogClip`
- `ProjectOrientation`
- `ClipSourceKind`
- `ClipPolicy.maximumDuration`
- Clip Duration Invariant
- SwiftData Persistent Model
- Repository Boundary
- In-memory Test Repository
- Project 자동 이름 생성
- Project Duration 계산
- Clip Order Model

## Explicitly Excluded

- 실제 Video File 저장
- Camera
- Import
- Thumbnail
- Trim UI
- Home UI
- Preview
- Export

## Implementation Tasks

1. Domain Model과 SwiftData Model의 책임을 정의한다.
2. `ProjectOrientation`에 `portrait9x16`, `landscape16x9`를 구현한다.
3. `ClipPolicy.maximumDuration = 10 seconds`를 단일 기준으로 정의한다.
4. 유효하지 않은 Clip Duration을 Domain Layer에서 거부한다.
5. Project Duration을 Clip Effective Duration의 합으로 계산한다.
6. Project Display Name을 `createdAt`과 Locale 기반 Formatter로 생성한다.
7. `ProjectRepository` Protocol을 정의한다.
8. SwiftData 기반 Repository Implementation을 작성한다.
9. Test용 In-memory Repository를 작성한다.
10. Relative Media Path를 저장할 수 있는 구조를 준비한다.
11. Clip 순서 변경 로직을 Domain 또는 Repository Layer에 구현한다.

## Unit Tests

- 10초 Clip 허용
- 10초 초과 Clip 거부
- 0 이하 Duration 거부
- Portrait Orientation 생성
- Landscape Orientation 생성
- Project Duration 합산
- Clip Reorder
- 자동 Project Display Name
- Repository Project Create / Read / Update / Delete
- 여러 Project 저장 및 조회

## Acceptance Criteria

- SwiftData에 Project Metadata를 저장할 수 있다.
- App을 재실행해도 Project Metadata가 복구된다.
- Clip Duration Rule이 UI 없이도 강제된다.
- Project Duration 계산이 정확하다.
- Unit Tests가 모두 통과한다.

## Exit Criteria

Domain과 Persistence Layer가 UI 없이 독립적으로 테스트 가능해야 한다.

---

# Phase 2 — Home, Recent, and Vlog Creation

## Goal

사용자가 App을 실행하고 새 Vlog를 만들거나 기존 Vlog를 다시 열 수 있는 첫 번째 실제 사용자 Flow를 완성한다.

## Included

- Home
- Recent
- Empty State
- New Vlog
- 9:16 / 16:9 선택
- Project 생성
- 자동 Project 이름
- Recent 정렬
- 기본 Placeholder Thumbnail
- Project 삭제 Confirmation

## Explicitly Excluded

- 실제 Camera Preview
- 실제 Recording
- Video Import
- Clip Editor
- Preview
- Export

## Decision Gate Before Implementation

Home / Recent를 구현하기 전에 다음 Structural UX Pending을 사용자 승인으로 해결한다.

- Recent의 List / Grid 또는 이에 준하는 Primary Layout 구조
- 구현 구조에 영향을 주는 Recent Item의 핵심 정보 Hierarchy
- New Vlog Entry의 Primary Placement
- Orientation Selection의 Control 배치와 기존 Project Delete Confirmation의 Presentation 구조
- 0 Clip Project를 정상 Draft로 전달하는 Empty Project State의 Presentation 구조

New Vlog의 Primary Action 역할, 이름 입력 없음, 9:16 / 16:9 선택과 자동 이름은 확정된 기준을 유지하며 여기서 List / Grid나 구체적인 배치를 선택하지 않는다.

ADR-026의 Empty Project Behavior는 이 Gate에서 구현하며 0 Clip Project를 정상 Draft로 표시하고 다시 열 수 있게 한다.

Exact Empty Project Visual과 Project-level Corruption의 Exact Failure Presentation은 별도 UX Gate로 유지하며 M06의 Thumbnail 책임은 이 Gate에서 해결하지 않는다.

## Implementation Tasks

1. Home 화면을 구현한다.
2. `New Vlog`를 Primary Action으로 배치한다.
3. Recent 영역을 구현한다.
4. Recent는 `updatedAt` 기준 최신순으로 정렬한다.
5. Clip이 없는 Project에는 Placeholder를 표시한다.
6. New Vlog 선택 시 Orientation Selection 화면으로 이동한다.
7. 9:16 선택 시 Portrait Project를 생성한다.
8. 16:9 선택 시 Landscape Project를 생성한다.
9. Project Name 입력은 요구하지 않는다.
10. Project 생성 후 Camera Placeholder 화면으로 진입한다.
11. 기존 Recent Project를 다시 열 수 있게 한다.
12. Project 삭제 시 Confirmation을 표시한다.
13. Project 삭제 후 Home 상태를 갱신한다.
14. 0 Clip Project를 Recent에서 Valid Draft로 표시하고 다시 열며 자동 삭제하지 않는다.
15. 0 Clip Project가 Project Orientation을 유지한 채 이후 Recording과 Photos Import 기능의 유효한 Target으로 남도록 Domain과 Persistence 경계를 유지한다.
16. Home / Recent, New Vlog / Orientation Selection과 기존 Project Delete Confirmation에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.

## Unit Tests

- Recent Sorting
- New Portrait Project
- New Landscape Project
- 자동 Project Name
- Project Delete
- 0 Clip Project Create / Read / Reopen

## UI Tests

- Empty Home → New Vlog → 9:16
- Empty Home → New Vlog → 16:9
- Recent Project 재진입
- 0 Clip Recent Project 재진입
- Project 삭제 Confirmation

## Physical Device Test

- iPhone 12에서 Portrait Home 사용성 확인
- Orientation Selection UI 확인
- Dynamic Type 기본 범위 확인

## UI Accessibility Verification

Home / Recent, New Vlog / Orientation Selection과 기존 Project Delete Confirmation에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- 사용자가 새 Vlog를 이름 입력 없이 만들 수 있다.
- 9:16과 16:9 Project가 올바르게 생성된다.
- 여러 Draft가 Recent에 표시된다.
- App 재실행 후 Recent가 유지된다.
- Project 삭제가 정상 동작한다.
- 0 Clip Project가 Recent에 표시되고 다시 열리며 자동으로 삭제되지 않는다.
- 0 Clip Project의 Project Orientation이 유지되고 이후 Recording과 Photos Import 기능의 유효한 Target으로 남는다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

Camera 없이도 Project Lifecycle의 기본 흐름이 완성되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 3 — Camera Foundation

## Goal

실제 촬영을 시작하기 전 안정적인 Camera Session과 Preview 기반을 구현한다.

## Included

- Camera Permission
- Microphone Permission 상태 기반
- Rear Camera Preview
- Front Camera Preview
- Rear 1× Wide Camera
- Rear Preview Continuous Zoom
- Front / Rear Switching
- Camera Session Lifecycle
- Camera / Microphone Recording Readiness
- Device Orientation Detection
- Orientation Mismatch State
- Front Preview Mirroring
- SwiftUI Preview Bridge

## Explicitly Excluded

- 실제 Video Recording
- 10초 Timer
- Audio Recording File
- Clip 저장
- Import
- Front Camera Zoom
- 0.5× Ultra Wide / Telephoto / Lens Selector
- Tap to Focus
- Exposure Control
- Torch
- Dual Camera

## Decision Gate Before Implementation

ADR-023의 Camera Capture, Rear Zoom, Permission, Front Mirroring과 Orientation High-level Behavior가 Accepted 상태여야 한다.

Camera 화면의 구현 구조에 필요한 다음 UX Pending을 Phase 3 시작 전에 사용자 승인으로 해결한다.

- Camera Control Placement / Hierarchy와 Overlay의 구조
- Front / Rear Switch와 기존 Record / Import / Clips 진입 Control의 배치
- Portrait / Landscape에서의 의도적인 Camera Layout
- Orientation mismatch 안내의 Presentation 구조와 위치
- Rear Zoom의 최종 Interaction / Visual Presentation이며 Pinch-to-zoom을 Primary Candidate로 평가하고 필요한 경우 Zoom Factor Indicator 여부를 결정한다.
- Camera / Microphone Permission 안내의 Presentation 구조와 Import가 계속 가능함을 보여주는 방식

Rear Zoom의 Maximum Product Quality Limit은 iPhone 12 Preview 화질과 사용성을 검증하여 Phase 3에서 사용자 승인을 받아야 하며 Device의 이론적 Maximum Zoom Factor를 Product Maximum으로 자동 채택하지 않는다.

Primary Record Action, Front / Rear 지원, Rear 1× Wide와 1× 이상 Continuous Zoom, Project Orientation 고정, Permission 동작, Front Mirroring과 조용한 mismatch 안내는 재결정하지 않는다.

이 Gate는 0.5× Ultra Wide / Telephoto / Lens Selector 또는 Front Zoom을 MVP 후보로 다시 열지 않는다.

이 Gate는 Camera Shell과 현재 Phase의 Control 구조만 정하며 이후 Recording / Import 기능을 미리 구현하지 않는다.

Recording 표현이 Camera Layout 구조에 이미 영향을 주는 부분은 Phase 3 전에 결정하고 Phase 4 전용 표현만 다음 Phase의 Gate로 남긴다.

## Implementation Tasks

1. `CameraCaptureService` Protocol과 Production Implementation을 작성한다.
2. Camera Session을 Main Thread 밖의 안전한 Serial Context에서 구성한다.
3. Rear Camera Input을 구성한다.
4. Front Camera Input을 구성한다.
5. Microphone Input은 다음 Phase Recording 준비가 가능하도록 구성한다.
6. Camera Preview Layer를 SwiftUI에 Bridge한다.
7. View 재생성으로 Session이 반복 생성되지 않게 한다.
8. Camera Permission State를 처리한다.
9. Front / Rear Camera Switching을 구현한다.
10. Recording 상태가 아니어야 Switch 가능하도록 API 구조를 제한한다.
11. Device Orientation을 감지한다.
12. Project Orientation과 Device Orientation mismatch 상태를 Feature Layer에 제공한다.
13. App Background 진입 시 Session을 안전하게 정지한다.
14. Foreground 복귀 시 필요한 조건에서 Session을 재개한다.
15. 현재 Phase의 Camera Controls, Front / Rear Switch와 Orientation 안내에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.
16. Rear Camera는 기본 1× Wide Device를 선택하고 Preview에서 1× 이상 Continuous Zoom을 제공하며 승인된 Maximum Product Quality Limit으로 Clamp한다.
17. Front Camera에 Zoom Capability나 UI를 노출하지 않고 Front Preview를 Mirrored Appearance로 표시한다.
18. Camera / Microphone Authorization과 Required Capture Device / Session Configuration 상태를 Direct Recording Readiness에 반영하며 Denied / Restricted 상태가 Photos Import를 차단하지 않게 한다.
19. Project Orientation, Device Physical Orientation, UI Orientation과 Video Presentation Orientation Signal을 분리한다.
20. Portrait Project의 Portrait Posture와 Landscape Project의 Landscape Left / Right를 유효 상태로 판단하고 Mismatch / Face Up / Face Down / Unknown / Unstable 상태를 Recording Start에 유효하지 않은 상태로 제공한다.
21. Camera Capability가 기대와 다르거나 unavailable이면 Low-level Error를 직접 노출하지 않는 Typed Failure로 전달한다.

## Unit Tests

- Camera Position State
- Orientation Mismatch Policy
- Permission State Mapping
- Camera Switch State Rule
- Rear Zoom 1× Minimum / 승인된 Maximum Clamp Policy
- Camera / Microphone Recording Readiness와 Photos Import 독립성
- Portrait / Landscape Left / Landscape Right Eligibility 및 Face Up / Down / Unknown / Unstable 거부
- Project / Device / Presentation Orientation State 분리

## UI Tests

실제 Camera 대신 Mock Camera Service를 사용한다.

- Permission Granted State
- Permission Denied State
- Rear / Front Switching UI
- Orientation Mismatch UI
- Rear Zoom 승인 Interaction과 Zoom 상태 Visual Feedback
- Camera / Microphone Denied 상태에서 Recording 제한과 Import 접근 가능 상태

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- Rear Preview
- Front Preview
- Rear 1× Wide Device Selection
- Rear Preview에서 1×부터 승인된 Maximum까지 Continuous Zoom과 Clamp
- Front Preview Mirrored Appearance와 Front Zoom UI 없음
- Front / Rear Switching
- Portrait Project에서 Orientation 안내
- Landscape Project에서 Orientation 안내
- Landscape Left / Right Recording Eligibility와 올바른 Preview Orientation
- Face Up / Face Down / Unknown / Unstable 상태의 Recording Start 차단
- Camera Permission Denied / Restricted와 Microphone Permission Denied / Restricted에서 Recording 차단 및 Photos Import 접근 가능
- Background / Foreground Session 복구

## UI Accessibility Verification

현재 Phase의 Camera Controls, Front / Rear Switch와 Orientation 안내에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- Camera Preview가 안정적으로 표시된다.
- Front와 Rear Camera를 Recording이 없는 상태에서 전환할 수 있다.
- Rear Camera는 기본 1× Wide를 사용하고 Preview에서 1× 이상 Continuous Zoom이 승인된 Maximum Quality Limit 안에서 동작한다.
- 0.5× Ultra Wide / Telephoto / Lens Selector와 Front Camera Zoom이 MVP Camera UI에 노출되지 않는다.
- Front Preview는 Mirrored Appearance를 사용한다.
- Camera 또는 Microphone Permission이 없으면 Direct Recording Ready가 되지 않지만 Photos Import는 사용할 수 있다.
- Orientation Mismatch / Face Up / Down / Unknown / Unstable 상태는 Recording Start 불가 상태로 전달되고 Landscape Left / Right는 모두 Landscape Project에 유효하다.
- Session Start / Stop으로 UI가 Freeze되지 않는다.
- Project Orientation이 Device Rotation으로 변경되지 않는다.
- iPhone 12에서 Preview가 안정적이다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

Recording 없이 Camera Infrastructure가 안정적으로 검증되어야 한다.

ADR-023의 Rear 1× Wide, Preview Zoom Range, Front Preview Mirroring, Permission Readiness와 Orientation Eligibility가 iPhone 12에서 검증되고 Rear Maximum Product Quality Limit 및 Structural UX Gate가 승인되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 4 — Video Recording

## Goal

Mellow의 핵심인 최대 10초 자유 Recording Flow를 실제 iPhone에서 완성한다.

최초 Production Media를 생성하는 Phase이므로 공통 Media Commit Lifecycle의 최소 구현과 기본 Crash / Relaunch Recovery를 이 Phase에 포함한다.

이 안전성 구현을 Phase 10까지 미루지 않는다.

## Included

- 1080p 30 fps Recording
- Audio Recording
- Manual Stop
- 10초 Auto Stop
- Recording Progress
- Clip File Staging
- Safe Media Write
- Durable Operation Identity
- 기본 Media Commit Recovery와 Recovery Classification
- Project Clip 추가
- Front Camera Recording
- Rear Camera Recording
- Rear Active Recording Continuous Zoom
- Recording Start Orientation Match Gate
- Front Preview / Recorded Result Mirroring Parity
- Camera / Microphone Recording Readiness
- Recording Haptic 기본 구현
- Interruption 기본 대응

## Explicitly Excluded

- Front Camera Zoom
- 0.5× Ultra Wide / Telephoto / Lens Selector
- Focus Control
- Exposure Control
- Torch
- Camera Switch during Recording
- Filters
- 4K Recording
- 60 fps Recording

## Architecture Contract Before Implementation

`ARCHITECTURE.md` 25절과 59절 및 Accepted ADR-020의 저장 완료, Validation, Failure Boundary, Recovery와 Cleanup 계약은 Phase 4 진입 전에 확정되어 있어야 한다.

구현 시점에는 Process Death 이후 Operation / Project / Clip / Media의 연결을 복구할 수 있는 가장 단순한 Durable Representation을 사용하며 특정 Manifest Format이나 Database Uniqueness 구현을 미리 고정하지 않는다.

ADR-021의 Project Invalid Target과 Late Commit 차단 계약도 Recording Finalization부터 적용하며 기존 Project Delete 경로와 연결한다.

ADR-023의 Rear 1× Wide / Continuous Zoom, Front Mirroring, Camera / Microphone Permission, Orientation Match와 Mid-record Rotation 계약도 Phase 4 Recording Flow에 적용한다.

ADR-024의 Operation-aware Storage Preflight, Operation-scoped Shortage, No Silent Quality Downgrade와 Runtime Disk Full Safety 계약도 최초 Media Writing 전에 적용한다.

## Decision Gate Before Implementation

### Recording Storage Technical Gate

실제 Recording Media Writing을 구현하기 전에 다음 항목을 사용자 승인으로 확정한다.

- 최대 10초 Recording의 Estimated Peak Additional Storage 계산 방법
- Recording에 필요한 Safety Reserve 정책
- 승인된 1080p / 30 fps Capture Profile과 Storage Estimate의 관계

정확한 Capture Codec / Bitrate, Estimate Formula의 상수와 Safety Reserve bytes는 이 Gate에서 실제 Pipeline Profile을 기준으로 결정하며 이번 Baseline에서 값을 임의로 고정하지 않는다.

이 Gate는 ADR-024의 `Required Free Space = Estimated Peak Additional Storage + Safety Reserve` 계약을 구체화해야 하며 해결되기 전에는 실제 Recording Media Writing 구현을 시작하지 않는다.

### Structural UX Gate

Recording UI를 구현하기 전에 다음 Structural UX Pending을 사용자 승인으로 해결한다.

- 확정된 Circular Progress Ring의 Layout-level 표현과 Record Control 주변 배치
- 현재 녹화 시간 표시의 구체적인 Presentation 구조
- Clip 저장 완료 Feedback의 비 Haptic Presentation 구조
- Recording Storage 부족으로 해당 작업을 시작할 수 없고 기존 Media는 유지되며 공간 확보 후 재시도할 수 있다는 상태의 Presentation 구조

Phase 3에서 승인한 Camera Layout을 재사용하며 최대 10초 자유 Recording, Manual Stop / Auto Stop과 Circular Progress Ring 방향은 다시 Open으로 만들지 않는다.

Recording Haptic은 H04 사용자 승인에 따라 Start에는 제공하지 않고 Successful Manual Stop과 Successful 10-second Auto-stop 완료 시 동일한 종료 의미의 subtle completion haptic을 제공하며 이 UX Gate에서 사용 여부를 다시 결정하지 않는다.

Recording Error / Interruption의 Haptic은 별도 Pending으로 유지하며 정상 Recording의 승인 정책을 다시 Open으로 만들지 않는다.

## Implementation Tasks

1. `AVCaptureMovieFileOutput` 기반 Recording을 구현한다.
2. 기본 Capture Profile을 1080p 30 fps로 설정한다.
3. Recording Start와 Stop API를 구성한다.
4. 사용자가 10초 이전 언제든 Stop할 수 있게 한다.
5. Capture Pipeline 자체에서 10초 Maximum Duration을 강제한다.
6. UI Progress Ring을 구현한다.
7. Progress 계산은 Monotonic Time을 사용한다.
8. 10초 Auto Stop 이후 정상 Completion Flow로 들어간다.
9. Audio Track이 포함되도록 구성한다.
10. Media 작성 전에 Durable Operation Identity와 Project / Clip / Media 연결을 확보하고 Recording 결과를 Staging에 생성하며 Incomplete Write와 Completed Staging을 구별한다.
11. Staged Media를 검증하고 필요한 Normalization이 있다면 그 Output도 Final Working Media로 등록하기 전에 다시 검증한다.
12. 검증된 Final Working Media를 Project Media Directory로 안전하게 Materialize하며 가능한 경우 동일 Filesystem 내 Atomic Move / Rename을 사용한다.
13. Project가 여전히 유효한지 확인하며 해당 Media를 참조하는 Clip Metadata를 Persist하고 실패 시 Recoverable Media와 Operation 정보를 보존한다.
14. Final Media 존재, Final Validation 성공, Metadata Persistence 성공과 유효한 Project를 모두 만족한 Committed Clip만 UI에 표시한다.
15. Recording Start에 Haptic이 발생하지 않도록 하며 Record Button Tap 또는 Recording Start 성공을 Haptic 발생 조건으로 사용하지 않는다.
16. Successful Manual Stop과 Successful 10-second Auto-stop 완료 시 "이 Clip의 Recording이 종료되었다."라는 동일한 의미의 subtle completion haptic을 제공하고 기존 Visual Recording State / Circular Progress / Completion State를 유지한다.
17. Recording 중 App Background 또는 Session Interruption을 처리한다.
18. 가능한 경우 유효한 Partial Recording을 보호한다.
19. Completed Staging과 Materialized Media에서 중단된 Operation을 재실행 후 연결하여 가능한 후속 처리와 Metadata Commit을 재개한다.
20. 이미 Persist된 Clip은 기존 Metadata를 사용하고 Operation / Clip Identity로 Duplicate Commit을 방지한다.
21. Temporary / Intermediate Artifact는 Commit 또는 Recovery Classification 이후 폐기 가능하다고 확인된 경우에 정리하며 Cleanup 실패가 Committed Clip을 무효화하지 않게 한다.
22. Project Delete가 확정되면 영속적인 Logical Invalid Target을 먼저 확립하고 Finalization Commit 직전의 Project Validity 검증과 결과 적용 사이에 삭제 Race가 발생하지 않게 한다.
23. 삭제된 Project의 Late Recording Result는 Commit하거나 Project를 재생성하지 않으며 Operation-owned Media는 ADR-020 Classification과 ADR-021 Deletion Safety 이후에 정리한다.
24. Recording Control, 현재 시간 / Progress 표현과 저장 완료 Feedback에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.
25. Rear Camera의 승인된 Zoom Range 안에서 Active Recording 중 Continuous Zoom을 지원하고 Zoom 변경이 현재 Recording을 Stop / Restart하거나 새 Clip을 만들거나 10초 Timer와 Durable Media Operation Identity를 Reset하지 않게 한다.
26. Front Recording에는 Zoom UI나 Behavior를 제공하지 않는다.
27. Record Request에서 Camera / Microphone Authorization, Required Capture Device와 Session Configuration, Project Validity 및 Orientation Eligibility를 Media Writing과 Progress / 10초 Timer 시작 전에 검증한다.
28. Camera 또는 Microphone Permission이 Denied / Restricted이면 Direct Recording을 시작하거나 무음 Video로 대체하지 않으며 Photos Import 경로는 Audio Track이 없는 Source를 포함하여 계속 사용할 수 있게 한다.
29. Portrait Project는 Portrait Posture, Landscape Project는 Landscape Left / Right에서 Recording을 시작하고 Mismatch / Face Up / Face Down / Unknown / Unstable 상태에서는 조용한 Rotate Device Guidance와 함께 시작을 차단한다.
30. Mid-record Rotation만으로 현재 Recording을 Stop / Restart하거나 새 Clip을 만들거나 Project Orientation / Clip Aspect Ratio를 변경하거나 Camera를 전환하거나 Active Rear Zoom을 Reset하지 않게 한다.
31. Recording 종료 후 다음 Record Request 전에 Orientation Eligibility를 다시 검증한다.
32. Direct-recorded Front Clip이 Preview에서 본 Mirrored Appearance를 이후 Preview / Editing / Export에서도 유지하도록 승인된 Transform Ownership을 적용한다.
33. Interruption은 Successful Manual Stop이나 Successful 10-second Auto-stop으로 표시하지 않고 Completion Haptic을 자동 발생시키지 않으며 결과 Media는 ADR-020 / ADR-021에 따라 검증·복구·Late Commit 차단한다.
34. Recording Operation과 실제 Media Writing을 시작하기 직전에 작업 대상 Volume의 현재 Usable Capacity를 확인하고 승인된 최대 10초 Capture Profile의 예상 Media, Staging / Finalization Overhead, Transactional Commit과 Recovery-safe Overlap 및 Safety Reserve를 반영한 Required Free Space를 계산한다.
35. Recording Storage Preflight가 실패하면 Operation-owned Artifact나 부분 Operation State를 만들지 않고 Recording / Progress / 10초 Timer를 시작하지 않으며 기존 Clip과 Draft를 변경하지 않는다.
36. Recording 공간 부족은 해당 Recording만 차단하고 앱 전체를 Fatal State로 전환하거나 1080p / 30 fps, Audio 또는 최대 Recording Duration을 조용히 낮추지 않는다.
37. Preflight 통과 후 Write / Finalization 도중 Disk Full이 발생하면 Partial Output을 Committed Clip으로 표시하지 않고 기존 Committed Media와 다른 Draft를 보존하며 ADR-020 / ADR-021에 따라 Recovery Candidate와 Disposable Artifact를 분류한다.
38. Storage 부족으로 Final Media 생성 후 Metadata Persistence가 실패하면 해당 Media와 Durable Operation을 Recovery Candidate로 보존하고 Cleanup 실패를 재시도 가능하게 한다.
39. 사용자가 공간을 확보한 뒤 새로운 Recording을 재시도할 수 있게 하며 실패한 Operation의 안전한 Reconciliation이 기존 Project 상태를 손상시키지 않게 한다.

Completion Haptic을 종료 직전 예고 신호로 사용하지 않으며 Haptic을 사용할 수 없거나 사용자가 인지하지 못해도 기존 Visual Feedback으로 Recording 상태를 이해할 수 있게 한다.

정확한 Haptic API / Style / Intensity / Sharpness / Pattern / Duration / Generator 구현은 승인된 의미를 유지하는 적절한 Native iOS 방법으로 Phase 4 구현 중 선택하고 실제 iPhone 12에서 Tuning하며 이 문서에서 특정 API나 값을 확정하지 않는다.

Interruption으로 짧아진 Recording의 보존 여부는 기존 확정 Policy와 Validation을 따르며 불완전한 Write를 정상 Final Media로 승격하지 않는다.

## Unit Tests

- 10초 Recording Policy
- Manual Stop State
- Auto Stop State
- Recording Progress Calculation
- Invalid Recording Completion 처리
- Committed Clip 조건과 Progress State의 구분
- Operation / Clip Identity 기반 Duplicate Commit 방지
- 정상 Recording Start에서 Haptic Event가 발생하지 않음
- Successful Manual Stop과 Successful 10-second Auto-stop이 동일한 Completion 의미의 Haptic Event로 연결됨
- Active Rear Zoom 변경 중 동일 Clip / Timer / Media Operation Identity 유지와 승인 Range Clamp
- Permission / Capability / Project Validity / Orientation 실패 시 Recording / Progress / Timer 미시작
- Mid-record Rotation에서 Recording / Project Orientation / Rear Zoom 상태 유지와 다음 Recording 전 Orientation 재검증
- Interruption과 Successful Completion State / Haptic Event 분리
- 승인된 Capture Profile 기반 Recording Estimated Peak Additional Storage와 Safety Reserve 입력 적용
- Storage Preflight 실패 시 Recording Operation / Progress / 10초 Timer 미시작
- Recording Storage 부족이 다른 사용 가능한 Operation을 전역 차단하지 않는 상태 분리
- Storage 부족 시 1080p / 30 fps, Audio와 최대 Duration 유지 및 Silent Downgrade 금지
- Runtime Disk Full과 Metadata Persistence 실패의 Failure State 및 Recovery Candidate 분류

## Integration Tests

- 생성된 Movie File이 AVAsset으로 열리는지 확인
- Audio Track 존재 확인
- Duration <= 10 seconds 확인

Media Commit의 주요 Failure Boundary에 기본 Failure Injection Integration Test를 적용한다.

| Boundary | 검증 결과 |
| --- | --- |
| A. File 생성 전 실패 | Committed Clip 없이 Operation을 안전하게 정리한다. |
| B. Write 도중 실패 | Incomplete Output과 Completed Staging을 구별하고 Partial Output을 등록하지 않는다. |
| C. Staging 작성 완료 후 중단 | 새 실행에서 Durable Identity로 Valid Staging을 연결하여 복구하며 일반 Temporary Cleanup으로 삭제하지 않는다. |
| D. Validation 실패 | 정상 Clip Metadata를 생성하지 않고 Ownership과 Operation State를 확인하여 Cleanup을 분류한다. |
| E. Normalization 도중 실패 | 정규화가 필요한 경로에서 Incomplete Output을 Final Media로 등록하지 않고 Valid Source / Staging을 보존한다. |
| F. Materialization 후 Metadata Save 직전 또는 Save 실패 | 정상 Clip을 표시하지 않고 Media를 Recovery Candidate로 보존하며 재실행 후 동일 Identity로 Metadata Commit을 재개한다. |
| G. Metadata Save 성공 직후 UI Update 전 중단 | Persisted Metadata로 Clip을 한 번만 복구한다. |
| H. Cleanup 실패 | Committed Clip을 유지하고 반복 Cleanup에서 이미 정리된 Artifact로 인한 오류를 반복하지 않는다. |

Phase 4에서 Normalization이 필요하지 않은 Recording 경로는 임의의 Codec / HDR 정책을 추가하지 않고 공통 실패 처리 계약을 검증하며 실제 Import Normalization Pipeline은 Phase 6에서 검증한다.

Project Delete와 Recording Finalization을 Staging 완료, Materialization 이후 및 Metadata Commit 직전 경계에서 경합시키는 Integration Test를 수행한다.

Project가 Invalid Target으로 전환된 이후에는 Late Commit과 Project Resurrection이 없고 Active Operation과 Recovery에 필요한 Media가 조기 삭제되지 않는지 확인한다.

Recording Storage Preflight 부족 상태를 주입하여 Operation-owned Artifact, Recording, Progress와 10초 Timer가 시작되지 않고 기존 Committed Clip과 Draft가 유지되는지 확인한다.

Staging Write, Finalization과 Metadata Persistence 경계에서 Runtime Disk Full을 주입하여 Partial Output이 성공으로 Commit되지 않고 Valid Media가 Recovery Candidate로 보존되며 안전하게 분류된 Disposable Artifact만 정리되는지 확인한다.

공간 확보 후 Recording을 재시도하여 이전 실패의 Cleanup / Reconciliation과 새 Commit이 중복 Clip이나 기존 Media 손상을 만들지 않는지 확인한다.

## Physical Device Test

iPhone 12에서 다음을 반드시 검증한다.

- Rear Camera 2초 Manual Stop
- Rear Camera 9초 Manual Stop
- Rear Camera 10초 Auto Stop
- Front Camera Recording
- Rear Camera 1× Recording
- Recording 전 Rear Zoom
- 하나의 Clip Recording 중 Rear Zoom In과 1× 복귀
- Rear Zoom으로 Clip이 분리되거나 10초 Timer가 Reset되지 않음
- 승인된 Rear Maximum Zoom Clamp
- Front Preview와 Direct-recorded Result의 Mirrored Appearance 일치
- Audio 정상 Recording
- 연속 여러 Clip 촬영
- Recording 후 즉시 다음 Recording
- Portrait 9:16 Project
- Landscape 16:9 Project
- Portrait Project Orientation Mismatch에서 Recording Start 차단
- Landscape Project Orientation Mismatch에서 Recording Start 차단
- Landscape Left Recording
- Landscape Right Recording
- Recording 중 Device Rotation에도 현재 Recording과 Project Orientation 유지
- 1×이 아닌 Rear Zoom 상태에서 Recording 중 Device Rotation에도 Zoom 유지
- Camera Permission Denied / Restricted에서 Recording 차단 및 Import 접근 가능
- Microphone Permission Denied / Restricted에서 Recording 차단, 무음 Recording 미생성 및 Import 접근 가능
- Background Interruption
- 승인된 10초 Recording의 실제 Storage Growth와 Preflight Estimate의 합리성 측정
- Recording Storage Preflight 부족 시 Recording / Progress / 10초 Timer 미시작과 기존 Clip / Draft 보존
- Runtime Disk Full 주입 가능한 범위에서 Partial Output 미등록, Recovery Classification과 공간 확보 후 재시도
- 저장 경계에서 중단 후 Relaunch 시 Valid Staging / Materialized Media의 복구와 중복 Clip 방지
- Recording Finalization 중 Project Delete 이후 Late Result와 Relaunch가 Project를 되살리지 않는지 확인
- Record Button Tap / Recording Start 성공에 Haptic이 없고 Successful Manual Stop / 10-second Auto-stop 완료 시 subtle completion haptic이 동일한 종료 의미로 인지되는지 확인
- 종료 직전 예고 Haptic이 없으며 Haptic을 사용할 수 없거나 인지하지 못하는 경우에도 Visual Recording State / Circular Progress / Completion State로 상태를 이해할 수 있는지 확인

## UI Accessibility Verification

Recording Control, 현재 시간 / Progress 표현과 저장 완료 Feedback에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- 모든 저장된 Clip은 최대 10초다.
- 10초 도달 시 Recording이 자동 종료된다.
- Manual Stop이 안정적으로 동작한다.
- Recording Start에는 Haptic이 없고 Successful Manual Stop과 Successful 10-second Auto-stop 완료 시 동일한 종료 의미의 subtle completion haptic을 제공한다.
- Haptic은 종료 직전 예고나 유일한 상태 전달 수단이 아니며 사용할 수 없거나 인지하지 못해도 기존 Visual Feedback으로 Recording 상태를 이해할 수 있다.
- Video와 Audio가 정상 저장된다.
- Recording 중 Camera Switch는 불가능하다.
- Rear Zoom은 Recording 중에도 승인된 1× 이상 Range에서 동작하며 Recording / Clip / Timer / Project Orientation을 다시 시작하거나 변경하지 않는다.
- Front Recording에는 Zoom이 없고 Direct-recorded 결과는 Front Preview의 Mirrored Appearance를 유지한다.
- Camera 또는 Microphone Permission이 없거나 Orientation Eligibility가 충족되지 않으면 Recording / Progress / 10초 Timer를 시작하지 않고 Photos Import는 계속 사용할 수 있다.
- Landscape Left / Right는 모두 Landscape Project에 유효하며 Mid-record Rotation은 현재 Recording이나 Project Orientation / Active Rear Zoom을 변경하지 않고 다음 Recording 전에 Orientation을 다시 검사한다.
- Interruption은 Successful Completion으로 표시하거나 Completion Haptic을 자동 발생시키지 않으며 결과 Media는 ADR-020 / ADR-021을 따른다.
- 연속 Recording으로 App이 불안정해지지 않는다.
- iPhone 12에서 실제 촬영이 정상 동작한다.
- Committed Clip 조건을 모두 충족하기 전에는 Progress만 표시할 수 있으며 정상 Clip으로 노출하지 않는다.
- Durable Operation Identity로 재실행 후 Media와 Commit 상태를 연결할 수 있다.
- Metadata Save 직전 / 직후 실패 후에도 Valid Media가 잘못 정리되거나 Clip이 중복 등록되지 않는다.
- 기본 Failure Boundary Integration Test가 통과하며 Cleanup 실패가 저장 완료된 Clip을 무효화하지 않는다.
- Project Delete 이후 Recording Finalization이 Metadata를 Commit하거나 삭제된 Project를 재생성하지 않는다.
- Recording 시작 전 Operation-aware Storage Preflight가 승인된 Estimate와 Safety Reserve를 적용하고 부족하면 Operation / Recording / Progress / 10초 Timer를 시작하지 않는다.
- Runtime Disk Full 또는 Storage로 인한 Metadata Persistence 실패를 성공으로 표시하지 않고 기존 Media를 보호하며 Recovery Candidate를 보존한다.
- Storage 부족 때문에 Capture Quality, Frame Rate, Audio나 최대 Recording Duration을 자동으로 낮추지 않는다.
- 공간 확보 후 Recording을 안전하게 재시도할 수 있다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

직접 촬영만으로 여러 Clip을 Project에 안전하게 추가할 수 있어야 한다.

공통 Media Commit Lifecycle과 기본 Relaunch Recovery가 Production Recording 경로에 적용되고 위 Failure Boundary Test 및 iPhone 12 검증이 완료되어야 한다.

승인된 Recording Haptic 정책의 Unit Test와 iPhone 12 검증이 완료되어야 하며 Phase 12를 최초 구현이나 사용 여부 결정 시점으로 삼지 않는다.

ADR-023의 Active Rear Zoom, Permission Readiness, Orientation Start Gate / Mid-record Rotation, Front Mirroring과 Interruption Safety 계약의 Test 및 iPhone 12 검증이 완료되어야 한다.

ADR-024의 Recording Estimate Formula와 Safety Reserve Gate가 구현 전에 승인되고 Preflight / Runtime Disk Full / Metadata Persistence Failure / Retry Integration Test 및 iPhone 12 실제 10초 Storage Growth 측정이 완료되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 5 — Clip Project Management

## Goal

촬영된 여러 Clip을 하나의 Mini Vlog 구조로 정리할 수 있게 한다.

## Included

- Clip List
- Thumbnail
- Duration
- Clip Selection
- Reorder
- Delete
- Undo
- Project Total Duration
- Add More Clip
- Project Autosave
- Logical Deletion과 Deferred Physical Cleanup
- Most-recent Undo와 Process Termination Reconciliation
- Thumbnail Late Result Validity
- Unavailable Clip Representation과 User-controlled Replace

## Explicitly Excluded

- Import
- Trim
- Full Vlog Preview
- Export
- Split
- Duplicate
- Multi-track Timeline

## Decision Gate Before Implementation

Clip Management 구현 전에 다음 Structural UX Pending을 사용자 승인으로 해결한다.

- Clip Organizer의 Horizontal Strip / Grid 등 Primary Layout
- 이미 요구된 Drag Reorder의 상세 Interaction 구조
- Clip Delete Action의 Control Placement
- Snackbar / Toast 등 Undo를 표시할 UI Surface와 Presentation 구조
- Project Duration과 Add Clip Action의 배치
- Unavailable Clip의 사용자-visible Representation과 Replace / Delete Action 접근 구조

Presentation 선택은 ADR-021과 F-MVP-025의 Accepted Undo semantics를 변경하지 않으며 Delete 즉시 UI 제거, 가장 최근 삭제 한 건의 Undo, 새 Delete 시 이전 Opportunity 종료, Process 종료 후 Undo 미유지와 동일 Clip Identity / Media 복원을 유지한다.

정확한 Undo Presentation 선택은 Pending이며 이 Gate가 해결되기 전에는 해당 UI 구현을 시작하지 않는다.

Replacement Metadata Migration을 구현하기 전에 다음을 사용자 승인으로 해결한다.

- Replacement가 Same Clip Identity를 유지할지 또는 새 Clip Identity와 Slot Reference를 사용할지
- Trim Preserve 또는 Reset
- Framing Preserve 또는 Reset
- Transform Preserve 또는 Reset
- Thumbnail Regeneration
- Metadata Reset을 사용자에게 알리는 방식

이 Gate는 ADR-026의 Replace 가능 여부, 기존 Timeline Position 보존, Failure 시 Placeholder 보존과 Unrelated Reorder 비복원을 다시 Open으로 만들지 않는다.

## Implementation Tasks

1. `ThumbnailService`를 구현한다.
2. Thumbnail을 Cache Data로 관리한다.
3. Project 화면에서 Clip을 Thumbnail 중심으로 표시한다.
4. Clip Duration을 표시한다.
5. Clip Reorder Interaction을 구현한다.
6. Reorder 결과를 Persistence에 저장한다.
7. Clip Delete를 Logical Deletion으로 적용하여 UI에서 즉시 제거한다.
8. Pending Deletion을 영속적으로 추적하고 Undo에 필요한 기존 Clip Identity, Media, Metadata, Original Index와 Stable Neighbor Anchor를 보존한다.
9. 가장 최근 Clip Delete 한 건의 사용자-visible Undo를 제공하며 새로운 Delete가 이전 Undo Opportunity를 종료하도록 한다.
10. Undo Opportunity가 종료되면 Logical Deletion을 확정하되 Physical Media Cleanup은 Undo / Recovery / Active Usage / Late Commit 차단과 Safe Classification 조건을 모두 충족할 때까지 지연한다.
11. App Process 종료 후에는 Undo Opportunity를 복원하지 않고 Pending Deletion을 Logical Deletion 확정 상태로 Reconciliation한다.
12. Project Total Duration을 계산하여 표시한다.
13. Add Clip Action으로 Camera에 다시 진입할 수 있게 한다.
14. Undo는 기존 Clip Identity와 Media를 재사용하고 이전 Stable Anchor 뒤, 이전 Anchor가 없으면 다음 Anchor 앞, 둘 다 없으면 Clamp된 Original Index로 복원한다.
15. Undo가 현재 다른 Clip의 상대 순서나 Unrelated Reorder를 되돌리지 않도록 한다.
16. Media Usage 추적과 Physical Delete를 조정하여 사용 확인 이후 실제 삭제 사이에도 안전 조건이 유지되도록 한다.
17. Thumbnail Generation의 Source Usage를 추적하고 Late Result 적용 직전에 Project / Clip Validity와 Media Identity를 확인하여 Stale Result를 폐기한다.
18. 참조 Media가 Missing, Unreadable, Corrupt, Validation 실패 또는 Expected Reference와 불일치하는 Clip을 기존 Timeline Position의 Unavailable 상태로 유지하며 자동 삭제하거나 숨기거나 자동 대체하지 않는다.
19. Unavailable Clip의 Replace Action이 Direct Recording 또는 Photos Import의 기존 Media Acquisition과 Transactional Media Commit을 사용하고 Photos 원본을 변경하지 않으며 성공 전 Placeholder를 유지하고 실패, 취소 또는 Interruption이 다른 Clip과 Project를 손상시키지 않게 한다.
20. Successful Replacement가 기존 Logical Slot을 복구하고 Unrelated Reorder를 되돌리지 않게 한다.
21. Unavailable Clip의 Delete에 ADR-021의 Logical Delete, Undo, Active Usage와 Physical Cleanup 계약을 적용한다.
22. Clip 표시, Reorder / Delete / Undo와 Add Clip Controls에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.

정확한 Undo Window Duration은 DESIGN Tuning으로 남기며 특정 Lease / Counter / Coordinator Type을 이 Phase의 선행 결정으로 강제하지 않는다.

아직 구현하지 않은 Preview / Export Consumer는 Test Double로 기본 Usage / Release 계약을 검증하고 실제 Production Service 검증은 Phase 8 / 9에서 수행한다.

## Unit Tests

- Reorder
- Delete
- Undo
- Pending Deletion Cleanup
- 연속 Delete에서 가장 최근 Undo만 유효한지 확인
- Undo의 Clip Identity / Media 재사용과 Duplicate Clip 방지
- Reorder 이후 이전 Anchor 우선, 다음 Anchor 대체 및 Original Index Clamp
- 양쪽 Anchor가 재정렬되거나 사라진 경우의 결정적 복원과 다른 Clip 상대 순서 보존
- Undo Eligibility / Recovery / Active Usage별 Physical Delete 차단
- Project Total Duration
- Autosave
- Unavailable Clip이 기존 Position에 남고 Healthy Clip의 Reorder와 Editing을 막지 않는지 확인
- Replacement Failure가 Placeholder, Project와 다른 Clip을 보존하는지 확인
- Successful Replacement가 Unrelated Reorder 없이 Original Logical Slot을 복구하는지 확인

## Integration Tests

- Undo Window 종료 후에도 Active Consumer가 참조하는 Media는 보존되고 Release 이후 안전하게 Cleanup되는지 확인
- Pending Deletion 중 Process Termination 후 Relaunch에서 Undo와 Clip이 자동 복원되지 않는지 확인
- 동일 Deletion / Cleanup의 반복 Reconciliation과 이미 정리된 Artifact 처리
- Undo와 Cleanup 경합에서 Physical Delete 이후 Undo 성공이 발생하지 않는지 확인
- Thumbnail 작업 중 Clip / Project 삭제 또는 Media Identity 변경 후 Late Result 폐기
- Project Delete의 영속적인 Invalid Target과 Metadata 정리 / Deferred Cleanup 순서

## UI Tests

- Multiple Mock Clips
- Reorder
- Delete + Undo
- 연속 Delete 이후 마지막 Clip에만 사용자-visible Undo 제공
- Delete 후 다른 Clip Reorder와 Undo를 함께 수행해 복원 위치 확인
- Pending Deletion 중 종료 후 Relaunch에서 삭제된 Clip이 다시 표시되지 않는지 확인
- Add Clip 진입
- Unavailable Clip Representation과 Replace / Delete 접근
- Replacement Failure 후 Placeholder 유지

## Physical Device Test

- 실제 촬영 Clip 10개 이상에서 스크롤 및 Reorder
- Thumbnail 생성 성능
- Delete + Undo 안정성
- 연속 Delete, Reorder 후 Undo 및 Pending Deletion 중 강제 종료 / Relaunch
- Unavailable Clip이 있는 Project에서 Healthy Clip Reorder / Editing과 Replace / Delete

## UI Accessibility Verification

Clip 표시, Reorder / Delete / Undo와 Add Clip Controls에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- 여러 Clip의 순서를 변경할 수 있다.
- 삭제 후 Undo가 정상 동작한다.
- Undo는 같은 Clip Identity와 Media를 복원하며 현재 다른 Clip의 Reorder를 보존한다.
- 새로운 Delete는 이전 사용자-visible Undo를 종료하고 가장 최근 Delete만 Undo할 수 있다.
- Process Termination 이후 Undo Opportunity를 복원하거나 삭제된 Clip을 다시 표시하지 않는다.
- Undo Opportunity 종료만으로 Local Media를 삭제하지 않으며 Physical Delete 안전 조건이 모두 충족된 이후 정리한다.
- Active Usage가 있는 Media는 Release 전까지 유지되고 Stale Thumbnail Result는 삭제된 Clip이나 Project를 되살리지 않는다.
- Project Duration이 정확하다.
- UI가 전문 Video Timeline처럼 복잡하지 않다.
- Unavailable Clip은 기존 Timeline Position에 사용자-visible 상태로 남고 자동 Delete, 자동 대체 또는 Silent Removal이 발생하지 않는다.
- Healthy Clip은 Unavailable Clip이 있어도 계속 사용할 수 있다.
- Replace Failure는 기존 Placeholder, Project와 다른 Clip을 유지하고 Successful Replacement는 Unrelated Reorder 없이 Original Logical Slot을 복구한다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

촬영한 Clip만으로 Project 구조를 안정적으로 관리할 수 있어야 한다.

Logical Deletion, Most-recent Undo, 결정적 복원, Unavailable Clip Replacement와 Deferred Cleanup의 Unit / Integration / UI Test 및 iPhone 12 검증이 완료되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 6 — Photos Video Import

## Goal

Photos Library의 기존 Video를 Mellow Project에 안전하게 추가할 수 있게 한다.

Phase 4에서 구현한 공통 Media Commit Lifecycle을 Import에도 적용하며 별도의 저장 완료 또는 Orphan 판정 기준을 만들지 않는다.

## Included

- System Photos Picker
- Video Selection
- 긴 Source 허용
- Source Metadata Load
- 최대 10초 Segment Selection 준비
- SDR / HDR / Dolby Vision Source 허용
- 4K / High-resolution 및 30 fps 초과 Source 허용
- Project-owned Media Materialization
- 1080p-class / 30 fps / SDR Working Media
- Source Presentation Aspect Ratio와 Framing 가능 영역 보존
- Imported Clip 생성
- 공통 Media Commit Recovery 적용

## Explicitly Excluded

- Full Trim UX 완성
- Advanced Crop
- Fit Layout
- Blur Background
- Multi-selection Import

## Decision Gate Before Implementation

### Accepted Direction — ADR-022

다음 방향은 이미 Accepted이며 Phase 6 Definition of Ready에서 확인한다.

- SDR / HDR / Dolby Vision Source Import 허용
- 4K / High-resolution Source Import 허용
- HDR / Dolby Vision → SDR Working Media
- Working Media 30 fps 및 1080p-class Target
- Photos Source 원본 보존
- Project Fill + Crop을 Normalization에 bake-in하지 않음
- Source Presentation Aspect Ratio와 이후 Framing 가능한 유효 영역 보존

### Pending Technical Gate

실제 Phase 6 Normalization Pipeline 구현 전에 다음 항목을 사용자 승인으로 확정해야 한다.

- Working Media Codec
- Working Media Container
- 정확한 SDR Color Profile / Tagging
- Low-resolution Source Upscaling Policy
- 1080p-class Working Media의 정확한 Raster Dimension Rule
- 선택된 Segment, Staging, Normalization Intermediate / Output, Project-owned Working Media와 Recovery-safe Overlap을 반영한 Import Storage Estimate Formula
- Photos Import / Normalization에 필요한 Safety Reserve 정책

이 Gate가 해결되지 않으면 실제 Normalization 구현을 시작하지 않는다.

1080p-class를 Project Output Canvas로 미리 Crop하거나 저해상도 Source를 무조건 확대한다는 의미로 해석하지 않으며 정확한 Raster Formula와 Upscaling 여부를 임의로 정하지 않는다.

Working Media Codec / Container는 Phase 9의 Export Codec / Container와 별개의 Decision일 수 있다.

Tone-mapping 구현 방법은 여전히 Pending이며 필요한 결정은 관련 Normalization 구현 전에 해결하되 여기서 특정 Algorithm이나 Apple API 조합을 강제하지 않는다.

Import Storage Estimate는 선택된 최대 10초 Segment와 승인된 Pipeline이 Operation lifetime에 추가로 요구하는 Peak Storage를 기준으로 하며 전체 Photos 원본 File을 Mellow Container에 무조건 복제한다고 가정하지 않는다.

### Existing Re-trim Decision Gate

Imported Clip의 Re-trim 정책이 아직 확정되지 않았다면 이 Phase 시작 전에 반드시 결정한다.

선택지는 최소한 다음을 비교한다.

- Materialized 최대 10초 Segment 내부에서만 Re-trim
- Source Reference를 유지하여 원본 전체 범위 Re-trim 허용

사용자 승인 전에는 임의로 선택하지 않는다.

### Structural UX Gate for Import Selection

이 Phase가 이미 포함하는 최대 10초 Segment Selection의 최소 Control / Interaction 구조는 Phase 6 구현 전에 사용자 승인으로 결정한다.

Import Storage 부족으로 Materialization / Normalization을 시작할 수 없고 Photos 원본과 기존 Project Media는 유지되며 공간 확보 후 재시도할 수 있다는 상태의 Presentation 구조도 이 Gate에서 사용자 승인으로 결정한다.

Trim / Crop 화면 분리 여부가 이 최소 구간 선택 구조에 영향을 준다면 그 필요한 부분도 Phase 6 전에 결정하고 나머지 Full Trim / Framing 구조는 Phase 7 Gate에서 해결한다.

이 Gate는 Full Trim UX를 Phase 6으로 옮기거나 Re-trim / Source Reference 및 Working Media Technical Pending을 확정하지 않는다.

## Implementation Tasks

1. PhotosPicker 기반 Video Selection을 구현한다.
2. Broad Photos Read Permission 없이 가능한 Flow를 우선한다.
3. Source Video Duration과 Display Transform을 읽는다.
4. SDR / HDR / Dolby Vision, 4K / High-resolution, Portrait / Landscape 및 Project Aspect와 다른 Source를 정상적으로 다룰 수 있게 한다.
5. 사용자가 최대 10초 Segment를 선택할 수 있는 Import Editing State를 준비한다.
6. Add Clip 확정 후 공통 Media Commit Lifecycle을 시작하며 Media 작성 전에 Durable Operation Identity를 확보하고 Source Ownership과 Staging Write 완료 상태를 추적한 뒤 Source / Staged Media를 검증한다.
7. 검증된 Source / Staged Media에서 승인된 Technical Gate를 적용하여 1080p-class / 30 fps / SDR Working Media를 생성하고 Project Crop을 bake-in하지 않으며 Source Presentation Transform과 Framing 가능 영역을 보존한다.
8. 30 fps 초과 Source를 포함하여 Working Media를 30 fps 기준으로 정규화하고 Source FPS를 Photos 원본에서 변경하지 않으며 VFR 변환 구현은 승인된 기준을 따른다.
9. Photos 원본을 변경하지 않는다.
10. Normalized Output의 SDR 해석, 30 fps, 승인된 1080p-class Target, Orientation 및 Framing 영역 보존을 Final Validation하고 명백한 변환 실패를 거부한 뒤 안전한 Materialization 및 Project 유효성 확인 후 Metadata를 Persist하여 Committed Clip만 UI에 추가한다.
11. Import 취소 또는 실패 시 Ownership과 Recovery Classification을 확인하여 Discardable Temporary Artifact만 정리한다.
12. Import 실패 시 Project에 깨진 Clip Metadata를 남기지 않는다.
13. Normalization 실패 시 Valid Source / Staging을 보존하고 Incomplete Derived Output을 Final Media로 취급하지 않는다.
14. Materialization 이후 Metadata Persistence 실패 시 Recoverable Operation을 보존하여 Relaunch에서 Metadata Commit을 재개한다.
15. 동일 Operation의 반복 Recovery가 Duplicate Clip을 생성하지 않고 삭제되었거나 존재하지 않는 Project에 Late Result를 등록하지 않도록 한다.
16. Import / Normalization / Materialization 중 Project Delete가 확정되면 영속적인 Invalid Target 전환과 가능한 작업의 Cancellation을 요청하고 Commit 직전 Validity를 검증한다.
17. Cancelled / Late Import의 Operation-owned Working / Temporary Media는 ADR-020 Classification과 Active Usage 해제 이후에만 정리하며 Photos 원본과 다른 Draft를 보호한다.
18. Photos Import와 최대 10초 Segment Selection Controls에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.
19. Source Materialization이나 Normalization을 시작하기 직전에 작업 대상 Volume의 현재 Usable Capacity를 확인하고 선택된 최대 10초 Segment, Staging, 승인된 Normalization Intermediate / Output, Project-owned Working Media, Recovery-safe Overlap과 Safety Reserve를 반영한 Required Free Space를 계산한다.
20. Import Storage Preflight가 실패하면 Materialization / Normalization Operation이나 Operation-owned Artifact를 시작하지 않고 Photos 원본과 기존 Project Media를 유지하며 Import Working Media Quality를 조용히 낮추지 않는다.
21. Preflight 통과 후 Materialization / Normalization / Metadata Persistence 중 Disk Full이 발생하면 Incomplete Output을 정상 Clip으로 Commit하지 않고 Photos 원본, 기존 Project Media와 Recovery Candidate를 보호하며 안전하게 분류된 Disposable Artifact만 정리한다.
22. 사용자가 공간을 확보한 뒤 Import를 재시도할 수 있게 하며 반복 Recovery / Cleanup이 중복 Clip이나 다른 Draft 손상을 만들지 않게 한다.

복구를 위한 Valid Source 보존은 진행 중이거나 복구 가능한 Operation에 대한 계약이며 Commit 이후 Source Reference와 Re-trim 범위는 이 Phase의 별도 Decision Gate를 따른다.

## Unit Tests

- Import State
- 10초 Segment Validation
- Source Metadata Mapping
- Imported Clip SourceKind
- 승인된 Working Media Profile과 Raster / Upscaling Policy의 Source Metadata Mapping
- 선택된 Segment와 승인된 Normalization Pipeline 기반 Import Estimated Peak Additional Storage 및 Safety Reserve 입력 적용
- Import Storage Preflight 실패 시 Materialization / Normalization Operation 미시작
- Storage 부족 시 Working Media Quality Silent Downgrade 금지
- Runtime Disk Full과 Metadata Persistence 실패의 Failure State 및 Recovery Candidate 분류

## Integration Tests

- 720p Source
- 1080p Source
- 4K Source
- Portrait Source
- Landscape Source
- 60 fps Source
- 10초 미만 Source
- 10초 초과 Source
- SDR / HDR / Dolby Vision Source 각각의 SDR Working Media 생성
- 4K / High-resolution → 1080p-class / 30 fps / SDR Working Media
- 30 fps 초과 Source의 Working Media Frame Rate 확인
- 승인된 Low-resolution Upscaling Policy와 Raster Dimension Rule 적용
- Portrait / Landscape 및 Source / Project Aspect Mismatch의 Presentation Transform 보존
- 16:9 Source → 9:16 Project 등에서 Project Crop bake-in 없이 Phase 7 Framing에 필요한 좌우 / 상하 Source 영역 보존
- 심각한 Highlight Clipping / 잘못된 색 변환 / Orientation 손상 등 명백한 변환 실패를 Final Validation에서 정상 Media로 등록하지 않음
- Import / Normalization 성공·실패·취소 후 Photos Source 불변
- Source / Staged Media와 Normalized Output의 각각의 Validation
- Normalization 도중 실패 후 Valid Source 보존과 Incomplete Derived Output 분류
- Materialization 후 Metadata Failure 및 Relaunch에서 동일 Clip의 Commit 재개
- Metadata Save 성공 후 UI Update 전 중단과 중복 없는 Recovery
- Cancel / Failure 후 Discardable Temporary Artifact Cleanup과 Recoverable Media 보존
- 반복 Recovery / Cleanup의 Idempotency 및 Invalid Project Late Result의 Commit 차단
- Import / Normalization / Materialization 각각에서 Project Delete를 경합시켜 Metadata Commit과 Resurrection 차단
- Cancellation 요청 직후 아직 Media를 사용하는 Operation의 Cleanup 지연과 Release 이후 안전한 정리
- 4K / HDR / Dolby Vision Source의 선택된 최대 10초 Segment에 대한 Staging + Normalization Peak Additional Storage Estimate
- Import Storage Preflight 실패 시 Source Materialization / Normalization 미시작과 기존 Project Media 보존
- Materialization / Normalization / Metadata Persistence 중 Runtime Disk Full에서 Partial Output 미등록, Photos 원본 불변과 Recovery Candidate 보호
- Storage Failure Cleanup이 Safe Classification 이후에만 실행되고 공간 확보 후 Retry가 중복 Clip을 만들지 않음

## Physical Device Test

iPhone 12에서 실제 Photos Library를 이용하여 검증한다.

SDR, HDR, Dolby Vision 및 4K / High-resolution Source를 실제로 Import하여 1080p-class / 30 fps / SDR Working Media 생성과 Source / Project Aspect Mismatch의 Framing 영역 보존을 검증한다.

특히 HDR / Dolby Vision Source의 SDR 변환 결과와 Source Orientation을 확인하며 Test Asset 확보 방식은 별도 준비 과정에서 결정한다.

Normalization 실패와 Materialization 후 Metadata Save 실패를 주입한 뒤 Relaunch하여 Valid Media 보존, 복구 및 Duplicate Clip 방지를 확인한다.

Import 중 Project Delete와 늦은 Completion을 검증하여 삭제된 Project가 다시 나타나지 않고 Photos 원본이 보존되는지 확인한다.

4K SDR 및 4K HDR / Dolby Vision Source의 선택된 최대 10초 Segment로 실제 Import Peak Additional Storage와 Preflight Estimate의 합리성을 측정하며 전체 Photos 원본 복제를 전제로 하지 않는다.

Storage Preflight 부족과 Normalization 중 Runtime Disk Full을 검증하여 Photos 원본과 기존 Project Media가 유지되고 Partial Output이 등록되지 않으며 공간 확보 후 안전하게 재시도되는지 확인한다.

## UI Accessibility Verification

Photos Import와 최대 10초 Segment Selection Controls에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- 긴 Video도 선택할 수 있다.
- Project에 들어가는 Clip은 최대 10초다.
- SDR / HDR / Dolby Vision Source와 4K / High-resolution Source를 허용하고 승인된 1080p-class / 30 fps / SDR Working Pipeline을 사용한다.
- 저해상도 Source는 Phase 6 전에 승인된 Upscaling / Raster 정책을 따르며 임의의 확대 여부를 가정하지 않는다.
- Project Crop이 Working File에 bake-in되지 않고 Phase 7에서 Framing할 Source의 유효 영역과 Presentation Aspect Ratio / Orientation이 보존된다.
- Normalization Output Validation을 통과한 Media만 등록하며 명백한 색 변환 실패나 Orientation 손상을 정상 Clip으로 취급하지 않는다.
- Import / Normalization은 Photos 원본을 수정하거나 삭제하지 않는다.
- Photos 원본 삭제가 Project-owned Media에 영향을 주지 않는다.
- Import 취소 또는 실패 시 Project가 손상되지 않는다.
- Normalization 실패가 Valid Source / Staging Media를 파괴하지 않는다.
- Materialization 이후 Metadata Persistence 실패를 복구할 수 있으며 Commit 완료 전 Clip을 정상 UI에 표시하지 않는다.
- Cancel / Failure Cleanup은 확인된 Discardable Artifact에만 적용되며 반복 수행해도 정상 Media와 Recovery Candidate를 훼손하지 않는다.
- Project Delete 이후 Cancelled / Late Import가 Metadata를 등록하거나 Project를 재생성하지 않는다.
- Import Operation이 사용하는 Media는 Cancellation 요청만으로 삭제되지 않으며 Release와 Safe Classification 이후 정리된다.
- Import 시작 전 Operation-aware Storage Preflight가 선택된 Segment와 승인된 Pipeline의 Estimate 및 Safety Reserve를 적용하고 부족하면 Materialization / Normalization을 시작하지 않는다.
- Runtime Disk Full 또는 Storage로 인한 Metadata Persistence 실패를 성공으로 표시하지 않고 Photos 원본, 기존 Project Media와 Recovery Candidate를 보호한다.
- Storage 부족 때문에 승인된 1080p-class / 30 fps / SDR Working Media 방향을 자동으로 낮추지 않는다.
- 공간 확보 후 Import를 안전하게 재시도할 수 있다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

촬영 Clip과 Imported Clip이 동일한 Project에서 함께 관리되어야 한다.

Import Production Pipeline이 공통 Media Commit 계약을 따르고 Failure Recovery Integration Test 및 iPhone 12 검증이 완료되어야 한다.

ADR-022의 SDR / 30 fps / 1080p-class 및 Framing 보존 계약과 Phase 6 Technical Gate가 충족되어야 하며 HDR / Dolby Vision Import의 iPhone 12 검증 결과 없이 완료로 처리하지 않는다.

ADR-024의 Import Estimate Formula와 Safety Reserve Gate가 구현 전에 승인되고 Preflight / Runtime Disk Full / Recovery-safe Cleanup / Retry Integration Test 및 iPhone 12 Peak Additional Storage 측정이 완료되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 7 — Trim and Framing

## Goal

모든 Clip의 사용 구간을 조정하고 Imported Video의 Framing을 Project Orientation에 맞게 조정할 수 있게 한다.

## Included

- Recorded Clip Trim
- Imported Clip Trim
- Maximum 10-second Rule
- Thumbnail Filmstrip 또는 단순 Trim UI
- Fill + Crop
- Drag Framing
- Non-destructive Metadata
- Portrait / Landscape Canvas
- Trim Preview

## Explicitly Excluded

- Split
- Duplicate
- Multi-cut
- Fit Layout
- Background Blur
- Professional Timeline
- Advanced Zoom unless separately approved

## Decision Gate Before Implementation

다음 Open Design Decision을 이 Phase 전에 확정한다.

- Trim과 Crop을 한 화면에서 처리할지
- 두 단계로 분리할지
- Pinch to Zoom을 MVP에 포함할지

### Remaining Structural UX Before Phase 7

- Primary Trim Interaction과 Thumbnail Filmstrip / Scrubbing 구조 및 Time Precision 표현
- 이미 확정된 Drag / Position Framing의 상세 Interaction 구조
- Crop Reset 필요 여부와 Crop UI 구조
- Portrait / Landscape Project에서의 Editing Control 배치

Phase 6에서 구현한 Import Segment Selection의 승인된 구조를 재사용하고 이 Phase에 남은 구조적 선택지는 사용자 승인 전까지 Pending으로 유지한다.

Pinch 포함 여부를 임의로 선택하지 않으며 ADR-022의 Project Crop bake-in 금지와 Metadata 기반 비파괴 Framing 계약을 유지한다.

## Implementation Tasks

1. `trimStart`와 `trimDuration` Editing State를 구현한다.
2. Trim 범위가 10초를 초과하지 않도록 한다.
3. Recorded Clip Re-trim을 구현한다.
4. Imported Clip Re-trim을 확정된 정책에 따라 구현한다.
5. Framing Metadata를 Normalized Coordinate로 저장한다.
6. Phase 6 Working Media에 보존된 Source 영역을 사용하여 Fill + Crop Transform을 Metadata 기반으로 구현하고 Crop Region / Position / Scale을 Working File에 bake-in하지 않는다.
7. Source `preferredTransform`을 고려한다.
8. Portrait Source와 Landscape Source를 올바르게 처리한다.
9. Trim과 Framing 변경사항을 Interaction 종료 시 Autosave한다.
10. Preview 중 원본 Media를 수정하지 않는다.
11. Trim / Framing Controls와 선택 구간 표시에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.

## Unit Tests

- Trim Start / End Validation
- Maximum 10 seconds
- CMTime Conversion
- Normalized Framing
- Aspect Fill Calculation
- Portrait to Landscape Crop
- Landscape to Portrait Crop

## Integration Tests

- Recorded Clip Trim
- Imported 4K Clip Trim
- Portrait → 16:9
- Landscape → 9:16
- Audio Sync 유지
- Phase 6 Normalization에서 미리 Crop되지 않은 Source 영역을 사용한 좌우 / 상하 Framing 변경
- HDR / Dolby Vision에서 생성한 SDR Working Media의 Trim / Framing Metadata 적용과 비파괴성

## Physical Device Test

- Trim Handle Interaction
- Framing Drag
- 9:16 Project
- 16:9 Project
- iPhone 12 UI Responsiveness

## UI Accessibility Verification

Trim / Framing Controls와 선택 구간 표시에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- 모든 Clip을 비파괴적으로 Trim할 수 있다.
- Trim 결과는 최대 10초를 초과하지 않는다.
- 다른 Aspect Ratio Source가 Fill + Crop으로 올바르게 보인다.
- 사용자가 Framing을 조절할 수 있다.
- Normalization 시 Project Crop으로 Framing 가능 영역이 손실되지 않았으며 보존된 Source 영역에서 Metadata로 Framing을 변경할 수 있다.
- Trim과 Framing 변경이 App 재실행 후 유지된다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

Project의 모든 Clip이 최종 Vlog에 사용될 정확한 Time Range와 Framing을 가져야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 8 — Full Vlog Preview

## Goal

현재 Project의 Clip Order, Trim, Framing, Orientation, Audio를 하나의 연속된 Vlog처럼 Preview할 수 있게 한다.

## Included

- Shared `VideoCompositionBuilder`
- Multi-clip Timeline
- Clip Order
- Trim
- Source Rotation
- Fill + Crop
- Framing
- Audio
- 1080p Canvas
- 30 fps Timing
- AVPlayer Preview
- SDR Preview와 Shared Color Handling
- Play / Pause / Seek 기본 UX
- Preview Active Media Usage
- Mutation 이후 Stale Composition Invalidation

## Explicitly Excluded

- Transition
- Music
- Text
- Filter
- Rendered Preview Cache unless performance issue proves need

## Decision Gate Before Implementation

Full Vlog Preview UI를 구현하기 전에 다음 Structural UX Pending을 사용자 승인으로 해결한다.

- Full Preview Playback Control Structure / Hierarchy
- Preview 진입·종료와 Project Editing 화면 복귀 Navigation 구조
- Scrubber 등 M01의 미정 범위가 Control 구조에 영향을 주는 부분
- Empty / Unavailable Project에서 Full Preview가 Blocked일 때의 State Presentation

이 Gate는 Preview 기능 범위를 새로 확정하지 않으며 M01은 별도 Repair 대상으로 유지한다.

Phase 12에는 승인된 Preview 구조의 시각적 Refinement만 남기며 UI 구현을 막는 미결정 사항은 Phase 8 전에 해결한다.

## Implementation Tasks

1. `VideoCompositionBuilder`를 구현한다.
2. Project Metadata에서 Virtual Timeline을 구성한다.
3. 모든 Clip Order를 반영한다.
4. Trim Range를 적용한다.
5. Source Display Transform을 정규화한다.
6. Project Orientation에 맞는 1080p Canvas를 생성한다.
7. Fill + Crop과 Framing을 적용한다.
8. Audio Track을 유지한다.
9. HDR / Dolby Vision Source에서 시작한 Clip을 포함하여 AVPlayer로 SDR Composition Preview를 구현하고 Framing / Trim / Transform과 SDR 해석을 Shared Composition 기준으로 적용한다.
10. Project 변경 시 Stale Composition을 Invalidate하고 다음 유효 Preview가 최신 Project State를 반영하도록 안전하게 Rebuild한다.
11. Composition Build는 Main Actor를 장시간 Block하지 않는다.
12. Preview Preparation / Playback의 Active Media Usage를 등록하고 실제 Reference Release 전까지 Physical Delete를 지연한다.
13. 필요한 경우 Playback을 중단하며 오래된 State의 Async Composition 결과나 삭제된 Project의 Late Result를 적용하지 않는다.
14. 0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Full Preview Composition을 생성하거나 손상된 Clip을 생략한 결과를 재생하지 않고 Healthy Clip의 Individual Preview는 계속 허용한다.
15. 승인된 Preview Controls와 진입·종료 Navigation에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.

Mutation 검증은 Test에서 Project State 변경을 주입할 수 있으며 이 계약으로 새로운 Preview Editing UI나 특정 Player Rebuilding Strategy를 확정하지 않는다.

## Unit Tests

- Timeline Duration
- Clip Order Mapping
- Canvas Size
- Transform Calculation

## Integration Tests

- 2 Clip
- 10 Clip
- Mixed Recorded / Imported Clip
- Portrait Project
- Landscape Project
- Audio 유지
- Trim 반영
- Framing 반영

SDR Source와 HDR / Dolby Vision Source에서 생성한 Working Media를 함께 Preview하여 SDR 재생과 Shared Composition의 Trim / Framing / Transform 반영을 검증한다.

### Preview Lifecycle Integration Tests

- Preview가 Media를 참조하는 동안 Clip Delete와 Undo 종료가 발생해도 Source File 보존
- Clip Delete / Reorder / Trim / Framing 변경 후 Stale Composition Invalidation과 다음 Preview의 새 State 반영
- Stale Preview Preparation Result의 적용 차단
- Project Delete 시 Cancellation 요청과 Preview Reference Release 전 Cleanup 차단
- Reference Release 이후 안전한 Deferred Cleanup과 조기 File 삭제로 인한 Player Failure 방지
- 0 Clip Project와 Unresolved Unavailable Clip이 Full Preview를 Block하고 Healthy Clip Individual Preview는 유지되는지 확인

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- Preview 시작 시간
- 20개 이상 Clip Project
- Scrubbing 또는 Seek
- Orientation
- Audio Sync
- UI Freeze 여부
- Memory Pressure 여부
- Preview 중 Project Mutation과 Project Delete 이후 Media 보존 / Release 및 다음 유효 Preview 상태
- HDR / Dolby Vision에서 시작한 Clip의 안정적인 SDR Preview

## UI Accessibility Verification

승인된 Preview Controls와 진입·종료 Navigation에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- Preview 결과가 Project Metadata와 일치한다.
- Preview는 SDR을 사용하고 HDR Source라는 이유로 HDR Preview / SDR Export의 이중 기본 Pipeline을 만들지 않는다.
- Clip 사이 재생이 정상적이다.
- Audio Sync가 유지된다.
- Preview를 위해 매번 하나의 완성 Video를 미리 Render하지 않는다.
- iPhone 12에서 실사용 가능한 성능을 보인다.
- Preview가 사용 중인 File은 실제 Reference Release 전까지 삭제되지 않는다.
- Clip Mutation 이후 Stale Composition을 무기한 사용하지 않으며 다음 유효 Preview는 새 State를 반영한다.
- 삭제된 Project 또는 이전 State의 Late Preview Result를 적용하지 않는다.
- 0 Clip Project에서는 Full Preview를 제공하지 않는다.
- Unresolved Unavailable Clip이 있는 Project에서는 Full Preview를 Block하고 해당 Clip을 Silent Skip하지 않으며 Healthy Clip의 Individual Preview는 계속 가능하다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

사용자가 Export 전에 현재 Vlog 결과를 신뢰할 수 있어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 9 — Export, Photos Save, and Share

## Goal

Preview와 동일한 결과를 하나의 1080p / 30 fps / SDR Video로 Export하고 Photos에 저장하거나 공유할 수 있게 한다.

## Included

- Export Service
- Shared Composition
- 1080p Output
- 30 fps Output
- SDR Output와 Preview / Export Color / Framing Parity
- Temporary Export File
- Successful Local Export Artifact
- Export Rendering / Photos Save Result State 분리
- Progress
- Cancel
- Photos Save
- Retry Photos Save
- Share Sheet
- Done / Discard Result Flow
- Active Consumer-aware Safe Cleanup
- Draft 유지
- Immutable Export Snapshot
- Export Source Media Usage와 Deferred Cleanup
- Project Delete 시 Export Cancellation / Invalid Target 적용

## Decision Gate Before Implementation

다음 항목은 이 Phase 전에 반드시 확정한다.

- H.264 또는 HEVC
- File Container
- 기본 Video Bitrate 방향
- Audio Format 방향
- Audio Bitrate
- Background Export 정책
- 재Export가 필요한 경우의 Export Retry 세부 정책
- 현재 Immutable Export Snapshot의 Project Duration / State와 승인된 Export Profile을 반영한 Export Storage Estimate Formula
- Export Temporary / Final Local Artifact와 Photos Save / Share Handoff까지의 Local Retention을 포함한 Safety Reserve 정책

MVP Export의 HDR vs SDR 방향은 ADR-022에서 SDR로 해결되었으며 이 Phase에서 다시 결정하지 않는다.

정확한 SDR Color Profile / Tagging과 Working Media Codec / Container, Upscaling 및 Raster Dimension Rule은 Phase 6 전에 해결한 기준을 사용하며 Export Codec / Container를 Working Media와 자동으로 동일하게 결정하지 않는다.

### Structural UX Gate Before Phase 9

Export UI 구현 전에 다음 Presentation 구조를 사용자 승인으로 결정한다.

- Export Action Placement와 Progress Presentation
- Exporting, local result ready, Saved to Photos, Photos save failed, Sharing과 Share cancelled / returned Result State Presentation
- Save Retry Placement, Share / Done Action 배치와 unsaved Result Discard Confirmation
- Render Failure, Photos Save Failure와 Storage Preflight Failure의 Presentation이 구현 구조에 영향을 주는 부분
- Empty / Unavailable Project에서 Export가 Blocked일 때의 State Presentation

Export 완료 후 Share / Done, iOS Share Sheet와 Draft 유지는 이미 확정된 요구사항이며 재결정하지 않는다.

이 Gate는 UI Decision Timing만 정의하며 ADR-025의 Photos Save / Share File Lifecycle과 Temporary File Policy를 다시 결정하지 않는다.

Background Export, 재Export가 필요한 경우의 Retry 세부 정책과 Exact Copy는 별도 Pending으로 유지한다.

## Implementation Tasks

1. Export 시작 시 현재 유효한 Project의 Immutable Logical Snapshot을 확보하고 Preview와 공통 Composition Definition을 사용하여 Snapshot을 Export한다.
2. `AVAssetExportSession` 기반 MVP Export를 구현한다.
3. Portrait는 1080 × 1920으로 Export한다.
4. Landscape는 1920 × 1080으로 Export한다.
5. Output은 30 fps / SDR 정책을 따르고 동일한 Snapshot State의 Preview와 가능한 한 공통 Color Handling / Framing / Transform 정의를 사용한다.
6. Export Result를 Temporary Location에 생성한다.
7. Progress State를 UI에 제공한다.
8. Export Cancel을 처리한다.
9. Export Process 성공, Output File 존재, Output Validation 성공과 Durable Export Operation Identity 연결을 모두 확인한 뒤에만 Successful Local Export Artifact를 만들고 Export Rendering Success로 전환한다.
10. Successful Local Export Artifact를 Photos Save Consumer에 전달하고 Photos Save Success와 Photos Save Failure를 Export Rendering Success와 별개로 처리한다.
11. Photos Save Failure에서는 같은 Valid Local Export Artifact를 사용한 Save Retry와 Share를 제공하며 단순 Photos Save Failure 때문에 동일 Project를 다시 Render하지 않는다.
12. iOS Share Sheet에 같은 Successful Local Export Artifact를 전달하고 Share Sheet 또는 Share Handoff가 Active인 동안 Artifact Physical Cleanup을 Defer하며 Share Cancel을 Export Failure로 처리하지 않는다.
13. Photos Save Success 후에는 Share와 Done을 제공하고 Photos Save에 성공하지 않은 Done 또는 close 요청에는 explicit Discard Confirmation을 적용하며 Cancel은 Result Flow와 Artifact를 유지한다.
14. Result Flow가 Resolved되고 Active Consumer, Retry와 Recovery Requirement가 없을 때만 Local Export Artifact를 Idempotent하게 Cleanup한다.
15. Export 성공 후 Draft를 삭제하지 않는다.
16. Temporary File Cleanup 정책을 적용한다.
17. Snapshot에 Clip Identity / Order, Trim, Framing / Transform, Project Orientation, Media Reference와 Audio / Video Composition State를 포함한다.
18. Snapshot 획득과 Source Media Usage 등록을 Cleanup과 조정하고 Export 종료 또는 취소 후 실제 Reference Release까지 Source Media를 보존한다.
19. Export 시작 이후 일반 Clip Edit / Reorder / Clip Delete가 진행 중인 Export Snapshot과 결과를 소급 변경하지 않도록 한다.
20. Project Delete 시 먼저 Invalid Target을 확립하고 Export에 Cancellation을 요청하며 실제 Release 이전의 Physical Cleanup과 Late Result의 Project Commit을 차단한다.
21. Export 시작 전에 하나 이상의 Usable Committed Clip, Unresolved Unavailable Clip 부재와 Valid Composition Source를 확인하고 0 Clip 또는 Unresolved Unavailable Project에서는 Export Operation을 시작하거나 Silent Omission Output을 만들지 않는다.
22. Project Delete 이후에도 Active Photos Save 또는 Share Consumer가 사용하는 Successful Local Export Artifact를 보존하고 Consumer 종료와 Retry 또는 Recovery Requirement 해제 뒤에만 Cleanup하며 이미 Photos에 저장된 외부 결과에는 영향을 주지 않는다.
23. Export Progress / Completion, Photos Save Failure, Share / Done과 Discard Confirmation에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.
24. Export Operation을 시작하기 직전에 작업 대상 Volume의 현재 Usable Capacity를 확인하고 Immutable Export Snapshot의 Duration / State, 승인된 Export Profile, Temporary Output, Final Local Artifact, Photos Save / Share Handoff까지 Mellow가 보존하는 Local Artifact와 Safety Reserve를 반영한 Required Free Space를 계산한다.
25. Export Storage Preflight가 실패하면 Export Operation이나 Partial Output을 시작하지 않고 해당 Export만 차단하며 기존 Draft와 Recording / Import 등 다른 사용 가능한 기능을 자동 차단하지 않는다.
26. Storage 부족 때문에 승인된 1080p / 30 fps / SDR Export Quality, Audio, Project Duration이나 Clip 수를 조용히 낮추거나 제한하지 않는다.
27. Preflight 통과 후 Temporary Export 또는 Finalization 중 Disk Full이 발생하면 Partial Output을 성공한 Export로 노출하지 않고 기존 Draft와 Source Media를 보존하며 ADR-020 / ADR-021 / ADR-025에 따라 Artifact를 분류하고 Cleanup을 재시도 가능하게 한다.
28. 사용자가 공간을 확보한 뒤 동일하거나 새로 획득한 승인된 Snapshot 정책에 따라 Export를 안전하게 재시도할 수 있게 하며 Local Storage Preflight가 Photos Library 저장 성공을 보장한다고 가정하지 않는다.

이 Lifecycle 계약은 ADR-025의 Result Artifact Lifecycle과 B03의 Source-media Lifetime 및 Project Validity를 함께 적용한다.

## Unit Tests

- Export Profile
- Output Canvas
- Export State Machine
- Retry State
- Render Success와 Photos Save Success의 분리
- Successful Local Export Artifact Validation과 Durable Result Identity
- Photos Save Failure에서 같은 Artifact를 사용하는 Save Retry와 Share
- Share Cancel의 Artifact 보존
- Saved Done과 unsaved Done / Discard의 Cleanup Eligibility
- Active Consumer가 존재하는 Artifact의 Physical Cleanup Defer
- Export Snapshot의 최소 Composition State와 불변성
- Export Snapshot Duration / State와 승인된 Profile 기반 Estimated Peak Additional Storage 및 Safety Reserve 입력 적용
- Export Storage Preflight 실패 시 Export Operation 미시작과 Operation-scoped Failure State
- Storage 부족 시 Output Quality / Audio / Project Scope Silent Downgrade 금지
- Runtime Disk Full의 Partial Output 비성공 처리와 기존 Draft 보존
- 0 Clip 또는 Unresolved Unavailable Project에서 Export Operation이 시작되지 않고 Silent Omission Output이 생성되지 않는지 확인

## Integration Tests

- Portrait Export
- Landscape Export
- Mixed Source Export
- 4K Imported Clip 포함 Export
- Audio 유지
- Trim 반영
- Framing 반영
- Output Resolution 확인
- Output Frame Rate 확인
- SDR Output 확인 및 HDR Export 경로 제외
- SDR / HDR / Dolby Vision에서 시작한 Clip을 포함한 동일한 Snapshot State의 Preview / Export Color / Framing / Transform Parity

### Export Lifecycle Integration Tests

- Export 시작 후 Clip Edit / Reorder / Clip Delete가 진행 중인 Snapshot과 Output을 변경하지 않는지 확인
- Export 시작 → Clip Delete → Undo 종료 이후에도 Source Media가 유지되고 실제 Export Release 후 안전 조건에 따라 정리되는지 확인
- Project Delete 시 Cooperative Cancellation 요청과 Invalid Target의 Late Commit 차단
- Cancellation 요청 이후 아직 사용 중인 Source Media의 조기 삭제 방지
- 늦게 생성된 Uncommitted Artifact의 안전한 Cleanup과 삭제된 Project Resurrection 방지
- Project Delete가 이미 Photos에 저장 완료된 외부 Export 결과에 영향을 주지 않는지 확인
- 짧은 Project와 더 큰 Project에서 Immutable Export Snapshot Duration / State 기반 Peak Additional Storage Estimate 검증
- Export Storage Preflight 실패 시 Export Operation / Partial Output 미시작과 기존 Draft 보존
- Temporary Export와 Finalization 중 Runtime Disk Full에서 Partial Output 비노출, Source Media 보호와 Retry 가능한 Cleanup
- 공간 확보 후 Export Retry와 Local Preflight 통과 이후 별도로 실패할 수 있는 Photos Save 상태 분리
- Render Success와 Photos Save Success
- Render Success와 Photos Save Failure
- Photos Save Failure 후 Save Retry Success
- Photos Save Failure 후 Share
- Share Cancel
- Share Handoff Return
- Photos Save Success 후 Done
- unsaved Result Done에서 Discard Cancel
- unsaved Result Done에서 Discard Confirm
- Rendering 중 Export Cancel
- Photos Save Failure가 Re-render를 유발하지 않는지 확인
- Active Share가 Artifact Cleanup을 막는지 확인
- Export Rendering 중 Project Delete
- Active Photos Save 또는 Share 중 Project Delete
- Photos Save 완료 후 Project Delete가 External Photos Result에 영향을 주지 않는지 확인
- 0 Clip Project와 Unresolved Unavailable Clip이 Export를 Block하고 사용자가 Replace 또는 Delete로 문제를 해결한 뒤에만 Export를 시작할 수 있는지 확인

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- 30초 Vlog
- 2분 이상 Vlog
- 20개 이상 Clip
- Photos Save
- Share Sheet
- Export Cancel
- Export Retry
- Photos Save Failure 후 Save Retry와 Share
- Share Cancel / Return
- unsaved Result Discard Confirmation
- 짧은 Project와 더 큰 Project의 실제 Export Peak Additional Storage 및 Snapshot 기반 Estimate 합리성
- Export Storage Preflight 부족 시 Export 미시작, 기존 Draft 보존과 다른 기능의 불필요한 전역 차단 없음
- Runtime Disk Full 주입 가능한 범위에서 Partial Output 미노출, Cleanup / Recovery와 공간 확보 후 Retry
- Background 이동 시 현재 정책
- Export 중 Clip Mutation / Undo 종료와 Project Delete 후 실제 Media Release 경계
- SDR / HDR / Dolby Vision Source가 혼합된 Project의 SDR Export와 동일한 Snapshot State의 Preview 색 / Framing 비교

## UI Accessibility Verification

Export Progress / Completion, Photos Save Failure, Save Retry, Share / Done, unsaved Discard Confirmation과 Storage Preflight Failure 상태 표현에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- Export 결과가 Export 시작 시 Snapshot과 동일한 Project State의 Preview와 시각적으로 일치한다.
- Successful Render는 Validation을 통과하고 Durable Export Operation / Result Identity와 연결된 Local Export Artifact를 만든다.
- Output Resolution이 정확하다.
- Portrait 1080 × 1920 또는 Landscape 1920 × 1080, 30 fps / SDR Output이며 HDR Export를 제공하지 않는다.
- 동일한 Snapshot State의 Preview와 Export가 가능한 한 동일한 SDR 해석과 Framing / Transform 결과를 사용한다.
- Photos Save가 정상 동작한다.
- Photos Save Failure는 Successful Render를 실패로 바꾸지 않고 동일 Artifact의 Save Retry와 Share를 제공한다.
- Share Sheet가 정상 동작한다.
- Share Cancel은 Artifact와 Draft를 유지하고 Export Failure가 아니다.
- Photos Save에 성공하지 않은 Result는 explicit Discard 없이 Cleanup하지 않으며 Active Consumer가 있는 Artifact는 Physical Cleanup하지 않는다.
- Draft는 Export 이후에도 유지된다.
- 실패 시 이해 가능한 상태를 제공한다.
- 일반 Clip Mutation이 진행 중인 Export 결과를 소급 변경하지 않는다.
- Export Snapshot Media는 Operation 종료 또는 취소 후 실제 Reference Release까지 Physical Delete되지 않는다.
- Project Delete는 Export Cancellation을 요청하고 Late Commit을 차단하며 삭제된 Project를 되살리지 않는다.
- Project Delete는 Active Photos Save 또는 Share Consumer의 Artifact를 조기 삭제하지 않고 이미 Photos에 저장 완료된 External Photos Result를 삭제하지 않는다.
- Export 시작 전 Operation-aware Storage Preflight가 Immutable Snapshot Duration / State와 승인된 Profile의 Estimate 및 Safety Reserve를 적용하고 부족하면 Export를 시작하지 않는다.
- Runtime Disk Full을 성공으로 표시하거나 Partial Output을 정상 Export로 노출하지 않고 기존 Draft와 Source Media를 보호한다.
- Storage 부족 때문에 Export Quality / Audio를 자동으로 낮추거나 Project Duration / Clip Count 제한을 추가하지 않는다.
- 공간 확보 후 Export를 안전하게 재시도할 수 있으며 Local Storage Preflight는 Photos Save 성공을 보장하지 않는다.
- 0 Clip Project에서는 Export를 제공하지 않는다.
- Unresolved Unavailable Clip이 있는 Project에서는 Export를 Block하고 해당 Clip을 Silent Skip한 Output을 만들지 않는다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

Mellow의 핵심 End-to-End Flow가 처음으로 완성되어야 한다.

Snapshot 불변성, Source Media Lifetime, ADR-025 Result Artifact Lifecycle과 Project Delete 경합의 Integration Test 및 iPhone 12 검증이 완료되어야 한다.

ADR-024의 Export Estimate Formula와 Safety Reserve Gate가 구현 전에 승인되고 Preflight / Runtime Disk Full / Partial Output / Retry Integration Test 및 iPhone 12 Peak Additional Storage 측정이 완료되어야 한다.

해당 화면의 Structural UX Gate가 구현 전에 승인되었고 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 10 — Draft Storage and Recovery Hardening

## Goal

여러 Draft와 Media File이 장기간 사용되어도 손상이나 유실 가능성을 최소화한다.

이 Phase는 Media Commit Lifecycle이나 Storage Policy를 처음 만드는 단계가 아니며 Phase 4의 Recording, Phase 6의 Import와 Phase 9의 Export에 이미 적용된 ADR-020 / ADR-021 / ADR-024 / ADR-025 계약을 반복 Low-storage, Disk Full, Cleanup과 Relaunch 조건에서 강화한다.

## Included

- Project Storage Layout 검증
- Recovery Classification과 Confirmed Orphan Reconciliation 강화
- Missing / Corrupt File과 Unavailable Clip 처리
- App Relaunch Recovery
- Pending Deletion Recovery
- Temporary File Cleanup
- Storage Usage 기본 계산
- Large Draft 안정성
- Forced Termination과 Repeated Relaunch
- Duplicate Recovery Prevention
- Cleanup Idempotency
- Multiple Draft Isolation
- Deferred Physical Deletion Reconciliation
- Project Logical Deletion과 Cleanup Retry
- Stale Async Result Discard
- Repeated Low-storage Launch Hardening
- Runtime Disk Full / Retry Hardening
- Storage Change Between Preflight and Write
- Safe Disposable / Confirmed Orphan Cleanup under Storage Pressure
- Export Result Artifact Recovery Hardening
- Unresolved Export Result Preservation
- Multiple Export Operation Isolation
- Replacement Crash / Failure Recovery
- Project-level Metadata Corruption Isolation

## Explicitly Excluded

- iCloud Sync
- Backup Server
- Account
- Cross-device Sync

## Decision Gate Before Implementation

Project-level Metadata Recovery Algorithm과 Exact Corrupted-project Failure State Presentation / Copy를 사용자 승인으로 해결한다.

이 Gate는 ADR-026의 Project-level Corruption Isolation, 다른 Draft 보호, 자동 Project Delete 금지와 Database 전체 Reset 비기본 정책을 다시 Open으로 만들지 않는다.

## Implementation Tasks

1. Phase 4 / 6의 Reconciliation을 기반으로 App Launch 시 Project Metadata, Media File과 Durable Operation State의 Consistency 검증을 강화한다.
2. Missing Media를 안전하게 표시한다.
3. 하나의 손상된 Clip이 Project 전체 Crash로 이어지지 않게 한다.
4. Metadata가 없는 Media의 Recovery Candidate 여부를 먼저 확인하고 Confirmed Orphan과 Discardable Temporary Artifact만 정리하는 기존 계약을 검증한다.
5. Phase 5의 Pending Deletion Reconciliation을 강화하여 Process Termination 후 Undo Opportunity를 복원하지 않고 Logical Deletion을 확정한다.
6. App 강제 종료 후 Draft를 재검증한다.
7. Export Temporary File Cleanup을 확인한다.
8. 여러 Draft의 Storage Usage를 계산할 수 있는 기반을 만든다.
9. Project Delete 이후 Active Usage와 Recovery 필요가 해제되면 남은 Project-owned Media를 안전하게 정리하며 실패한 Cleanup을 재시도할 수 있는지 검증한다.
10. 주요 Media Commit 실패 경계에서 Forced Termination과 Repeated Relaunch를 수행하여 Staging / Materialized Media Recovery를 반복 검증한다.
11. 동일 Operation / Clip Identity의 반복 Recovery가 Duplicate Clip 또는 동일 Media의 중복 등록을 만들지 않는지 확인한다.
12. Cleanup 실패와 재시도 및 이미 정리된 Artifact를 검증하여 정상 Committed Media와 Recovery Candidate가 삭제되지 않게 한다.
13. 한 Draft의 Missing / Corrupt Media 또는 실패한 Operation이 다른 Draft의 정상 Media와 Metadata를 손상시키지 않는지 검증한다.
14. Project Logical Deletion의 영속화, Metadata 정리와 Physical Cleanup 사이에서 강제 종료하고 반복 Relaunch하여 Project Resurrection과 중복 Deletion State가 없는지 확인한다.
15. Deferred Physical Deletion을 Reconciliation하며 Active Usage / Recovery / Undo 조건을 다시 확인하고 이미 정리된 Artifact를 안전하게 처리한다.
16. Recording / Import / Preview / Export / Thumbnail의 Stale Async Result를 적용하지 않고 삭제된 Project나 Clip을 되살리지 않는지 검증한다.
17. 반복 Low-storage 상태로 App을 실행해도 기존 Draft와 Committed Media를 자동 삭제하거나 앱 전체를 Fatal State로 고정하지 않는지 검증한다.
18. Preflight 이후 실제 Write 전에 다른 Process나 System이 Storage를 소비하는 조건과 반복 Runtime Disk Full / 공간 확보 / Retry를 검증한다.
19. Failed Cleanup과 Stale Disposable Artifact를 반복 Reconciliation하여 안전하게 분류된 Disposable Artifact와 Confirmed Orphan만 정리하고 Recovery Candidate, Undo Candidate, Active Media와 다른 Reference를 보호한다.
20. Storage Pressure에서도 Recovery Classification과 Active Usage / Undo / Reference 확인을 생략하지 않고 Multiple Draft Isolation을 유지한다.
21. 반복 Cleanup이 Idempotent하며 이미 정리된 Artifact나 실패한 이전 Operation 때문에 정상 Draft가 손상되지 않는지 확인한다.
22. Phase 4 / 6 / 9의 Operation-aware Preflight와 Runtime Disk Full 계약이 Hardening 과정에서 하나의 고정 Global Threshold나 User Media 자동 삭제 정책으로 대체되지 않게 한다.
23. Export Rendering 중 Crash, Rendering 완료 후 Result State Persistence 전 Crash, Photos Save Failure 후 Crash과 Photos Save Success 후 Cleanup 전 Crash에서 ADR-025 Export Result Artifact를 Reconciliation한다.
24. Valid Unresolved Local Export Artifact를 metadata 부재만으로 Orphan으로 삭제하지 않고 Durable Export Operation / Result Identity로 분류하며 반복 Relaunch가 Duplicate Export Result 또는 automatic duplicate Photos Save를 만들지 않게 한다.
25. Successful Local Export Artifact Cleanup이 Active Consumer, Retry와 Recovery Requirement를 확인하고 Idempotent하게 재시도되는지 검증한다.
26. Multiple Draft와 Multiple Export Operation에서 한 Result Artifact의 Recovery, Cleanup 또는 Project Delete가 다른 Result Artifact나 External Photos Result에 영향을 주지 않게 한다.
27. Relaunch에서 Missing, Corrupt 또는 Unreadable Committed Media를 기존 Timeline Position의 Unavailable Clip으로 유지하고 Project, Healthy Clip과 다른 Draft를 보호한다.
28. Metadata 없는 Media를 자동 User-visible Clip으로 노출하지 않고 ADR-020 Recovery Candidate와 True Missing / Corrupt Media를 구분한다.
29. All-unavailable Project가 자동 삭제되지 않고 새 Direct Recording, Photos Import, Replace와 Delete를 허용하며 Full Preview와 Export는 Block되는지 검증한다.
30. Replacement 중 Crash, Storage Failure, Cancellation 또는 Interruption이 기존 Unavailable Placeholder, Healthy Clip과 Project를 손상시키지 않는지 검증한다.
31. Project Metadata Read, Decode 또는 Persistence Failure가 Home / Recent 전체 Load, 다른 Draft 또는 다른 Project Media Cleanup에 전파되지 않게 한다.

## Tests

- Missing Media
- Corrupt Media
- Metadata 없는 Valid Staging / Materialized Media의 Recovery Classification
- Confirmed Orphan과 Known Disposable Artifact의 안전한 Cleanup
- Interrupted Save
- 각 Commit Boundary에서 Forced Termination 후 Repeated Relaunch
- Metadata Save 직전 / 직후 Recovery와 Duplicate Commit 방지
- Normalization 실패 후 Valid Source 보존
- Cleanup Failure / Retry와 Cleanup Idempotency
- Pending Deletion Relaunch
- Multiple Draft Recovery
- Multiple Draft Isolation
- Deleted / Nonexistent Project Late Result의 Project 재생성 및 Commit 차단
- Project Delete Cleanup
- Pending Deletion 중 Process Termination 후 Undo / Clip 비복원
- Logical Project Deletion 이후 Metadata / Media 정리 경계별 Forced Termination
- Deferred Physical Delete의 Repeated Relaunch Reconciliation
- Project Cleanup Failure / Retry와 이미 삭제된 Target의 반복 처리
- Stale Async Result Discard와 다른 Draft Isolation
- Repeated Low-storage Launch와 기존 Draft / Committed Media 보존
- Storage Change Between Preflight and Write 및 반복 Runtime Disk Full / Space Recovery / Retry
- Failed Cleanup과 Stale Disposable Artifact의 Idempotent Reconciliation
- Recovery Candidate / Undo Candidate / Active Media / Referenced Media 보호
- Confirmed Orphan만 안전 조건 충족 후 정리
- Storage Pressure에서 Multiple Draft Isolation과 User Draft 자동 삭제 금지
- Export Rendering 중 Crash
- Render 완료 후 Result State Persistence 전 Crash
- Photos Save Failure 후 Crash
- Photos Save Success 후 Local Artifact Cleanup 전 Crash
- Repeated Relaunch에서 Unresolved Valid Artifact 보존과 Duplicate Export Result / automatic duplicate Photos Save 방지
- Active Consumer, Retry와 Recovery Requirement를 고려한 Export Artifact Cleanup Idempotency
- Multiple Draft / Multiple Export Operation Result Artifact Isolation
- Missing / Corrupt / Unreadable Media의 Unavailable Clip 유지와 Original Timeline Position
- All-unavailable Project의 Draft 보존, Full Preview / Export Block과 새 Direct Recording / Photos Import
- Replacement Crash, Storage Failure, Cancellation과 Placeholder Preservation
- True Missing / Corrupt Media와 Metadata 없는 Recovery Candidate의 분리
- Project-level Metadata Corruption Isolation과 다른 Draft 보호

## Physical Device Test

- App 강제 종료
- Device Restart 후 Draft 복구
- 여러 Draft 생성
- 대용량 Draft
- Photos 원본 삭제 이후 Imported Clip 확인
- Recording / Import 저장 경계별 강제 종료와 반복 Relaunch 후 Clip 중복 및 정상 Media 유실 여부
- Undo Window 중 강제 종료와 Project Delete Cleanup 실패 후 반복 Relaunch
- 반복 Low-storage Launch와 기존 Draft / Committed Media 보존
- Preflight 이후 Storage 변화 및 Runtime Disk Full 반복 후 공간 확보와 Retry
- Failed Cleanup / Stale Disposable / Confirmed Orphan Reconciliation과 Multiple Draft Isolation
- Render, Result State Persistence, Photos Save Failure와 Photos Save Success 후 Cleanup 경계에서 Forced Termination과 Repeated Relaunch
- Multiple Export Operation과 Project Delete가 Active Save / Share Artifact에 미치는 영향
- Missing / Corrupt Media와 All-unavailable Project의 Relaunch 후 Unavailable 상태, Replace / Delete 및 Healthy Clip 보호
- Replacement 중 강제 종료, Storage Failure, Cancellation과 Placeholder Preservation
- Project-level Metadata Corruption이 Home / Recent와 다른 Draft에 미치는 격리 결과

## Acceptance Criteria

- 정상 저장된 Draft가 App Relaunch로 유실되지 않는다.
- 하나의 손상 File로 전체 앱이 실패하지 않는다.
- Project Delete 후 Active Usage와 Recovery 필요가 남아 있는 Media를 보존하고 모든 Physical Delete 안전 조건을 충족하면 Cleanup / Retry로 삭제 대상 Project-owned Media를 정리할 수 있다.
- Temporary File이 무한히 누적되지 않는다.
- 반복 Recovery가 동일 Clip 또는 동일 Media를 중복 등록하지 않는다.
- Metadata가 없는 Valid Media는 Recovery 판정 전에 Orphan으로 삭제되지 않는다.
- Confirmed Disposable Artifact의 반복 Cleanup과 실패 후 재시도가 정상 Committed Media의 유효성을 변경하지 않는다.
- 한 Draft의 실패 또는 손상이 다른 Draft의 정상 상태에 영향을 주지 않는다.
- Process Termination 후 Pending Deletion을 처리해도 Undo Opportunity와 삭제된 Clip이 다시 표시되지 않는다.
- Cleanup 실패 또는 Late Result가 Logical Deleted Project를 다시 생성하지 않는다.
- Deletion / Cleanup을 반복해도 중복 상태나 이미 삭제된 Artifact의 오류가 반복되지 않는다.
- 반복 Low-storage Launch와 Runtime Disk Full / Retry에서도 기존 Draft, Committed Media와 Recovery Candidate가 보존된다.
- Storage Pressure 때문에 User Draft를 자동 삭제하거나 Recovery / Undo / Active Usage / Reference 확인을 생략하지 않는다.
- Failed Cleanup, Stale Disposable Artifact와 Confirmed Orphan Reconciliation이 Idempotent하고 다른 Draft에 영향을 주지 않는다.
- Preflight 이후 실제 Write 전 Storage가 변해도 Partial Result를 성공으로 Commit하지 않는다.
- Valid Unresolved Local Export Artifact는 Result Metadata 부재만으로 Orphan으로 삭제되지 않으며 Repeated Relaunch가 Duplicate Export Result 또는 automatic duplicate Photos Save를 만들지 않는다.
- Photos Save Success 이전과 이후의 Result Artifact Cleanup은 Active Consumer, Retry와 Recovery Requirement를 따르고 Idempotent하다.
- 한 Project의 Export Result Recovery, Cleanup 또는 Project Delete가 다른 Project Result나 External Photos Result에 영향을 주지 않는다.
- Missing, Corrupt 또는 Unreadable Media는 기존 Timeline Position의 Unavailable Clip으로 유지되고 자동 Delete, 자동 대체 또는 Silent Skip이 발생하지 않는다.
- All-unavailable Project는 Draft로 유지하고 새 Direct Recording, Photos Import, Replace와 Delete를 허용하며 Full Preview와 Export는 Block한다.
- Replacement Crash 또는 Failure는 기존 Placeholder, Healthy Clip과 Project를 보존한다.
- Metadata 없는 Media는 ADR-020 Recovery Candidate 판정 전에 User-visible Clip으로 노출하지 않는다.
- Project-level Metadata Corruption은 Home / Recent 전체 Load, 다른 Draft와 다른 Project Media에 영향을 주지 않는다.

## Exit Criteria

Draft Persistence가 실제 장기 사용을 견딜 수 있는 수준이어야 한다.

Phase 4 / 6의 Media Commit 계약을 유지하면서 Forced Termination, Repeated Relaunch, Recovery Classification, Unavailable Clip과 Project-level Failure Isolation, Duplicate Prevention, Cleanup Idempotency와 Multiple Draft Isolation 검증이 통과해야 한다.

Phase 5 / 8 / 9의 Logical Deletion과 Active Media Lifetime 계약을 반복 Deletion / Relaunch / Cleanup Retry 조건에서 검증해야 한다.

Phase 4 / 6 / 9의 ADR-024 Storage 계약과 ADR-025 Export Result Artifact Lifecycle을 반복 Low-storage Launch, Storage Change Between Preflight and Write, Runtime Disk Full / Retry, Failed Cleanup, Forced Termination, Repeated Relaunch과 Multiple Draft / Export Operation Isolation 조건에서 검증해야 한다.

---

# Phase 11 — Permissions, Errors, and Interruptions

## Goal

정상 Flow 밖의 실제 iPhone 상황에서 Mellow가 안전하고 이해 가능하게 동작하도록 한다.

이 Phase는 ADR-023의 Camera / Microphone Permission, Rear Zoom, Front Mirroring, Orientation과 Interruption 기본 정책이나 ADR-025의 Photos Save Failure Result Semantics를 처음 결정하지 않으며 기존 동작을 실제 실패·복구 조건에서 강화한다.

## Included

- Camera Permission
- Microphone Permission
- Photos Save Permission
- Permission Denied UX
- Settings Deep Link
- Camera Interruption
- Recording Failure
- Import Failure
- Export Failure
- Storage Error
- Typed Error Mapping
- User-facing Copy
- Permission Change Recovery
- Camera Resource Unavailable
- Session / App Lifecycle Recovery
- Relevant Rear Zoom State Recovery
- Photos Permission / Status Change during Save
- Photos Save Error
- Observable Share Handoff Failure
- App Lifecycle Interruption during Export Result Workflow

## Explicitly Excluded

- 서버 오류
- Account 오류
- Cloud 오류

## Decision Gate Before Implementation

Recording Interruption에서 Validation을 통과한 Partial Clip을 Commit할지 폐기할지와 Minimum Valid Clip Duration은 Phase 11 구현 전에 사용자 승인을 받아야 한다.

두 결정은 Partial Media의 Validation 결과를 사용자 Project에 Committed Clip으로 연결할 수 있는지 함께 규정하므로 하나의 Gate에서 관계를 명확히 하되 이 Roadmap에서 결과나 Duration 값을 미리 확정하지 않는다.

Error / Interruption Haptic은 별도 Pending이며 이 Gate에서 Successful Manual Stop / Auto-stop의 기존 H04 Completion Haptic 정책을 변경하지 않는다.

## Implementation Tasks

1. `PermissionService`를 완성한다.
2. Permission은 사용 시점에 Contextual하게 요청한다.
3. Denied 상태에서 기능별 안내 UI를 구현한다.
4. 필요한 경우 Settings 이동 Action을 제공한다.
5. Low-level Error를 Typed Application Error로 Mapping한다.
6. Recording Interruption을 사용자에게 설명한다.
7. Import 실패 후 Retry 가능 상태를 제공한다.
8. Export 실패 후 Retry 가능 상태를 제공한다.
9. Storage 부족 시 명확한 메시지를 제공한다.
10. Technical Error String을 사용자에게 직접 노출하지 않는다.
11. 기존 Permission / Error 안내와 Settings / Retry Controls에 3.11절과 `DESIGN.md` 33절의 기존 Accessibility 기준을 처음부터 적용한다.
12. Camera / Microphone의 Denied, Restricted와 실행 중 Authorization Change에서 Direct Recording을 안전하게 차단하고 Capture Pipeline이 부분적으로 시작되거나 무음 Recording으로 전환되지 않게 한다.
13. Camera / Microphone Permission 문제와 무관하게 Photos Import가 접근 가능한지 검증한다.
14. Camera Resource Unavailable, Session Interruption, App Background / Foreground 전환에서 Active Capture를 안전하게 종료 또는 복구하고 Late Result에 ADR-020 / ADR-021을 적용한다.
15. Interruption 결과를 Successful Manual / Auto-stop으로 표시하거나 Completion Haptic을 자동 발생시키지 않고 승인된 Partial Clip / Minimum Duration Gate 결과를 적용한다.
16. Capture / Session Recovery 이후 Rear Zoom State를 복구해야 하는 경우 승인 Range를 유지하고 Device의 이론적 Maximum을 Product Maximum으로 사용하지 않는다.
17. Permission 변경 또는 Session Recovery 후 새 Recording 전에 Camera / Microphone Readiness, Project Validity와 Orientation Eligibility를 다시 검사한다.
18. Photos Permission 또는 Status Change와 Photos Save Error를 Typed Error로 Mapping하되 ADR-025의 Successful Render, Local Artifact 유지, Save Retry와 Share 가능 상태를 변경하지 않는다.
19. 관찰 가능한 Share Handoff Failure와 App Lifecycle Interruption 중 Result Workflow를 처리하되 External App Final Delivery를 보장하거나 Share Cancel을 Export Failure로 표시하지 않는다.
20. Result Workflow의 Permission / Error / Retry Controls가 Local Export Artifact Active Consumer와 Cleanup Safety를 위반하지 않는지 검증한다.

## Tests

- 모든 Permission State
- Error Mapping
- Retry Flow
- Storage Error State
- Camera / Microphone Denied / Restricted / Authorization Change
- Permission 실패에서 Direct Recording 미시작, 무음 Fallback 없음과 Photos Import 독립성
- Resource Unavailable / Session Interruption / App Lifecycle Recovery
- Interruption과 Successful Completion / Completion Haptic 분리
- 승인된 Partial Clip / Minimum Duration Policy 적용
- Session Recovery 이후 Rear Zoom Range / State 및 다음 Recording Readiness 재검증
- Photos Permission / Status Change와 Photos Save Error가 Successful Render와 Photos Save Failure를 혼동하지 않는지 확인
- Observable Share Handoff Failure와 Result Workflow App Lifecycle Interruption
- Result Workflow Error / Retry Control 중 Active Consumer와 Artifact Cleanup Safety

## Physical Device Test

- Camera Deny
- Microphone Deny
- Photos Save Deny
- Permission Re-enable
- 전화 또는 유사 System Interruption 가능한 범위
- App Background Recording Interruption
- Camera Resource Unavailable과 Session Recovery 가능한 범위
- Camera / Microphone Permission Denied 상태에서도 Photos Import 접근 가능
- Permission 재활성화 후 Orientation Gate를 포함한 Recording Readiness 재검증
- Rear Zoom 사용 중 Capture / Session Interruption과 Recovery 후 승인 Range 유지 여부
- Photos Save Permission / Status Change, Photos Save Failure 후 Save Retry와 Share
- Result Workflow 중 App Background / Foreground 전환과 가능한 Share Handoff Failure

## UI Accessibility Verification

기존 Permission / Error 안내와 Settings / Retry Controls에서 3.11절의 Touch Target, VoiceOver Label / 식별, Dynamic Type, Color 이외 상태 표현과 Contrast를 검증하고 해당 Motion의 Reduce Motion 대응을 검토·검증한다.

현재 Phase에서 지원하는 Orientation을 기준으로 기존 Safe Area 요구사항을 확인하고 적용 범위와 실제 검증 결과를 기록하며 기존 iPhone 12 Device Gate를 유지한다.

## Acceptance Criteria

- Permission Denied가 Crash 또는 빈 화면으로 이어지지 않는다.
- 사용자가 다음 행동을 이해할 수 있다.
- Recording Failure가 기존 정상 Clip을 손상시키지 않는다.
- Error 메시지에 내부 Framework 용어가 노출되지 않는다.
- Camera 또는 Microphone Permission이 없으면 Direct Recording이나 무음 Fallback이 시작되지 않고 Photos Import는 계속 접근할 수 있다.
- Permission Change, Resource Unavailable, Session / App Lifecycle Interruption 이후 현재 Operation과 기존 Draft가 손상되지 않으며 다음 Recording 전에 Readiness를 다시 검사한다.
- Interruption은 Successful Manual / Auto-stop이나 Completion Haptic으로 표시되지 않고 결과 Media가 ADR-020 / ADR-021 및 승인된 Partial Clip Gate를 따른다.
- Capture / Session Recovery에서 Rear Zoom은 승인된 Product Range를 벗어나지 않는다.
- Photos Save Error와 Permission / Status Change는 ADR-025의 Render Success를 실패로 바꾸지 않고 Valid Local Export Artifact, Save Retry와 Share 가능 상태를 유지한다.
- 관찰 가능한 Share Handoff Failure 또는 Result Workflow App Lifecycle Interruption이 Active Artifact를 조기 Cleanup하거나 External Result를 삭제하지 않는다.

- 해당 UI의 기존 Accessibility 기준 적용과 위 검증이 완료되며 미해결 사항을 Phase 12의 최초 구현 작업으로 미루지 않는다.

## Exit Criteria

주요 Failure Path가 정의되고 테스트되어야 한다.

ADR-023의 Permission / Interruption / Session Recovery 계약, ADR-025의 Photos Save / Share Error Semantics와 승인된 Partial Clip / Minimum Duration Gate 결과가 실제 iPhone 12에서 검증되어야 한다.

해당 화면의 기존 Accessibility 검증 결과와 필요한 iPhone 12 확인이 완료되어야 한다.

---

# Phase 12 — UI Polish, Accessibility, and Haptics

## Goal

기능적으로 완성된 MVP를 Mellow의 브랜드와 디자인 원칙에 맞는 제품 수준의 사용자 경험으로 정리한다.

이 Phase의 역할은 이미 승인·구현된 구조의 Visual Polish, 화면 간 일관성, Interaction Quality와 Accessibility Regression / Hardening이다.

Home Primary Layout, Camera Control Structure, Recording Core Interaction, Clip Management, Trim / Framing Interaction, Preview Core Controls와 Export Completion Structure는 각각의 Owning Phase 구현 전에 결정되어 있어야 한다.

Phase 12에서 이러한 구조를 처음 선택하거나 대규모 Structural Redesign을 수행하지 않으며 필요성이 확인되면 일반 Polish로 처리하지 않고 기존 Exception and Replanning Protocol에 따라 보고하고 사용자 승인을 받는다.

## Included

- Brand Color Token Refinement
- Non-structural Typography Refinement
- Non-blocking Corner Radius Tuning
- Spacing Refinement
- Home Polish
- Recent Visual Polish
- Camera Overlay Polish
- Progress Ring Polish
- 승인된 Completion Haptic의 Subtlety / Consistency Tuning
- Subtle Motion / Animation Refinement
- 기존 Empty / Loading State의 Visual Polish
- Cross-screen / Component Consistency
- Orientation-specific Visual Polish
- Final Interaction Quality Pass
- VoiceOver Regression / Hardening
- Dynamic Type Regression / Hardening
- Contrast Consistency Verification
- Reduce Motion Regression / Hardening

## Explicitly Excluded

- 새 기능 추가
- 새로운 편집 기능
- 필터
- 음악
- 자막
- Transition
- Core UX Structure의 최초 결정 또는 승인 없는 Structural Redesign

## Decision Gate Before Implementation

이전 UI Phase의 Structural UX Gate와 해당 화면의 기존 Accessibility 적용·검증이 완료되었는지 확인한다.

다음 항목은 승인된 구조를 유지하는 비구조적 Refinement 범위에서 조정하며 Layout / Interaction 구조나 Accessibility 기준에 영향을 주면 일반 Polish로 확정하지 않는다.

- Home / Recent / Camera / Trim / Preview / Export의 Spacing와 Visual Balance
- 승인된 Trim Interaction 안에서의 Handle 등 세부 Visual Tuning
- 승인된 Completion Haptic의 Subtlety / Consistency Tuning
- 최종 Color Palette
- Non-structural Typography Tuning
- Non-blocking Corner Radius Tuning
- Subtle Motion / Animation Polish

Recording Haptic 사용 여부와 Completion 의미는 Phase 4 이전에 승인된 정책을 따르며 Phase 12에서는 Subtlety, Consistency, Perceived Quality와 Accessibility Regression만 다듬는다.

Start Haptic 추가 등 승인된 의미 변경은 일반 Polish가 아니라 Exception and Replanning Protocol에 따른 사용자 승인 대상이며 Error / Interruption Haptic은 별도 Pending으로 유지한다.

Recent List / Grid, New Vlog Placement, Camera Control Placement, Trim / Framing 구조, Preview Controls와 Export Completion 구조는 이 Phase의 최초 결정 Gate가 아니다.

## Implementation Tasks

1. 승인된 구조를 유지하는 범위에서 Design Tokens를 다듬는다.
2. Brand Screen과 Content Screen의 색상 사용을 구분한다.
3. Home과 Recent를 다듬는다.
4. Orientation Selection을 다듬는다.
5. Camera Overlay를 최소화한다.
6. Recording Progress와 승인된 Completion Haptic의 Subtlety / Consistency / Perceived Quality를 실제 Device에서 다듬고 Haptic에 의존하지 않는 기존 Visual Feedback의 Accessibility Regression을 확인한다.
7. ADR-026으로 확정된 Empty Project와 Unavailable Clip 동작을 유지한 채 이미 정의된 Loading State와 Empty State의 Visual만 다듬으며 Exact Unavailable UI나 Replace UI 구조를 새로 선택하지 않는다.
8. Motion을 Reduce Motion 환경에서 검증한다.
9. 각 UI Phase에서 이미 적용한 VoiceOver Label과 Control 식별을 전체 화면에서 회귀 검증한다.
10. 이미 적용한 Touch Target과 Contrast 및 Color 이외 상태 표현의 화면 간 일관성을 점검한다.
11. 각 UI Phase에서 적용한 Dynamic Type을 핵심 Flow와 Edge Case에서 종합 검증한다.
12. Portrait / Landscape Safe Area와 Orientation별 Visual 일관성을 회귀 검증한다.
13. Component Consistency와 최종 Interaction Quality를 확인하고 구조 변경이 필요하면 Replanning 대상으로 보고한다.

## Physical Device Test

iPhone 12에서 모든 핵심 화면을 Portrait 및 Landscape Project 기준으로 확인한다.

이미 적용된 VoiceOver / Dynamic Type / Touch Target / Contrast와 Reduce Motion 대응을 종합 검증하고 화면 간 Regression과 Edge Case 결과를 기록한다.

## Acceptance Criteria

- UI가 Mellow의 Calm / Warm / Minimal 방향과 일치한다.
- Camera 화면은 영상보다 강하게 보이지 않는다.
- 주요 기능을 VoiceOver로 식별할 수 있다.
- Dynamic Type에서 핵심 Flow를 사용할 수 있다.
- Haptic이 과도하지 않다.
- Start Haptic 없음과 Successful Manual Stop / 10-second Auto-stop의 동일한 Completion 의미가 유지되며 Haptic 사용 여부를 처음 결정하지 않는다.
- 새 기능이 추가되지 않는다.
- Accessibility가 각 UI Phase부터 적용되었으며 이 Phase의 종합 Regression / Hardening 결과가 확인된다.
- Core UX Structure를 처음 선택하거나 일반 Polish로 재설계하지 않는다.

## Exit Criteria

기능 완성도를 해치지 않으면서 UI 품질이 제품 수준에 도달해야 한다.

기존 화면 구조를 유지하면서 Cross-screen Consistency와 Accessibility Regression / Hardening 검증이 완료되어야 하며 구조 변경이 필요한 경우 Replanning 승인 전에는 진행하지 않는다.

---

# Phase 13 — Performance and iPhone 12 Hardening

## Goal

iPhone 12를 실제 성능 기준 기기로 사용하여 Camera, Import, Preview, Export, Draft가 안정적으로 동작하도록 최적화한다.

## Included

- Memory Profiling
- CPU Profiling
- Export Timing
- Preview Startup
- Thumbnail Cost
- Camera Session Stability
- Storage Stress
- Large Project Stress
- Thermal Observation
- Main Thread Hitches

## Explicitly Excluded

- 최신 Pro 전용 최적화
- Benchmark 목적의 과도한 저수준 최적화
- 기능 변경

## Test Matrix

최소한 다음 Project를 만든다.

### Small Project

- 5 Clips
- 총 30초 이하

### Medium Project

- 20 Clips
- 총 2분 전후

### Large Project

- 60 Clips 이상
- 5분 이상

### Mixed Import Project

- Recorded Clip
- 1080p Import
- 4K Import
- 4K SDR Import
- 4K HDR / Dolby Vision Import
- Portrait Source
- Landscape Source

## Implementation Tasks

1. Instruments로 Main Thread Hitch를 확인한다.
2. Memory Graph를 확인한다.
3. Preview 준비 시간을 측정한다.
4. Export 시간을 측정한다.
5. Thumbnail Generation이 UI를 Block하지 않는지 확인한다.
6. Large Project에서 모든 Asset을 동시에 Load하지 않는지 확인한다.
7. 반복 Camera Open / Close를 테스트한다.
8. 반복 Front / Rear Switching을 테스트한다.
9. 4K SDR 및 4K HDR / Dolby Vision Import의 1080p-class / 30 fps / SDR Working Media 생성 시간, Memory Pressure와 Release 및 Thermal Behavior를 측정한다.
10. Export 반복 후 Temporary File Cleanup을 확인한다.
11. 비정상 발열이 지속되는 Flow를 조사한다.
12. 정규화된 SDR Working Media의 Preview Stability와 동일한 Project State의 Export Color / Framing Parity를 iPhone 12에서 검증한다.
13. 승인된 10초 Recording의 실제 Storage Growth를 측정하고 Phase 4 Estimate와 비교한다.
14. 4K SDR 및 4K HDR / Dolby Vision Source의 선택된 최대 10초 Segment Import에서 실제 Peak Additional Storage를 측정하고 Phase 6 Estimate와 비교한다.
15. Short / Medium / Large Project Export의 실제 Peak Additional Storage를 측정하고 Snapshot Duration / State 기반 Phase 9 Estimate와 비교한다.
16. Recording / Import / Export 각각의 관측값과 승인된 Safety Reserve가 Estimate Error, Filesystem Overhead, Metadata Persistence와 작은 예기치 않은 Temporary Growth에 합리적인 여유를 제공하는지 검토한다.
17. Recording / Import / Export를 반복하여 Operation-owned Temporary Artifact가 안전한 Cleanup 이후 비정상적으로 누적되지 않는지 측정한다.
18. 측정 결과가 기존 Estimate Formula나 Safety Reserve 변경을 요구하면 수치를 임의로 조정하지 않고 Exception and Replanning Protocol과 해당 Decision 기록을 따른다.

이 검증은 성능 측정 범위를 연결하는 것이며 새로운 수치 Threshold를 확정하지 않고 M07 Performance Threshold는 별도 Repair 대상으로 유지한다.

## Acceptance Criteria

- iPhone 12에서 일반 사용 중 반복적인 UI Freeze가 없다.
- Camera Preview가 안정적이다.
- Medium Project Preview가 실사용 가능하다.
- Large Project가 임의 Crash하지 않는다.
- Export 중 Memory Pressure로 반복 종료되지 않는다.
- App 사용 후 Temporary Media가 비정상적으로 누적되지 않는다.
- Recording 실제 Storage Growth, Import Normalization Peak Additional Storage와 Export Peak Additional Storage가 iPhone 12에서 측정되고 각 승인된 Estimate와 비교된다.
- Safety Reserve의 합리성이 실제 관측값과 반복 Operation / Cleanup 결과를 근거로 검토된다.
- Storage 측정 결과를 이유로 M07의 새로운 수치 Pass / Fail Threshold를 임의로 만들지 않는다.

## Exit Criteria

iPhone 12에서 핵심 Flow의 안정성과 성능이 QA 가능한 수준이어야 한다.

Recording / Import / Export의 실제 Peak Additional Storage, 승인된 Estimate 대비 관측값, Safety Reserve 합리성과 반복 Temporary Cleanup 결과가 기록되어야 하며 수치 변경이 필요하면 승인된 Replanning 절차를 따라야 한다.

---

# Phase 14 — Full MVP QA

## Goal

`FEATURES.md`의 MVP Completion Definition을 처음부터 끝까지 실제로 검증한다.

## Scope Freeze

이 Phase에서는 새로운 기능을 추가하지 않는다.

발견된 Issue는 Bug, UX Defect, Performance Defect, Documentation Mismatch로만 분류한다.

## End-to-End Scenario

1. Mellow를 실행한다.
2. 새로운 Vlog를 생성한다.
3. 9:16 또는 16:9를 선택한다.
4. Rear Camera로 Clip을 촬영한다.
5. Front Camera로 Clip을 촬영한다.
6. 10초 Auto Stop을 검증한다.
7. 여러 Clip을 추가한다.
8. Photos에서 기존 Video를 Import한다.
9. 긴 Video에서 최대 10초 구간을 선택한다.
10. 4K Video를 Import한다.
11. Imported Clip의 Framing을 조정한다.
12. Clip을 삭제하고 Undo한다.
13. Clip 순서를 변경한다.
14. 각 Clip을 Trim한다.
15. 전체 Vlog를 Preview한다.
16. App을 종료한다.
17. App을 다시 실행하여 Draft를 복구한다.
18. Preview를 다시 확인한다.
19. Vlog를 Export한다.
20. Photos에 저장한다.
21. Share Sheet를 연다.
22. Draft를 다시 열어 수정한다.
23. 다시 Export한다.

## QA Categories

- Functional
- Persistence
- Camera
- Audio
- Orientation
- Import
- Trim
- Framing
- Preview
- Export
- Permissions
- Storage
- Error Handling
- Accessibility
- Performance
- Regression

## Severity

### Blocker

데이터 유실, 반복 Crash, Recording 불가, Export 불가 등 MVP 사용 자체가 불가능한 문제다.

### High

핵심 Flow가 자주 실패하거나 결과가 잘못되는 문제다.

### Medium

우회 가능하지만 UX 또는 결과 품질이 명확히 저하되는 문제다.

### Low

Cosmetic 또는 작은 UX 문제다.

## Release Gate

- Blocker 0개
- High 0개
- 주요 Medium Issue는 승인 없이 남기지 않는다.
- 전체 Unit Tests 통과
- 전체 Integration Tests 통과
- UI Tests 통과
- iPhone 12 End-to-End Test 통과
- `git diff --check` 통과
- 문서와 실제 구현이 일치

## Exit Criteria

MVP Completion Definition의 모든 항목을 실제 iPhone 12에서 완료할 수 있어야 한다.

---

# Phase 15 — TestFlight Readiness

## Goal

완성된 MVP를 내부 TestFlight Build로 배포할 수 있는 상태로 준비한다.

## Included

- App Identity 확인
- Bundle Identifier 최종화
- App Icon
- Launch Experience
- Privacy Usage Description
- Camera Usage Description
- Microphone Usage Description
- Photos Usage Description
- Signing
- Version / Build Number
- Release Build
- Archive
- TestFlight Internal Build
- Basic Release Notes

## Explicitly Excluded

- App Store Public Release
- Marketing Campaign
- Subscription
- In-app Purchase
- Analytics SDK
- Server Backend

## Implementation Tasks

1. Bundle Identifier를 최종 확인한다.
2. App Icon Asset을 적용한다.
3. 필요한 Privacy Usage Description을 검토한다.
4. 사용하지 않는 Permission Description을 제거한다.
5. Signing 설정을 확인한다.
6. Release Configuration에서 Build한다.
7. Debug-only 코드가 남지 않았는지 확인한다.
8. Production Log에 민감한 정보가 없는지 확인한다.
9. Archive를 생성한다.
10. TestFlight Internal Testing용 Build를 업로드한다.
11. 설치 후 iPhone 12에서 Smoke Test를 수행한다.
12. Known Issues가 있다면 Release Notes에 기록한다.

## Acceptance Criteria

- Release Build가 성공한다.
- Archive가 성공한다.
- TestFlight Build가 설치된다.
- Camera와 Export가 TestFlight Build에서도 정상 동작한다.
- Privacy Description이 실제 기능과 일치한다.
- Debug Dependency가 없다.

## Exit Criteria

Mellow MVP를 내부 TestFlight에서 실제 테스트할 수 있어야 한다.

---

# Post-MVP Backlog

다음 기능은 MVP 완료 전에 현재 Phase로 끌어오지 않는다.

- Text Overlay
- Background Music
- Transitions
- Video Looks
- Templates
- Smart Editing
- Tap to Focus
- Exposure Control
- Front Camera Zoom
- Torch
- Advanced Camera Lens Selection
- Clip Split
- Clip Duplicate
- Fit Layout
- Background Blur
- 4K Export
- 60 fps Export
- iPad
- Android
- iCloud Sync
- Account
- Social Features
- Analytics SDK
- Subscription
- One-time Purchase

Backlog Feature가 필요해 보여도 MVP Scope를 변경하려면 별도의 승인과 관련 문서 수정이 필요하다.

---

# Backlog Intake Policy

새로운 아이디어는 발견 즉시 현재 MVP에 넣지 않는다.

Backlog Item은 최소한 다음 정보를 기록할 수 있다.

- 아이디어 또는 요청
- 어떤 문제를 해결하는가
- 어느 사용자에게 필요한가
- MVP에 반드시 필요한가
- 기존 Feature와 중복되는가
- Architecture 영향이 있는가
- 예상 구현 비용
- 현재 Roadmap에 넣지 않는 이유

MVP 개발 중 Backlog는 구현 Queue가 아니라 Scope 보호 장치로 사용한다.

MVP 완료 후 다음 Release Planning에서 우선순위를 다시 평가한다.

---

# Decision Gates Before Development Completion

다음 Decision은 관련 Phase 진입 전에 반드시 해결한다.

Structural UX는 해당 UI를 필요로 하는 가장 이른 Phase 전에 결정하며 아래 항목은 선택 결과가 아닌 Decision Timing을 나타낸다.

## Before Phase 2

- Recent List / Grid 및 구현 구조에 영향을 주는 Item 정보 Hierarchy
- New Vlog Primary Placement
- Orientation Selection과 기존 Project Delete Confirmation의 Presentation 구조

## Before Phase 3

- Camera Control Placement / Hierarchy와 Overlay 구조
- Front / Rear Switch 및 기존 진입 Control 배치
- Portrait / Landscape Camera Layout과 Orientation mismatch 안내 Presentation
- Rear Maximum Zoom Product Quality Limit을 iPhone 12 Preview 화질과 사용성으로 검증한 뒤 사용자 승인
- Rear Zoom Final Interaction / Visual Presentation이며 Pinch-to-zoom Candidate와 필요한 경우 Zoom Factor Indicator를 검토

ADR-023의 Rear 1× Wide / Continuous Zoom, Front Zoom 제외 / Mirroring, Permission과 Orientation High-level Behavior는 Accepted 상태이며 이 Gate에서 0.5× Ultra Wide / Telephoto / Lens Selector를 MVP 후보로 다시 열지 않는다.

## Before Phase 4

- Transactional Media Commit and Recovery 계약: ADR-020 Accepted 및 `ARCHITECTURE.md` 25절 / 59절을 기준으로 한다.
- Durable Operation Identity, Committed Clip 정의, Failure Boundary와 Recovery Classification의 기본 검증 범위를 Phase 4에서 확인한다.
- 최대 10초 Recording의 Estimated Peak Additional Storage 계산 방법, Recording Safety Reserve와 승인된 1080p / 30 fps Capture Profile의 관계를 실제 Media Writing 전에 승인한다.

이 Gate의 Transactional 계약과 ADR-024의 Operation-aware Storage 방향은 확정되어 있으며 구체적인 Durable Representation, Capture Codec / Bitrate 상수, Estimate Formula와 Safety Reserve bytes는 필요한 승인 Gate에서 실제 Pipeline Profile을 기준으로 결정한다.

### Structural UX Pending Before Recording

- 확정된 Circular Progress Ring의 Layout-level 표현
- 현재 녹화 시간 표시의 구체적인 Presentation 구조
- Clip 저장 완료 Feedback의 비 Haptic Presentation 구조
- Recording Storage 부족 상태와 공간 확보 후 Retry의 Presentation 구조

Camera Layout에 이미 영향을 주는 공통 구조는 Phase 3 이전에 결정하며 Recording Haptic은 H04에서 승인된 Start 없음 / Successful Manual Stop 및 10-second Auto-stop의 subtle completion 정책을 따른다.

Error / Interruption Haptic은 별도 Pending이며 정확한 Native iOS 구현과 승인된 의미 안의 Tuning은 Phase 4 구현 세부사항으로 남긴다.

## Before Phase 5

- Clip Organizer Layout과 Drag Reorder의 상세 Interaction 구조
- Delete Control Placement와 Snackbar / Toast 등 Undo Presentation Surface
- Project Duration / Add Clip 배치
- Unavailable Clip의 User-visible Representation과 Replace / Delete Action 접근 구조
- Replacement Clip Identity 또는 Slot Reference Model
- Replacement의 Trim, Framing, Transform, Thumbnail Metadata Preserve / Reset과 Reset Communication

ADR-021 / F-MVP-025의 Accepted Undo semantics와 정확한 Undo Window Duration의 Pending 상태를 유지한다.

ADR-026의 Empty Project와 Unavailable Clip High-level Behavior는 Accepted 상태이며 이 Gate에서 Replace 가능 여부, Placeholder 보존, 기존 Timeline Position 또는 Silent Skip 금지를 다시 Open으로 만들지 않는다.

## Before Phase 6

- Imported Clip Re-trim 범위
- Source Reference 유지 여부
- Working Media Codec
- Working Media Container
- 정확한 SDR Color Profile / Tagging
- Low-resolution Source Upscaling Policy
- 1080p-class Working Media의 정확한 Raster Dimension Rule
- 선택된 Segment와 승인된 Pipeline의 Peak Additional Storage를 반영한 Import Storage Estimate Formula
- Photos Import / Normalization에 필요한 Safety Reserve 정책

HDR / Dolby Vision Source 허용, SDR / 30 fps / 1080p-class Working 방향과 Project Crop bake-in 금지 / Framing 영역 보존은 ADR-022 Accepted 기준이다.

위 Technical Gate가 해결되기 전에는 실제 Normalization 구현을 시작하지 않으며 Tone-mapping의 필요한 미결정 사항도 관련 구현 전에 해결한다.

Import Estimate는 전체 Photos 원본 File을 Mellow Container에 무조건 복제한다고 가정하지 않고 선택된 최대 10초 Segment의 실제 Materialization / Normalization Pipeline을 기준으로 한다.

Phase 6에서 이미 구현하는 최소 Import Segment Selection의 Control / Interaction 구조와 Import Storage 부족 / 공간 확보 후 Retry의 Presentation 구조도 구현 전에 결정하고 그 구조에 영향을 주는 Trim / Crop 화면 분리 결정을 Phase 7이나 Phase 12로 미루지 않는다.

## Before Phase 7

- Trim과 Crop의 화면 구성
- Editing Framing에서 Pinch to Zoom MVP 포함 여부
- Primary Trim Interaction, Thumbnail Filmstrip / Scrubbing 구조와 Time Precision 표현
- Drag / Position Framing 세부 구조와 Crop Reset 필요 여부
- Portrait / Landscape Editing Control 배치

Phase 6에서 승인된 구간 선택 구조는 재사용하며 ADR-022의 Framing 영역 보존과 Metadata Editing 계약은 변경하지 않는다.

이 Phase의 Pinch to Zoom Pending은 Phase 7 Editing Framing Interaction에 관한 것으로 ADR-023의 Rear Capture Zoom Candidate와 별개다.

## Before Phase 8

- Full Preview Control Structure / Hierarchy
- Preview 진입·종료와 Project 화면 복귀 Navigation
- M01 Pending 중 해당 UI 구조에 영향을 주는 부분

Preview 기능 범위는 이번 Timing 보정으로 확정하지 않는다.

## Before Phase 9

- H.264 또는 HEVC
- File Container
- Export Bitrate 방향
- Audio Format
- Audio Bitrate
- Background Export 정책
- 재Export가 필요한 경우의 Export Retry 세부 정책
- Immutable Export Snapshot의 Project Duration / State와 승인된 Export Profile 기반 Export Storage Estimate Formula
- Temporary / Final Local Artifact와 Photos Save / Share Handoff까지의 Local Retention을 반영한 Export Safety Reserve 정책

HDR vs SDR은 ADR-022로 SDR 방향이 해결되었으며 Phase 9는 1080p / 30 fps / SDR Export와 Preview Color / Framing Parity를 검증한다.

정확한 SDR Profile / Tagging과 Working Media 세부 Gate는 Phase 6 이전에 해결하며 Working Media와 Export Codec / Container를 자동으로 동일하게 정하지 않는다.

Export Storage Estimate Formula와 Safety Reserve는 위 Codec / Container / Bitrate / Audio Profile 결정 후 실제 Export 구현 전에 승인하며 Local Storage Preflight가 Photos Save 성공을 보장한다고 해석하지 않는다.

### Structural Export UI Pending

- Export Action Placement와 Progress / Completion Presentation
- Exporting, local result ready, Saved to Photos, Photos save failed, Sharing과 Share cancelled / returned의 Result State Presentation
- Save Retry, Share / Done 배치와 unsaved Discard Confirmation 및 Storage Preflight Failure 상태의 UI 구조

Share / Done, Share Sheet와 Draft 유지 동작은 재결정하지 않으며 ADR-025의 Export Rendering, Photos Save, Share와 Local Artifact Lifecycle을 다시 Open으로 만들지 않는다.

Background Export, 재Export가 필요한 경우의 Retry 세부 정책과 Exact Result UI Copy는 Pending으로 유지한다.

## Before Phase 11

- Recording Interruption에서 Valid Partial Clip의 최종 Product 처리
- Minimum Valid Clip Duration

두 결정은 Partial Media를 정상 Clip으로 Commit할 수 있는 조건을 함께 규정하며 Phase 11 구현 전에 사용자 승인으로 해결하되 Error / Interruption Haptic은 별도 Pending으로 유지한다.

## Before Phase 12

- 이미 승인된 구조의 Spacing / Visual Balance와 화면 간 일관성 조정
- Final Color Palette
- Non-structural Typography Tuning
- Non-blocking Corner Radius Tuning
- Subtle Motion / Animation Polish
- 승인된 Completion Haptic의 Subtlety / Consistency Tuning

Home / Camera / Clip Management / Trim / Framing / Preview / Export의 Structural Decision은 앞선 Owning Phase Gate에서 해결되어 있어야 한다.

Phase 12는 기존 Accessibility의 종합 Regression / Hardening 단계이며 Haptic은 승인된 Completion 의미의 Polish만 수행하고 Start Haptic을 추가하지 않는다.

Haptic 의미 변경은 Replanning 대상이며 Error / Interruption Haptic은 별도 Pending으로 유지한다.

## Before Phase 15

- Bundle Identifier
- App Icon 최종본
- Privacy Copy
- TestFlight Metadata

Decision Gate가 해결되지 않은 상태에서는 해당 Phase 구현을 시작하지 않는다.

---

# Definition of Done

기능이 화면에 보인다는 이유만으로 완료 처리하지 않는다.

다음 조건을 모두 만족해야 완료로 본다.

- 요구사항이 구현되었다.
- 관련 Unit Test가 있다.
- 관련 Integration Test가 있다면 통과한다.
- UI Test 대상이면 통과한다.
- Compiler Warning이 없다.
- Error Path를 검토했다.
- Persistence가 필요한 기능은 Relaunch 후 유지된다.
- Media 기능은 Original Media를 손상시키지 않는다.
- Physical Device Test 대상이면 iPhone 12에서 검증했다.
- `git diff --check`가 통과한다.
- 관련 문서와 실제 구현이 일치한다.
- 현재 Phase / Change Set의 미해결 Blocker를 다음 Phase로 넘기지 않는다.
- 현재 범위의 필요한 Decision Gate가 해결되었고 Unresolved Blocking Decision 및 관련 Source of Truth 모순이 없다.

아직 Required Gate에 도달하지 않은 Future Phase-only Pending은 위 Merge Rule에 따라 기록된 상태로 남을 수 있으며 현재 완료 조건을 충족하는 것과 미래 Gate를 통과하는 것은 별도로 검증한다.

---

# Codex Execution Protocol

Codex는 각 Phase 시작 시 다음 순서로 작업한다.

1. 현재 `main`과 Git Status를 확인한다.
2. 현재 Phase의 문서 요구사항을 다시 읽는다.
3. 필요한 Branch를 생성한다.
4. 해당 Phase의 Implementation Plan을 짧게 보고한다.
5. Scope 밖의 작업은 하지 않는다.
6. 작은 단위로 구현한다.
7. 관련 Test를 함께 작성한다.
8. Build와 Test를 반복한다.
9. Phase Acceptance Criteria를 하나씩 확인한다.
10. Physical Device Test가 필요하면 자동으로 완료 처리하지 않고 사용자 테스트를 요청한다.
11. 사용자 테스트 결과를 반영한다.
12. Exit Criteria를 모두 충족하면 전체 Diff를 Review한다.
13. 변경 파일과 이유를 보고한다.
14. 사용자의 승인 후 Commit 또는 Merge를 진행한다.

Codex는 단순히 “구현 완료”라고 보고하지 않는다.

완료 보고에는 최소한 다음을 포함한다.

- 구현한 내용
- 변경한 파일
- 실행한 Test
- Test 결과
- iPhone 12 실기기 검증 필요 여부
- 남아 있는 Issue
- Open Decision
- 다음 Phase 진입 가능 여부

---

# Development Baseline and Freeze Policy

`ROADMAP.md`가 사용자 검토를 거쳐 확정되고 Commit된 시점을 Mellow MVP Development Baseline으로 취급한다.

Baseline 이후 다음 항목은 통제된 변경 절차 없이 수정하지 않는다.

- MVP Scope
- Phase 순서
- Confirmed Product Decisions
- Architecture Invariants
- Device Quality Baseline
- Video Standard
- Clip Duration Policy
- Orientation Policy
- Draft Retention Policy

Baseline 이후 문서 변경이 필요한 경우 단순 문구 수정인지 실제 Decision 변경인지 구분한다.

실제 Decision 변경이라면 Exception and Replanning Protocol을 따른다.

---

# Roadmap Completion

Mellow MVP Roadmap은 Phase 0부터 Phase 15까지 순차적으로 완료될 때 종료된다.

Phase를 건너뛰거나 여러 Phase를 한 번에 완료 처리하지 않는다.

MVP 완료 후 새로운 제품 기능을 시작하기 전에 `PRODUCT.md`, `FEATURES.md`, `DECISIONS.md`를 다시 검토하고 다음 Release 범위를 별도로 정의한다.
