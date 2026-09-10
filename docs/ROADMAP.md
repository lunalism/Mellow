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
- 다음 Phase의 Decision Gate가 준비되었는가?

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
| Accessibility / Haptics / Visual Polish | Phase 12 |
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

## Unit Tests

- Recent Sorting
- New Portrait Project
- New Landscape Project
- 자동 Project Name
- Project Delete

## UI Tests

- Empty Home → New Vlog → 9:16
- Empty Home → New Vlog → 16:9
- Recent Project 재진입
- Project 삭제 Confirmation

## Physical Device Test

- iPhone 12에서 Portrait Home 사용성 확인
- Orientation Selection UI 확인
- Dynamic Type 기본 범위 확인

## Acceptance Criteria

- 사용자가 새 Vlog를 이름 입력 없이 만들 수 있다.
- 9:16과 16:9 Project가 올바르게 생성된다.
- 여러 Draft가 Recent에 표시된다.
- App 재실행 후 Recent가 유지된다.
- Project 삭제가 정상 동작한다.

## Exit Criteria

Camera 없이도 Project Lifecycle의 기본 흐름이 완성되어야 한다.

---

# Phase 3 — Camera Foundation

## Goal

실제 촬영을 시작하기 전 안정적인 Camera Session과 Preview 기반을 구현한다.

## Included

- Camera Permission
- Microphone Permission 상태 기반
- Rear Camera Preview
- Front Camera Preview
- Front / Rear Switching
- Camera Session Lifecycle
- Device Orientation Detection
- Orientation Mismatch State
- SwiftUI Preview Bridge

## Explicitly Excluded

- 실제 Video Recording
- 10초 Timer
- Audio Recording File
- Clip 저장
- Import
- Zoom
- Tap to Focus
- Exposure Control
- Torch
- Dual Camera

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

## Unit Tests

- Camera Position State
- Orientation Mismatch Policy
- Permission State Mapping
- Camera Switch State Rule

## UI Tests

실제 Camera 대신 Mock Camera Service를 사용한다.

- Permission Granted State
- Permission Denied State
- Rear / Front Switching UI
- Orientation Mismatch UI

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- Rear Preview
- Front Preview
- Front / Rear Switching
- Portrait Project에서 Orientation 안내
- Landscape Project에서 Orientation 안내
- Background / Foreground Session 복구

## Acceptance Criteria

- Camera Preview가 안정적으로 표시된다.
- Front와 Rear Camera를 Recording이 없는 상태에서 전환할 수 있다.
- Session Start / Stop으로 UI가 Freeze되지 않는다.
- Project Orientation이 Device Rotation으로 변경되지 않는다.
- iPhone 12에서 Preview가 안정적이다.

## Exit Criteria

Recording 없이 Camera Infrastructure가 안정적으로 검증되어야 한다.

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
- Recording Haptic 기본 구현
- Interruption 기본 대응

## Explicitly Excluded

- Zoom
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
15. Recording Start / Stop Haptic을 최소 범위에서 구현한다.
16. 10초 종료 직전 Haptic은 디자인 결정 범위에서 최소한으로 적용한다.
17. Recording 중 App Background 또는 Session Interruption을 처리한다.
18. 가능한 경우 유효한 Partial Recording을 보호한다.
19. Completed Staging과 Materialized Media에서 중단된 Operation을 재실행 후 연결하여 가능한 후속 처리와 Metadata Commit을 재개한다.
20. 이미 Persist된 Clip은 기존 Metadata를 사용하고 Operation / Clip Identity로 Duplicate Commit을 방지한다.
21. Temporary / Intermediate Artifact는 Commit 또는 Recovery Classification 이후 폐기 가능하다고 확인된 경우에 정리하며 Cleanup 실패가 Committed Clip을 무효화하지 않게 한다.

Interruption으로 짧아진 Recording의 보존 여부는 기존 확정 Policy와 Validation을 따르며 불완전한 Write를 정상 Final Media로 승격하지 않는다.

## Unit Tests

- 10초 Recording Policy
- Manual Stop State
- Auto Stop State
- Recording Progress Calculation
- Invalid Recording Completion 처리
- Committed Clip 조건과 Progress State의 구분
- Operation / Clip Identity 기반 Duplicate Commit 방지

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

## Physical Device Test

iPhone 12에서 다음을 반드시 검증한다.

- Rear Camera 2초 Manual Stop
- Rear Camera 9초 Manual Stop
- Rear Camera 10초 Auto Stop
- Front Camera Recording
- Audio 정상 Recording
- 연속 여러 Clip 촬영
- Recording 후 즉시 다음 Recording
- Portrait 9:16 Project
- Landscape 16:9 Project
- Background Interruption
- Storage 부족 Simulation 가능한 범위
- 저장 경계에서 중단 후 Relaunch 시 Valid Staging / Materialized Media의 복구와 중복 Clip 방지

## Acceptance Criteria

- 모든 저장된 Clip은 최대 10초다.
- 10초 도달 시 Recording이 자동 종료된다.
- Manual Stop이 안정적으로 동작한다.
- Video와 Audio가 정상 저장된다.
- Recording 중 Camera Switch는 불가능하다.
- 연속 Recording으로 App이 불안정해지지 않는다.
- iPhone 12에서 실제 촬영이 정상 동작한다.
- Committed Clip 조건을 모두 충족하기 전에는 Progress만 표시할 수 있으며 정상 Clip으로 노출하지 않는다.
- Durable Operation Identity로 재실행 후 Media와 Commit 상태를 연결할 수 있다.
- Metadata Save 직전 / 직후 실패 후에도 Valid Media가 잘못 정리되거나 Clip이 중복 등록되지 않는다.
- 기본 Failure Boundary Integration Test가 통과하며 Cleanup 실패가 저장 완료된 Clip을 무효화하지 않는다.

## Exit Criteria

직접 촬영만으로 여러 Clip을 Project에 안전하게 추가할 수 있어야 한다.

공통 Media Commit Lifecycle과 기본 Relaunch Recovery가 Production Recording 경로에 적용되고 위 Failure Boundary Test 및 iPhone 12 검증이 완료되어야 한다.

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

## Explicitly Excluded

- Import
- Trim
- Full Vlog Preview
- Export
- Split
- Duplicate
- Multi-track Timeline

## Implementation Tasks

1. `ThumbnailService`를 구현한다.
2. Thumbnail을 Cache Data로 관리한다.
3. Project 화면에서 Clip을 Thumbnail 중심으로 표시한다.
4. Clip Duration을 표시한다.
5. Clip Reorder Interaction을 구현한다.
6. Reorder 결과를 Persistence에 저장한다.
7. Clip Delete를 즉시 적용한다.
8. Pending Deletion 상태를 구현한다.
9. Undo를 제공한다.
10. Undo 기간 종료 후 Metadata와 Media를 최종 삭제한다.
11. App 종료 중 Pending Deletion 상태도 일관되게 정리한다.
12. Project Total Duration을 계산하여 표시한다.
13. Add Clip Action으로 Camera에 다시 진입할 수 있게 한다.

## Unit Tests

- Reorder
- Delete
- Undo
- Pending Deletion Cleanup
- Project Total Duration
- Autosave

## UI Tests

- Multiple Mock Clips
- Reorder
- Delete + Undo
- Add Clip 진입

## Physical Device Test

- 실제 촬영 Clip 10개 이상에서 스크롤 및 Reorder
- Thumbnail 생성 성능
- Delete + Undo 안정성

## Acceptance Criteria

- 여러 Clip의 순서를 변경할 수 있다.
- 삭제 후 Undo가 정상 동작한다.
- Undo 기간 종료 후 실제 Local Media가 정리된다.
- Project Duration이 정확하다.
- UI가 전문 Video Timeline처럼 복잡하지 않다.

## Exit Criteria

촬영한 Clip만으로 Project 구조를 안정적으로 관리할 수 있어야 한다.

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
- 4K Source 허용
- Project-owned Media Materialization
- 1080p Working Media
- Imported Clip 생성
- 공통 Media Commit Recovery 적용

## Explicitly Excluded

- Full Trim UX 완성
- Advanced Crop
- Fit Layout
- Blur Background
- Multi-selection Import

## Decision Gate Before Implementation

Imported Clip의 Re-trim 정책이 아직 확정되지 않았다면 이 Phase 시작 전에 반드시 결정한다.

선택지는 최소한 다음을 비교한다.

- Materialized 최대 10초 Segment 내부에서만 Re-trim
- Source Reference를 유지하여 원본 전체 범위 Re-trim 허용

사용자 승인 전에는 임의로 선택하지 않는다.

## Implementation Tasks

1. PhotosPicker 기반 Video Selection을 구현한다.
2. Broad Photos Read Permission 없이 가능한 Flow를 우선한다.
3. Source Video Duration과 Display Transform을 읽는다.
4. 4K Source를 정상적으로 다룰 수 있게 한다.
5. 사용자가 최대 10초 Segment를 선택할 수 있는 Import Editing State를 준비한다.
6. Add Clip 확정 후 공통 Media Commit Lifecycle을 시작하며 Media 작성 전에 Durable Operation Identity를 확보하고 Source Ownership과 Staging Write 완료 상태를 추적한 뒤 Source / Staged Media를 검증한다.
7. 검증된 Source / Staged Media에서 Working Media를 1080p 기준으로 정규화한다.
8. Source Frame Rate가 달라도 Project Output 30 fps 정책과 충돌하지 않게 한다.
9. Photos 원본을 변경하지 않는다.
10. Normalized Output의 Final Validation을 수행하고 안전한 Materialization 및 Project 유효성 확인 후 Metadata를 Persist하여 Committed Clip만 UI에 추가한다.
11. Import 취소 또는 실패 시 Ownership과 Recovery Classification을 확인하여 Discardable Temporary Artifact만 정리한다.
12. Import 실패 시 Project에 깨진 Clip Metadata를 남기지 않는다.
13. Normalization 실패 시 Valid Source / Staging을 보존하고 Incomplete Derived Output을 Final Media로 취급하지 않는다.
14. Materialization 이후 Metadata Persistence 실패 시 Recoverable Operation을 보존하여 Relaunch에서 Metadata Commit을 재개한다.
15. 동일 Operation의 반복 Recovery가 Duplicate Clip을 생성하지 않고 삭제되었거나 존재하지 않는 Project에 Late Result를 등록하지 않도록 한다.

복구를 위한 Valid Source 보존은 진행 중이거나 복구 가능한 Operation에 대한 계약이며 Commit 이후 Source Reference와 Re-trim 범위는 이 Phase의 별도 Decision Gate를 따른다.

## Unit Tests

- Import State
- 10초 Segment Validation
- Source Metadata Mapping
- Imported Clip SourceKind

## Integration Tests

- 720p Source
- 1080p Source
- 4K Source
- Portrait Source
- Landscape Source
- 60 fps Source
- 10초 미만 Source
- 10초 초과 Source
- 4K → 1080p Working Media
- Source / Staged Media와 Normalized Output의 각각의 Validation
- Normalization 도중 실패 후 Valid Source 보존과 Incomplete Derived Output 분류
- Materialization 후 Metadata Failure 및 Relaunch에서 동일 Clip의 Commit 재개
- Metadata Save 성공 후 UI Update 전 중단과 중복 없는 Recovery
- Cancel / Failure 후 Discardable Temporary Artifact Cleanup과 Recoverable Media 보존
- 반복 Recovery / Cleanup의 Idempotency 및 Invalid Project Late Result의 Commit 차단

## Physical Device Test

iPhone 12에서 실제 Photos Library를 이용하여 검증한다.

Normalization 실패와 Materialization 후 Metadata Save 실패를 주입한 뒤 Relaunch하여 Valid Media 보존, 복구 및 Duplicate Clip 방지를 확인한다.

## Acceptance Criteria

- 긴 Video도 선택할 수 있다.
- Project에 들어가는 Clip은 최대 10초다.
- 4K Source에서 1080p Working Media가 정상 생성된다.
- Photos 원본 삭제가 Project-owned Media에 영향을 주지 않는다.
- Import 취소 또는 실패 시 Project가 손상되지 않는다.
- Normalization 실패가 Valid Source / Staging Media를 파괴하지 않는다.
- Materialization 이후 Metadata Persistence 실패를 복구할 수 있으며 Commit 완료 전 Clip을 정상 UI에 표시하지 않는다.
- Cancel / Failure Cleanup은 확인된 Discardable Artifact에만 적용되며 반복 수행해도 정상 Media와 Recovery Candidate를 훼손하지 않는다.

## Exit Criteria

촬영 Clip과 Imported Clip이 동일한 Project에서 함께 관리되어야 한다.

Import Production Pipeline이 공통 Media Commit 계약을 따르고 Failure Recovery Integration Test 및 iPhone 12 검증이 완료되어야 한다.

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

## Implementation Tasks

1. `trimStart`와 `trimDuration` Editing State를 구현한다.
2. Trim 범위가 10초를 초과하지 않도록 한다.
3. Recorded Clip Re-trim을 구현한다.
4. Imported Clip Re-trim을 확정된 정책에 따라 구현한다.
5. Framing Metadata를 Normalized Coordinate로 저장한다.
6. Fill + Crop Transform을 구현한다.
7. Source `preferredTransform`을 고려한다.
8. Portrait Source와 Landscape Source를 올바르게 처리한다.
9. Trim과 Framing 변경사항을 Interaction 종료 시 Autosave한다.
10. Preview 중 원본 Media를 수정하지 않는다.

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

## Physical Device Test

- Trim Handle Interaction
- Framing Drag
- 9:16 Project
- 16:9 Project
- iPhone 12 UI Responsiveness

## Acceptance Criteria

- 모든 Clip을 비파괴적으로 Trim할 수 있다.
- Trim 결과는 최대 10초를 초과하지 않는다.
- 다른 Aspect Ratio Source가 Fill + Crop으로 올바르게 보인다.
- 사용자가 Framing을 조절할 수 있다.
- Trim과 Framing 변경이 App 재실행 후 유지된다.

## Exit Criteria

Project의 모든 Clip이 최종 Vlog에 사용될 정확한 Time Range와 Framing을 가져야 한다.

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
- Play / Pause / Seek 기본 UX

## Explicitly Excluded

- Transition
- Music
- Text
- Filter
- Rendered Preview Cache unless performance issue proves need

## Implementation Tasks

1. `VideoCompositionBuilder`를 구현한다.
2. Project Metadata에서 Virtual Timeline을 구성한다.
3. 모든 Clip Order를 반영한다.
4. Trim Range를 적용한다.
5. Source Display Transform을 정규화한다.
6. Project Orientation에 맞는 1080p Canvas를 생성한다.
7. Fill + Crop과 Framing을 적용한다.
8. Audio Track을 유지한다.
9. AVPlayer로 Composition Preview를 구현한다.
10. Project 변경 시 Composition을 안전하게 Rebuild한다.
11. Composition Build는 Main Actor를 장시간 Block하지 않는다.

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

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- Preview 시작 시간
- 20개 이상 Clip Project
- Scrubbing 또는 Seek
- Orientation
- Audio Sync
- UI Freeze 여부
- Memory Pressure 여부

## Acceptance Criteria

- Preview 결과가 Project Metadata와 일치한다.
- Clip 사이 재생이 정상적이다.
- Audio Sync가 유지된다.
- Preview를 위해 매번 하나의 완성 Video를 미리 Render하지 않는다.
- iPhone 12에서 실사용 가능한 성능을 보인다.

## Exit Criteria

사용자가 Export 전에 현재 Vlog 결과를 신뢰할 수 있어야 한다.

---

# Phase 9 — Export, Photos Save, and Share

## Goal

Preview와 동일한 결과를 하나의 1080p 30 fps Video로 Export하고 Photos에 저장하거나 공유할 수 있게 한다.

## Included

- Export Service
- Shared Composition
- 1080p Output
- 30 fps Output
- Temporary Export File
- Progress
- Cancel
- Photos Save
- Retry Photos Save
- Share Sheet
- Export Completion
- Draft 유지

## Decision Gate Before Implementation

다음 항목은 이 Phase 전에 반드시 확정한다.

- H.264 또는 HEVC
- File Container
- HDR / SDR 정책
- 기본 Video Bitrate 방향
- Audio Format 방향

## Implementation Tasks

1. Preview와 동일한 Composition Definition을 Export에 사용한다.
2. `AVAssetExportSession` 기반 MVP Export를 구현한다.
3. Portrait는 1080 × 1920으로 Export한다.
4. Landscape는 1920 × 1080으로 Export한다.
5. Output은 30 fps 정책을 따른다.
6. Export Result를 Temporary Location에 생성한다.
7. Progress State를 UI에 제공한다.
8. Export Cancel을 처리한다.
9. Export 성공 후 Photos에 저장한다.
10. Photos Save만 실패한 경우 Export File을 재사용하여 Retry한다.
11. iOS Share Sheet를 제공한다.
12. Export 성공 후 Draft를 삭제하지 않는다.
13. Temporary File Cleanup 정책을 적용한다.

## Unit Tests

- Export Profile
- Output Canvas
- Export State Machine
- Retry State

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

## Physical Device Test

iPhone 12에서 다음을 검증한다.

- 30초 Vlog
- 2분 이상 Vlog
- 20개 이상 Clip
- Photos Save
- Share Sheet
- Export Cancel
- Export Retry
- Storage 부족 상황 가능한 범위
- Background 이동 시 현재 정책

## Acceptance Criteria

- Export 결과가 Preview와 시각적으로 일치한다.
- Output Resolution이 정확하다.
- Photos Save가 정상 동작한다.
- Share Sheet가 정상 동작한다.
- Draft는 Export 이후에도 유지된다.
- 실패 시 이해 가능한 상태를 제공한다.

## Exit Criteria

Mellow의 핵심 End-to-End Flow가 처음으로 완성되어야 한다.

---

# Phase 10 — Draft Storage and Recovery Hardening

## Goal

여러 Draft와 Media File이 장기간 사용되어도 손상이나 유실 가능성을 최소화한다.

이 Phase는 Media Commit Lifecycle을 처음 만드는 단계가 아니며 Phase 4의 Recording과 Phase 6의 Import에 이미 적용된 계약을 강화한다.

## Included

- Project Storage Layout 검증
- Recovery Classification과 Confirmed Orphan Reconciliation 강화
- Missing / Corrupt File 처리
- App Relaunch Recovery
- Pending Deletion Recovery
- Temporary File Cleanup
- Storage Usage 기본 계산
- Large Draft 안정성
- Forced Termination과 Repeated Relaunch
- Duplicate Recovery Prevention
- Cleanup Idempotency
- Multiple Draft Isolation

## Explicitly Excluded

- iCloud Sync
- Backup Server
- Account
- Cross-device Sync

## Implementation Tasks

1. Phase 4 / 6의 Reconciliation을 기반으로 App Launch 시 Project Metadata, Media File과 Durable Operation State의 Consistency 검증을 강화한다.
2. Missing Media를 안전하게 표시한다.
3. 하나의 손상된 Clip이 Project 전체 Crash로 이어지지 않게 한다.
4. Metadata가 없는 Media의 Recovery Candidate 여부를 먼저 확인하고 Confirmed Orphan과 Discardable Temporary Artifact만 정리하는 기존 계약을 검증한다.
5. Pending Deletion 복구를 구현한다.
6. App 강제 종료 후 Draft를 재검증한다.
7. Export Temporary File Cleanup을 확인한다.
8. 여러 Draft의 Storage Usage를 계산할 수 있는 기반을 만든다.
9. Project Delete가 모든 Project-owned Media를 정리하는지 검증한다.
10. 주요 Media Commit 실패 경계에서 Forced Termination과 Repeated Relaunch를 수행하여 Staging / Materialized Media Recovery를 반복 검증한다.
11. 동일 Operation / Clip Identity의 반복 Recovery가 Duplicate Clip 또는 동일 Media의 중복 등록을 만들지 않는지 확인한다.
12. Cleanup 실패와 재시도 및 이미 정리된 Artifact를 검증하여 정상 Committed Media와 Recovery Candidate가 삭제되지 않게 한다.
13. 한 Draft의 Missing / Corrupt Media 또는 실패한 Operation이 다른 Draft의 정상 Media와 Metadata를 손상시키지 않는지 검증한다.

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

## Physical Device Test

- App 강제 종료
- Device Restart 후 Draft 복구
- 여러 Draft 생성
- 대용량 Draft
- Photos 원본 삭제 이후 Imported Clip 확인
- Recording / Import 저장 경계별 강제 종료와 반복 Relaunch 후 Clip 중복 및 정상 Media 유실 여부

## Acceptance Criteria

- 정상 저장된 Draft가 App Relaunch로 유실되지 않는다.
- 하나의 손상 File로 전체 앱이 실패하지 않는다.
- Project Delete 후 Project-owned Media가 남지 않는다.
- Temporary File이 무한히 누적되지 않는다.
- 반복 Recovery가 동일 Clip 또는 동일 Media를 중복 등록하지 않는다.
- Metadata가 없는 Valid Media는 Recovery 판정 전에 Orphan으로 삭제되지 않는다.
- Confirmed Disposable Artifact의 반복 Cleanup과 실패 후 재시도가 정상 Committed Media의 유효성을 변경하지 않는다.
- 한 Draft의 실패 또는 손상이 다른 Draft의 정상 상태에 영향을 주지 않는다.

## Exit Criteria

Draft Persistence가 실제 장기 사용을 견딜 수 있는 수준이어야 한다.

Phase 4 / 6의 Media Commit 계약을 유지하면서 Forced Termination, Repeated Relaunch, Recovery Classification, Duplicate Prevention, Cleanup Idempotency와 Multiple Draft Isolation 검증이 통과해야 한다.

---

# Phase 11 — Permissions, Errors, and Interruptions

## Goal

정상 Flow 밖의 실제 iPhone 상황에서 Mellow가 안전하고 이해 가능하게 동작하도록 한다.

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

## Explicitly Excluded

- 서버 오류
- Account 오류
- Cloud 오류

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

## Tests

- 모든 Permission State
- Error Mapping
- Retry Flow
- Storage Error State

## Physical Device Test

- Camera Deny
- Microphone Deny
- Photos Save Deny
- Permission Re-enable
- 전화 또는 유사 System Interruption 가능한 범위
- App Background Recording Interruption

## Acceptance Criteria

- Permission Denied가 Crash 또는 빈 화면으로 이어지지 않는다.
- 사용자가 다음 행동을 이해할 수 있다.
- Recording Failure가 기존 정상 Clip을 손상시키지 않는다.
- Error 메시지에 내부 Framework 용어가 노출되지 않는다.

## Exit Criteria

주요 Failure Path가 정의되고 테스트되어야 한다.

---

# Phase 12 — UI Polish, Accessibility, and Haptics

## Goal

기능적으로 완성된 MVP를 Mellow의 브랜드와 디자인 원칙에 맞는 제품 수준의 사용자 경험으로 정리한다.

## Included

- Brand Color Tokens
- Typography Tokens
- Corner Radius
- Spacing
- Home Polish
- Recent Card Polish
- Camera Overlay Polish
- Progress Ring Polish
- Haptic Timing
- Motion
- Empty State
- Loading State
- VoiceOver
- Dynamic Type
- Contrast
- Reduce Motion

## Explicitly Excluded

- 새 기능 추가
- 새로운 편집 기능
- 필터
- 음악
- 자막
- Transition

## Decision Gate Before Implementation

다음 Design Open Decisions를 확정한다.

- Recent List 또는 Grid
- New Vlog Placement
- Camera Control Placement
- Trim UI Visual
- Haptic Timing
- Export Completion Layout
- 최종 Color Palette
- Typography
- Corner Radius System

## Implementation Tasks

1. Design Tokens를 확정한다.
2. Brand Screen과 Content Screen의 색상 사용을 구분한다.
3. Home과 Recent를 다듬는다.
4. Orientation Selection을 다듬는다.
5. Camera Overlay를 최소화한다.
6. Recording Progress와 Haptic Timing을 실제 Device에서 조정한다.
7. Loading State와 Empty State를 정리한다.
8. Motion을 Reduce Motion 환경에서 검증한다.
9. 주요 Control에 VoiceOver Label을 추가한다.
10. Touch Target을 점검한다.
11. Dynamic Type에서 Layout이 깨지지 않는 범위를 확인한다.
12. Landscape Safe Area를 검증한다.

## Physical Device Test

iPhone 12에서 모든 핵심 화면을 Portrait 및 Landscape Project 기준으로 확인한다.

## Acceptance Criteria

- UI가 Mellow의 Calm / Warm / Minimal 방향과 일치한다.
- Camera 화면은 영상보다 강하게 보이지 않는다.
- 주요 기능을 VoiceOver로 식별할 수 있다.
- Dynamic Type에서 핵심 Flow를 사용할 수 있다.
- Haptic이 과도하지 않다.
- 새 기능이 추가되지 않는다.

## Exit Criteria

기능 완성도를 해치지 않으면서 UI 품질이 제품 수준에 도달해야 한다.

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
9. 4K Import 반복 처리 후 Memory Release를 확인한다.
10. Export 반복 후 Temporary File Cleanup을 확인한다.
11. 비정상 발열이 지속되는 Flow를 조사한다.

## Acceptance Criteria

- iPhone 12에서 일반 사용 중 반복적인 UI Freeze가 없다.
- Camera Preview가 안정적이다.
- Medium Project Preview가 실사용 가능하다.
- Large Project가 임의 Crash하지 않는다.
- Export 중 Memory Pressure로 반복 종료되지 않는다.
- App 사용 후 Temporary Media가 비정상적으로 누적되지 않는다.

## Exit Criteria

iPhone 12에서 핵심 Flow의 안정성과 성능이 QA 가능한 수준이어야 한다.

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
- Zoom
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

## Before Phase 4

- Transactional Media Commit and Recovery 계약: ADR-020 Accepted 및 `ARCHITECTURE.md` 25절 / 59절을 기준으로 한다.
- Durable Operation Identity, Committed Clip 정의, Failure Boundary와 Recovery Classification의 기본 검증 범위를 Phase 4에서 확인한다.

이 Gate의 계약은 확정되어 있으며 구체적인 Durable Representation은 계약을 만족하는 가장 단순한 구현으로 선택할 수 있다.

## Before Phase 6

- Imported Clip Re-trim 범위
- Source Reference 유지 여부

## Before Phase 7

- Trim과 Crop의 화면 구성
- Pinch to Zoom MVP 포함 여부

## Before Phase 9

- H.264 또는 HEVC
- File Container
- HDR / SDR 정책
- Export Bitrate 방향
- Audio Format

## Before Phase 12

- Recent List 또는 Grid
- Camera Controls Layout
- Final Color Palette
- Typography
- Corner Radius
- Haptic Timing

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
- 다음 Phase에 미해결 Blocker를 넘기지 않는다.

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
