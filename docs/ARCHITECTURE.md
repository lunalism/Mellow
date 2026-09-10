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

Mellow MVP의 표준 Working Resolution과 Export Resolution은 1080p다.

### Portrait Project

- Resolution: 1080 × 1920
- Aspect Ratio: 9:16

### Landscape Project

- Resolution: 1920 × 1080
- Aspect Ratio: 16:9

### Default Frame Rate

- 30 fps

Mellow MVP에서는 720p를 기본 작업 해상도로 사용하지 않는다.

Mellow MVP에서는 4K Export를 제공하지 않는다.

Photos에서 4K를 포함한 고해상도 Video를 Import할 수 있다.

Imported Video는 사용자가 선택한 최대 10초 구간을 기준으로 Mellow의 1080p Working Media로 정규화하는 것을 기본 방향으로 한다.

사용자의 Photos Library에 존재하는 원본 Video는 Resolution 변환 과정에서도 수정하지 않는다.

---

## 6. Video Input Policy

입력 Video의 Resolution은 Mellow의 Working Resolution과 동일할 필요가 없다.

Mellow는 다음과 같은 Source Media를 받아들일 수 있는 구조를 가져야 한다.

- 720p
- 1080p
- 4K
- Portrait Video
- Landscape Video
- 서로 다른 Frame Rate의 Video

입력 포맷이 다양하더라도 Mellow Project 내부에서는 가능한 한 일관된 Working Media를 사용한다.

MVP에서는 다양한 Source Format을 Project 내부에 그대로 혼합하여 처리하는 것보다 1080p 중심으로 정규화하여 Preview와 Export Pipeline의 복잡성을 낮추는 방향을 우선한다.

---

## 7. Frame Rate Policy

Mellow MVP의 기본 Project Frame Rate는 30 fps다.

Mellow Camera에서 새로 촬영하는 Clip은 1080p 30 fps를 기본 Capture Profile로 사용한다.

Photos에서 가져오는 Source Video의 Frame Rate는 30 fps와 다를 수 있다.

Imported Video의 Frame Rate 정규화 방식은 AVFoundation Composition 및 Export 과정에서 일관된 30 fps Output을 생성할 수 있도록 구성한다.

60 fps Export는 MVP에서 제공하지 않는다.

Slow Motion 또는 Variable Speed Editing은 MVP 범위에 포함하지 않는다.

---

## 8. HDR Policy

HDR 및 Dolby Vision 입력 영상의 최종 처리 정책은 아직 확정하지 않는다.

다음 항목은 별도 검토 후 결정한다.

- HDR Source Import 지원 범위
- HDR Metadata 유지 여부
- SDR 변환 여부
- HDR Preview 정책
- HDR Export 지원 여부
- Color Space 변환 정책

HDR 처리를 임의로 확정하지 않는다.

HDR 정책이 결정되기 전까지 Architecture가 특정 HDR 또는 SDR 결과를 제품 요구사항으로 가정하지 않도록 한다.

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
- Orphaned Media 정리
- Storage Availability 확인 지원

`MediaStore`는 Actor 기반으로 구성하는 방향을 사용한다.

동시 File Operation으로 Project Storage가 손상되지 않도록 한다.

---

## 25. Safe Media Write

새로운 Clip은 파일 생성이 시작되었다는 이유만으로 Project의 정상 Clip으로 취급하지 않는다.

다음 Flow를 우선한다.

1. Temporary 또는 Staging Location에 Media 생성
2. Media File 존재 여부 확인
3. AVAsset으로 정상적으로 읽을 수 있는지 확인
4. 필요한 Metadata 확인
5. 필요한 경우 1080p Working Media로 정규화
6. Project Media Directory로 안전하게 이동
7. Project Metadata에 Clip 추가
8. Temporary Data 정리

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
- Camera Switching
- Preview 연결
- Recording 시작
- Recording 종료
- 10초 Maximum Duration 적용
- Orientation 정보 처리
- Session Interruption 처리
- Recording 결과 반환

---

## 27. Camera Capture Profile

Mellow MVP의 기본 Camera Capture Profile은 다음과 같다.

- 1080p
- 30 fps

Mellow Camera에서 4K 촬영 옵션을 MVP에서 제공하지 않는다.

Mellow Camera에서 60 fps 선택 옵션을 MVP에서 제공하지 않는다.

사용자가 촬영 Resolution이나 Frame Rate를 매번 설정하도록 하지 않는다.

Mellow는 Camera Configuration보다 기록 경험의 단순함을 우선한다.

---

## 28. Camera Threading

`AVCaptureSession`의 구성, Start, Stop, Input 변경을 SwiftUI Main Thread에서 직접 수행하지 않는다.

Camera Session 관련 작업은 안전한 Serial Execution Context에서 처리한다.

SwiftUI State Update만 Main Actor에서 수행한다.

Camera Configuration이 UI Rendering을 Block하지 않도록 한다.

---

## 29. Camera Preview

Camera Preview는 AVFoundation Preview Layer를 SwiftUI에 Bridge하여 구성한다.

SwiftUI View의 `body` 재평가가 Capture Session을 새로 생성하지 않아야 한다.

Camera Session Lifecycle과 SwiftUI Rendering Lifecycle을 분리한다.

---

## 30. Video Recording

MVP Recording은 `AVCaptureMovieFileOutput`을 우선 사용한다.

현재 MVP에는 실시간 Filter 또는 Frame-by-frame Video Processing 요구사항이 없다.

따라서 초기부터 `AVCaptureVideoDataOutput`과 `AVAssetWriter`를 이용한 Custom Recording Engine을 만들지 않는다.

향후 실시간 Video Look 또는 Camera Filter가 실제 제품 요구사항이 되면 Recording Pipeline 교체를 별도로 검토한다.

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

---

## 34. Device Orientation

Device Orientation과 Project Orientation을 서로 별도로 관리한다.

Architecture는 Device Rotation을 이유로 Project Orientation 값을 변경하지 않는다.

9:16 Project는 항상 Portrait Project로 유지한다.

16:9 Project는 항상 Landscape Project로 유지한다.

Capture Metadata와 Video Transform은 올바른 Orientation을 유지할 수 있도록 처리한다.

Orientation mismatch 상태는 Feature Layer에 전달하여 `DESIGN.md`에서 정의한 안내 UI를 표시할 수 있어야 한다.

---

## 35. Front Camera Mirroring

Front Camera의 Preview Mirroring과 실제 저장 Video Mirroring은 서로 분리하여 관리할 수 있어야 한다.

Preview는 사용자가 자연스럽게 느끼는 Mirror 상태를 사용할 수 있다.

최종 Recording의 Mirror 정책은 아직 확정하지 않는다.

Mirror Policy는 이후 쉽게 변경할 수 있도록 명시적인 설정으로 관리한다.

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

Mellow Working Media는 1080p 기준으로 정규화한다.

이 과정에서 Photos의 원본 Video는 변경하지 않는다.

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

16:9 Source를 9:16 Project에 추가하면 9:16 Canvas를 가득 채운 후 초과 영역을 Crop한다.

9:16 Source를 16:9 Project에 추가하는 경우에도 동일한 Aspect Fill 원칙을 사용한다.

사용자가 Framing 위치를 조절할 수 있어야 한다.

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

Preview와 Export는 가능한 한 동일한 Composition Definition을 사용한다.

---

## 46. Preview Architecture

전체 Vlog Preview를 위해 매번 하나의 완성 Video File을 미리 Render하지 않는다.

AVFoundation Composition 기반 Virtual Timeline을 우선 사용한다.

AVPlayer가 필요한 Source Media를 재생하도록 한다.

모든 Clip Video Frame을 Memory에 동시에 Load하지 않는다.

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

Mellow MVP는 일관된 1080p 30 fps 결과를 기본으로 제공한다.

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

Export 전 사용할 수 있는 Storage를 확인한다.

Storage가 부족하면 Export 시작 전에 가능한 한 사용자에게 안내한다.

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

앱 실행 시 Project Metadata와 Media File의 일관성을 검증할 수 있어야 한다.

Metadata가 있지만 Media File이 없는 경우 해당 Clip을 손상된 상태로 인식한다.

Media File이 있지만 Metadata가 없는 경우 Orphaned Media로 판단할 수 있다.

하나의 손상된 Clip 때문에 앱 전체가 Crash하거나 모든 Draft를 열 수 없게 되어서는 안 된다.

---

## 60. Clip Deletion and Undo

Clip 삭제 UX는 즉시 삭제 후 Undo를 지원한다.

따라서 사용자가 Delete를 누르는 순간 Media File을 즉시 영구 삭제하지 않는다.

삭제된 Clip은 짧은 Undo Window 동안 Pending Deletion 상태로 처리한다.

Undo가 발생하면 기존 순서와 Metadata를 복구한다.

Undo Window가 종료된 후 실제 Metadata와 Media File을 정리한다.

---

## 61. Project Deletion

Project 삭제는 사용자 Confirmation 이후 실행한다.

Project Metadata와 Project-owned Media를 모두 삭제한다.

Photos Library의 원본 Video에는 영향을 주지 않는다.

부분적으로 삭제된 상태가 남지 않도록 Project 단위 Cleanup Operation으로 구성한다.

---

## 62. Storage Monitoring

`StorageMonitor`는 Media 생성과 Export 전에 사용 가능한 Storage를 확인한다.

다음 작업 전 Storage 상태를 확인한다.

- Recording 시작
- Imported Media Materialization
- Export 시작

고정된 Vlog Duration Limit을 Storage 관리 수단으로 사용하지 않는다.

Storage가 부족한 경우 Typed Error를 Feature Layer로 전달한다.

---

## 63. Permissions Architecture

Permission Logic을 SwiftUI View마다 반복 구현하지 않는다.

`PermissionService`가 다음 권한 상태를 관리한다.

- Camera
- Microphone
- Photos Save

Photos Video Import는 가능한 한 System Photos Picker를 사용하여 광범위한 Photos Read Permission 의존성을 최소화한다.

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

Recording Stop은 일반 Task Cancellation과 별개의 Camera Operation으로 관리한다.

---

## 67. App Lifecycle

Camera Session은 App Lifecycle에 맞게 시작하고 중지한다.

앱이 Background로 이동한 상태에서 Camera Recording을 계속한다고 가정하지 않는다.

Recording 중 System Interruption이 발생하면 가능한 한 안전하게 Recording을 종료하고 유효한 File을 보존한다.

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
- Rear Camera Recording
- Front Camera Recording
- Camera Switching
- 1080p 30 fps Recording
- 10초 자동 종료
- Microphone Audio
- Portrait 9:16 Recording
- Landscape 16:9 Recording
- Photos Video Import
- 4K Source Import
- 4K to 1080p Working Media Processing
- Trim
- Framing
- Multi-clip Preview
- 1080p Export
- Photos Save
- Share Sheet
- Draft Recovery
- Large Project Behavior
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
- 30 fps Output
- Export File 생성

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
- Portrait Project는 1080 × 1920을 사용한다.
- Landscape Project는 1920 × 1080을 사용한다.
- 기본 Frame Rate는 30 fps다.
- Mellow Camera는 MVP에서 1080p 30 fps를 기본으로 촬영한다.
- MVP에서 720p Export를 제공하지 않는다.
- MVP에서 4K Export를 제공하지 않는다.
- MVP에서 60 fps Export를 제공하지 않는다.
- 4K를 포함한 고해상도 Photos Video를 Import할 수 있다.
- Imported Video는 선택한 최대 10초 구간을 기준으로 1080p Working Media로 정규화하는 방향을 사용한다.
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
- Project Orientation과 Device Orientation을 분리한다.
- Trim은 Non-destructive 방식으로 구현한다.
- Imported Video의 기본 Layout은 Fill + Crop이다.
- Preview와 Export는 Shared Composition Definition을 사용한다.
- Preview는 Composition 기반 Virtual Timeline을 우선 사용한다.
- MVP Export는 `AVAssetExportSession`을 우선 사용한다.
- Media File Operation은 Actor 기반으로 관리한다.
- Core Media Processing은 Local-first로 구현한다.
- Third-party Dependency를 최소화한다.

---

## 83. Architecture Invariants

구현 과정에서 다음 원칙은 항상 유지한다.

### Media Safety

정상적으로 촬영 또는 Import가 완료된 Clip이 단순한 UI Navigation 때문에 유실되어서는 안 된다.

### Original Preservation

Photos Library의 원본 Video를 수정하거나 삭제하지 않는다.

### Clip Duration

Project에서 사용하는 하나의 Clip은 10초를 초과하지 않는다.

### Project Orientation

Project Aspect Ratio는 Device Rotation으로 자동 변경되지 않는다.

### 1080p Project Standard

Mellow MVP의 Working Media와 Export Pipeline은 1080p를 기준으로 설계한다.

### Preview and Export Parity

Preview와 Export는 가능한 한 동일한 Composition Definition을 사용한다.

### Local-first

MVP의 핵심 Media Workflow는 Server Connection 없이 동작해야 한다.

### No Arbitrary Vlog Limit

전체 Vlog Duration이나 Clip Count에 기술적 편의를 위한 임의의 제품 제한을 추가하지 않는다.

### UI and Infrastructure Separation

SwiftUI View는 Camera Session, File System 또는 SwiftData를 직접 조작하지 않는다.

### iPhone 12 Performance Baseline

핵심 사용자 Flow는 iPhone 12에서 실사용 가능한 수준으로 동작해야 한다.

---

## 84. Open Architecture Decisions

### Capture

- Camera Session Preset의 세부 설정
- Front Camera 저장 영상의 Mirror Policy
- Camera Lens 선택 정책

### HDR

- HDR Source Import 정책
- Dolby Vision 처리
- HDR 유지 여부
- SDR 변환 여부
- Export Color Space

### Imported Media

- Materialized Segment 외 원본 Source Reference를 유지할지 여부
- Imported Clip의 Re-trim 범위
- Source Video Transcoding 세부 정책
- 매우 낮은 Resolution Source의 Upscaling 정책

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

- Recording 시작 전 최소 Free Storage Threshold
- Import 전 최소 Free Storage Threshold
- Export 예상 용량 계산
- Storage Warning Threshold

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
