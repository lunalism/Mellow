# Mellow — Architecture Definition

## 1. Document Purpose

이 문서는 Mellow의 기술 아키텍처와 구현 원칙을 정의한다.

`PRODUCT.md`가 제품의 목적을 정의하고, `FEATURES.md`가 기능 범위를 정의하고, `DESIGN.md`가 사용자 경험을 정의한다면, 이 문서는 해당 요구사항을 안정적으로 구현하기 위한 기술 구조를 정의한다.

이 문서는 Mellow iPhone 애플리케이션의 실제 구현에 대한 source of truth로 사용한다.

제품 요구사항을 기술적 편의를 이유로 임의로 변경하지 않는다.

제품 또는 UX 변경이 필요한 기술적 제약이 발견되면 문제, 영향 범위, 가능한 대안을 먼저 제시하고 승인 이후 반영한다.

---

## 2. Architecture Goals

Mellow의 기술 아키텍처는 다음 목표를 우선한다.

- 안정적인 Video Recording
- 사용자가 촬영한 영상의 안전한 보존
- 여러 Draft Project의 안정적인 복구
- 많은 Clip을 가진 프로젝트에서도 예측 가능한 동작
- Preview와 Export 결과의 일관성
- Portrait 9:16과 Landscape 16:9의 정확한 처리
- iPhone 12에서도 원활한 사용자 경험
- 불필요하게 높은 Memory 사용 방지
- SwiftUI와 AVFoundation의 명확한 책임 분리
- 테스트 가능한 구조
- MVP에 불필요한 Architecture Complexity 방지
- 향후 기능 확장을 방해하지 않는 구조

Mellow는 초기부터 전문 영상 편집기를 위한 범용 Architecture를 만들지 않는다.

현재 Mellow의 Mini Vlog 경험을 안정적으로 구현하기 위한 가장 단순하고 유지보수 가능한 구조를 우선한다.

---

## 3. Platform Strategy

Mellow는 iPhone-first Native Application으로 개발한다.

### Language

- Swift

### UI

- SwiftUI

### Minimum Deployment Target

- iOS 18.0

### Official Device Quality Baseline

- iPhone 12 and later

### Primary Physical Test Device

- iPhone 12

`iPhone 12 and later`는 Mellow의 공식 개발 및 QA 기준이며 App Store에서 이전 기기의 설치를 인위적으로 차단하기 위한 조건으로 사용하지 않는다.

Mellow의 Camera, Preview, Trim, Import, Export 성능은 최소한 iPhone 12에서 만족스러운 수준으로 동작해야 한다.

최신 Pro 모델에서만 원활하게 동작하는 구현은 Mellow MVP의 성능 기준을 충족한 것으로 판단하지 않는다.

---

## 4. Core Apple Frameworks

Mellow MVP는 가능한 한 Apple의 Native Framework를 사용한다.

### Primary Frameworks

- SwiftUI
- AVFoundation
- PhotosUI
- Photos
- SwiftData
- CoreMedia
- CoreGraphics
- OSLog

필요하지 않은 Third-party Dependency는 추가하지 않는다.

Third-party Library가 없어도 합리적인 수준으로 구현할 수 있다면 Apple Native API를 우선한다.

---

## 5. Video Resolution Policy

Mellow MVP의 Project Output / Export Resolution은 1080p이며 Imported Working Media는 1080p-class를 기준으로 한다.

아래 Pixel Size는 Project Output Canvas이며 Imported Working Media를 이 Canvas로 미리 Crop한다는 의미가 아니다.

### Portrait Project Output

- Resolution: 1080 × 1920
- Aspect Ratio: 9:16

### Landscape Project Output

- Resolution: 1920 × 1080
- Aspect Ratio: 16:9

### Default Frame Rate

- 30 fps

Mellow MVP에서는 720p를 기본 작업 해상도로 사용하지 않는다.

Mellow MVP에서는 4K Export를 제공하지 않는다.

Photos에서 4K를 포함한 고해상도 Video를 Import할 수 있다.

Imported Video는 사용자가 선택한 최대 10초 구간을 기준으로 1080p-class / 30 fps / SDR Working Media로 정규화한다.

1080p-class는 고해상도 Source를 제한·정규화하는 Working Target이며 저해상도 Source를 무조건 Upscale하라는 요구사항은 아니다.

Source Presentation Aspect Ratio와 이후 Framing 가능한 영역을 보존하며 정확한 Raster Dimension Rule과 Low-resolution Upscaling Policy는 Phase 6 구현 전 Technical Gate로 남긴다.

사용자의 Photos Library에 존재하는 원본 Video는 Resolution 변환 과정에서도 수정하지 않는다.

---

## 6. Video Input Policy

입력 Video의 Resolution은 Mellow의 Working Resolution과 동일할 필요가 없다.

Mellow는 다음과 같은 Source Media를 받아들일 수 있는 구조를 가져야 한다.

- 720p
- 1080p
- 4K
- High-resolution Video
- SDR Video
- HDR / Dolby Vision Video
- Portrait Video
- Landscape Video
- 서로 다른 Frame Rate의 Video

입력 포맷이 다양하더라도 Mellow Project 내부에서는 가능한 한 일관된 Working Media를 사용한다.

MVP에서는 다양한 Source Format을 Project 내부에 그대로 혼합하여 처리하는 것보다 1080p-class / 30 fps / SDR Working Media로 정규화하여 Preview와 Export Pipeline의 복잡성을 낮춘다.

---

## 7. Frame Rate Policy

Mellow MVP의 기본 Project Frame Rate는 30 fps다.

Mellow Camera에서 새로 촬영하는 Clip은 1080p 30 fps를 기본 Capture Profile로 사용한다.

Photos에서 가져오는 Source Video의 Frame Rate는 30 fps와 다를 수 있다.

30 fps보다 높은 Source도 Import할 수 있지만 Imported Working Media는 30 fps 기준으로 정규화하며 Final Validation과 Preview / Export도 이 기준을 따라야 한다.

Photos Source 자체의 Frame Rate는 변경하지 않는다.

Variable Frame Rate 또는 비정상 Source의 구체적인 변환 구현 방식은 여기서 고정하지 않으며 Working Media Validation과 최종 30 fps Output 기준에 모순되지 않아야 한다.

60 fps Export는 MVP에서 제공하지 않는다.

Slow Motion 또는 Variable Speed Editing은 MVP 범위에 포함하지 않는다.

---

## 8. HDR Policy

ADR-022에 따라 SDR, HDR 및 Dolby Vision Source Import를 허용하며 HDR / Dolby Vision Source는 Project-owned SDR Working Media로 정규화한다.

Photos Source 자체는 수정하거나 삭제하지 않으며 HDR Metadata와 Dolby Vision을 Working Pipeline에서 보존하는 것을 MVP requirement로 하지 않는다.

MVP Preview와 Export는 SDR을 기준으로 하고 HDR Export는 MVP 범위에서 제외한다.

HDR → SDR 변환 결과는 Final Working Media 등록 전에 Validation하며 심각한 Highlight Clipping, 잘못된 색 변환 또는 Source Orientation 손상 등 명백한 변환 실패를 정상 Media로 취급하지 않는다.

Preview와 Export가 동일한 SDR 해석을 사용하도록 45절의 Shared Composition / Color Handling 원칙을 적용한다.

정확한 Tone-mapping Algorithm과 Apple API 조합은 고정하지 않으며 Apple Native Framework 우선 원칙을 유지한다.

정확한 SDR Color Profile / Tagging과 Tone-mapping 구현 방법은 여전히 Pending이며 SDR 정규화 방향 자체를 다시 Open으로 취급하지 않는다.

---

## 9. High-level Architecture

Mellow는 Feature-oriented SwiftUI Architecture와 명확한 Service Boundary를 사용한다.

전체 구조는 다음 책임으로 구분한다.

```text
SwiftUI Views
    ↓
Feature State / View Models
    ↓
Domain Models / Policies
    ↓
Services / Repositories
    ↓
Apple Frameworks
    ↓
Camera / Files / Photos / AVFoundation / Persistence
```

SwiftUI View에서 AVFoundation Session, FileManager, SwiftData 등의 Low-level API를 직접 조작하지 않는다.

View는 화면 표현과 사용자 Interaction을 담당한다.

Camera, Media Processing, Persistence, File Management는 별도의 Service가 담당한다.

---

## 10. Architecture Style

Mellow MVP에서는 과도한 Clean Architecture 또는 복잡한 Module System을 도입하지 않는다.

다음 원칙을 사용한다.

- Feature-first folder organization
- SwiftUI View
- Feature State 또는 View Model
- Protocol-based Service Boundary
- Repository Pattern
- Dependency Injection
- Swift Concurrency
- Actor-based Media Operations
- Typed Error Model

추상화는 실제 테스트 또는 책임 분리가 필요한 Boundary에 사용한다.

모든 Class 또는 Struct에 불필요한 Protocol과 Layer를 만들지 않는다.

---

## 11. Initial Project Structure

초기 Xcode Project는 다음 구조를 기본 방향으로 사용한다.

```text
Mellow/
├── MellowApp/
│   ├── App/
│   │   ├── MellowApp.swift
│   │   ├── AppEnvironment.swift
│   │   └── AppRouter.swift
│   │
│   ├── Domain/
│   │   ├── Models/
│   │   ├── Policies/
│   │   └── Errors/
│   │
│   ├── Features/
│   │   ├── Home/
│   │   ├── VlogCreation/
│   │   ├── Camera/
│   │   ├── VideoImport/
│   │   ├── ProjectEditor/
│   │   ├── Trim/
│   │   ├── Preview/
│   │   └── Export/
│   │
│   ├── Core/
│   │   ├── Camera/
│   │   ├── Media/
│   │   ├── Persistence/
│   │   ├── Photos/
│   │   ├── Permissions/
│   │   ├── Storage/
│   │   ├── Thumbnails/
│   │   └── Logging/
│   │
│   ├── DesignSystem/
│   └── Resources/
│
├── MellowTests/
├── MellowUITests/
├── docs/
└── AGENTS.md
```

초기에는 각 Feature를 별도 Swift Package로 분리하지 않는다.

실제 코드 규모가 커져 Module 분리가 명확한 이점을 제공할 때 별도로 검토한다.

---

## 12. Domain Model

Mellow의 핵심 Domain Object는 `VlogProject`와 `VlogClip`이다.

UI State와 Persistent Model을 무조건 하나의 객체로 통합하지 않는다.

Domain Rule은 UI 구현과 독립적으로 검증할 수 있어야 한다.

---

## 13. VlogProject

`VlogProject`는 하나의 Mini Vlog Project를 표현한다.

### Core Properties

- `id`
- `createdAt`
- `updatedAt`
- `orientation`
- `clips`

사용자에게 표시되는 자동 Project Name은 `createdAt`을 기반으로 생성한다.

MVP에서는 사용자 지정 Project Name을 저장하지 않는다.

---

## 14. Project Orientation

Project Orientation은 명시적인 Domain Type으로 관리한다.

### Supported Values

- `portrait9x16`
- `landscape16x9`

Project Orientation은 프로젝트 생성 이후 자동 변경하지 않는다.

Device Orientation과 Project Orientation은 서로 다른 개념으로 취급한다.

기기를 회전했다고 해서 Project Orientation이 변경되지 않는다.

---

## 15. VlogClip

`VlogClip`은 Vlog를 구성하는 하나의 Video Segment를 표현한다.

### Core Properties

- `id`
- `projectID`
- `sourceKind`
- `mediaRelativePath`
- `createdAt`
- `sourceDuration`
- `trimStart`
- `trimDuration`
- `framing`
- `sortOrder`

`sourceKind`는 최소한 다음을 구분할 수 있어야 한다.

- Recorded
- Imported

Project에서 실제 사용하는 하나의 Clip Duration은 최대 10초다.

---

## 16. Clip Duration Invariant

10초 제한은 단순 UI Rule로만 관리하지 않는다.

Domain Layer에서 다음 Invariant를 강제한다.

`0 < effectiveClipDuration <= 10 seconds`

10초 제한은 여러 Feature에 Magic Number로 반복하지 않는다.

공통 Domain Policy에서 관리한다.

예시 개념은 다음과 같다.

`ClipPolicy.maximumDuration`

현재 값은 10초다.

---

## 17. Project Duration

전체 Vlog Duration에는 고정 최대 제한을 두지 않는다.

Project Duration은 각 Clip의 Effective Duration 합으로 계산한다.

전체 Duration을 authoritative 값으로 별도 중복 저장하지 않는 방향을 우선한다.

Clip Reorder 또는 Trim 변경으로 Project Duration이 잘못된 상태가 되지 않아야 한다.

---

## 18. Clip Count

하나의 Project에 포함할 수 있는 Clip 개수에는 제품 차원의 고정 최대 제한을 두지 않는다.

Architecture는 Clip 개수가 증가하더라도 모든 Video Frame을 동시에 Memory에 유지하지 않는다.

Project 및 Clip Metadata는 가벼운 데이터 구조로 유지한다.

---

## 19. Persistence Strategy

Mellow는 Metadata와 실제 Media File을 분리하여 저장한다.

### Metadata

다음 정보는 구조화된 Persistence Store에서 관리한다.

- Project
- Orientation
- Clip 목록
- Clip 순서
- Trim
- Framing
- Creation Date
- Last Edited Date

### Media

실제 Video File은 File System에서 관리한다.

대용량 Video Binary Data를 SwiftData Blob으로 저장하지 않는다.

---

## 20. Metadata Persistence

MVP Metadata Persistence에는 SwiftData를 사용한다.

Minimum Deployment Target이 iOS 18.0이므로 SwiftData를 기본 Persistence Technology로 확정한다.

Feature Layer는 SwiftData를 직접 사용하지 않는다.

Persistent Model의 변화가 App 전체 Feature에 직접 전파되지 않도록 Repository Boundary를 유지한다.

---

## 21. Relative Media Paths

SwiftData에는 Media File의 Absolute Path를 저장하지 않는다.

Project Storage Root 기준 Relative Path를 저장한다.

App Container의 Physical Path가 변경되어도 Project Media Reference를 다시 구성할 수 있어야 한다.

---

## 22. Project Repository

Feature Layer와 Persistence 사이에는 `ProjectRepository` Boundary를 사용한다.

### Responsibilities

- Project 생성
- Project 조회
- Recent Project 조회
- Project 수정
- Clip 추가
- Clip 삭제
- Clip 순서 변경
- Trim 저장
- Framing 저장
- Project 삭제

Production Implementation은 SwiftData 기반으로 구성한다.

Test에서는 In-memory 또는 Mock Repository를 주입할 수 있어야 한다.

---

## 23. Project Storage Layout

Draft Media는 Application Support 영역의 Mellow 전용 Directory에 저장한다.

개념적인 구조는 다음과 같다.

```text
Application Support/
└── Mellow/
    └── Projects/
        └── <Project UUID>/
            └── Media/
                ├── <Clip UUID>.mov
                ├── <Clip UUID>.mov
                └── ...
```

Thumbnail은 다시 생성할 수 있는 Cache Data로 취급한다.

Temporary Import와 Export File은 Temporary Directory 또는 별도의 Temporary Workspace에서 관리한다.

Recording과 Import에서 재실행 복구에 필요한 Staging Media와 Operation 정보는 복구 가능성을 유지할 수 있는 저장 수명으로 관리하며 일반 Disposable Temporary Data와 동일하게 정리하지 않는다.

---

## 24. MediaStore

Project Media File 작업은 `MediaStore`가 담당한다.

SwiftUI View 또는 Feature View Model에서 FileManager를 직접 사용하지 않는다.

### Responsibilities

- Project Directory 생성
- Recording File 저장
- Imported Media 저장
- Temporary Media 관리
- Atomic File Move
- Clip File 삭제
- Project Media 삭제
- Recovery Classification 이후 Confirmed Orphan 정리
- Storage Availability 확인 지원

`MediaStore`는 Actor 기반으로 구성하는 방향을 사용한다.

동시 File Operation으로 Project Storage가 손상되지 않도록 한다.

MediaStore Actor 하나만으로 Repository, Preview, Export와 Producer 사이의 Cross-service Media Lifetime Race가 해결된다고 가정하지 않는다.

Repository / Operation Lifecycle / Media Storage 사이에는 60절과 61절의 Active Media Usage, Project Validity와 Deferred Physical Cleanup을 조정하는 책임이 존재해야 한다.

구체적인 Reference Counter, Lease Class, Coordinator Type 또는 Database Schema는 이 계약에서 고정하지 않는다.

---

## 25. Safe Media Write

Recording과 Import는 다음 Media Commit Lifecycle을 공통으로 따른다.

이 계약은 `DECISIONS.md`의 ADR-020을 따르며 최초 Production Media를 생성하는 Phase 4 이전에 확정되어 있어야 한다.

### Media Commit Lifecycle

1. Media Operation 시작
2. Durable Operation Identity 확보
3. Staging에 Media 작성
4. Staged Media 작성 완료
5. Staged Media Validation
6. 필요한 경우 Normalization
7. Final Working Media Validation
8. Project-owned Media 위치로 Materialization
9. Clip Metadata Persistence
10. Commit Complete
11. Temporary / Intermediate Cleanup

Process Death 이후에도 Operation과 Media의 관계를 식별하고 처리 완료 지점을 확인할 수 있는 Durable Operation Identity가 필요하다.

Operation Identity, 대상 Project Identity, Clip Identity와 관련 Media의 연결은 재실행 후에도 복구와 중복 Commit 방지에 사용할 수 있어야 한다.

Operation 정보의 Persistence는 정상 Clip Metadata의 등록과 구별하며 Media 생성 전에 Operation 정보를 남기는 것이 Committed Clip 생성을 의미하지 않는다.

Sidecar Manifest, Persistence Record 등 구체적인 Durable Representation이나 Type / Class 이름은 강제하지 않는다.

구현 시점에 이 계약을 만족하는 가장 단순한 방법을 선택할 수 있다.

### Definition of Committed Clip

Clip은 다음 조건을 모두 만족한 뒤에만 Commit 완료로 인정한다.

- Project-owned Final Media가 존재한다.
- Final Media Validation이 성공했다.
- 해당 Media를 참조하는 Clip Metadata Persistence가 성공했다.
- Project가 여전히 유효한 상태다.

Commit 완료 전 Media는 정상 Project Clip으로 사용자 UI에 노출하지 않는다.

SwiftUI State의 Recording Progress 또는 Import Progress는 Committed Clip을 의미하지 않는다.

Final Media File이 존재해도 Metadata Persistence가 완료되지 않았다면 Committed Clip이 아니다.

Project 유효성 확인과 Metadata Commit은 삭제되었거나 존재하지 않는 Project의 Late Result가 정상 Clip으로 등록되지 않도록 일관성을 유지해야 한다.

Recording / Import Finalization은 61절의 Project-scoped Operation Validity를 Commit 직전에 다시 검증하며 Project Logical Deletion 이후의 결과로 Project를 재생성하지 않는다.

### Validation Contract

Staged Media와 Final Working Media의 Validation은 최소한 다음 성질을 확인한다.

- File이 존재한다.
- 읽기 가능한 Media Resource다.
- 최소 하나의 유효한 Video Track이 존재한다.
- Duration이 유효하다.
- 현재 Phase에서 확정된 Clip Duration Policy를 준수한다.
- 필요한 Audio / Video Track Metadata에 접근할 수 있다.
- 불완전한 Write 또는 Partial Output을 Final Media로 취급하지 않는다.

Import Source 전체에 Project Clip의 최대 10초 제한을 적용하지 않으며 Project에서 사용할 Segment에 확정된 Clip Duration Policy를 적용한다.

Normalization을 수행했다면 그 Output을 Final Media로 등록하기 전에 다시 Validation한다.

Imported Working Media에는 ADR-022 및 38절의 SDR / Frame Rate / Spatial Normalization Validation을 함께 적용한다.

정확한 SDR Color Profile / Tagging, Codec / Container, 최소 Clip 길이 등 Pending 값을 Validation 구현 편의를 위해 임의로 확정하지 않는다.

### Failure Boundary Contract

| Boundary | 기대 결과 |
| --- | --- |
| A. Media File 생성 전 실패 | Committed Clip은 없으며 Operation을 안전하게 정리할 수 있다. |
| B. Media Write 도중 실패 | Partial Output을 Committed Media로 등록하지 않으며 Incomplete Output과 Completed Staging Media를 구별할 수 있어야 한다. |
| C. Staged Media 작성 완료 후 Crash | Valid Staging Media는 Recovery Candidate로 보존하며 단순 Temporary Cleanup으로 즉시 제거하지 않는다. |
| D. Validation 실패 | 정상 Clip Metadata를 등록하지 않으며 Invalid Candidate의 Cleanup 가능 여부는 Source Ownership과 Operation State를 확인한 뒤 판단한다. |
| E. Normalization 도중 실패 | Incomplete Normalized Result는 Final Media가 아니며 Valid Source / Staging Media를 보존하여 Retry 또는 Recovery가 가능하게 한다. |
| F. Final Working Media 생성 후 Metadata Persistence 실패 | Media를 즉시 Orphan으로 삭제하지 않으며 Recoverable Operation의 Candidate를 보존하여 재실행 후 Metadata Commit을 재시도할 수 있어야 한다. |
| G. Metadata Persistence 성공 후 UI Update 이전 Crash | Relaunch 시 Persisted Metadata를 Source of Truth로 사용하며 동일 Clip을 중복 생성하지 않는다. |
| H. Cleanup 실패 | 이미 Committed Clip의 유효성에 영향을 주지 않으며 Cleanup을 재시도할 수 있어야 한다. |

Storage Preflight를 통과한 뒤 Runtime Disk Full 또는 Write Failure가 발생해도 이 Failure Boundary 계약을 그대로 적용한다.

Storage 실패로 생성된 Partial / Incomplete Output을 정상 Clip으로 Commit하거나 성공으로 표시하지 않고 기존 Committed Media, 다른 Draft와 Photos 원본을 보호한다.

Final Media 생성 후 Metadata Persistence가 Storage 부족으로 실패하면 해당 Media를 즉시 Orphan으로 삭제하지 않고 Boundary F의 Recovery Candidate로 유지한다.

Storage Pressure는 Recovery Classification, Project Validity 또는 Active Usage 확인을 생략할 근거가 아니다.

### Atomicity and Ordering

File과 SwiftData Metadata를 하나의 Atomic Transaction으로 취급하지 않는다.

가능한 File Finalization은 동일 Container / Filesystem 내 Atomic Move 또는 Rename을 우선한다.

Partial Filename 또는 Staging Namespace는 Final Project Media와 명확히 구별되어야 한다.

- Valid Final Media 확보 전 Clip Metadata를 Commit하지 않는다.
- Metadata Persistence 완료 전 사용자에게 Committed Clip으로 표시하지 않는다.
- Commit 완료 전 Recovery Information을 파괴하지 않는다.
- Temporary / Intermediate Cleanup은 Commit 또는 Recovery Classification 이후 수행한다.

MediaStore와 ProjectRepository 사이의 실패 경계는 Durable Operation 정보와 59절의 Reconciliation으로 복구할 수 있어야 한다.

Media 생성이 실패했는데 정상적인 Clip Metadata만 남는 상황을 방지한다.

---

## 26. Camera Architecture

SwiftUI View에서 `AVCaptureSession`을 직접 관리하지 않는다.

`CameraCaptureService`가 Camera Session과 Recording Lifecycle을 관리한다.

### Responsibilities

- Capture Session 구성
- Camera Device 선택
- Rear Camera 구성
- Front Camera 구성
- Microphone Input 구성
- Camera / Microphone Authorization과 Recording Readiness 확인
- Camera Switching
- Rear Continuous Zoom
- Preview 연결
- Recording 시작
- Recording 종료
- 10초 Maximum Duration 적용
- Device / Project / UI / Video Presentation Orientation 정보 분리와 Recording Start Eligibility 처리
- Front Camera Mirroring Transform Ownership 유지
- Session Interruption 처리
- Recording 결과 반환

MVP Camera Capability는 Rear 1× Wide, Front Camera, Rear Continuous Zoom과 Idle 상태의 Front / Rear Switching으로 제한한다.

0.5× Ultra Wide, Telephoto, 사용자 Lens Selector, Front Camera Zoom, Dual Camera와 Recording 중 Front / Rear Switching은 MVP Camera Capability에 포함하지 않는다.

Camera 또는 Microphone Permission이 없거나 Required Capture Device가 unavailable하면 Typed Failure를 반환할 수 있어야 하며 부분적으로 Direct Recording을 시작하지 않는다.

---

## 27. Camera Capture Profile

Mellow MVP의 기본 Camera Capture Profile은 다음과 같다.

- 1080p
- 30 fps

Mellow Camera에서 4K 촬영 옵션을 MVP에서 제공하지 않는다.

Mellow Camera에서 60 fps 선택 옵션을 MVP에서 제공하지 않는다.

사용자가 촬영 Resolution이나 Frame Rate를 매번 설정하도록 하지 않는다.

Mellow는 Camera Configuration보다 기록 경험의 단순함을 우선한다.

Rear Camera Capture Device는 기본 1× Wide Camera를 사용한다.

Rear Continuous Zoom은 해당 Wide Camera가 지원하는 Zoom Capability 안에서 1× 이상으로 동작하고 Phase 3에서 승인한 Product Maximum Quality Limit을 넘지 않도록 Clamp한다.

Device가 보고하는 이론적 Maximum Zoom Factor를 Product Maximum으로 자동 채택하지 않는다.

정확한 Capture Device Discovery와 Zoom API는 이 문서에서 고정하지 않으며 기대한 Capability가 없거나 사용할 수 없으면 Typed Failure로 처리한다.

---

## 28. Camera Threading

`AVCaptureSession`의 구성, Start, Stop, Input 변경을 SwiftUI Main Thread에서 직접 수행하지 않는다.

Camera Session 관련 작업은 안전한 Serial Execution Context에서 처리한다.

Rear Zoom 변경은 Camera Configuration State Change와 같은 안전한 실행 경계에서 직렬화한다.

구체적인 Actor / Queue / Lock Type은 이 문서에서 강제하지 않는다.

SwiftUI State Update만 Main Actor에서 수행한다.

Camera Configuration이 UI Rendering을 Block하지 않도록 한다.

---

## 29. Camera Preview

Camera Preview는 AVFoundation Preview Layer를 SwiftUI에 Bridge하여 구성한다.

SwiftUI View의 `body` 재평가가 Capture Session을 새로 생성하지 않아야 한다.

Camera Session Lifecycle과 SwiftUI Rendering Lifecycle을 분리한다.

Rear Preview는 Recording 전 Continuous Zoom 상태를 반영할 수 있어야 한다.

Front Preview는 Mirrored Appearance를 사용하며 저장된 Direct-recorded Front Clip과 사용자-visible Framing이 일치해야 한다.

---

## 30. Video Recording

MVP Recording은 `AVCaptureMovieFileOutput`을 우선 사용한다.

현재 MVP에는 실시간 Filter 또는 Frame-by-frame Video Processing 요구사항이 없다.

따라서 초기부터 `AVCaptureVideoDataOutput`과 `AVAssetWriter`를 이용한 Custom Recording Engine을 만들지 않는다.

향후 실시간 Video Look 또는 Camera Filter가 실제 제품 요구사항이 되면 Recording Pipeline 교체를 별도로 검토한다.

Rear Continuous Zoom은 Capture-time Camera Behavior이며 Preview와 Active Recording에서 같은 Rear Camera의 Field of View를 변경한다.

Active Recording 중 Zoom 변경은 동일 Clip과 Media Operation Identity 안에서 이어지며 Recording을 Stop / Restart하거나 Clip Boundary를 만들거나 10초 Timer를 Reset하거나 Project Orientation을 변경하지 않는다.

Recording 중 Zoom을 이유로 Capture Session 전체를 불필요하게 재구성하는 설계를 기본으로 하지 않는다.

Capture Zoom은 Phase 7 Editing Framing과 별개의 책임이다.

Capture Zoom은 실제 촬영 결과에 반영되며 이후 Metadata Framing으로 Zoom 이전의 전체 1× Field of View를 복원할 수 있다고 보장하지 않는다.

Editing Framing은 기존 Working Media 영역 안에서 Metadata 기반 Fill + Crop / Position / Scale을 적용하며 ADR-022의 Non-destructive Framing 계약을 유지한다.

---

## 31. Ten-second Recording Limit

10초 Recording Limit은 UI Timer에만 의존하지 않는다.

Capture Pipeline 자체에서도 Maximum Duration을 강제한다.

사용자는 10초 이전 언제든 Recording을 직접 종료할 수 있다.

Recording이 10초에 도달하면 정상적인 Recording Completion Flow를 통해 자동 종료한다.

Progress Ring은 실제 제한을 결정하는 Source가 아니라 사용자에게 Recording 상태를 표현하는 UI다.

---

## 32. Recording Progress

UI Recording Progress는 Recording 시작 시점과 최대 10초 Duration을 기준으로 계산한다.

Wall Clock 변경에 영향을 받지 않는 Monotonic Time을 사용한다.

Progress Animation과 실제 Recording Stop Policy를 분리한다.

---

## 33. Camera Switching

Front Camera와 Rear Camera는 Recording이 진행 중이지 않을 때만 전환할 수 있다.

Recording 중에는 Camera Switch Operation을 허용하지 않는다.

Camera Input 교체가 실패할 경우 가능한 한 기존 유효한 Camera Configuration을 유지한다.

Rear Continuous Zoom은 다른 Camera 또는 물리 Lens로 전환하는 의미가 아니며 Recording 중 Zoom을 Camera Switching으로 처리하지 않는다.

---

## 34. Device Orientation

Device Orientation과 Project Orientation을 서로 별도로 관리한다.

Architecture는 Device Rotation을 이유로 Project Orientation 값을 변경하지 않는다.

9:16 Project는 항상 Portrait Project로 유지한다.

16:9 Project는 항상 Landscape Project로 유지한다.

Capture Metadata와 Video Transform은 올바른 Orientation을 유지할 수 있도록 처리한다.

Orientation mismatch 상태는 Feature Layer에 전달하여 `DESIGN.md`에서 정의한 안내 UI를 표시할 수 있어야 한다.

Project Orientation은 영속적인 Project State이며 9:16 Portrait 또는 16:9 Landscape로 Project Lifetime 동안 고정한다.

Device Orientation은 Recording Start Eligibility에 사용하는 일시적인 Physical State이며 UI Orientation, Video Connection Orientation과 Track Presentation Transform을 같은 값으로 취급하지 않는다.

Portrait Project는 Portrait Posture에서, Landscape Project는 Landscape Left 또는 Landscape Right에서 새 Recording을 시작할 수 있다.

Face Up, Face Down, Unknown 또는 안정적으로 판단할 수 없는 Orientation은 Recording Start에 충분한 Evidence가 아니다.

Record Request는 Camera / Microphone Authorization과 Capability, Project Validity 및 Orientation Eligibility를 확인한 뒤 Media Writing을 시작해야 한다.

Orientation이 유효하지 않으면 Committed Recording Operation, Recording Progress와 10초 Timer를 시작하지 않는다.

Recording 시작 후 Device Orientation이 변경되어도 현재 Recording을 자동 Stop / Restart하거나 새 Clip을 만들거나 Project Orientation / Clip Aspect Ratio를 변경하지 않는다.

Mid-record Rotation만으로 Active Rear Zoom Factor를 Reset하지 않고 현재 Clip의 Presentation Orientation은 Recording 시작 시의 Project Orientation 계약을 유지한다.

Recording 종료 후 다음 Record Request 전에 Orientation Eligibility를 다시 확인한다.

Landscape Left와 Landscape Right에서 생성된 Clip 모두 뒤집히거나 180° 잘못 회전되지 않도록 Capture Metadata, Connection Orientation과 Presentation Transform을 올바르게 정규화한다.

정확한 Orientation Detection API, Threshold, Debounce와 Sensor-to-video Mapping은 구현 및 iPhone 12 검증 대상으로 남긴다.

---

## 35. Front Camera Mirroring

Front Camera Preview는 Mirrored Appearance를 사용한다.

Mellow에서 직접 촬영하고 Commit한 Front Clip은 이후 Preview, Editing과 Export에서도 촬영 중 사용자가 본 Mirrored Framing과 동일한 사용자-visible Appearance를 유지한다.

Preview Transform, Capture / Working Media Transform과 Composition Transform 사이에 Double-mirroring 또는 Accidental Un-mirroring이 발생하지 않도록 하나의 명확한 Transform Ownership을 정의해야 한다.

구현은 Capture Connection Mirroring, Transform Metadata, Normalization 또는 Composition Transform 중 하나의 특정 방식을 이 문서에서 강제하지 않지만 Shared Preview / Export Composition 계약과 일치해야 한다.

Front Camera Zoom과 Mirror Toggle은 MVP에 포함하지 않는다.

Photos Import Source에는 Front Camera Mirroring 정책을 소급 적용하지 않고 Source의 원래 Presentation을 기준으로 처리한다.

---

## 36. Video Import Architecture

Photos Import는 가능한 한 SwiftUI의 System Photos Picker를 우선 사용한다.

사용자가 명시적으로 선택한 Video에만 접근하는 방향을 사용한다.

Photos Library 전체에 대한 불필요한 Read Permission을 요구하지 않는다.

Import 과정에서 SwiftUI View가 직접 File Processing을 수행하지 않는다.

`VideoImportService`가 Import Media를 처리한다.

---

## 37. Imported Video Duration

Photos에서 Import하는 원본 Video의 전체 Duration에는 제한을 두지 않는다.

원본 Video가 몇 초이든 몇 분이든 선택할 수 있다.

Mellow Project에 실제로 추가하는 하나의 Clip Segment는 최대 10초다.

사용자는 원본 Video에서 원하는 최대 10초 구간을 선택한다.

---

## 38. Imported Media Processing

Imported Video는 사용자가 Clip 추가를 확정한 후 Project-owned Media로 Materialize하는 방향을 사용한다.

4K Source Video가 선택된 경우에도 전체 4K Video를 Draft Storage에 그대로 복사하는 것을 기본 동작으로 하지 않는다.

사용자가 선택한 최대 10초 Segment를 기준으로 Mellow Working Media를 생성한다.

Imported Working Media는 ADR-022의 1080p-class / 30 fps / SDR 기준으로 정규화한다.

이 과정에서 Photos의 원본 Video는 변경하지 않는다.

Import는 25절의 공통 Media Commit Lifecycle을 사용하며 Source Validation과 Normalized Output의 Final Validation을 구별한다.

Normalization 실패 시 Valid Source / Staging Media를 보존하고 Materialization 이후 Metadata Persistence 실패 시 Recovery Candidate로 유지한다.

이 보존 계약은 진행 중이거나 복구 가능한 Import를 위한 것이며 Commit 이후 원본 Source Reference 유지와 Re-trim 범위는 40절의 미결정 사항으로 유지한다.

### Source, Working Media and Project Output

| Layer | Ownership and Contract |
| --- | --- |
| Source Media | Photos가 소유한 원본이며 SDR / HDR / Dolby Vision, 4K / High-resolution 및 30 fps 초과 Source를 포함할 수 있고 Mellow가 수정하거나 삭제하지 않는다. |
| Project-owned Working Media | 선택된 최대 10초 Segment를 기반으로 Mellow Project가 소유하며 1080p-class / 30 fps / SDR을 기준으로 하고 이후 Framing 가능한 Source Content를 보존하며 Project Crop을 bake-in하지 않는다. |
| Project Output / Export | 고정된 Project Orientation에 따라 Portrait 9:16은 1080 × 1920, Landscape 16:9는 1920 × 1080이며 30 fps / SDR로 출력하고 Trim / Framing / Transform / Order를 Composition에서 적용한다. |

### Spatial Normalization Contract

Normalization standardizes media characteristics, but does not commit the user's project framing.

- Source의 Presentation Aspect Ratio를 불필요하게 파괴하지 않는다.
- Project 9:16 또는 16:9 Fill + Crop을 Normalization Output에 bake-in하지 않는다.
- 이후 사용자가 Framing에 사용할 수 있는 Source의 유효 화면 영역을 보존한다.
- Codec Alignment 등을 위한 기술적 Padding이 필요하더라도 사용자-visible Framing 영역을 임의로 제거하지 않는다.
- Source Rotation / Presentation Transform을 올바르게 해석한다.
- Working Representation은 이후 Framing Metadata를 적용할 수 있어야 한다.

16:9 Source를 9:16 Project에 가져온다는 이유로 Import 때 중앙 9:16 영역만 잘라 저장하지 않으며 이후 좌우 Framing에 필요한 Source 영역을 유지한다.

실제 Crop Region, Position과 Scale은 Editing Metadata로 유지하고 Preview / Export Composition에서 적용한다.

Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 Editing으로 유지하며 일반 편집 때마다 Working Media를 다시 인코딩하지 않는다.

### Color and Frame Rate Validation

SDR, HDR 및 Dolby Vision Source 모두 승인된 SDR Working Pipeline으로 진입하며 HDR Metadata 보존을 성공 조건으로 요구하지 않는다.

Final Working Media 등록 전 SDR 변환 결과, 30 fps 기준, 승인된 1080p-class Working Target, Presentation Aspect Ratio / Transform 및 Framing 영역 보존을 검증한다.

심각한 Highlight Clipping, 잘못된 색 변환, Orientation 손상 또는 Incomplete Normalization Output 등 명백한 변환 실패를 정상 Working Media로 등록하지 않는다.

실패 시 ADR-020의 Valid Source / Recovery Candidate 보존 계약을 따르며 Cancellation과 Deleted Target / Active Usage는 ADR-021의 경계를 그대로 적용한다.

### Technical Gate Before Phase 6 Normalization

다음 항목은 아직 Pending이며 Phase 6 Definition of Ready / Decision Gate에서 사용자 승인을 받아야 한다.

- Working Media Codec
- Working Media Container
- 정확한 SDR Color Profile / Tagging
- Low-resolution Source Upscaling Policy
- 1080p-class Working Media의 정확한 Raster Dimension Rule

이 Gate가 해결되기 전에는 실제 Normalization Pipeline 구현을 시작하지 않는다.

1080p-class는 저해상도 Source의 항상 Upscale 또는 절대 Upscale하지 않음을 뜻하지 않으며 임의 Raster Formula를 추가하지 않는다.

Tone-mapping 구현 방법과 Variable Frame Rate 처리의 구체적인 Apple API 조합은 이 문서에서 강제하지 않으며 필요한 미결정 사항을 구현 전에 해결한다.

Working Media Codec / Container는 Phase 9의 Export Codec / Container와 별개로 결정할 수 있으며 자동으로 동일하게 설정하지 않는다.

---

## 39. Imported Media Ownership

Mellow Project에 정상적으로 추가된 Clip은 Photos 원본의 Runtime Availability에 의존하지 않아야 한다.

Project-owned Media 생성이 완료된 이후에는 사용자가 Photos 원본을 삭제하더라도 Mellow Draft에서 해당 Clip을 유지할 수 있어야 한다.

Draft를 삭제할 경우 Mellow가 소유한 Project Media만 삭제한다.

Photos 원본은 삭제하거나 수정하지 않는다.

---

## 40. Imported Segment Re-trim

Imported Video에서 선택한 Segment를 1080p Working Media로 Materialize할 경우 이후 Re-trim 가능한 범위가 제한될 수 있다.

예를 들어 2분 Source에서 20초 지점부터 30초 지점까지 선택하여 10초 Segment만 Materialize하면 이후 사용자가 전혀 다른 1분 지점으로 이동할 수 없다.

MVP에서 Re-trim을 현재 Materialized Segment 내부에서만 허용할지 원본 Source 범위까지 다시 접근할 수 있게 할지는 아직 확정하지 않는다.

이 결정은 Storage 사용량과 Edit Flexibility 사이의 Trade-off로 `DECISIONS.md`에서 최종 결정한다.

---

## 41. Trim Model

Trim은 원본 Video File을 반복적으로 수정하는 방식으로 구현하지 않는다.

Clip은 Time Range Metadata를 가진다.

### Core Trim Properties

- `trimStart`
- `trimDuration`

Preview와 Export Pipeline은 해당 Time Range를 이용한다.

Trim은 Non-destructive 방식으로 유지한다.

---

## 42. Trim Precision

Trim Time은 반복적인 Floating-point Second 계산에 의존하지 않는다.

가능한 한 CoreMedia의 `CMTime` 의미를 유지한다.

Persistence에서는 `CMTime`을 안정적으로 저장 가능한 Primitive 값으로 변환한다.

예를 들어 Value와 Timescale을 저장하는 방식을 사용할 수 있다.

---

## 43. Framing Model

Imported Video와 Project Aspect Ratio가 다른 경우 사용자의 Framing 값을 Metadata로 저장한다.

Pixel 좌표보다 Normalized Coordinate를 우선한다.

### Candidate Values

- normalizedCenterX
- normalizedCenterY
- scale

MVP에서 Pinch Zoom을 지원하지 않는 경우 Scale은 Aspect Fill 기준값으로 제한할 수 있다.

---

## 44. Fill and Crop

Imported Video의 Project Layout 기본값은 Fill + Crop이다.

16:9 Source를 9:16 Project에 추가하면 Preview / Export Composition에서 9:16 Canvas를 가득 채운 후 초과 영역을 Crop한다.

9:16 Source를 16:9 Project에 추가하는 경우에도 동일한 Aspect Fill 원칙을 사용한다.

사용자가 Framing 위치를 조절할 수 있어야 한다.

이 Crop은 Working Media File에 bake-in하지 않으며 38절에서 보존한 Source 영역에 Framing Metadata를 적용한다.

Video의 `naturalSize`만으로 Orientation을 판단하지 않는다.

Source Asset의 Display Transform을 반영한 실제 Display Orientation을 기준으로 처리한다.

---

## 45. Shared Composition Builder

Preview와 Export가 서로 다른 Video Transform Logic을 구현하지 않는다.

공통 `VideoCompositionBuilder`를 사용한다.

### Responsibilities

- Clip Order 적용
- Trim 적용
- Project Orientation 적용
- Source Rotation 정규화
- Fill + Crop 적용
- User Framing 적용
- Audio Track 구성
- Timeline 생성
- 1080p Output Canvas 구성
- 30 fps Project Timing 반영
- Shared SDR Interpretation / Color Handling 적용

Preview와 Export는 가능한 한 동일한 Composition Definition을 사용한다.

동일한 Logical Project State에서 Framing / Transform / SDR Interpretation이 가능한 한 일치해야 하며 HDR Source라는 이유로 Preview는 HDR이고 Export는 SDR인 이중 기본 Pipeline을 두지 않는다.

이 원칙은 Export Codec / Container / Bitrate를 확정하지 않으며 진행 중 Export는 48절의 Immutable Snapshot 의미를 유지한다.

---

## 46. Preview Architecture

전체 Vlog Preview를 위해 매번 하나의 완성 Video File을 미리 Render하지 않는다.

AVFoundation Composition 기반 Virtual Timeline을 우선 사용한다.

AVPlayer가 필요한 Source Media를 재생하도록 한다.

MVP Preview는 SDR을 기준으로 하며 HDR / Dolby Vision Source에서 시작한 Clip도 SDR Working Media와 공통 Color Handling으로 재생한다.

모든 Clip Video Frame을 Memory에 동시에 Load하지 않는다.

### Preview State and Media Usage

Preview는 현재 유효한 Project State로 Composition을 구성한다.

Preview 준비와 Playback이 참조하는 Media의 Active Usage를 추적하며 해당 Reference가 Release되기 전에는 Source Media를 Physical Delete하지 않는다.

Clip Delete, Reorder, Trim 또는 Framing 변경으로 Project State가 바뀌면 Stale Composition을 무기한 사용하지 않고 Invalidate하며 다음 유효 Preview는 변경된 State를 반영한다.

필요한 경우 현재 Playback을 중단하고 Composition을 Rebuild할 수 있다.

이전 State로 시작한 비동기 Preview Preparation 결과를 새로운 State의 유효한 Preview로 적용하지 않는다.

Project가 Logical Deleted 상태가 되면 신규 Preview 결과를 적용하지 않으며 가능한 작업에 Cancellation을 요청하고 실제 Media Reference Release 이후에만 Physical Cleanup을 허용한다.

Preview에 사용 중인 File을 강제로 삭제하여 Player Failure를 만드는 구조를 허용하지 않는다.

구체적인 UI Transition이나 Player Rebuilding Strategy는 이 계약에서 고정하지 않는다.

---

## 47. Preview Performance

Composition 생성과 Media Metadata 조회가 Main Actor를 장시간 Block하지 않도록 한다.

Thumbnail Generation도 Main Actor에서 수행하지 않는다.

많은 Clip을 가진 Project에서도 Main Thread가 모든 AVAsset을 동기적으로 읽지 않는다.

Preview 준비에 시간이 필요한 경우 Loading State를 Feature Layer에 전달한다.

---

## 48. Export Architecture

Export는 Preview와 동일한 Composition Definition을 사용한다.

MVP에서는 `AVAssetExportSession` 기반 구현을 우선한다.

MVP 초기부터 Custom Encoder Pipeline을 구현하지 않는다.

다음과 같은 요구사항이 실제로 필요해질 경우 `AVAssetReader` 및 `AVAssetWriter` 기반 Pipeline을 검토한다.

- Custom Codec Control
- Advanced HDR Processing
- Frame-level Video Effects
- Complex Rendering
- AVAssetExportSession으로 충족할 수 없는 품질 요구사항

### Immutable Export Snapshot

Export 시작 시 현재 유효한 Project State의 Immutable Logical Snapshot을 사용한다.

Snapshot은 Export 결과를 재현하는 데 필요한 최소한 다음 의미를 포함한다.

- Clip Identity
- Clip Order
- Trim State
- Framing / Transform State
- Project Orientation
- 참조하는 Media Identity / Reference
- 해당 Export의 Audio / Video Composition State

Snapshot은 일관된 하나의 Project State를 나타내며 Snapshot 획득과 Media Usage 등록 사이에 Cleanup으로 Source Media가 사라지는 경합을 허용하지 않는다.

Export 시작 이후의 일반 Clip Edit, Reorder 또는 Clip Delete는 이미 실행 중인 Export 결과를 소급 변경하지 않는다.

Snapshot이 참조하는 Media는 Export Operation이 종료되거나 취소되어 실제 Reference가 Release될 때까지 Physical Delete하지 않는다.

Export 시작 후 Clip Delete와 Undo Window 종료가 발생해도 Export가 사용하는 Source Media는 Release 전까지 보존한다.

Preview / Export Parity는 동일한 Logical Project State에 공통 Composition Definition을 적용한 결과를 기준으로 검증하며 이후 변경된 현재 Preview와 진행 중인 Export Snapshot이 항상 같다고 가정하지 않는다.

구체적인 Snapshot Swift Type은 고정하지 않는다.

### Project Delete During Export

Project 전체 Delete가 확정되면 61절에 따라 Project를 Logical Deleted / Invalid Commit Target으로 전환하고 진행 중인 Project-scoped Export에 Cancellation을 요청한다.

Cancellation은 Cooperative하므로 요청 직후 Operation이 종료되거나 Media Reference가 해제되었다고 간주하지 않는다.

Export의 Late Result는 삭제된 Project State에 신규 결과를 Commit하거나 Project를 재생성하지 않는다.

필요한 Source Media는 Export가 실제로 Release할 때까지 보존하며 취소 이후 생성된 Uncommitted Temporary Artifact는 Ownership, Recovery Classification과 Active Usage를 확인하여 안전하게 정리한다.

이미 Photos에 저장 완료된 외부 Export 결과는 Project Delete로 삭제하지 않는다.

이 계약은 Export의 Source-media Lifetime과 Project Validity를 정의하며 Photos Save / Share 완료 파일, Background Export와 Retry의 상세 Lifecycle은 M05 / Export Lifecycle Repair 대상으로 유지한다.

---

## 49. Export Profile

Mellow MVP의 기본 Export Profile은 다음과 같다.

### Resolution

Portrait:

- 1080 × 1920

Landscape:

- 1920 × 1080

### Frame Rate

- 30 fps

### 720p

- MVP에서 지원하지 않음

### 4K

- MVP에서 지원하지 않음

### User-selectable Resolution

- MVP에서 지원하지 않음

### User-selectable Frame Rate

- MVP에서 지원하지 않음

사용자에게 Resolution과 Frame Rate를 매 Export마다 선택하도록 하지 않는다.

Mellow MVP는 일관된 1080p / 30 fps / SDR 결과를 기본으로 제공한다.

HDR Export는 MVP에서 제공하지 않으며 정확한 SDR Color Profile / Tagging과 Export Codec / Container / Bitrate는 별도 Pending Technical Decision을 따른다.

---

## 50. Export Codec

최종 Video Codec은 아직 확정하지 않는다.

다음 후보를 검토할 수 있다.

- H.264
- HEVC

Codec은 다음 요소를 고려하여 결정한다.

- iPhone Compatibility
- Export Performance
- File Size
- Share Compatibility
- Photos Compatibility
- Quality
- iPhone 12 Performance

Codec을 구현 편의만으로 임의 결정하지 않는다.

---

## 51. Export Canvas

Project Aspect Ratio와 Export Resolution을 별개의 개념으로 관리한다.

Portrait Project는 항상 9:16 Canvas를 사용한다.

Landscape Project는 항상 16:9 Canvas를 사용한다.

MVP의 실제 Pixel Size는 각각 1080 × 1920과 1920 × 1080이다.

향후 Resolution이 변경되더라도 Project Aspect Ratio 자체는 영향을 받지 않아야 한다.

---

## 52. Large Project Export

Mellow는 전체 Vlog Duration이나 Clip Count에 임의의 Product Limit을 두지 않는다.

많은 Clip이 존재한다고 해서 모든 Source Asset을 동시에 Decode하거나 Memory에 Load하지 않는다.

Composition은 Timeline Metadata 중심으로 구성한다.

Export 전 현재 Immutable Export Snapshot의 Project Duration과 승인된 Output Profile을 기준으로 Operation-specific Storage Requirement를 판단한다.

Estimate에는 Temporary Export Output, Final Local Export Artifact, Photos Save / Share Handoff까지 필요한 Local Artifact와 Safety Reserve를 포함한다.

Storage가 부족하면 Export 시작 전에 해당 Export를 차단하고 사용자에게 안내하며 기존 Draft와 다른 Media Operation을 자동으로 차단하지 않는다.

Local Storage Preflight는 Photos Library의 최종 Save 성공을 보장하지 않는다.

---

## 53. Export Temporary File

Export Result는 먼저 Mellow의 Temporary Export Location에 생성한다.

Export가 정상 완료된 이후 Photos Save 또는 Share 대상으로 사용한다.

불완전한 Export File을 Photos Library에 저장하지 않는다.

Export 완료, 실패, 취소 이후 불필요한 Temporary File을 안전하게 정리한다.

---

## 54. Save to Photos

완성된 Export Result를 Photos에 저장하는 역할은 `PhotoLibraryService`가 담당한다.

Photos Save Failure와 Video Export Failure를 서로 다른 Error로 취급한다.

Export 자체는 성공했지만 Photos Save만 실패한 경우 가능한 한 기존 Export File을 이용하여 Save Retry할 수 있도록 한다.

불필요하게 Video를 다시 Export하지 않는다.

---

## 55. Share Sheet

iOS Share Sheet에는 정상적으로 Export가 완료된 Local Video URL을 전달한다.

Share Sheet UI는 Feature Layer에서 관리한다.

Export Service 자체가 Share UI에 의존하지 않는다.

---

## 56. Thumbnail Architecture

Thumbnail은 Project의 authoritative data가 아니다.

Video File에서 다시 생성할 수 있는 Cache로 취급한다.

`ThumbnailService`가 AVAsset 기반 Thumbnail 생성을 담당한다.

Thumbnail 생성은 Main Actor에서 수행하지 않는다.

Thumbnail Cache가 삭제되어도 Project와 Clip은 정상적으로 유지되어야 한다.

Thumbnail Generation과 기타 비동기 Derived Result는 Source Media의 Active Usage를 추적하고 결과 적용 시 Project와 Clip이 모두 유효하며 대상 Clip이 여전히 같은 Media Identity를 참조하는지 확인한다.

Logical Deleted Project 또는 Clip은 유효한 결과 적용 Target이 아니며 Stale Result는 폐기할 수 있어야 한다.

Late Thumbnail Result로 삭제된 Clip이나 Project를 다시 생성하지 않는다.

Thumbnail 생성이 Source Media를 Release하기 전에는 해당 File을 Physical Delete하지 않는다.

---

## 57. Draft Autosave

Project 편집 과정에서 별도의 Save Button을 요구하지 않는다.

다음 변경사항은 자동 저장한다.

- Clip 추가
- Clip 삭제
- Clip Reorder
- Trim 변경 확정
- Framing 변경 확정
- Project 생성

Trim Handle 또는 Framing Drag처럼 매우 자주 발생하는 변경을 매 Frame SwiftData에 기록하지 않는다.

Interaction 동안 Temporary State를 사용하고 Interaction 종료 시 Persistence에 반영한다.

---

## 58. Draft Retention

Draft는 사용자가 직접 삭제하기 전까지 자동 만료하지 않는다.

Project Metadata와 Project Media는 앱 재실행 이후에도 유지되어야 한다.

Export를 완료했다고 Draft를 자동 삭제하지 않는다.

사용자는 Export 이후에도 Project를 다시 열어 수정하고 재Export할 수 있다.

---

## 59. Draft Recovery

App Launch 또는 필요한 Recovery 시점에 Project Metadata, Media File과 Durable Operation 정보의 일관성을 Reconciliation할 수 있어야 한다.

### Recovery Classification

다음 상태는 개념적으로 구분하며 정확한 Enum 이름이나 구현 Type을 강제하지 않는다.

| 분류 | 의미 |
| --- | --- |
| Active / In-progress Operation | 현재 진행 중인 Operation이 소유하거나 필요로 하는 Media다. |
| Recoverable Media | Durable Operation과 연결되어 Validation, 후속 처리 또는 Metadata Commit을 재개할 수 있는 Media다. |
| Committed Media | 25절의 Committed Clip 조건을 충족한 Clip이 참조하는 Media다. |
| Discardable Temporary Media | Ownership과 Operation State 확인 결과 복구 또는 현재 작업에 필요하지 않아 폐기 가능하다고 확정된 Temporary / Intermediate Artifact다. |
| Confirmed Orphan | 아래 Orphan Contract의 모든 조건을 확인하여 정상 사용자 Media로 복구할 근거가 없다고 판정한 Media다. |

Metadata가 존재하지 않는다는 사실만으로 File을 Confirmed Orphan으로 판단해서는 안 된다.

Recovery Candidate 여부를 먼저 확인한다.

Project-owned Media Directory에 있지만 Metadata가 없는 File도 저장 중단의 결과일 수 있으므로 즉시 삭제하지 않는다.

### Confirmed Orphan Contract

Confirmed Orphan은 최소한 다음 조건을 모두 만족해야 한다.

- Committed Clip Metadata에서 참조되지 않는다.
- Active Operation이 소유하지 않는다.
- Recoverable Operation과 연결되지 않는다.
- 현재 사용 중인 작업이 필요로 하지 않는다.
- Recovery / Reconciliation 결과 정상 사용자 Media로 복구할 근거가 없다.

이 조건을 확인하기 전에 Orphan으로 간주한 Destructive Cleanup을 수행하지 않는다.

Known Disposable Temporary Namespace의 명백한 Incomplete Artifact와 Project-owned Unknown Media를 동일하게 취급하지 않는다.

소유권이나 복구 가능성이 불명확한 Media는 자동으로 폐기 가능한 것으로 분류하지 않는다.

### Reconciliation Contract

| 확인된 상태 | 기대 결과 |
| --- | --- |
| Committed Metadata + Valid Media | 정상 상태를 유지한다. |
| Committed Metadata + Missing / Corrupt Media | Damaged / Missing 상태를 감지하고 다른 Clip과 Draft를 보호한다. |
| Valid Materialized Media + Missing Metadata + Recoverable Operation | Project 유효성을 확인한 뒤 동일 Operation / Clip Identity로 Metadata Commit을 재개할 수 있어야 한다. |
| Valid Staging Media + Recoverable Completed Operation | Staging Write가 완료된 Operation의 가능한 Validation 또는 후속 처리를 재개한다. |
| Valid Source + Incomplete Normalization Output | 폐기 가능하다고 확인된 Incomplete Derived Output을 정리하고 Valid Source를 보존한다. |
| Deleted / Nonexistent Project에 속한 Late Result | Project를 재생성하거나 Clip Metadata를 Commit하지 않으며 Artifact는 Ownership과 Recovery Classification에 따라 처리한다. |
| Confirmed Disposable Artifacts | 정상 Committed Media와 Recovery Candidate에 영향을 주지 않고 안전하게 Cleanup한다. |

Persisted Metadata가 존재하면 이미 완료된 Commit을 다시 신규 Commit으로 수행하지 않는다.

파일과 Metadata 사이의 불일치를 발견한 경우 정상 Clip으로 노출하기 전에 위 계약에 따라 상태를 판정한다.

하나의 손상된 Clip 때문에 앱 전체가 Crash하거나 모든 Draft를 열 수 없게 되어서는 안 된다.

### Idempotency and Uniqueness

Recovery와 Reconciliation은 앱 재실행마다 반복되어도 안전하고 Idempotent해야 한다.

동일 Recovery Operation을 여러 번 수행해도 다음을 보장한다.

- 같은 Clip이 중복 등록되지 않는다.
- 동일 Media가 여러 Clip으로 중복 등록되지 않는다.
- 정상 Committed Media가 삭제되지 않는다.
- 이미 Cleanup된 Temporary Artifact 때문에 오류가 반복되지 않는다.
- 완료된 Operation을 다시 신규 Operation처럼 처리하지 않는다.

Media Operation Identity와 Clip Identity를 사용해 Duplicate Commit을 방지하며 구체적인 Database Uniqueness 구현 방법은 코드 단계에서 선택할 수 있다.

Cleanup 실패는 Committed Clip을 실패 상태로 되돌리지 않으며 재시도 시에도 위 보존 조건을 유지한다.

### Scope Boundary

이 계약은 Recording / Import의 저장 완료, 복구 후보 분류와 Cleanup 경계를 정의한다.

Delete / Undo와 Active-consumer Lifetime은 ADR-021 및 46절, 48절, 56절, 60절과 61절을 함께 적용한다.

Logical Deletion은 ADR-020의 Recovery Classification을 생략할 근거가 아니며 삭제된 Target의 Late Result는 복구 과정에서도 Project나 Clip을 다시 생성하지 않는다.

Process Termination 중 Pending Deletion과 Deferred Physical Cleanup의 Reconciliation은 60절과 61절에 정의한다.

정상 Commit 복구를 적용하기 전에 영속적인 Logical Deletion 여부를 확인하여 남아 있는 Metadata나 Valid File만으로 Pending Deletion Clip 또는 삭제된 Project를 정상 상태로 다시 노출하지 않는다.

---

## 60. Clip Deletion and Undo

### Logical Deletion and Physical Deletion

Clip 또는 Project가 사용자 관점에서 삭제되는 Logical Deletion과 실제 Media File을 제거하는 Physical Deletion은 별도의 Lifecycle이다.

Logical Deletion does not imply immediate Physical Deletion.

Clip Delete Action 직후 UI에서는 즉시 제거하며 Undo 가능한 Pending Deletion 상태로 관리한다.

Pending Deletion은 정상 Project Clip 표시와 구별하고 재실행 시 삭제 의도를 Reconciliation할 수 있도록 영속적으로 추적한다.

Undo Window가 종료되었다는 사실만으로 Media File을 즉시 삭제하지 않는다.

### Physical Media Delete Safety

Physical Media Delete를 허용하기 전에 최소한 다음 조건을 모두 확인한다.

- Committed Clip Metadata의 Logical Ownership / Reference에서 더 이상 필요하지 않는다.
- Undo Eligibility가 종료되어 Undo Candidate가 아니다.
- Recovery Candidate가 아니며 Recovery에 필요하지 않는다.
- Preview가 참조 중이지 않다.
- Export가 참조 중이지 않다.
- Thumbnail 또는 기타 Active Consumer가 참조 중이지 않다.
- Recording / Import / Finalization Operation이 해당 Media 또는 관련 Project State에 의존하지 않는다.
- Late Commit 가능성이 차단되어 있다.
- ADR-020에 따른 Safe Cleanup Classification이 완료되었다.
- 다른 안전한 Cleanup을 방해하지 않는다.

Active Media Usage를 추적하여 Physical Delete를 Defer할 수 있어야 하며 Usage 확인과 실제 삭제 사이에 새로운 사용이 끼어들어 안전 조건을 깨지 않도록 조정한다.

Cancellation 요청이나 UI에서 사라진 사실은 실제 Reference Release를 대신하지 않는다.

삭제에 필요한 정보는 안전한 Cleanup과 재시도가 가능하도록 유지하며 동일 Artifact의 반복 Cleanup은 오류나 중복 상태를 만들지 않는다.

### Most-recent Undo Opportunity

MVP에서는 한 시점에 사용자에게 노출되는 Undo Action은 가장 최근 Clip Delete 한 건이다.

새로운 Clip Delete가 발생하면 이전 Delete의 사용자-visible Undo Opportunity는 종료되지만 이전 Media의 Physical Cleanup은 위 안전 조건을 계속 따른다.

Undo는 짧은 Opportunity로 제공하며 정확한 Window Duration과 표시 시간은 DESIGN Tuning으로 남긴다.

Undo 성공 시 동일 Clip Identity와 기존 Media 및 해당 Clip의 Metadata를 복원하고 새로운 Clip이나 Media를 중복 생성하지 않는다.

Undo Eligibility가 남아 있는 동안 해당 Media를 Physical Delete하지 않으며 Physical Media 삭제 이후에 Undo가 성공하는 구조를 허용하지 않는다.

Project가 Logical Deleted 상태가 되면 그 Project의 Clip Undo도 유효하지 않으며 Undo로 Project를 재생성하지 않는다.

### Undo and Process Termination

Undo Window 중 App Process가 종료되어도 사용자-visible Undo Opportunity를 다음 실행까지 유지하지 않는다.

재실행 시 남아 있는 Pending Deletion은 Logical Deletion이 확정된 것으로 Reconciliation하며 Pending 상태를 이유로 Clip을 임의로 다시 표시하지 않는다.

Physical Cleanup은 Undo Opportunity 종료와 별도로 Active Usage, Recovery와 Media Safety 조건을 모두 확인한 뒤 수행한다.

동일 Deletion을 반복 Reconciliation해도 오류나 Duplicate State를 만들지 않아야 한다.

### Undo after Reorder

삭제 시 Original Index와 삭제 당시 이전 / 다음 인접 Clip의 Stable Identity를 보존할 수 있어야 한다.

Undo 복원 위치는 다음 순서로 결정한다.

1. 삭제 당시 이전 인접 Clip이 현재 Project의 유효한 Clip으로 남아 있으면 그 Clip 바로 뒤에 복원한다.
2. 이전 Anchor를 사용할 수 없고 다음 인접 Clip이 유효하게 남아 있으면 그 Clip 바로 앞에 복원한다.
3. 두 Anchor 모두 사용할 수 없으면 Original Index를 현재 Clip 배열의 유효한 삽입 범위로 Clamp하여 복원한다.

두 Anchor가 모두 존재하더라도 Reorder 이후 모호해지지 않도록 이전 Anchor를 우선한다.

복원은 현재 존재하는 다른 Clip의 상대 순서를 유지하며 Undo를 이유로 Unrelated Reorder를 되돌리지 않는다.

구체적인 Undo 데이터 구조, Reference Counter 또는 Lease 구현은 고정하지 않는다.

---

## 61. Project Deletion

Project 삭제는 사용자 Confirmation 이후 실행한다.

### Project Delete Ordering

Project 전체 삭제는 다음 순서를 만족해야 한다.

1. 사용자 Confirmation
2. Project를 Logical Deleted / Invalid Target 상태로 영속적으로 전환
3. 신규 Project-scoped Commit 차단
4. 가능한 Active Producer / Consumer에 Cancellation 요청
5. Clip / Project Metadata 정리
6. Active Usage와 Recovery Requirement가 해제되고 60절의 안전 조건을 충족한 Media부터 Physical Cleanup
7. Cleanup 실패는 재시도 가능하게 유지

Confirmation으로 Delete가 확정되면 해당 Project는 즉시 신규 Commit의 유효한 Target이 아니며 Invalid Target 전환과 Commit 차단 사이에 신규 결과가 적용되는 틈을 허용하지 않는다.

영속적인 Logical Deletion을 확립하기 전에 Metadata 제거 또는 파괴적 Media Cleanup으로 진행하지 않는다.

Project Metadata 삭제와 Media File 삭제를 하나의 Filesystem / Database Atomic Transaction으로 가정하지 않는다.

Metadata를 정리하더라도 삭제 상태와 Deferred Cleanup을 재실행 후 판정하는 데 필요한 정보는 유지할 수 있어야 한다.

Media Cleanup이 실패해도 삭제된 Project가 UI에 다시 나타나거나 복구 과정에서 Resurrect되어서는 안 된다.

Logical Project Deletion과 Cleanup은 Idempotent하며 이미 삭제된 Project에 같은 작업을 반복해도 안전해야 한다.

모든 참조와 Recovery 필요가 해제되면 삭제 대상 Project-owned Media의 Cleanup을 재시도할 수 있어야 한다.

Photos Library의 원본 Video와 이미 Photos에 저장 완료된 외부 Export 결과에는 영향을 주지 않는다.

### Project-scoped Operation Validity

Recording, Import, Thumbnail Generation, Preview Preparation, Export 등 Project-scoped Async Operation은 결과 Commit 또는 적용 직전에 Project Liveness / Operation Validity를 검증해야 한다.

유효성 검사와 결과 적용 사이에 Project Delete가 끼어들어 Late Commit이 허용되지 않도록 Repository / Operation Lifecycle / Media Storage 사이에서 조정한다.

삭제된 Project의 Late Result는 Metadata를 등록하거나 Project를 자동 재생성하지 않는다.

Clip을 대상으로 하는 Derived Result는 Project뿐 아니라 Clip의 유효성과 Media Identity도 확인하며 삭제된 Clip을 되살리지 않는다.

Stale Result는 폐기하고 Operation-owned Temporary Media는 Recovery Classification과 Active Usage 해제 여부를 확인한 뒤 안전하게 정리한다.

이 처리는 이미 Committed된 다른 Project나 Draft에 영향을 주지 않는다.

구체적인 Coordinator Type, Generation Counter 또는 Persistence Schema는 강제하지 않는다.

### Recording / Import Finalization and Project Delete

Recording이 종료되어도 Media Commit Lifecycle이 완료되지 않았다면 Finalization Commit 직전에 Project Validity를 다시 확인한다.

Project Delete가 확정된 뒤에는 Logical Invalid Target 상태를 우선 적용하여 Clip Metadata Commit과 Project 재생성을 금지한다.

Import / Normalization / Materialization 도중 Project Delete가 발생해도 가능한 작업에 Cancellation을 요청하고 Late Result의 Metadata Commit을 차단한다.

Operation-owned Staging / Final / Working Media는 ADR-020 Recovery Classification 이후 60절의 Deletion Safety 조건을 만족할 때만 정리한다.

Project Delete 또는 Cancellation만으로 Valid Media를 즉시 폐기하지 않으며 아직 필요한 Recovery Information과 Active Usage를 보호한다.

Import 취소와 Cleanup은 Mellow의 Operation-owned Media에만 적용하며 Photos 원본을 수정하거나 삭제하지 않는다.

### Deletion Reconciliation

App Relaunch 시 영속적인 Logical Deletion을 확인하고 삭제된 Target을 정상 Draft 또는 Clip으로 복구하지 않는다.

Process가 종료되었다는 사실만으로 모든 Media가 Discardable이라고 가정하지 않으며 ADR-020의 Recovery Classification과 현재 Active Usage를 함께 확인한다.

Deferred Cleanup과 실패한 Project Cleanup을 반복해도 다른 Draft를 손상시키거나 이미 삭제된 Artifact의 오류를 반복하지 않는다.

이 계약은 구체적인 Tombstone Format이나 Active Usage 추적 Type을 강제하지 않는다.

---

## 62. Storage Monitoring

`StorageMonitor`는 ADR-024에 따라 Recording, Photos Import / Normalization과 Export 각각의 Operation-aware Storage Preflight를 지원한다.

### Core Requirement

개념적인 Required Free Space는 다음과 같다.

`Required Free Space = Estimated Peak Additional Storage + Safety Reserve`

Estimated Peak Additional Storage는 Final File Size만이 아니라 Operation Lifetime 동안 동시에 존재할 수 있는 Staging, 선택된 Source Materialization, Normalization Intermediate / Output, Temporary Output, Final Output과 Operation-owned Recovery Material을 고려한다.

기존 Committed Media의 크기를 해당 Operation이 새로 요구하는 Additional Storage로 다시 계산하지 않는다.

Safety Reserve는 Estimate 오차, Filesystem Overhead, Metadata Persistence, 예상 밖의 작은 Temporary Growth와 OS / App Headroom을 위한 필수 여유이며 기본값을 0으로 두지 않는다.

정확한 Safety Reserve Bytes, Estimate Formula, Bitrate Constant, Temporary Multiplier와 Warning Threshold는 이 계약에서 숫자로 고정하지 않고 관련 Pipeline Profile과 iPhone 12 측정을 바탕으로 각 Owning Phase Gate에서 결정한다.

Estimate는 안전을 위해 보수적일 수 있지만 모든 Operation에 실제 필요량과 무관한 하나의 과도한 고정값을 적용하지 않고 각 Pipeline의 Peak Additional Storage 특성을 근거로 산정한다.

Estimate 조정을 이유로 승인된 Media Quality 변경, User Media 자동 Cleanup 또는 새로운 Project Limit이 필요해지면 별도 Product Decision과 Replanning을 거친다.

### Operation-specific Estimates

Recording Estimate는 승인된 최대 10초 Capture Profile이 생성할 Media, Staging / Finalization Overhead, Transactional Commit과 Safety Reserve를 고려한다.

Import Estimate는 선택된 최대 10초 Source Segment의 Operation-owned Storage, Staging, Normalization Intermediate / Output, Project-owned Working Media, Recovery-safe Overlap과 Safety Reserve를 고려한다.

Import Estimate는 전체 Photos Original 4K Source를 Mellow Container에 무조건 복제한다고 가정하지 않으며 ADR-022의 Source / Working Media 계약을 따른다.

Export Estimate는 현재 Immutable Export Snapshot의 Project Duration과 State, 승인된 Export Profile, Temporary Export Output, Final Local Export Artifact, Photos Save / Share Handoff까지 보존할 Local Artifact와 Safety Reserve를 고려한다.

Export Preflight가 성공해도 Photos Library Save가 성공한다고 보장하지 않는다.

### Available Capacity and Recheck

Storage Preflight는 Operation이 실제로 쓰는 Application Container / Filesystem Volume의 Usable Capacity를 기준으로 판단하고 장시간 유지된 Cached Value만 신뢰하지 않는다.

Preflight는 다른 App과 System의 동시 Storage 사용 때문에 Runtime Disk Full이 발생하지 않는다는 보장이 아니다.

Operation 특성상 필요한 경우 시작 직전, 큰 Derived Output 생성 직전 또는 Required Estimate가 크게 바뀌는 경계에서 Storage를 다시 확인할 수 있어야 하지만 모든 Write마다 Storage API를 호출하도록 강제하지 않는다.

### Operation-scoped Failure

Storage가 부족하면 기본적으로 해당 Operation만 시작하지 않고 Typed Error를 Feature Layer로 전달한다.

Recording Storage가 부족하면 Recording, Progress, 10초 Timer와 부분 Media Operation을 시작하지 않는다.

Import Storage가 부족하면 Materialization / Normalization을 시작하지 않는다.

Export Storage가 부족하면 해당 Export를 시작하지 않는다.

다른 Operation은 자체 Requirement로 독립적으로 판단하며 Mellow 전체를 Low-storage Fatal State로 전환하거나 기존 Draft 열기, Clip 확인, Metadata-only Editing과 다른 사용 가능한 기능을 자동 차단하지 않는다.

Feature Layer는 사용자가 현재 시작할 수 없는 Operation, 기존 Media가 유지된다는 점과 공간 확보 후 재시도할 수 있음을 이해할 수 있게 전달한다.

정확한 Copy, Alert / Banner / Sheet, Icon과 Button Placement는 이 Architecture에서 확정하지 않고 각 Owning Phase의 Structural UX Gate에 남긴다.

Storage 부족을 이유로 1080p를 720p로 낮추거나 Frame Rate, Audio, Recording Duration, Import Working Media 또는 Export Quality를 자동으로 변경하지 않는다.

Storage-based Quality Mode나 새로운 Project Size Cap은 별도 Product Decision 없이는 도입하지 않는다.

전체 Vlog Duration이나 Clip Count의 임의 Product Limit을 Storage 관리 수단으로 사용하지 않는다.

### Runtime Disk Full and Cleanup Safety

Preflight 이후 Runtime Disk Full 또는 Write Failure가 발생하면 실패 Operation을 성공으로 표시하지 않고 Partial / Incomplete Output을 정상 Clip 또는 Export로 Commit하지 않는다.

기존 Committed Media, 다른 Draft와 Photos 원본은 변경하거나 삭제하지 않는다.

Recording / Import Media는 ADR-020의 Recovery Classification을 적용하고 Project Delete 또는 Late Result Race에는 ADR-021의 Project Validity와 Deletion Safety를 적용한다.

Final Media가 존재하지만 Metadata Persistence가 Storage 부족으로 실패한 경우 Recovery Candidate로 보존한다.

Cleanup 실패는 재시도 가능해야 하며 Storage Pressure 때문에 Committed Clip, Draft, Project-owned Valid Media, Recovery Candidate, Undo Candidate, Active Usage Media 또는 다른 Project Media를 자동 삭제하지 않는다.

자동 Cleanup은 ADR-020 / ADR-021에 따라 Recovery가 필요하지 않고 Undo / Active Usage / 다른 Reference가 없다고 안전하게 확인된 Disposable Temporary Artifact 또는 Confirmed Orphan에만 적용한다.

Recovery Classification을 생략하거나 불명확한 Media를 공간 확보 목적으로 삭제하지 않는다.

---

## 63. Permissions Architecture

Permission Logic을 SwiftUI View마다 반복 구현하지 않는다.

`PermissionService`가 다음 권한 상태를 관리한다.

- Camera
- Microphone
- Photos Save

Photos Video Import는 가능한 한 System Photos Picker를 사용하여 광범위한 Photos Read Permission 의존성을 최소화한다.

Direct Recording Ready 상태는 최소한 Camera Authorization 허용, Microphone Authorization 허용, Required Capture Device 사용 가능, Capture Session 구성 성공, 유효한 Project와 Orientation Eligibility 충족을 요구한다.

Camera 또는 Microphone Permission이 Denied / Restricted이면 Capture Pipeline이나 Recording Timer를 부분적으로 시작하지 않고 Typed Permission Failure를 Feature Layer에 전달한다.

Microphone Permission이 없을 때 Video-only Direct Recording으로 자동 Fallback하지 않는다.

Photos Video Import는 Camera / Microphone Authorization과 결합하지 않고 자체 Photos Picker / Permission 계약을 따르며 Camera 또는 Microphone Permission 문제로 차단하지 않고 Audio Track이 없는 Source도 허용한다.

---

## 64. Error Architecture

Low-level Apple Framework Error를 사용자 UI에 직접 노출하지 않는다.

Typed Application Error를 사용한다.

### Candidate Error Types

- `cameraUnavailable`
- `cameraPermissionDenied`
- `microphonePermissionDenied`
- `recordingInterrupted`
- `recordingFailed`
- `mediaImportFailed`
- `unsupportedMedia`
- `insufficientStorage`
- `previewFailed`
- `exportFailed`
- `photosSaveFailed`
- `projectCorrupted`

Technical Error 정보는 Logging에 기록할 수 있다.

사용자에게는 `DESIGN.md`에서 정의한 Error UX에 맞는 메시지를 제공한다.

---

## 65. Swift Concurrency

Mellow는 Swift Concurrency를 기본 비동기 모델로 사용한다.

UI State 변경은 Main Actor에서 수행한다.

File System과 Media Processing은 Main Actor 밖에서 수행한다.

Camera Session Operation은 안전한 Serial Execution Context에서 관리한다.

Thumbnail 생성, Media Import, Composition 생성, Export 준비가 Main Thread를 Block하지 않아야 한다.

---

## 66. Cancellation

사용자가 Import, Preview 준비 또는 Export Flow를 종료한 경우 취소 가능한 작업은 중단할 수 있어야 한다.

Task Cancellation을 무시하고 불필요한 Media Processing을 계속 수행하지 않는다.

취소된 Temporary Media는 안전하게 정리한다.

Recording / Import의 Temporary Media는 취소 또는 실패 사실만으로 폐기하지 않으며 25절과 59절에 따라 Recovery Candidate 여부와 Source Ownership을 먼저 확인하고 Discardable Artifact만 정리한다.

Cancellation은 Cooperative하므로 요청 사실만으로 Active Producer / Consumer가 종료되거나 Media를 Release했다고 간주하지 않는다.

Project Delete로 취소된 작업도 60절과 61절의 Validity 및 Deletion Safety 조건을 따르며 Source Media를 사용하는 동안 Physical Cleanup을 지연한다.

Recording Stop은 일반 Task Cancellation과 별개의 Camera Operation으로 관리한다.

---

## 67. App Lifecycle

Camera Session은 App Lifecycle에 맞게 시작하고 중지한다.

앱이 Background로 이동한 상태에서 Camera Recording을 계속한다고 가정하지 않는다.

Recording 중 App Lifecycle / Capture Session / System Interruption, Camera Resource Unavailable 또는 Unexpected Termination이 발생하면 Capture Operation을 안전하게 Stop / Cancel / Finalize 가능한 경로로 이동한다.

Interruption을 Successful Manual Stop 또는 Successful 10-second Auto-stop으로 표시하지 않고 H04의 Completion Haptic을 자동 적용하지 않는다.

Interruption으로 생성된 Media는 ADR-020의 Transactional Commit / Validation / Recovery를 따르며 Invalid / Incomplete Media는 정상 Clip으로 Commit하지 않는다.

Interrupted Result의 Late Commit은 ADR-021의 Project Validity / Late Result / Deletion Safety 계약을 따라야 하며 현재 Project나 다른 Draft를 되살리거나 변경하지 않는다.

Valid Partial Media의 최종 보존 / Commit / 폐기와 Minimum Valid Clip Duration은 별도 Pending으로 유지한다.

Interruption 상태는 Feature Layer에 전달한다.

---

## 68. Export and Background

전체 Vlog 길이에는 제한이 없으므로 Export가 길어질 수 있다.

iOS가 Background Processing을 무제한 허용한다고 가정하지 않는다.

MVP에서는 Foreground Export를 기본 방향으로 한다.

Export 중 앱이 Background로 이동했을 때의 정책은 실제 Device Test 결과를 바탕으로 별도로 결정한다.

---

## 69. Logging

System Logging은 `OSLog` 기반으로 구성한다.

### Logging Categories

- App
- Camera
- Recording
- Import
- Persistence
- Preview
- Export
- Storage

사용자의 실제 Video Frame 또는 Audio Content를 Logging하지 않는다.

Production Log에 불필요한 Personal Media 정보나 전체 Local Path를 기록하지 않는다.

---

## 70. Privacy

Mellow의 MVP Media Processing은 Local-first 원칙을 따른다.

다음 작업은 Server Upload 없이 iPhone에서 수행한다.

- Camera Recording
- Video Import
- Trim
- Framing
- Preview
- Export

사용자의 Video 또는 Audio를 Mellow Server로 자동 Upload하지 않는다.

---

## 71. Analytics

Third-party Analytics SDK는 MVP의 기본 Dependency로 추가하지 않는다.

Analytics 사용 여부가 제품적으로 결정되기 전까지 Tracking System을 Architecture 필수 요소로 만들지 않는다.

향후 Analytics가 필요하면 별도의 Analytics Boundary를 추가한다.

---

## 72. Dependency Injection

Service Instance를 SwiftUI View 내부에서 반복 생성하지 않는다.

App Startup에서 `AppEnvironment` 또는 유사한 Dependency Container를 구성한다.

### Primary Dependencies

- ProjectRepository
- MediaStore
- CameraCaptureService
- VideoImportService
- ThumbnailService
- PreviewService
- ExportService
- PhotoLibraryService
- PermissionService
- StorageMonitor

Production과 Test에서 서로 다른 구현을 주입할 수 있어야 한다.

---

## 73. Navigation

Navigation은 SwiftUI Native Navigation을 사용한다.

MVP에서 Third-party Navigation Framework를 추가하지 않는다.

전역 Navigation State가 필요한 경우 얇은 `AppRouter`를 사용할 수 있다.

Feature State가 다른 Feature의 Concrete SwiftUI View를 직접 생성하는 구조를 피한다.

---

## 74. Physical Device Testing

Camera와 실제 Video Processing이 핵심인 Mellow에서는 Simulator만으로 기능 완료를 판단하지 않는다.

Primary Physical Test Device는 iPhone 12다.

### iPhone 12에서 반드시 검증할 항목

- App Launch
- SwiftUI Navigation
- Rear Camera Preview
- Front Camera Preview
- Rear 1× Wide Device Selection
- Rear Preview / Active Recording Continuous Zoom과 1× Minimum / 승인된 Maximum Clamp
- Zoom 중 동일 Clip / Timer / Operation 유지와 Mid-record Rotation 시 Zoom 유지
- Rear Camera Recording
- Front Camera Recording
- Front Preview / Direct-recorded Result Mirroring Parity
- Camera Switching
- Camera / Microphone Permission Denied 상태에서 Direct Recording 차단과 Photos Import 독립성
- 1080p 30 fps Recording
- 10초 자동 종료
- Microphone Audio
- Portrait 9:16 Recording
- Landscape 16:9 Recording
- Portrait / Landscape Orientation Start Gate, Landscape Left / Right와 Face Up / Down / Unknown 처리
- Mid-record Rotation 중 Recording / Project Orientation 유지와 다음 Recording Eligibility 재확인
- Recording Interruption의 Successful Completion 분리와 ADR-020 / ADR-021 Media Safety
- Photos Video Import
- 4K Source Import
- 4K SDR / HDR / Dolby Vision Source의 1080p-class / 30 fps / SDR Working Media Processing
- Normalization 이후 Source Orientation과 Framing 가능 영역 보존
- Trim
- Framing
- Multi-clip Preview
- 1080p Export
- Photos Save
- Share Sheet
- Draft Recovery
- Large Project Behavior
- Recording / Import / Export Operation-aware Storage Preflight와 Estimate 대비 실제 Peak Additional Storage
- Runtime Disk Full, Retry와 Recovery Candidate / Existing Media 보호
- Storage Pressure에서 안전하게 분류된 Disposable Artifact만 Cleanup되는지 확인
- Storage Error Handling
- Haptic Feedback

iPhone 12에서 반복적으로 Frame Drop, UI Freeze, Memory Pressure 또는 비정상적인 발열이 발생하는 구현은 최적화 대상이다.

---

## 75. Unit Tests

다음 Logic은 AVFoundation Hardware 없이 Unit Test할 수 있어야 한다.

- Clip 최대 10초 Validation
- Project Duration 계산
- Clip Reorder
- Clip Delete / Undo State
- Draft Metadata
- 자동 Project Display Name
- Project Orientation Policy
- Trim Range Validation
- Normalized Framing
- Export Canvas Size
- Export Profile
- Recording / Import / Export Storage Requirement Policy
- Estimated Peak Additional Storage와 Safety Reserve 계산 경계
- Operation-scoped Insufficient Storage State
- Error Mapping

---

## 76. Media Integration Tests

작은 Video Fixture를 이용해 실제 AVFoundation Media Pipeline을 검증한다.

### Test Areas

- Clip Trim
- Multiple Clip Composition
- Clip Order
- Portrait Composition
- Landscape Composition
- Audio Track 유지
- Fill + Crop
- 4K Input to 1080p Output
- SDR / HDR / Dolby Vision 및 High-resolution Source의 SDR Working Media Normalization
- 30 fps 초과 Source의 30 fps Working Media Validation
- Source Presentation Transform 및 Aspect Mismatch에서 Framing 영역 보존과 Project Crop bake-in 방지
- SDR 변환 실패의 Final Validation 거부와 Valid Source / Recovery Candidate 보존
- 동일한 Project State의 Preview / Export SDR Color 및 Framing Parity
- 30 fps Output
- Export File 생성
- Recording / Import Media Commit의 Failure Boundary A–H
- Materialization 이후 Metadata Persistence 실패와 Relaunch Recovery
- Normalization 실패 시 Valid Source 보존
- Reconciliation 반복 시 Duplicate Commit 방지
- Recovery Classification 이후 Cleanup과 Cleanup Idempotency
- Missing / Corrupt Media와 Multiple Draft Isolation
- Project Delete와 Recording / Import Finalization의 Late Commit Race
- Undo Eligibility 및 Active Usage에 따른 Deferred Physical Delete
- Pending Deletion의 Process Termination / Relaunch Reconciliation
- Export Snapshot 불변성과 Source Media Release 전 Cleanup 차단
- Preview Mutation Invalidation 및 Stale Derived Result 폐기
- Project Delete Cleanup 실패와 Idempotent Retry
- Recording / Import / Export Storage Preflight 실패와 Operation 미시작
- Preflight 이후 Runtime Disk Full에서 Partial Output 비Commit과 Existing Media 보호
- Metadata Persistence Storage Failure에서 Final Media의 Recovery Candidate 보존
- Storage Pressure Cleanup의 Safe Classification, Multiple Draft Isolation과 Idempotent Retry

Media Commit의 기본 Failure Boundary 검증은 Recording을 구현하는 Phase 4부터 수행하고 Phase 6에서 Import에 적용하며 Phase 10에서 반복 Relaunch와 복합 실패 조건을 강화한다.

Repository에 지나치게 큰 Test Video File을 포함하지 않는다.

---

## 77. UI Tests

UI Test에서는 실제 Camera Hardware 대신 Test Double을 주입할 수 있는 구조를 만든다.

다음 Flow를 자동 검증할 수 있는 방향을 목표로 한다.

- Home
- New Vlog
- Orientation Selection
- Mock Recorded Clip 추가
- Mock Imported Clip 추가
- Clip Reorder
- Clip Delete + Undo
- Trim
- Preview 진입
- Export Success
- Recent Project Recovery

---

## 78. Build Quality

새 기능 구현 후 최소한 다음 검증을 수행한다.

- Xcode Build
- Unit Tests
- 관련 Integration Tests
- Compiler Warning 확인
- `git diff --check`

Camera, Orientation, Media Import 또는 Export 변경사항은 Physical iPhone Test를 추가한다.

---

## 79. Swift Concurrency Safety

Swift의 Concurrency Warning을 초기부터 무시하지 않는다.

Actor Isolation과 MainActor 경계를 명확하게 관리한다.

단순히 Compiler Warning을 제거하기 위해 `@unchecked Sendable`을 남용하지 않는다.

AVFoundation 객체가 임의의 Thread에서 안전하다고 가정하지 않는다.

---

## 80. Third-party Dependencies

MVP에서는 Third-party Dependency를 기본적으로 사용하지 않는다.

새 Dependency를 추가할 경우 다음 기준을 검토한다.

- Apple Native API만으로 해결하기 지나치게 어려운가
- 장기 유지보수가 가능한가
- Privacy Risk가 없는가
- App Size에 미치는 영향이 적절한가
- License가 적절한가
- Library가 사라져도 교체 가능한 구조인가

Third-party Dependency 도입 전 이유를 `DECISIONS.md`에 기록한다.

---

## 81. Architecture Decision Records

중요한 Architecture Decision은 `DECISIONS.md`에 기록한다.

### ADR 대상 예시

- iOS 18 Minimum Deployment Target
- iPhone 12 Quality Baseline
- SwiftData 사용
- 1080p 30 fps Working Profile
- Camera Recording Pipeline
- Imported Media Storage Strategy
- Re-trim Policy
- Export Codec
- HDR Policy
- Background Export Policy
- Third-party Dependency 도입

---

## 82. Confirmed Technical Decisions

현재 확정된 기술 방향은 다음과 같다.

- Mellow는 iPhone-first Native Application이다.
- Swift를 사용한다.
- UI는 SwiftUI를 사용한다.
- Minimum Deployment Target은 iOS 18.0이다.
- Mellow의 공식 Device Quality Baseline은 iPhone 12 이상이다.
- Primary Physical Test Device는 iPhone 12다.
- Camera와 Media 핵심 기능은 Physical iPhone Test를 필수로 한다.
- Mellow MVP의 표준 Video Resolution은 1080p다.
- Portrait Project Output은 1080 × 1920을 사용한다.
- Landscape Project Output은 1920 × 1080을 사용한다.
- 기본 Frame Rate는 30 fps다.
- Mellow Camera는 MVP에서 1080p 30 fps를 기본으로 촬영한다.
- MVP에서 720p Export를 제공하지 않는다.
- MVP에서 4K Export를 제공하지 않는다.
- MVP에서 60 fps Export를 제공하지 않는다.
- 4K를 포함한 고해상도 Photos Video를 Import할 수 있다.
- SDR, HDR / Dolby Vision 및 30 fps 초과 Source Import를 허용한다.
- Imported Video는 선택한 최대 10초 구간을 기준으로 1080p-class / 30 fps / SDR Working Media로 정규화한다.
- Working Media는 Source Presentation Aspect Ratio와 Framing 가능 영역을 보존하며 Project Fill + Crop을 bake-in하지 않는다.
- MVP Preview와 Export는 SDR이며 HDR Export는 MVP에서 제공하지 않는다.
- Preview / Export는 가능한 한 동일한 Composition / Color Handling으로 SDR Interpretation과 Framing을 일치시킨다.
- Photos 원본 Media는 변경하지 않는다.
- Metadata는 SwiftData를 사용한다.
- 실제 Video File은 File System에서 관리한다.
- Draft Media는 Application Support에 저장한다.
- Absolute File Path를 SwiftData에 저장하지 않는다.
- Camera Session은 SwiftUI View에서 분리한다.
- MVP Recording은 `AVCaptureMovieFileOutput`을 우선 사용한다.
- Clip 최대 10초 Rule은 Domain과 Capture Pipeline 모두에서 강제한다.
- Front Camera와 Rear Camera를 지원한다.
- Recording 중 Camera Switching은 허용하지 않는다.
- Rear Camera는 기본 1× Wide를 사용하고 Preview와 Active Recording에서 1× 이상 Continuous Zoom을 지원한다.
- Rear Zoom은 Phase 3에서 승인한 Maximum Product Quality Limit으로 Clamp하며 0.5× Ultra Wide / Telephoto / Lens Selector와 Front Camera Zoom은 MVP에서 제공하지 않는다.
- Rear Zoom은 동일 Recording / Clip / Operation Identity와 10초 Timer를 유지하며 Phase 7 Editing Framing과 별개의 Capture-time Behavior다.
- Front Camera Preview와 Direct-recorded Front Clip의 Preview / Editing / Export는 동일한 Mirrored Appearance를 유지하고 Photos Import Source에는 이 정책을 적용하지 않는다.
- Direct Recording은 Camera와 Microphone Authorization을 모두 요구하며 Video-only 자동 Fallback 없이 Photos Import와 독립적으로 동작한다.
- Project Orientation과 Device Orientation을 분리한다.
- 새 Recording은 Project와 Device Orientation이 일치할 때만 시작하고 Landscape Left / Right는 모두 유효하며 Face Up / Down / Unknown / Unstable 상태는 유효하지 않다.
- Mid-record Rotation은 현재 Recording을 Stop / Restart하거나 Project Orientation / Clip Aspect Ratio / Rear Zoom을 변경하지 않으며 다음 Recording 전에 Eligibility를 다시 확인한다.
- Recording Interruption은 Successful Completion과 구분하고 ADR-020 / ADR-021을 따르며 Partial Clip 처리와 Minimum Valid Clip Duration은 Pending이다.
- Trim은 Non-destructive 방식으로 구현한다.
- Imported Video의 기본 Layout은 Fill + Crop이다.
- Preview와 Export는 Shared Composition Definition을 사용한다.
- Preview는 Composition 기반 Virtual Timeline을 우선 사용한다.
- MVP Export는 `AVAssetExportSession`을 우선 사용한다.
- Media File Operation은 Actor 기반으로 관리한다.
- Core Media Processing은 Local-first로 구현한다.
- Recording과 Import는 Durable Operation Identity를 사용하는 공통 Media Commit Lifecycle을 따른다.
- Clip Commit 완료는 Valid Project-owned Final Media와 성공한 Clip Metadata Persistence 및 유효한 Project를 모두 요구한다.
- Recording / Import Media Cleanup은 Recovery Classification 이후 수행하며 Metadata 부재만으로 Confirmed Orphan을 판정하지 않는다.
- Recovery와 Reconciliation은 Idempotent하며 Operation / Clip Identity로 Duplicate Commit을 방지한다.
- Logical Deletion과 Physical Deletion을 분리하고 Undo / Recovery / Active Usage가 남아 있으면 Physical Cleanup을 지연한다.
- Project Delete는 먼저 영속적인 Invalid Commit Target을 확립하며 Late Async Result로 Project나 Clip을 되살리지 않는다.
- MVP의 사용자-visible Undo는 가장 최근 Clip Delete 한 건이며 Process Termination 이후에는 유지하지 않는다.
- Undo는 기존 Clip Identity와 Media를 재사용하고 Stable Anchor 및 Original Index로 복원 위치를 결정한다.
- Export는 Immutable Project Snapshot을 사용하며 이후 일반 Clip Mutation이 진행 중인 Export 결과를 소급 변경하지 않는다.
- Preview는 현재 Project State를 반영하며 Stale Composition을 Invalidate / Rebuild한다.
- Third-party Dependency를 최소화한다.

---

## 83. Architecture Invariants

구현 과정에서 다음 원칙은 항상 유지한다.

### Media Safety

정상적으로 촬영 또는 Import가 완료된 Clip이 단순한 UI Navigation 때문에 유실되어서는 안 된다.

### Original Preservation

Photos Library의 원본 Video를 수정하거나 삭제하지 않는다.

### Media Commit Completion

25절의 Committed Clip 조건을 모두 만족하기 전에는 정상 Project Clip으로 노출하지 않는다.

### Recovery Before Cleanup

Metadata가 없는 Media도 Recovery Candidate 여부를 먼저 확인하며 59절의 분류와 Orphan 조건을 충족하기 전에 파괴적으로 정리하지 않는다.

Recovery와 Cleanup을 반복해도 정상 Media 유실이나 Duplicate Clip 등록이 발생해서는 안 된다.

### Logical Deletion and Active Media Usage

Logical Deletion does not imply immediate Physical Deletion.

Physical Delete는 Logical Ownership / Reference 해제, Undo Eligibility 종료, Recovery 필요 없음, Active Media Usage 없음, Late Commit 차단과 Safe Cleanup Classification을 모두 요구한다.

MediaStore Actor만으로 Cross-service Lifecycle이 해결된다고 가정하지 않으며 Repository / Operation Lifecycle / Media Storage 사이에서 이 조건을 조정해야 한다.

### No Deleted Target Resurrection

삭제된 Project나 Clip에 Late Async Result를 적용하여 Metadata 또는 사용자-visible 상태를 다시 생성하지 않는다.

### In-flight Export Stability

일반 Clip Mutation은 이미 시작된 Immutable Export Snapshot을 변경하지 않으며 Snapshot Media는 실제 Reference Release 전까지 Physical Delete하지 않는다.

### Clip Duration

Project에서 사용하는 하나의 Clip은 10초를 초과하지 않는다.

### Project Orientation

Project Aspect Ratio는 Device Rotation으로 자동 변경되지 않는다.

Recording Start Eligibility는 일시적인 Device Orientation과 고정된 Project Orientation을 비교하며 Mid-record Rotation은 현재 Clip의 Project Presentation Orientation을 변경하지 않는다.

### Rear Camera and Continuous Zoom

MVP Rear Capture는 1× Wide를 기본으로 하며 1× 이상 Continuous Zoom은 Preview와 Active Recording에서 같은 Camera, Clip, Operation Identity와 Timer를 유지한다.

Zoom Factor는 승인된 Product Range로 Clamp하고 Rotation만으로 Reset하지 않으며 0.5× / Telephoto / Lens Selector와 Front Zoom은 MVP에 포함하지 않는다.

### Capture Zoom and Editing Framing Separation

Rear Capture Zoom은 촬영 결과에 반영되는 Camera Behavior이고 Editing Framing은 Working Media 범위 안의 비파괴 Metadata Transform이며 두 책임을 하나의 복원 가능한 Zoom 개념으로 합치지 않는다.

### Front Camera Appearance Parity

Front Camera Preview와 Committed Direct-recorded Front Clip의 Preview / Editing / Export는 동일한 Mirrored Appearance를 유지하며 명확한 Transform Ownership으로 Double-mirroring과 Accidental Un-mirroring을 방지한다.

### Recording Readiness and Interruption

Camera / Microphone Permission, Required Device, Session Configuration, Project Validity와 Orientation Eligibility를 모두 확인하기 전에는 Direct Recording을 시작하지 않는다.

Interruption은 Successful Completion이 아니며 Media 결과는 ADR-020 / ADR-021의 Validation, Recovery, Project Validity와 Late Result 계약을 따른다.

### 1080p Project Standard

Imported Working Media는 1080p-class / 30 fps / SDR을 기준으로 하며 Project Output / Export는 Orientation에 맞는 1080p Canvas / 30 fps / SDR을 사용한다.

### Framing Preservation During Normalization

Normalization standardizes media characteristics, but does not commit the user's project framing.

Source Presentation Aspect Ratio와 이후 Framing 가능한 유효 영역을 보존하며 Project Fill + Crop은 Working File에 bake-in하지 않고 Metadata를 통해 Preview / Export Composition에서 적용한다.

### Preview and Export Parity

Preview와 Export는 SDR을 기준으로 가능한 한 동일한 Composition Definition / Color Handling을 사용하며 동일한 Project State의 Framing, Transform과 SDR Interpretation을 일치시킨다.

### Local-first

MVP의 핵심 Media Workflow는 Server Connection 없이 동작해야 한다.

### No Arbitrary Vlog Limit

전체 Vlog Duration이나 Clip Count에 기술적 편의를 위한 임의의 제품 제한을 추가하지 않는다.

### Operation-aware Storage Safety

Recording, Import와 Export는 각각 Estimated Peak Additional Storage와 Safety Reserve를 사용하는 독립적인 Preflight를 적용하고 하나의 고정 Global Threshold를 기본 전략으로 사용하지 않는다.

Storage 부족은 해당 Operation을 차단하며 승인된 Media Quality를 자동 하향하거나 User Media와 Recovery Candidate를 자동 삭제하지 않는다.

Runtime Disk Full의 Partial Output을 성공으로 Commit하지 않고 ADR-020 / ADR-021의 Recovery와 Cleanup Safety를 유지한다.

### UI and Infrastructure Separation

SwiftUI View는 Camera Session, File System 또는 SwiftData를 직접 조작하지 않는다.

### iPhone 12 Performance Baseline

핵심 사용자 Flow는 iPhone 12에서 실사용 가능한 수준으로 동작해야 한다.

---

## 84. Open Architecture Decisions

### Capture

- Camera Session Preset의 세부 설정
- Rear Camera Lens 정책 — Resolved by ADR-023: MVP 기본 1× Wide이며 0.5× Ultra Wide / Telephoto / Lens Selector는 제외.
- Rear Continuous Zoom — Resolved by ADR-023: Preview와 Active Recording에서 1× 이상 지원.
- Rear Maximum Zoom Product Quality Limit — Pending, Phase 3 Gate.
- Rear Zoom의 정확한 Interaction / Indicator / Visual Presentation — Pinch-to-zoom은 Primary Candidate이며 Final 선택은 Phase 3 Gate.
- Front Camera Zoom — Out of MVP by ADR-023.
- Front Camera 저장 영상의 Mirror Policy — Resolved by ADR-023: Preview와 Direct-recorded Result 모두 Mirrored Appearance 유지.
- Camera / Microphone Permission의 Direct Recording 동작 — Resolved by ADR-023: 둘 다 필요하며 Video-only Fallback 없음.
- 정확한 Orientation Detection API / Threshold / Debounce — Pending.
- Minimum Valid Clip Duration — Pending.
- Recording Interruption에서 Valid Partial Clip의 최종 처리 — Pending.
- Recording Error / Interruption Haptic — Pending.

### SDR Color Technical Details

HDR / Dolby Vision Source 허용, SDR Working Media / Preview / Export 방향은 ADR-022로 확정되어 있으며 다음 세부사항만 Pending이다.

- 정확한 SDR Color Profile / Tagging
- HDR / Dolby Vision Source의 Tone-mapping 구현 방법

### Imported Media

- Materialized Segment 외 원본 Source Reference를 유지할지 여부
- Imported Clip의 Re-trim 범위
- Source Video Transcoding 세부 정책
- 매우 낮은 Resolution Source의 Upscaling 정책
- Working Media Codec
- Working Media Container
- 1080p-class Working Media의 정확한 Raster Dimension Rule

Working Media Codec / Container, SDR Profile / Tagging, Upscaling과 Raster Dimension Rule은 Phase 6 구현 전 Gate이며 Export Codec / Container와 별개로 결정한다.

### Preview

- Composition Rebuild Cache 정책
- 매우 많은 Clip이 존재할 때 Preview Optimization

### Export

- H.264 또는 HEVC
- File Container
- Audio Format
- Audio Bitrate
- Video Bitrate
- Background Export 정책
- Export Retry 정책

### Storage

- Operation-aware Storage Preflight와 Fixed Global Threshold 미사용 — Resolved by ADR-024.
- Recording / Import / Export별 Estimated Peak Additional Storage + Safety Reserve — High-level Policy Resolved by ADR-024.
- 정확한 Safety Reserve Bytes — Pending, 관련 Owning Phase Gate.
- Recording Estimate Formula, Capture Codec / Bitrate 상수와 Finalization Overhead — Pending, Before Phase 4.
- Import Estimate Formula와 Temporary / Recovery-safe Overlap Multiplier — Pending, Before Phase 6.
- Export Snapshot 기반 Estimate Formula와 Temporary Multiplier — Pending, Before Phase 9.
- Storage Warning Threshold와 Low-storage UI Presentation — Pending, Owning UX Gate.

### Testing

- iPhone 12 외 추가 Device Test Matrix
- CI 환경
- Test Fixture Format

이 항목들은 관련 기능 구현 전에 제품 가치, 호환성, 성능, 구현 비용을 검토하여 결정한다.

---

## 85. Architecture Completion Criteria

Architecture는 최소한 다음 질문에 명확한 답을 제공해야 한다.

- Mellow가 지원하는 Minimum iOS Version은 무엇인가?
- 어떤 iPhone을 성능 기준으로 사용하는가?
- Mellow Camera는 어떤 Resolution과 Frame Rate로 촬영하는가?
- 4K Imported Video는 어떻게 1080p Project에 들어오는가?
- Project Metadata는 어디에 저장하는가?
- 실제 Video File은 어디에 저장하는가?
- 촬영된 Clip은 어떻게 안전하게 Project에 추가하는가?
- Photos 원본은 어떻게 보호하는가?
- 긴 Photos Video에서 어떻게 최대 10초 Clip을 만드는가?
- Trim은 어떻게 비파괴적으로 관리하는가?
- 9:16과 16:9 Project를 어떻게 일관되게 유지하는가?
- Preview와 Export 결과를 어떻게 동일하게 유지하는가?
- 많은 Clip을 가진 Project에서 Memory 사용량을 어떻게 제어하는가?
- Draft는 앱 재실행 이후 어떻게 복구하는가?
- Clip 삭제 Undo와 실제 Media File 삭제를 어떻게 일치시키는가?
- Camera Session과 SwiftUI를 어떻게 분리하는가?
- iPhone 12에서 어떤 기능을 반드시 테스트하는가?

이 질문에 대한 Architecture Decision이 변경될 경우 해당 문서와 `DECISIONS.md`를 함께 업데이트한다.
