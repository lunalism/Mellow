# Mellow — Architecture Decision Records

## 1. Document Purpose

이 문서는 Mellow 프로젝트에서 이미 확정된 중요한 제품 및 기술 결정을 기록한다.

`PRODUCT.md`, `FEATURES.md`, `DESIGN.md`, `ARCHITECTURE.md`가 현재의 기준을 설명한다면, 이 문서는 왜 특정 방향을 선택했는지와 어떤 대안을 의도적으로 선택하지 않았는지를 추적하기 위한 기록이다.

새로운 중요한 결정이 발생하거나 기존 결정을 변경해야 하는 경우 이 문서를 함께 업데이트한다.

단순한 UI 조정, 코드 스타일 변경, 파일명 변경과 같은 세부 구현 변경은 ADR 대상으로 만들지 않는다.

---

## 2. ADR Status

각 결정은 다음 상태 중 하나를 사용한다.

- `Accepted`: 현재 확정되어 구현 기준으로 사용하는 결정
- `Superseded`: 이후 다른 ADR로 대체된 결정
- `Deprecated`: 더 이상 새로운 구현에 사용하지 않는 결정
- `Proposed`: 아직 확정되지 않은 제안

현재 문서에 기록된 ADR은 별도 표기가 없는 한 `Accepted` 상태다.

---

# ADR-001 — iPhone-first Native Application

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow는 Camera Recording, Video Import, Trim, Preview, Export가 핵심인 Mini Vlog 앱이다.

Camera와 AVFoundation을 깊게 사용하는 제품 특성상 초기부터 여러 플랫폼을 동시에 지원하면 구현 복잡성과 테스트 범위가 크게 증가할 수 있다.

## Decision

Mellow의 첫 번째 제품은 iPhone-first Native Application으로 개발한다.

- Language: Swift
- UI Framework: SwiftUI
- Android는 초기 범위에서 제외한다.
- iPad는 초기 범위에서 제외한다.
- 미래의 Cross-platform 가능성을 이유로 초기 iPhone Architecture를 복잡하게 만들지 않는다.

## Rationale

Native iOS 환경을 사용하면 AVFoundation, Photos, SwiftData, Swift Concurrency 등의 Apple Framework를 직접 활용할 수 있다.

Camera와 Video Processing의 안정성 및 성능을 우선하면서 초기 MVP 범위를 작게 유지할 수 있다.

## Consequences

Mellow의 초기 제품 품질과 QA는 iPhone에 집중한다.

Android 또는 iPad 지원이 필요해질 경우 별도의 제품 및 기술 검토가 필요하다.

---

# ADR-002 — iOS 18 Minimum Deployment Target

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow는 새로운 앱이며 오래된 iOS 버전에 대한 호환성보다 현대적인 SwiftUI와 SwiftData 기반 개발 경험을 우선한다.

사용자가 보유한 Primary Physical Test Device는 iPhone 12다.

## Decision

Mellow의 Minimum Deployment Target은 iOS 18.0으로 설정한다.

Mellow의 공식 Device Quality Baseline은 iPhone 12 이상으로 정의한다.

Primary Physical Test Device는 iPhone 12를 사용한다.

## Rationale

iOS 18을 기준으로 하면 최신 SwiftUI와 SwiftData API를 활용하면서 Legacy Compatibility Layer를 줄일 수 있다.

iPhone 12를 성능 기준 기기로 사용하면 최신 Pro 모델에서만 정상적으로 동작하는 구현을 방지할 수 있다.

## Consequences

iPhone 12에서 Camera, Trim, Preview, Import, Export가 실사용 가능한 수준으로 동작해야 한다.

`iPhone 12 and later`는 공식 QA 기준이며 App Store에서 이전 기기의 설치를 인위적으로 제한하기 위한 조건으로 사용하지 않는다.

---

# ADR-003 — 1080p / 30 fps Standard

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow는 짧은 Mini Vlog 제작을 목표로 하며 4K Editing 또는 Professional Video Production을 MVP 목표로 하지 않는다.

고해상도와 높은 Frame Rate를 기본으로 사용하면 Storage, Processing Time, Export Time, Memory Pressure가 증가한다.

## Decision

Mellow MVP의 표준 Working Media와 Export Profile은 1080p / 30 fps로 한다.

- Portrait Project: 1080 × 1920
- Landscape Project: 1920 × 1080
- Default Frame Rate: 30 fps
- 720p Export는 MVP에서 제공하지 않는다.
- 4K Export는 MVP에서 제공하지 않는다.
- 60 fps Export는 MVP에서 제공하지 않는다.

## Rationale

1080p / 30 fps는 모바일 Mini Vlog 용도로 충분한 영상 품질을 제공하면서 iPhone 12에서도 현실적인 Processing Cost를 유지할 수 있다.

## Consequences

4K를 포함한 고해상도 Source Video는 Import할 수 있지만 Mellow의 Working Media는 1080p 기준으로 정규화한다.

Photos Library의 원본 Video는 변경하지 않는다.

---

# ADR-004 — Fixed Project Orientation

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow는 Portrait Mini Vlog와 Landscape Mini Vlog를 모두 지원해야 한다.

하나의 Project 내부에서 Orientation이 자동으로 바뀌면 Clip 간 Canvas가 달라지고 Preview 및 Export UX가 복잡해진다.

## Decision

새 Vlog 생성 시 Project Orientation을 선택한다.

지원하는 Orientation은 다음 두 가지다.

- Portrait 9:16
- Landscape 16:9

선택된 Orientation은 Project가 유지되는 동안 변경하지 않는다.

Device Rotation만으로 Project Orientation을 변경하지 않는다.

## Rationale

Project 단위로 Canvas를 고정하면 촬영, Import, Crop, Preview, Export 결과를 일관되게 유지할 수 있다.

## Consequences

Device Orientation과 Project Orientation은 별개의 상태로 관리한다.

기기 방향이 Project Orientation과 다를 경우 Project를 자동 변경하지 않고 조용한 Rotation 안내를 제공한다.

---

# ADR-005 — Maximum 10-second Clip

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow는 긴 Video Recording 앱이 아니라 짧은 순간들을 여러 Clip으로 기록하여 Mini Vlog를 만드는 앱이다.

고정된 Recording Preset보다 사용자가 순간의 길이를 자유롭게 결정할 수 있는 방식이 제품 방향에 더 적합하다.

## Decision

Mellow Project에서 사용하는 하나의 Clip은 최대 10초다.

Mellow Camera Recording은 다음 규칙을 사용한다.

- 사용자는 Recording을 시작한 후 원하는 시점에 직접 종료할 수 있다.
- 10초 이전에는 자유롭게 Recording을 종료할 수 있다.
- Recording이 10초에 도달하면 자동으로 종료한다.
- 1초, 3초, 5초 등의 고정 Recording Preset은 MVP에서 제공하지 않는다.
- Recording Pause / Resume는 MVP에서 제공하지 않는다.

## Rationale

자유 촬영 방식은 순간을 자연스럽게 기록하면서도 Mini Vlog의 짧은 Clip 중심 구조를 유지한다.

## Consequences

10초 제한은 UI Timer뿐 아니라 Domain Policy와 Capture Pipeline에서도 강제한다.

Recording Progress는 Progress Ring을 중심으로 표현한다.

---

# ADR-006 — Existing Photos Video Import

**Date:** 2026-09-10  
**Status:** Accepted

## Context

사용자가 Mellow에서 직접 촬영한 Clip만 사용할 수 있다면 기존에 촬영한 일상 영상을 Mini Vlog에 활용할 수 없다.

Mini Vlog 앱으로서 Photos Library의 기존 Video를 사용할 수 있는 기능은 핵심 사용성에 중요하다.

## Decision

Photos Library의 기존 Video를 Mellow Project에 Import할 수 있도록 한다.

Source Video 자체의 Duration에는 제한을 두지 않는다.

Project에 실제로 추가하는 하나의 Clip Segment는 최대 10초다.

10초보다 긴 Source Video에서는 사용자가 원하는 최대 10초 구간을 선택한다.

10초보다 짧은 Source Video는 전체 구간을 사용할 수 있다.

## Rationale

Source의 길이를 제한하지 않으면서 Project 내부의 Clip 규칙을 최대 10초로 통일하면 사용자 자유도와 내부 일관성을 동시에 유지할 수 있다.

## Consequences

직접 촬영한 Clip과 Imported Clip은 Project 내부에서 가능한 한 동일한 Clip Model로 처리한다.

Photos 원본 Video는 비파괴적으로 유지한다.

---

# ADR-007 — Project-owned Imported Media

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow Draft가 Photos Library의 원본 Asset만 참조하면 사용자가 원본 Video를 삭제했을 때 Draft가 손상될 수 있다.

반대로 긴 4K Source Video 전체를 Draft Storage에 복사하면 불필요한 Storage 사용량이 크게 증가할 수 있다.

## Decision

사용자가 Imported Clip 추가를 확정하면 Mellow가 Project에서 사용할 Media를 Project-owned Local Media로 생성한다.

4K를 포함한 고해상도 Source Video는 선택된 최대 10초 구간을 기준으로 1080p Working Media로 정규화하는 방향을 사용한다.

Photos 원본 Video는 수정하거나 삭제하지 않는다.

## Rationale

Project-owned Media를 사용하면 Photos 원본의 이후 Availability에 Draft가 의존하지 않는다.

선택한 짧은 Segment만 Working Media로 생성하면 Draft Storage 증가를 제한할 수 있다.

## Consequences

Imported Clip의 Re-trim을 원본 Source 전체 범위까지 허용할지 현재 Materialized Segment 내부로 제한할지는 별도 결정이 필요하다.

해당 사항은 Pending Decision으로 유지한다.

---

# ADR-008 — Multiple Persistent Drafts

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mini Vlog는 한 번에 완성하지 않고 하루 또는 여러 날에 걸쳐 Clip을 추가할 수 있다.

사용자가 하나의 Project를 완료할 때까지 다른 Vlog를 만들 수 없거나 Draft가 자동 만료되면 기록 경험을 해칠 수 있다.

## Decision

Mellow는 여러 개의 미완성 Vlog Project를 동시에 저장할 수 있도록 한다.

Draft는 자동 만료하지 않는다.

사용자가 직접 삭제하기 전까지 로컬 기기에 유지한다.

앱 종료 또는 재실행 이후에도 Draft를 다시 열 수 있어야 한다.

Export 이후에도 Draft를 자동 삭제하지 않는다.

## Rationale

사용자가 시간에 구애받지 않고 여러 기록을 이어서 만들 수 있도록 한다.

Export 이후에도 Clip을 수정하고 다시 Export할 수 있는 유연성을 유지한다.

## Consequences

Draft Media와 Metadata의 안정적인 Persistence가 필수다.

앱 삭제 또는 기기 변경 이후의 복구는 MVP에서 보장하지 않는다.

iCloud Sync 또는 Backup은 Future Candidate로 유지한다.

---

# ADR-009 — Automatic Project Naming

**Date:** 2026-09-10  
**Status:** Accepted

## Context

새 Vlog를 만들 때 이름을 입력하도록 요구하면 촬영까지의 시간이 길어지고 Capture-first 원칙을 해칠 수 있다.

## Decision

MVP에서는 Project Name 입력 단계를 제공하지 않는다.

Project Display Name은 생성 날짜와 시간을 기준으로 자동 생성한다.

Recent 화면에서는 첫 번째 사용 가능한 Clip의 Thumbnail을 대표 이미지로 사용한다.

Project Rename은 MVP에서 제공하지 않는다.

## Rationale

사용자는 프로젝트 관리보다 빠른 촬영에 집중할 수 있다.

Thumbnail과 날짜를 함께 사용하면 별도 이름이 없어도 Project를 구분할 수 있다.

## Consequences

Rename 기능은 실제 사용자 요구가 확인된 이후 Post-MVP에서 검토한다.

---

# ADR-010 — Front and Rear Camera Support

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mini Vlog에는 풍경이나 사물뿐 아니라 사용자의 얼굴을 직접 촬영하는 장면도 자연스럽게 포함될 수 있다.

## Decision

Mellow MVP는 Rear Camera와 Front Camera를 모두 지원한다.

사용자는 Recording이 시작되지 않은 상태에서 Front Camera와 Rear Camera를 전환할 수 있다.

Recording 중 Camera Switching은 허용하지 않는다.

Front Camera와 Rear Camera를 동시에 Recording하는 Dual Camera 기능은 MVP에서 제공하지 않는다.

## Rationale

일반적인 Self Vlog 사용성을 제공하면서 Recording Pipeline의 복잡성과 안정성 Risk를 제한할 수 있다.

## Consequences

Front Camera Preview Mirroring과 저장 Video Mirroring은 분리 가능한 Policy로 관리한다.

최종 저장 영상의 Mirror Policy는 아직 확정하지 않는다.

---

# ADR-011 — Fill + Crop for Aspect Ratio Mismatch

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Photos에서 Import하는 Source Video의 Aspect Ratio가 현재 Mellow Project의 9:16 또는 16:9 Canvas와 다를 수 있다.

## Decision

Imported Video의 기본 Layout은 Fill + Crop으로 한다.

Source Video가 Project Canvas를 가득 채우도록 표시하고 초과 영역을 Crop한다.

사용자는 Video의 Framing Position을 조정할 수 있어야 한다.

`Fit` 및 Background Blur Layout은 MVP 필수 기능으로 제공하지 않는다.

## Rationale

Canvas에 Letterbox 또는 빈 영역이 생기지 않아 Mini Vlog 결과가 일관되게 보인다.

단일 기본 Layout을 사용하면 MVP Editing UX를 단순하게 유지할 수 있다.

## Consequences

Source Rotation과 Display Transform을 정확하게 반영해야 한다.

Framing State는 Resolution-independent한 Normalized Coordinate로 관리하는 방향을 사용한다.

---

# ADR-012 — Local-first Persistence Architecture

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow MVP의 핵심 기능은 Camera, Import, Trim, Preview, Export이며 Server가 없어도 완전히 동작할 수 있다.

대용량 Video File을 Database Blob으로 저장하면 Persistence와 Storage 관리가 복잡해질 수 있다.

## Decision

Mellow MVP는 Local-first Architecture를 사용한다.

- Project 및 Clip Metadata는 SwiftData에 저장한다.
- 실제 Video File은 File System에 저장한다.
- Draft Media는 Application Support 영역에 저장한다.
- SwiftData에는 Absolute Media Path 대신 Relative Path를 저장한다.
- 핵심 Video Processing을 위해 Server Upload를 요구하지 않는다.

## Rationale

Metadata와 Media의 책임을 분리하면 대용량 Video 처리와 Draft Recovery를 안정적으로 관리할 수 있다.

서버 의존성이 없으므로 기본 촬영 및 편집 경험을 Offline에서도 제공할 수 있다.

## Consequences

MediaStore와 ProjectRepository의 일관성 관리가 중요하다.

앱 삭제 시 Local Draft가 사라질 수 있다.

Cloud Sync는 Future Candidate로 유지한다.

---

# ADR-013 — Shared Preview and Export Composition

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Preview와 Export가 별도의 Transform 및 Timeline Logic을 사용하면 Preview에서 본 결과와 최종 저장 결과가 달라질 수 있다.

## Decision

Preview와 Export는 공통 `VideoCompositionBuilder` 또는 동등한 Shared Composition Definition을 사용한다.

공통 Composition은 최소한 다음 정보를 반영한다.

- Clip Order
- Trim
- Project Orientation
- Source Rotation
- Fill + Crop
- User Framing
- Audio
- 1080p Output Canvas
- 30 fps Project Timing

## Rationale

Preview와 최종 Export의 결과 차이를 최소화하고 중복 Video Processing Logic을 줄인다.

## Consequences

Composition Builder는 UI와 분리된 테스트 가능한 Component로 구현한다.

Preview에서는 가능한 한 완성 Video File을 매번 Render하지 않고 Virtual Timeline을 사용한다.

---

# ADR-014 — No Fixed Total Vlog Duration or Clip Count Limit

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow의 개별 Clip은 최대 10초지만 사용자가 몇 개의 순간을 하나의 Vlog에 넣을지는 사용 상황에 따라 달라질 수 있다.

임의의 전체 Duration 또는 Clip Count 제한은 기록 앱의 사용성을 불필요하게 제한할 수 있다.

## Decision

Mellow는 전체 Vlog Duration과 Project 내 Clip Count에 제품 차원의 고정 Maximum Limit을 두지 않는다.

## Rationale

사용자가 필요한 만큼 짧은 순간을 이어서 하나의 Mini Vlog를 만들 수 있도록 한다.

## Consequences

Large Project에서도 모든 Video Frame을 동시에 Memory에 Load하지 않는 Architecture가 필요하다.

Storage 및 Export 가능 여부는 Project Length 제한 대신 실제 Device Resource 상태를 기준으로 처리한다.

---

# ADR-015 — Native Apple Frameworks First

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow MVP는 Apple Platform의 Camera, Photos, Video Processing, Persistence 기능을 중심으로 한다.

초기부터 많은 Third-party Library를 도입하면 Dependency Risk와 유지보수 비용이 증가할 수 있다.

## Decision

Mellow MVP는 Apple Native Framework를 우선 사용한다.

주요 Framework는 다음과 같다.

- SwiftUI
- AVFoundation
- PhotosUI
- Photos
- SwiftData
- CoreMedia
- CoreGraphics
- OSLog

Third-party Dependency는 Native API만으로 해결하기 지나치게 어렵거나 명확한 제품 가치가 있는 경우에만 추가한다.

## Rationale

Apple Framework와 직접 통합하면 iOS 기능과의 호환성, Privacy, 유지보수 가능성을 높일 수 있다.

## Consequences

새 Third-party Dependency를 추가하기 전 이유와 Trade-off를 이 문서 또는 새로운 ADR에 기록한다.

---

# ADR-016 — Non-destructive Editing

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Trim이나 Framing을 변경할 때마다 원본 Video를 다시 자르거나 덮어쓰면 품질 손실, File Duplication, Undo 문제를 만들 수 있다.

## Decision

Mellow의 Clip Editing은 기본적으로 Non-destructive Metadata 방식으로 관리한다.

- Trim은 `trimStart`와 `trimDuration`으로 관리한다.
- Framing은 Metadata로 관리한다.
- Photos Library 원본은 수정하지 않는다.
- Project-owned Media도 반복 Editing을 이유로 불필요하게 다시 Encode하지 않는다.

## Rationale

편집을 수정하거나 다시 Preview 및 Export할 때 원본 상태를 보존할 수 있다.

## Consequences

최종 Result는 Preview 또는 Export 단계에서 Metadata를 Composition에 적용하여 생성한다.

---

# ADR-017 — Clip Delete with Undo, Project Delete with Confirmation

**Date:** 2026-09-10  
**Status:** Accepted

## Context

모든 Clip 삭제에 Confirmation Dialog를 사용하면 Mini Vlog Editing 흐름이 느려질 수 있다.

반면 Project 삭제는 여러 Clip과 Mellow 내부 Media 전체를 제거하므로 더 높은 보호 수준이 필요하다.

## Decision

Clip 삭제는 즉시 적용하고 짧은 Undo Window를 제공한다.

Project 삭제는 명시적인 Confirmation 이후 실행한다.

Clip 삭제 직후 Media File을 즉시 영구 삭제하지 않고 Undo 가능 기간 동안 Pending Deletion 상태로 관리한다.

## Rationale

일상적인 Clip Editing은 빠르게 유지하면서 큰 데이터 손실 Risk가 있는 Project 삭제는 보호할 수 있다.

## Consequences

Pending Deletion과 실제 Media File Cleanup의 일관성을 Architecture에서 보장해야 한다.

---

# ADR-018 — Export Does Not Complete or Delete a Project

**Date:** 2026-09-10  
**Status:** Accepted

## Context

사용자는 Export 이후 특정 Clip을 다시 조정하거나 다른 결과로 재Export하고 싶을 수 있다.

Export를 Project의 종료 또는 삭제와 동일하게 처리하면 이러한 반복 Editing이 어렵다.

## Decision

Export는 현재 Project State에서 Result Video를 생성하는 Action으로 정의한다.

Export가 성공하더라도 Draft는 유지한다.

사용자는 Project를 다시 열고 수정한 후 재Export할 수 있다.

Export 완료 후 Photos 저장과 iOS Share Sheet를 제공한다.

## Rationale

Export와 Project Lifecycle을 분리하면 사용자가 결과물을 자유롭게 다시 만들 수 있다.

## Consequences

완성된 결과 Video와 Draft Project는 별개의 데이터로 취급한다.

---

# ADR-019 — MVP Scope Excludes Photo and Advanced Editing

**Date:** 2026-09-10  
**Status:** Accepted

## Context

Mellow의 핵심 가치는 짧은 Video Clip을 촬영하고 이어 하나의 Mini Vlog로 만드는 것이다.

Photo Camera, Photo Filter, Advanced Video Editor 기능까지 동시에 구현하면 초기 제품 범위가 크게 증가한다.

## Decision

Mellow MVP에서는 다음 영역을 구현하지 않는다.

### Photo

- Photo Capture
- Photo Import Workflow
- Photo Filters
- Photo Editing
- Photo Export

### Advanced Video Editing

- Multi-track Timeline
- Layer System
- Keyframes
- Masks
- Chroma Key
- Professional Color Grading
- Complex Speed Curves
- Motion Graphics

### Additional Creative Features

- Video Filters
- Music
- Text Overlay
- Transitions
- Templates
- Smart Editing

위 Creative Feature는 필요성이 확인되면 Post-MVP 또는 Future Candidate로 검토한다.

## Rationale

첫 번째 Vertical Slice를 Camera, Import, Clip Organization, Trim, Preview, Export에 집중하여 완성도를 높인다.

## Consequences

MVP가 안정적으로 완성되기 전에는 기능 수를 늘리는 것보다 핵심 Flow의 Reliability와 UX를 우선한다.

---

## 3. Pending Decisions

다음 항목은 아직 확정된 ADR이 아니며 임의로 구현 기준을 결정하지 않는다.

### HDR and Color

- HDR Source Import 정책
- Dolby Vision 처리
- HDR 유지 또는 SDR 변환
- Export Color Space

### Export

- H.264 또는 HEVC
- Video Bitrate
- Audio Format
- Audio Bitrate
- Background Export 정책
- Export Retry 정책

### Imported Media

- Imported Clip을 이후 원본 Source 전체 범위에서 다시 Trim할 수 있게 할지 여부
- 현재 Materialized Segment 내부에서만 Re-trim할지 여부
- Source Reference를 함께 유지할지 여부

### Camera

- Front Camera 저장 영상의 Mirror Policy
- Camera Lens 선택 정책
- Tap to Focus 도입 시점
- Exposure Control 도입 시점
- Zoom 도입 시점
- Torch 도입 시점

### Storage

- Recording 시작 전 최소 Free Storage Threshold
- Import 전 최소 Free Storage Threshold
- Export 시작 전 최소 Free Storage Threshold
- Storage Warning 기준

### Design Details

- Recent Project의 List 또는 Grid Layout
- Imported Video Crop에서 Pinch to Zoom 지원 여부
- Recording Haptic의 정확한 Timing
- Camera Control의 정확한 Placement

Pending Decision이 확정되면 기존 ADR에 단순히 내용을 끼워 넣기보다 결정의 중요도에 따라 새로운 ADR을 추가한다.

---

## 4. Decision Change Policy

Accepted ADR의 내용이 변경되는 경우 기존 기록을 삭제하거나 과거의 결정을 현재 결정처럼 다시 작성하지 않는다.

중요한 방향 변경은 새로운 ADR로 기록하고 이전 ADR의 Status를 `Superseded`로 변경한다.

새 ADR에는 어떤 ADR을 대체하는지 명시한다.

이를 통해 Mellow의 제품 및 기술 방향이 왜 변경되었는지 추적할 수 있도록 한다.
