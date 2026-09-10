# Mellow — Development Rules

## 1. Purpose

이 문서는 Mellow 개발 과정에서 항상 지켜야 하는 운영 규칙과 구현 원칙을 정의한다.

이 문서는 특정 기능의 상세 요구사항을 정의하는 문서가 아니다.

제품 요구사항은 `PRODUCT.md`, 기능 범위는 `FEATURES.md`, UX 기준은 `DESIGN.md`, 기술 구조는 `ARCHITECTURE.md`, 확정된 결정은 `DECISIONS.md`, 실행 순서는 `ROADMAP.md`를 따른다.

`RULES.md`는 위 문서들을 실제 개발 과정에서 어떻게 지킬 것인지에 대한 공통 행동 규칙을 정의한다.

Codex와 사람이 모두 동일한 기준으로 개발하도록 하는 것이 목적이다.

---

## 2. Source of Truth

Mellow 개발 중 요구사항 또는 구현 방향을 판단할 때 다음 문서를 기준으로 사용한다.

1. `PRODUCT.md`
2. `FEATURES.md`
3. `DESIGN.md`
4. `ARCHITECTURE.md`
5. `DECISIONS.md`
6. `ROADMAP.md`
7. `RULES.md`
8. 실제 코드

코드가 문서와 충돌하는 경우 코드가 기준이 아니다.

문서와 코드가 다르면 원인을 확인하고 코드 또는 문서를 올바른 기준에 맞게 수정한다.

문서끼리 충돌하는 경우 임의로 해석하지 않는다.

충돌을 발견하면 작업을 중단하고 사용자에게 보고한다.

---

## 3. No Silent Decisions

Codex는 제품, UX, Architecture 또는 Scope에 영향을 주는 결정을 임의로 내리지 않는다.

명확하지 않은 요구사항을 편의상 가정하지 않는다.

Open Decision을 발견하면 구현 전에 사용자에게 보고한다.

보고에는 최소한 다음 내용을 포함한다.

- 결정이 필요한 항목
- 현재 Phase
- 현재 작업에 미치는 영향
- 가능한 선택지
- 각 선택지의 장점
- 각 선택지의 단점
- 추천안

사용자 승인 전에는 해당 Decision에 의존하는 구현을 진행하지 않는다.

---

## 4. Phase Discipline

개발은 `ROADMAP.md`에 정의된 Phase 순서를 따른다.

현재 Phase의 Exit Criteria를 충족하기 전에는 다음 Phase를 시작하지 않는다.

여러 Phase를 한 번에 구현하지 않는다.

현재 Phase에 포함되지 않은 기능은 구현하지 않는다.

다음 Phase에 필요한 기반을 미리 과도하게 구현하지 않는다.

필요한 최소 Skeleton은 허용하지만 미래 기능을 미리 완성하지 않는다.

---

## 5. Scope Protection

Mellow MVP의 Scope를 개발 편의 또는 새로운 아이디어 때문에 임의로 확대하지 않는다.

개발 중 좋은 아이디어가 발견되어도 현재 Phase에 바로 추가하지 않는다.

새로운 아이디어는 Backlog로 분리한다.

MVP에 새 기능을 포함하려면 사용자 승인과 관련 문서 업데이트가 필요하다.

다음 항목은 승인 없이 MVP에 추가하지 않는다.

- Photo Capture
- Photo Editing
- Photo Filters
- Video Filters
- Music
- Text Overlay
- Transitions
- Templates
- Smart Editing
- Clip Split
- Clip Duplicate
- Multi-track Timeline
- Layer System
- Keyframes
- Masks
- Chroma Key
- Professional Color Grading
- 4K Export
- 60 fps Export
- iPad Support
- Android Support
- iCloud Sync
- Account System
- Social Features
- Analytics SDK
- Subscription
- In-app Purchase

---

## 6. Confirmed Product Invariants

다음 항목은 승인된 변경 절차 없이 변경하지 않는다.

- Mellow는 iPhone-first Mini Vlog 앱이다.
- Mellow의 핵심은 짧은 일상 순간을 기록하고 여러 Video Clip을 하나의 Mini Vlog로 만드는 것이다.
- Photo Workflow는 MVP 범위가 아니다.
- 하나의 직접 촬영 Clip은 최대 10초다.
- Imported Video Source는 길이 제한 없이 선택할 수 있다.
- Project에 추가되는 Imported Clip Segment는 최대 10초다.
- Project 전체 Duration에는 임의의 고정 Maximum을 두지 않는다.
- Project Clip Count에는 임의의 고정 Maximum을 두지 않는다.
- 9:16 Portrait와 16:9 Landscape Project를 지원한다.
- 하나의 Project는 생성 이후 하나의 Aspect Ratio를 유지한다.
- Device Rotation이 Project Aspect Ratio를 변경하지 않는다.
- Rear Camera와 Front Camera를 지원한다.
- Recording 중 Camera Switching은 허용하지 않는다.
- 여러 Draft를 동시에 유지할 수 있다.
- Draft는 사용자가 삭제하기 전까지 자동 만료하지 않는다.
- Export 이후에도 Draft를 유지한다.
- Photos 원본 Media를 수정하거나 삭제하지 않는다.

---

## 7. Confirmed Technical Invariants

다음 기술 기준은 승인된 변경 절차 없이 변경하지 않는다.

- Minimum Deployment Target은 iOS 18.0이다.
- 공식 Device Quality Baseline은 iPhone 12 이상이다.
- Primary Physical Test Device는 iPhone 12다.
- Swift를 사용한다.
- SwiftUI를 사용한다.
- Mellow MVP의 표준 Video Profile은 1080p / 30 fps다.
- Portrait Output은 1080 × 1920이다.
- Landscape Output은 1920 × 1080이다.
- 4K Source Import는 허용한다.
- MVP에서 4K Export는 제공하지 않는다.
- MVP에서 60 fps Export는 제공하지 않는다.
- Metadata는 SwiftData를 사용한다.
- 실제 Video File은 File System에 저장한다.
- SwiftData에 대용량 Video Binary를 저장하지 않는다.
- Media Path는 Absolute Path가 아니라 Relative Path를 사용한다.
- Camera Session은 SwiftUI View에서 직접 관리하지 않는다.
- Preview와 Export는 가능한 한 동일한 Composition Definition을 사용한다.
- Media Processing은 Local-first로 동작한다.
- 승인 없이 Third-party Dependency를 추가하지 않는다.

---

## 8. Media Safety First

사용자 Media의 안전성은 구현 편의보다 우선한다.

정상적으로 촬영 또는 Import가 완료된 Clip은 단순 Navigation, View 재생성 또는 App State 변경 때문에 유실되어서는 안 된다.

새 Media는 정상 File 생성과 Validation이 완료된 이후에만 정상 Clip Metadata로 등록한다.

Media File 생성 실패 상태에서 유효한 Clip Metadata만 남기지 않는다.

Photos Library의 원본 Video를 수정하지 않는다.

Photos Library의 원본 Video를 삭제하지 않는다.

Mellow Draft 삭제는 Mellow가 소유한 Project Media에만 영향을 준다.

하나의 손상된 Clip 때문에 전체 Draft 또는 전체 App이 Crash해서는 안 된다.

---

## 9. Non-destructive Editing

Trim과 Framing은 기본적으로 Metadata 기반 비파괴 Editing으로 구현한다.

사용자의 Editing Interaction마다 Video File을 반복적으로 Re-encode하지 않는다.

Photos 원본 Media는 항상 보존한다.

Project-owned Working Media도 불필요하게 반복 변환하지 않는다.

최종 Transform은 Preview와 Export Composition에서 적용하는 방향을 우선한다.

---

## 10. UI Responsibility

SwiftUI View는 사용자 Interface와 Interaction 표현을 담당한다.

SwiftUI View에서 다음 Low-level 작업을 직접 수행하지 않는다.

- `AVCaptureSession` Lifecycle 관리
- `FileManager` 기반 Project Media 관리
- SwiftData 직접 Persistence Logic
- Video Export Pipeline
- Photos Save Infrastructure
- Thumbnail Processing
- Heavy AVAsset Processing

이러한 작업은 Service, Repository 또는 Domain Layer에 배치한다.

---

## 11. Concurrency Rules

UI State 변경은 Main Actor에서 수행한다.

Camera Session Configuration은 안전한 Serial Execution Context에서 수행한다.

Media Processing과 File Operation은 Main Actor를 Block하지 않는다.

Thumbnail Generation은 Main Actor에서 수행하지 않는다.

Import와 Export는 가능한 경우 Cancellation을 지원한다.

Swift Concurrency Warning을 무시하지 않는다.

Compiler Warning을 제거하기 위해 `@unchecked Sendable`을 무분별하게 사용하지 않는다.

AVFoundation Object가 임의의 Thread에서 안전하다고 가정하지 않는다.

---

## 12. Performance Rules

성능 최적화는 실제 측정에 기반한다.

단순 추측만으로 복잡한 Cache 또는 Custom Rendering Engine을 먼저 만들지 않는다.

다만 다음 구조는 처음부터 피한다.

- 전체 Vlog의 모든 Video Frame을 동시에 Memory에 Load하는 구조
- Main Thread에서 긴 AVAsset Metadata Processing을 수행하는 구조
- SwiftUI View 재평가마다 Camera Session을 다시 생성하는 구조
- 긴 4K Source 전체를 이유 없이 Memory에 Load하는 구조
- Preview를 위해 매번 전체 Vlog를 사전 Render하는 구조
- 반복 Editing마다 원본 Media를 Re-encode하는 구조

iPhone 12에서 반복적인 UI Freeze, Memory Pressure 또는 비정상적인 Thermal Issue가 발생하면 완료로 처리하지 않는다.

---

## 13. Dependency Rules

MVP에서는 Apple Native Framework를 우선 사용한다.

새 Third-party Dependency는 사용자 승인 없이 추가하지 않는다.

Dependency 도입을 제안할 경우 최소한 다음을 검토한다.

- Native API로 해결 가능한지
- Library 유지보수 상태
- License
- Privacy 영향
- App Size 영향
- Security Risk
- Lock-in Risk
- 제거 또는 교체 가능성

중요한 Dependency 추가는 `DECISIONS.md`에 기록한다.

---

## 14. Git Rules

`main`은 항상 가능한 한 Build 가능한 상태를 유지한다.

기능 개발은 `ROADMAP.md`의 Phase Branch Strategy를 따른다.

`main`에 Force Push하지 않는다.

공유된 Git History를 임의로 Rewrite하지 않는다.

관련 없는 파일을 하나의 Commit에 섞지 않는다.

사용자 요청 없이 대규모 Rename 또는 Formatting을 수행하지 않는다.

사용자 요청 없이 기존 Commit을 Squash, Rebase 또는 Amend하지 않는다.

Commit 전 변경사항을 확인한다.

Commit 전 `git diff --check`를 실행한다.

Phase 완료 전 전체 Diff를 Review한다.

---

## 15. Commit Rules

Commit은 작은 목적 단위로 만든다.

Commit Message는 실제 변경 내용을 명확하게 설명한다.

좋은 Commit 예시는 다음과 같다.

- `feat: add vlog project domain models`
- `feat: implement rear and front camera switching`
- `feat: enforce ten second recording limit`
- `fix: preserve clip after recording interruption`
- `test: cover imported clip duration policy`
- `docs: record export codec decision`

다음과 같은 모호한 Commit Message는 피한다.

- `update`
- `changes`
- `fix stuff`
- `work`
- `misc`

---

## 16. No Unrequested Git Actions

Codex는 사용자 승인 없이 다음 작업을 수행하지 않는다.

- `git push`
- Branch Merge
- Branch Delete
- Tag 생성
- Release 생성
- Force Push
- History Rewrite

사용자가 Push 또는 Merge까지 명시적으로 요청한 경우에만 수행한다.

---

## 17. Testing Rules

새로운 Domain Logic에는 가능한 한 Unit Test를 작성한다.

Media Pipeline 변경에는 관련 Integration Test를 추가한다.

사용자 Flow 변경에는 필요한 경우 UI Test를 추가한다.

Camera Hardware 기능은 Simulator Test만으로 완료 처리하지 않는다.

실제 Device에서만 검증 가능한 항목은 완료 보고 시 명확하게 표시한다.

Codex가 직접 실행하지 못한 Test를 통과했다고 보고하지 않는다.

---

## 18. iPhone 12 Physical Device Rule

다음 기능은 iPhone 12 실기기 검증이 필요하다.

- Rear Camera Preview
- Front Camera Preview
- Camera Switching
- Video Recording
- 10초 Auto Stop
- Audio Recording
- Device Orientation
- Project Orientation UX
- Haptic Feedback
- Photos Video Import
- 4K Source Import
- Trim Interaction
- Framing Interaction
- Multi-clip Preview
- Export
- Photos Save
- Share Sheet
- Storage Failure Handling
- Camera Interruption
- Background / Foreground Camera Lifecycle

실기기 검증이 남아 있는 Phase는 `Needs Device Test` 상태로 보고한다.

사용자 확인 없이 `Completed`로 처리하지 않는다.

---

## 19. Build Quality Rules

Phase 작업이 끝났다고 판단하기 전에 최소한 다음을 확인한다.

- App Build 성공
- 관련 Unit Tests 통과
- 관련 Integration Tests 통과
- 필요한 UI Tests 통과
- Compiler Warning 검토
- `git diff --check` 통과
- 예상하지 못한 파일 변경 여부 확인
- 관련 문서와 코드의 일치 여부 확인

Warning이 존재하면 무시하지 않고 원인을 설명한다.

---

## 20. Error Handling Rules

Low-level Framework Error를 사용자에게 그대로 노출하지 않는다.

사용자에게는 이해 가능한 Product-level Error를 제공한다.

Technical Error는 Logging에 남길 수 있다.

Error Handling을 정상 Flow 이후의 선택 기능으로 미루지 않는다.

Media Loss 가능성이 있는 Error Path는 기능 완료 전에 처리한다.

---

## 21. Logging and Privacy Rules

Logging에는 사용자의 실제 Video Frame 또는 Audio Content를 기록하지 않는다.

Production Log에 불필요한 개인 Media 정보를 남기지 않는다.

전체 Local File Path를 필요 이상으로 Logging하지 않는다.

사용자 Media를 서버로 자동 Upload하지 않는다.

Analytics가 승인되지 않은 상태에서 Tracking SDK를 추가하지 않는다.

---

## 22. Permission Rules

Permission은 실제 기능이 필요한 시점에 Contextual하게 요청한다.

불필요하게 App Launch 직후 모든 Permission을 한 번에 요청하지 않는다.

Photos Import는 가능한 한 System Photos Picker를 사용한다.

Permission Denied 상태를 Crash 또는 Blank Screen으로 처리하지 않는다.

필요한 경우 사용자가 Settings에서 권한을 다시 활성화할 수 있도록 안내한다.

---

## 23. Documentation Rules

문서 내용을 코드에 맞추기 위해 조용히 왜곡하지 않는다.

실제 Decision이 변경되면 문서와 ADR을 먼저 또는 같은 변경 범위에서 업데이트한다.

기존 Accepted ADR이 변경되면 과거 내용을 삭제하지 않는다.

중요한 Decision 변경은 새로운 ADR로 기록하고 기존 ADR을 `Superseded` 처리한다.

최초 작성 단계의 문서에는 임의의 Version Label을 붙이지 않는다.

Baseline 이후 실제 Product 또는 Architecture 변경으로 Version 관리가 필요해질 때 별도로 적용한다.

Markdown 문서에서는 하나의 문장을 임의로 여러 줄로 분리하지 않는다.

가독성을 위한 문단, Heading, List, Code Block은 정상적으로 사용할 수 있다.

---

## 24. Exception and Replanning Rule

Roadmap에서 벗어나야 할 합리적인 이유가 발견되면 잘못된 방향을 억지로 계속 구현하지 않는다.

동시에 Codex가 새로운 방향을 임의로 선택하지도 않는다.

`ROADMAP.md`의 Exception and Replanning Protocol을 따른다.

필요하면 `spike/<topic>` 또는 `experiment/<topic>` Branch를 사용한다.

Spike는 기술적 질문을 검증하기 위한 것이며 Product Feature 구현 Branch가 아니다.

실험 결과가 성공했다고 자동으로 Production Architecture에 채택하지 않는다.

Decision 변경은 사용자 승인 후 반영한다.

---

## 25. Emergency Fix Rule

Data Loss, 반복 Crash, Security Risk 또는 Build Blocker는 현재 Phase 밖이라도 Emergency Fix 대상으로 처리할 수 있다.

Emergency Fix는 문제 해결에 필요한 최소 범위만 수정한다.

Emergency Fix를 새로운 기능 추가 수단으로 사용하지 않는다.

수정 후 관련 Test와 문서를 보완한다.

---

## 26. No Fake Completion

화면이 표시된다는 이유만으로 기능을 완료 처리하지 않는다.

Build 성공만으로 Phase를 완료 처리하지 않는다.

Simulator에서 동작한다는 이유만으로 Camera 또는 Media 기능을 완료 처리하지 않는다.

Placeholder가 연결되었다는 이유만으로 실제 Feature를 구현했다고 보고하지 않는다.

TODO가 남아 있으면 해당 TODO가 Phase 완료에 영향을 주는지 명확하게 보고한다.

Mock Service가 동작해도 Production Service 검증이 필요한 경우 완료가 아니다.

---

## 27. Completion Report Format

Codex가 Phase 또는 주요 Task 완료를 보고할 때 최소한 다음을 포함한다.

### Implemented

실제로 구현한 내용을 설명한다.

### Changed Files

변경한 파일과 각 파일의 목적을 설명한다.

### Tests Run

실행한 Test를 설명한다.

### Test Results

성공, 실패, 미실행 항목을 구분한다.

### Physical Device

iPhone 12 검증이 필요한지와 현재 상태를 설명한다.

### Open Issues

남아 있는 Bug 또는 Risk를 설명한다.

### Open Decisions

사용자 결정이 필요한 항목을 설명한다.

### Scope Check

현재 Phase 밖의 기능을 추가하지 않았는지 확인한다.

### Next Gate

다음 Phase로 이동 가능한지 명확히 설명한다.

---

## 28. Review Before Merge

Phase Branch를 `main`에 Merge하기 전 다음을 확인한다.

- Phase Acceptance Criteria 완료
- Phase Exit Criteria 완료
- Build 성공
- Tests 통과
- 필요한 iPhone 12 Test 완료
- 문서 Sync 완료
- Open Decision 없음
- Blocker 없음
- 예상하지 못한 Dependency 추가 없음
- Scope Creep 없음
- 전체 Diff 검토 완료

조건을 충족하지 않으면 Merge하지 않는다.

---

## 29. Code Quality Principles

코드는 읽기 쉬운 구조를 우선한다.

짧다는 이유만으로 복잡한 코드를 선택하지 않는다.

중복 제거를 위해 지나치게 추상적인 범용 Layer를 만들지 않는다.

미래 가능성만을 이유로 사용되지 않는 abstraction을 추가하지 않는다.

Feature State에 Infrastructure Object를 직접 저장하지 않는다.

하나의 거대한 God Object가 Camera, Media, Persistence, Navigation을 모두 관리하게 하지 않는다.

Domain Rule은 가능한 한 UI와 독립적으로 테스트 가능하게 유지한다.

Magic Number는 제품 Policy 또는 명시적인 Configuration으로 관리한다.

---

## 30. Naming Rules

제품에서 사용자에게 보여주는 용어와 내부 기술 용어를 구분한다.

사용자 UI에서는 내부 구현 용어인 `Draft`보다 Product Language인 `Recent`를 우선한다.

코드에서는 의미가 명확한 이름을 사용한다.

`Manager`, `Helper`, `Utils`처럼 역할이 모호한 이름을 남발하지 않는다.

Service, Repository, Policy, Model의 이름은 실제 책임을 반영한다.

---

## 31. Final Rule

Mellow 개발에서 가장 중요한 우선순위는 기능 수가 아니라 핵심 Mini Vlog Flow의 안정성이다.

빠르게 많이 만드는 것보다 사용자가 촬영한 순간을 잃지 않는 것이 우선이다.

새로운 기능보다 Recording, Draft, Preview, Export의 Reliability를 우선한다.

문서보다 코드가 앞서가지 않도록 한다.

Codex는 결정권자가 아니라 승인된 Product Direction을 정확하게 구현하는 실행자 역할을 한다.
