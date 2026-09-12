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

# ADR-020 — Transactional Media Commit and Recovery

**Date:** 2026-09-11

**Status:** Accepted

## Context

Media File과 SwiftData Metadata는 하나의 Atomic Transaction으로 저장되지 않는다.

File 작성, Materialization과 Metadata Persistence 사이에서 Process Death가 발생할 수 있다.

Metadata가 없다는 사실만으로 Orphan을 판정하여 삭제하면 정상 사용자 Media가 유실될 수 있다.

Phase 4부터 실제 사용자 Recording Media가 생성되므로 저장 완료와 기본 Recovery 계약을 Phase 10까지 미룰 수 없다.

## Decision

Recording과 Import는 다음 공통 Media Commit Lifecycle을 따른다.

1. Media Operation 시작
2. Process Death 이후에도 Operation과 Media의 관계를 식별할 수 있는 Durable Operation Identity 확보
3. Staging에 Media 작성
4. Staged Media 작성 완료
5. Staged Media Validation
6. 필요한 경우 Normalization
7. Final Working Media Validation
8. Project-owned Media 위치로 Materialization
9. Clip Metadata Persistence
10. Commit Complete
11. Temporary / Intermediate Cleanup

Committed Clip은 Project-owned Final Media가 존재하고 Final Validation과 해당 Media를 참조하는 Clip Metadata Persistence가 성공했으며 Project가 여전히 유효한 경우에만 성립한다.

Commit 완료 전 Media는 정상 Project Clip으로 사용자 UI에 노출하지 않으며 Recording / Import Progress는 Committed Clip을 의미하지 않는다.

Validation은 File 존재, 읽기 가능한 Media Resource, 유효한 Video Track과 Duration, 현재 Phase의 확정된 Clip Duration Policy, 필요한 Track Metadata 접근 가능 여부 및 Write 완결성을 확인한다.

Normalization Output은 Final Media로 등록하기 전에 다시 Validation한다.

Active / In-progress Operation, Recoverable Media, Committed Media, Discardable Temporary Media와 Confirmed Orphan을 구별한다.

Metadata가 없는 File도 Recovery Candidate 여부를 먼저 확인하며 Project-owned Directory에 있다는 이유로 이 확인을 생략하지 않는다.

Confirmed Orphan은 Committed Metadata 참조, Active Operation 소유, Recoverable Operation 연결과 현재 작업의 필요가 모두 없고 Reconciliation 결과 정상 사용자 Media로 복구할 근거가 없을 때만 성립한다.

Known Disposable Temporary Artifact와 Project-owned Unknown Media를 동일하게 취급하지 않는다.

Normalization 실패 시 Valid Source / Staging Media를 보존하며 Materialization 이후 Metadata Persistence 실패 시 Recoverable Operation의 Metadata Commit을 재시도할 수 있어야 한다.

Deleted / Nonexistent Project의 Late Result는 Project를 재생성하거나 Clip Metadata를 Commit해서는 안 된다.

Recovery와 Reconciliation은 Idempotent해야 하며 Media Operation Identity와 Clip Identity로 Duplicate Commit과 동일 Media의 중복 등록을 방지한다.

Metadata Persistence 성공 후 UI Update 전에 Crash가 발생해도 Relaunch 시 Persisted Metadata를 기준으로 이미 완료된 Commit을 유지한다.

가능한 File Finalization은 동일 Container / Filesystem 내 Atomic Move 또는 Rename을 우선하며 Partial Output과 Final Media를 명확히 구분한다.

Valid Final Media 확보 전 Clip Metadata Commit, Metadata Persistence 완료 전 Committed Clip 표시 및 Commit 완료 전 Recovery Information 파괴를 금지한다.

Temporary / Intermediate Cleanup은 Commit 또는 Recovery Classification 이후 수행하며 Cleanup 실패는 이미 Committed Clip의 유효성을 훼손하지 않아야 한다.

반복 Recovery와 Cleanup은 정상 Committed Media를 삭제하지 않고 이미 정리한 Artifact의 오류를 반복하지 않으며 완료된 Operation을 신규 Operation처럼 재처리하지 않아야 한다.

구체적인 Durable Representation, Type / Class 이름과 Database Uniqueness 구현 방법은 고정하지 않으며 구현 시 이 계약을 만족하는 가장 단순한 방법을 선택할 수 있다.

상세 Failure Boundary A–H와 Reconciliation 기준은 `ARCHITECTURE.md`의 25절과 59절을 따른다.

계약 자체는 Phase 4 이전에 확정하며 Phase 4에서 Recording의 최소 Production Lifecycle과 기본 실패 경계 검증을 구현하고 Phase 6에서 Import에 동일 계약을 적용한다.

Phase 10은 기존 Lifecycle의 Forced Termination, Repeated Relaunch, Orphan Reconciliation, Missing / Corrupt Media, Duplicate Recovery Prevention, Cleanup Idempotency와 Multiple Draft Isolation을 강화한다.

## Consequences

### Benefits

- Process Death 이후에도 Operation과 Media를 연결하여 가능한 저장 및 Metadata Commit을 복구할 수 있다.
- 정상 사용자 Media의 잘못된 Orphan Deletion을 방지한다.
- Recording과 Import가 일관된 저장 완료와 Recovery Lifecycle을 사용한다.
- 명시적인 Failure Boundary와 Reconciliation 결과를 기준으로 Recovery를 검증할 수 있다.

### Costs

- Durable Operation State 추적이 필요하다.
- File과 Metadata의 Reconciliation Complexity가 증가한다.
- Media Cleanup은 단순 Directory Scan보다 복잡해진다.

## Non-goals

- 구체적인 Manifest Format 또는 Persistence Representation 확정
- 최종 Codec / Container 결정
- HDR / SDR 정책 결정
- Storage Threshold 결정
- Delete / Undo와 Preview / Export의 Active-consumer Lifecycle 해결

Delete / Undo의 Active-consumer Lifecycle을 포함한 B03은 Step 3에서 별도로 다룬다.

---

# ADR-021 — Logical Deletion and Active Media Lifecycle

**Date:** 2026-09-11

**Status:** Accepted

## Context

사용자 UI의 Delete와 실제 Media File의 Physical Delete는 동일한 작업이 아니다.

삭제 대상 Media를 Preview, Export, Thumbnail 또는 다른 작업이 여전히 사용 중일 수 있다.

Recording / Import Completion이 Project Delete보다 늦게 도착하면 삭제된 Project에 Metadata를 다시 등록하는 Race가 발생할 수 있다.

File Delete와 Metadata Delete는 하나의 Atomic Transaction이 아니며 MediaStore Actor만으로 Cross-service Race를 해결할 수 없다.

Undo Opportunity, Recovery 필요, Project Validity와 Active Media Usage를 함께 고려하는 계약이 필요하다.

## Decision

Logical Delete와 Physical Delete를 분리하며 Logical Deletion이 즉각적인 Physical Deletion을 의미하지 않도록 한다.

Physical Delete는 Logical Ownership / Reference 해제, Undo Eligibility 종료, Recovery 필요 없음, Active Media Usage 없음, Late Commit 차단과 Safe Cleanup Classification을 모두 요구한다.

Preview / Export / Thumbnail 등 Active Consumer와 Recording / Import / Finalization 등 Producer가 필요로 하는 Media의 삭제를 Defer한다.

Usage 확인과 실제 삭제 사이에 새로운 사용이 끼어들지 않도록 Repository / Operation Lifecycle / Media Storage 사이에서 조정하며 구체적인 Reference Counter, Lease Class, Coordinator 또는 Schema는 고정하지 않는다.

Project Delete는 사용자 Confirmation 이후 영속적인 Logical Deleted / Invalid Commit Target을 먼저 확립하고 신규 Commit을 차단한 뒤 가능한 Active Producer / Consumer에 Cancellation을 요청한다.

이후 Clip / Project Metadata를 정리하고 Active Usage와 Recovery 필요가 해제된 Media부터 안전하게 Physical Cleanup하며 실패한 Cleanup은 재시도 가능하게 유지한다.

Logical Deletion과 Cleanup은 Idempotent해야 하며 Metadata 정리 이후에도 재실행 시 삭제 상태와 남은 Cleanup을 판정할 수 있어야 한다.

Recording, Import, Thumbnail, Preview Preparation, Export 등 Project-scoped Async Operation은 Commit 또는 결과 적용 직전에 Target Validity를 확인하며 삭제와 Commit 사이의 Race를 차단한다.

Late Result는 삭제된 Project에 Metadata를 등록하거나 Project를 Resurrect하지 않으며 Clip 대상 Derived Result는 유효한 Project / Clip과 동일 Media Identity를 확인하여 삭제된 Clip을 되살리지 않는다.

Clip Delete는 즉시 UI Removal과 짧은 Pending Deletion / Undo Opportunity를 제공한다.

MVP에서 사용자에게 노출되는 Undo는 가장 최근 Clip Delete 한 건이며 새로운 Delete가 이전 사용자-visible Undo Opportunity를 종료해도 이전 Media의 Cleanup은 별도의 안전 조건을 따른다.

Undo 성공 시 기존 Clip Identity, Media와 해당 Clip Metadata를 재사용하며 Physical Media 삭제 이후 Undo 성공이나 Duplicate Clip 생성을 허용하지 않는다.

Undo 복원 위치는 삭제 당시 이전 인접 Stable Clip이 남아 있으면 그 뒤, 그렇지 않고 다음 인접 Clip이 남아 있으면 그 앞을 사용하며 둘 다 없으면 Original Index를 현재 유효 삽입 범위로 Clamp한다.

두 Anchor가 모두 남아 있어도 이전 Anchor를 우선하며 현재 다른 Clip의 상대 순서와 Unrelated Reorder를 보존한다.

Process Termination 이후 Undo Opportunity는 유지하지 않으며 남은 Pending Deletion을 Logical Deletion 확정 상태로 Reconciliation하고 Physical Cleanup에는 동일한 안전 조건을 적용한다.

Project가 Logical Deleted 상태이면 Clip Undo의 유효한 Target도 아니며 Undo로 Project를 재생성하지 않는다.

Export는 시작 시 Clip Identity / Order, Trim, Framing / Transform, Project Orientation, Media Reference와 Audio / Video Composition State를 포함한 Immutable Logical Snapshot을 사용한다.

이후 일반 Clip Edit / Reorder / Clip Delete는 진행 중인 Export 결과를 소급 변경하지 않으며 Snapshot이 참조하는 Source Media는 Operation 종료 또는 취소 이후 실제 Reference Release까지 유지한다.

Project 전체 Delete는 해당 Project의 Export에 Cancellation을 요청하지만 Cooperative Cancellation 요청만으로 Source Media를 Release했다고 간주하지 않는다.

삭제된 Project에 Export 결과를 Commit하지 않으며 취소 이후의 Uncommitted Operation-owned Artifact는 Recovery Classification과 Active Usage 확인 후 안전하게 정리한다.

이미 Photos에 저장 완료된 외부 Export 결과는 Project Delete로 삭제하지 않는다.

Preview는 현재 Project State로 Composition을 구성하고 Clip Mutation 후 Stale Composition을 Invalidate / Rebuild하며 다음 유효 Preview는 변경된 State를 반영한다.

Preview Preparation / Playback이 참조하는 Media는 실제 Reference가 Release될 때까지 Physical Delete하지 않으며 Stale Async Composition 결과를 현재 State에 적용하지 않는다.

Recording / Import Finalization 도중 Project가 삭제되면 Commit 직전에 Invalid Target을 확인하여 Metadata Commit을 금지하고 Project를 자동 재생성하지 않는다.

ADR-020의 Valid Media 보호와 Recovery Classification은 계속 적용하며 Deletion이나 Cancellation을 이유로 이를 생략하지 않는다.

Deletion Reconciliation과 Deferred Cleanup은 반복 Relaunch에도 안전해야 하며 다른 Committed Draft와 Photos 원본에 영향을 주지 않는다.

상세 계약은 `ARCHITECTURE.md`의 46절, 48절, 56절, 60절과 61절을 따르며 ADR-017과 ADR-020을 대체하지 않고 함께 적용한다.

## Consequences

### Benefits

- Preview / Export 중 Source Media가 사라지는 문제를 방지한다.
- 삭제된 Project의 Resurrection을 방지한다.
- Async Completion과 Deletion 사이의 Race를 줄인다.
- Undo Opportunity와 Physical Cleanup을 분리한다.
- 진행 중인 Export 결과를 일관되게 재현할 수 있다.
- Deletion / Recovery의 기대 결과를 테스트할 수 있다.

### Costs

- Active Media Usage 추적이 필요하다.
- Deferred Cleanup과 Retry가 필요하다.
- Project Operation Validity를 조정할 책임이 필요하다.
- Deletion State와 Reconciliation의 복잡성이 증가한다.

## Non-goals

- Undo Window의 정확한 시간과 UI 표시 Tuning
- Export Background / Retry 상세 정책
- Photos Save / Share Result File Lifecycle
- HDR / Codec / Container
- Storage Threshold
- Camera Lens / Mirror
- Import Re-trim
- 구체적인 Snapshot / Coordinator / Lease Type 또는 Database Schema

Photos Save / Share 완료 파일의 상세 Lifecycle은 M05 / Export Lifecycle Repair 대상으로 남긴다.

---

# ADR-022 — SDR Working Media Normalization Policy

**Date:** 2026-09-11

**Status:** Accepted

## Context

Phase 6에서 실제 4K / HDR Import Source로 Project-owned Working Media를 생성해야 하지만 기존 HDR / SDR Decision Gate는 Phase 9에 있어 구현 시점보다 늦었다.

HDR / SDR Source를 별도 Working Pipeline으로 혼합하면 Preview / Export의 Color Handling과 결과 일관성이 복잡해진다.

Project Aspect Ratio의 Crop을 Working Media에 bake-in하면 Phase 7에서 사용자가 Framing을 조정할 수 있는 Source 영역을 잃는다.

iPhone 12가 Primary Physical Test Device이므로 MVP Pipeline의 예측 가능성과 단순성이 중요하다.

## Decision

SDR, HDR 및 Dolby Vision Source Import와 4K / High-resolution Source Import를 허용하며 Photos Source 원본을 수정하거나 삭제하지 않는다.

30 fps를 초과하는 Source도 Import할 수 있지만 Imported Working Media는 30 fps 기준으로 정규화하며 Photos Source의 Frame Rate를 변경하지 않는다.

선택된 최대 10초 Segment를 기반으로 하는 Project-owned Working Media는 MVP에서 1080p-class / 30 fps / SDR을 기준으로 한다.

HDR / Dolby Vision Source는 SDR Working Media로 정규화하며 HDR Metadata와 Source의 Dynamic Range를 Working Pipeline에서 완전히 보존하는 것은 MVP requirement가 아니다.

Source Media, Project-owned Working Media와 Project Output / Export를 구별하며 1080p-class는 고해상도 Source의 Working Target이지 Project Output Canvas로 미리 Crop하라는 의미가 아니다.

Project Fill + Crop을 Working Media에 bake-in하지 않으며 Source의 Presentation Aspect Ratio와 이후 Framing 가능한 유효 화면 영역을 보존한다.

Source Rotation / Presentation Transform을 올바르게 해석하며 Codec Alignment용 Padding이 필요하더라도 사용자-visible Framing 영역을 임의로 제거하지 않는다.

Normalization standardizes media characteristics, but does not commit the user's project framing.

Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 Editing으로 유지하고 실제 Crop Region / Position / Scale 및 Transform / Order는 Preview / Export Composition에서 적용한다.

MVP Preview는 SDR이며 Export는 1080p / 30 fps / SDR을 기준으로 하고 HDR Export는 MVP에서 제공하지 않는다.

Project Output은 고정된 Orientation에 따라 Portrait 9:16은 1080 × 1920, Landscape 16:9는 1920 × 1080을 사용한다.

Preview / Export Color Handling은 가능한 한 동일한 Composition 정의를 사용하며 동일한 Project State의 Framing / Transform / SDR Interpretation을 일치시킨다.

HDR Source라는 이유로 Preview는 HDR이고 Export는 SDR인 이중 기본 Pipeline을 두지 않는다.

HDR → SDR 변환 결과는 Final Working Media 등록 전에 Validation하며 심각한 Highlight Clipping, 잘못된 색 변환 또는 Source Orientation 손상 등 명백한 변환 실패를 정상 Media로 간주하지 않는다.

Normalization 구현은 Apple Native Framework를 우선하며 정확한 Tone-mapping Algorithm, Apple API 조합과 Variable Frame Rate 변환 구현은 이 ADR에서 강제하지 않는다.

Working Media Codec / Container, 정확한 SDR Color Profile / Tagging, Low-resolution Upscaling Policy와 정확한 Raster Dimension Rule은 Pending이며 Phase 6 구현 전 Technical Gate에서 해결해야 한다.

이 Gate가 해결되기 전에는 실제 Normalization Pipeline 구현을 시작하지 않으며 저해상도 Source의 항상 Upscale 또는 절대 Upscale하지 않음을 임의로 선택하지 않는다.

Working Media Codec / Container와 Export Codec / Container는 별도 Decision이며 자동으로 동일하게 결정하지 않는다.

ADR-003 / ADR-007의 1080p Working 방향을 Source 영역을 보존하는 1080p-class Target으로 구체화하며 기존 Project Output Dimension과 최대 10초 Segment 정책은 유지한다.

ADR-020의 Transactional Commit / Validation / Recovery 계약과 ADR-021의 Logical Deletion / Active Usage / Late Commit 차단 / Immutable Export Snapshot 계약을 그대로 적용한다.

Phase 6에서 Color / Spatial / Frame Rate Normalization을 검증하고 Phase 7에서는 보존된 영역의 Metadata Framing, Phase 8에서는 SDR Preview, Phase 9에서는 SDR Export와 Color / Framing Parity를 검증한다.

## Consequences

### Benefits

- Mixed HDR / SDR Project의 Pipeline 복잡도를 줄인다.
- iPhone 12 Preview / Export의 예측 가능성을 높인다.
- Preview / Export Parity를 개선한다.
- HDR Metadata 및 Dolby Vision Export 복잡도를 줄인다.
- Phase 7에서 사용자가 Framing을 조정할 Source 영역을 보존한다.
- 향후 HDR Pipeline은 별도 Decision으로 확장할 수 있다.

### Costs

- HDR Source의 Dynamic Range를 MVP Working Media / Export에서 완전히 보존하지 않는다.
- HDR → SDR 변환 비용이 발생한다.
- Normalization이 필요한 Source에는 추가 Processing 비용이 발생한다.
- Project-owned Working Media가 저장 공간을 사용한다.

## Non-goals

- Exact Tone-mapping Algorithm 및 Apple API 조합
- Exact SDR Color Profile / Tagging
- Working Media Codec
- Working Media Container
- Low-resolution Upscaling Policy
- Exact Raster Dimension Formula
- Export H.264 vs HEVC
- Export Container / Bitrate
- Audio Codec / Bitrate
- Background Export
- Export Retry
- Import Re-trim / Source Reference
- Performance Threshold

---

# ADR-023 — Camera Capture, Zoom, Permission, Mirroring, and Orientation Policy

**Date:** 2026-09-12

**Status:** Accepted

## Context

Phase 3 / 4 Camera 구현 전에 Lens, Zoom, Permission, Mirroring, Orientation과 Interruption 동작이 명확해야 한다.

기본 1× Wide Camera를 사용하면서도 Mini Vlog 촬영에 필요한 Continuous Zoom은 제공할 필요가 있다.

Lens Selector와 Capture Zoom을 같은 기능으로 취급하면 0.5× Ultra Wide, Telephoto와 복잡한 Camera Control까지 MVP Scope가 불필요하게 확장될 수 있다.

Front Camera Preview와 저장된 결과가 서로 다르게 좌우 반전되면 사용자가 촬영한 Framing을 신뢰하기 어렵다.

Project Orientation과 Physical Device Orientation, UI Orientation, Video Connection Orientation 및 Track Transform을 혼동하면 Recording Start 상태와 최종 Clip Orientation이 잘못될 수 있다.

Microphone Permission 거부 시 Video-only Recording으로 자동 Fallback하면 승인되지 않은 Product Behavior가 생긴다.

Recording Interruption은 정상 Completion과 구분하고 ADR-020 / ADR-021의 Media Safety와 연결해야 한다.

## Decision

MVP Rear Camera의 기본 Capture Device는 1× Wide Camera다.

Rear Continuous Zoom은 Recording 시작 전 Preview와 Active Recording에서 지원하며 Product Minimum은 1×다.

Active Recording 중 Rear Zoom 변경은 동일 Clip과 Media Operation Identity 안에서 이어지고 Recording을 Stop / Restart하거나 Clip Boundary를 만들거나 10초 Timer를 Reset하거나 Project Orientation을 변경하지 않는다.

Rear Zoom은 해당 Wide Camera의 지원 범위 안에서 수행하되 정확한 Product Maximum은 Phase 3에서 iPhone 12 화질과 사용성을 검증하여 승인한다.

Device가 보고하는 이론적 Maximum Zoom Factor를 Product Maximum으로 자동 채택하지 않는다.

0.5× Ultra Wide 선택, Telephoto 선택과 사용자 Lens Selector는 MVP에 포함하지 않는다.

Pinch-to-zoom은 Rear Zoom의 Primary Interaction Candidate이며 최종 Interaction, Zoom Indicator, Visual Presentation, Sensitivity와 Maximum Quality Limit은 Phase 3 Structural / Quality Gate에서 결정한다.

Front Camera Zoom은 MVP에 포함하지 않는다.

Front / Rear Camera Switching은 Idle 상태에서만 허용하고 Recording 중에는 허용하지 않는다.

Front Camera Preview는 Mirrored Appearance를 사용하며 Mellow에서 직접 촬영하고 Commit한 Front Clip은 이후 Preview, Editing과 Export에서도 촬영 중 본 Mirrored Framing과 동일한 사용자-visible Appearance를 유지한다.

Mirror Toggle은 MVP에 포함하지 않으며 구현은 특정 Mirroring API로 고정하지 않는다.

Preview, Capture / Working Media와 Composition Transform 사이에 하나의 명확한 Transform Ownership을 두어 Double-mirroring과 Accidental Un-mirroring을 방지하고 Shared Preview / Export Composition 원칙을 유지한다.

Photos Import Source에는 Front Camera Mirroring 정책을 소급 적용하지 않고 Source의 원래 Presentation을 기준으로 처리한다.

Direct Recording은 Camera Permission과 Microphone Permission을 모두 요구하며 Denied / Restricted 상태에서는 Recording이나 Timer를 시작하지 않고 Video-only Direct Recording으로 자동 Fallback하지 않는다.

Camera 또는 Microphone Permission 문제는 Photos Video Import를 차단하지 않으며 Import는 자체 Photos Picker / Permission 계약을 따르고 Audio Track이 없는 Source Video도 허용한다.

Project Orientation은 생성 시 선택한 9:16 Portrait 또는 16:9 Landscape로 Project Lifetime 동안 고정하며 Physical Device Rotation으로 변경하지 않는다.

새 Recording은 Camera / Microphone Authorization, Required Capture Device, Session Configuration, Project Validity와 Orientation Eligibility를 확인한 뒤 시작한다.

Portrait Project는 Portrait Posture, Landscape Project는 Landscape Left 또는 Landscape Right에서 Recording을 시작할 수 있다.

Project Orientation Mismatch, Face Up, Face Down, Unknown 또는 안정적으로 판단할 수 없는 Orientation에서는 새 Recording, Progress와 10초 Timer를 시작하지 않고 quiet Rotate Device Guidance를 제공한다.

Recording 시작 후 Device가 회전해도 현재 Recording을 자동 Stop / Restart하거나 새 Clip을 만들거나 Project Orientation / Clip Aspect Ratio를 변경하지 않고 Rotation만으로 Rear Zoom을 Reset하지 않는다.

현재 Clip의 Presentation Orientation은 Recording 시작 시의 Project Orientation을 유지하며 다음 Recording 시작 전에는 Orientation Eligibility를 다시 확인한다.

Landscape Left / Right에서 촬영한 Clip은 올바른 Presentation Transform으로 정규화하여 뒤집히거나 180° 잘못 회전되지 않게 한다.

Rear Capture Zoom은 촬영 결과에 반영되는 Camera Behavior이며 Phase 7의 Working Media 범위 안에서 적용하는 Metadata 기반 Editing Framing과 별개의 책임이다.

Phase 7 Framing으로 Capture Zoom 이전의 전체 1× Field of View를 복원할 수 있다고 보장하지 않는다.

Interruption 발생 시 Capture Operation을 안전한 Stop / Cancel / Finalize 경로로 이동하고 Successful Manual Stop 또는 Successful 10-second Auto-stop으로 표시하지 않으며 정상 Completion Haptic을 자동 적용하지 않는다.

Interruption Media는 ADR-020의 Transactional Commit / Validation / Recovery와 ADR-021의 Project Validity / Late Result / Deletion Safety를 따르고 Invalid / Incomplete Media를 정상 Clip으로 Commit하지 않는다.

Valid Partial Clip의 최종 보존 / Commit / 폐기와 Minimum Valid Clip Duration은 Pending으로 유지한다.

## Consequences

### Benefits

- Camera Behavior와 Recording Readiness가 예측 가능해진다.
- Lens Selector 없이 Mini Vlog 촬영 중 유용한 Rear Zoom을 제공한다.
- Preview와 Direct-recorded Front Result의 사용자-visible Framing이 일치한다.
- Permission 거부 상태에서 의도하지 않은 무음 Recording을 방지한다.
- Orientation 오류와 잘못된 Clip Transform 위험을 줄인다.
- Phase 3 / 4 구현의 모호함을 줄인다.
- Interruption 결과를 기존 Media Recovery 계약으로 안전하게 처리한다.

### Costs

- 1× 미만 Ultra Wide 촬영을 제공하지 않는다.
- Rear Digital Zoom에 따른 화질 저하 가능성이 있어 Product Maximum Quality Limit 검증이 필요하다.
- Front Camera Zoom을 제공하지 않는다.
- Microphone Permission을 거부한 사용자는 Direct Recording을 사용할 수 없다.
- Mirrored Front Output은 일부 Professional Camera Convention과 다를 수 있다.
- Orientation Gating과 Transform Ownership 구현 및 검증이 필요하다.
- Interruption Partial Media의 최종 Product Policy는 별도 Pending으로 남는다.

## Non-goals

- Exact AVCapture Zoom API
- Exact Maximum Zoom Factor
- Final Zoom Gesture / Indicator Design
- Ultra Wide Selection
- Telephoto Selection
- Advanced Camera Lens Selection
- Front Camera Zoom
- Exposure / Focus Manual Control
- Exact Permission UI Copy / Layout
- Exact Orientation Detection API / Debounce / Threshold
- Minimum Valid Clip Duration
- Interrupted Partial Clip Final Disposition
- Error / Interruption Haptic
- Exact Mirroring Implementation Mechanism

ADR-020의 Transactional Commit / Recovery, ADR-021의 Project Validity / Late Result / Deletion Safety와 ADR-022의 SDR Working Media / Non-destructive Project Framing 계약은 변경하지 않는다.

---

# ADR-024 — Operation-Aware Storage Preflight and Low-Storage Safety

**Date:** 2026-09-12

**Status:** Accepted

## Context

Recording, Photos Import / Normalization과 Export는 Operation Lifetime 동안 동시에 필요한 Staging, Intermediate, Final 및 Recovery Media의 특성이 서로 다르다.

하나의 고정 Global Free-space Threshold를 모든 Operation에 적용하면 일부 작업에는 지나치게 보수적이고 다른 작업에는 안전하지 않을 수 있다.

Storage Preflight를 통과해도 다른 App이나 System의 동시 Storage 사용과 실제 Write 특성 때문에 Runtime Disk Full이 발생할 수 있다.

Storage Pressure를 이유로 User Media나 Recovery Candidate를 자동 삭제하면 Data Loss와 Draft 손상 위험이 생긴다.

Large Project의 Storage 문제를 임의의 Total Duration 또는 Clip Count 제한으로 해결하면 기존 제품 방향과 충돌한다.

Storage Failure는 ADR-020의 Transactional Media Commit / Recovery와 ADR-021의 Logical Deletion / Active Media / Cleanup Safety 계약에 연결되어야 한다.

## Decision

Mellow MVP는 Direct Recording, Photos Video Import / Normalization과 Export 각각에 Operation-aware Storage Preflight를 적용한다.

개념적인 Required Free Space는 Estimated Peak Additional Storage와 Safety Reserve의 합이다.

Estimated Peak Additional Storage는 Final File Size만이 아니라 Operation Lifetime 동안 동시에 존재할 수 있는 Staging, Source Materialization, Normalization Intermediate / Output, Temporary Output, Final Output과 Operation-owned Recovery Material을 고려한다.

기존 Committed Media의 크기를 해당 Operation의 Additional Storage로 다시 계산하지 않는다.

Safety Reserve는 필수 개념이며 기본값을 0으로 두지 않는다.

Recording, Import와 Export는 각 Pipeline 특성에 맞는 별도 Estimate를 사용한다.

Recording Estimate는 최대 10초 Capture Profile, Staging / Finalization Overhead와 Transactional Commit을 고려한다.

Import Estimate는 선택된 최대 10초 Source Segment, Staging, Normalization Intermediate / Output, Project-owned Working Media와 Recovery-safe Overlap을 고려하고 전체 Photos Original 4K Source를 무조건 복제한다고 가정하지 않는다.

Export Estimate는 현재 Immutable Export Snapshot의 Project Duration과 State, 승인된 Export Profile, Temporary / Final Local Output과 Photos Save / Share Handoff까지 필요한 Local Artifact를 고려한다.

정확한 Safety Reserve Bytes, Operation별 Estimate Formula, Bitrate Constant, Temporary Multiplier와 Warning Threshold는 관련 Phase Technical Gate에서 Pipeline Profile과 iPhone 12 측정을 바탕으로 결정한다.

Storage가 부족하면 기본적으로 해당 Operation만 시작하지 않으며 다른 Operation은 자신의 Requirement로 독립적으로 판단한다.

Mellow 전체를 Low-storage Fatal State로 전환하거나 기존 Draft 열기, Clip 확인, Metadata-only Editing과 다른 사용 가능한 기능을 자동 차단하지 않는다.

Storage 부족을 이유로 1080p를 720p로 낮추거나 Frame Rate, Audio, 최대 Recording Duration, Import Working Media 또는 Export Quality를 자동으로 낮추지 않는다.

Committed Clip, Draft, Project-owned Valid Media, Recovery Candidate, Undo Candidate, Active Usage Media 또는 다른 Project Media를 Storage 확보 목적으로 자동 삭제하지 않는다.

자동 Cleanup은 ADR-020 / ADR-021에 따라 Recovery가 필요하지 않고 Undo / Active Usage / 다른 Reference가 없다고 안전하게 확인된 Disposable Temporary Artifact 또는 Confirmed Orphan에만 적용한다.

Preflight 이후 Runtime Disk Full 또는 Write Failure가 발생하면 Partial / Incomplete Output을 정상 Clip이나 Export로 Commit하거나 성공으로 표시하지 않는다.

기존 Committed Media, 다른 Draft와 Photos 원본을 보호하고 Media의 Recovery Candidate 또는 Disposable 여부를 ADR-020으로 판정하며 Project Delete / Late Result에는 ADR-021을 적용한다.

Final Media가 존재하지만 Metadata Persistence가 Storage 부족으로 실패한 경우 Recovery Candidate로 보존하고 Cleanup 실패는 재시도 가능하게 유지한다.

Storage Preflight는 실제 작업 대상 Application Container / Filesystem Volume의 Usable Capacity를 기준으로 판단하고 필요하면 Operation 시작 직전 또는 큰 Derived Output 경계에서 다시 확인할 수 있어야 한다.

Preflight 성공은 Runtime Disk Full이 불가능하거나 Photos Library의 최종 Save가 성공한다는 보장이 아니다.

Storage 문제를 해결하기 위해 새로운 Total Vlog Duration 또는 Clip Count Cap을 추가하지 않는다.

## Consequences

### Benefits

- 각 Operation의 실제 Peak Storage 특성에 맞는 판단이 가능하다.
- 사용자 Media와 Recovery Candidate를 Storage Pressure에서 보호한다.
- Large Project를 임의의 Product Limit으로 축소하지 않는다.
- Runtime Disk Full을 ADR-020 Recovery와 일관되게 처리할 수 있다.
- 향후 Codec / Bitrate와 Pipeline Tuning 변화에 대응할 수 있다.

### Costs

- Recording, Import와 Export마다 Estimate Logic이 필요하다.
- Safety Reserve의 적절성을 검증해야 한다.
- Estimate와 실제 사용량 사이에 오차가 생길 수 있다.
- Device와 Filesystem 상태에 따른 Runtime Failure를 완전히 제거할 수 없다.
- iPhone 12에서 실제 Peak Additional Storage 측정이 필요하다.

## Non-goals

- Exact Safety Reserve Bytes
- Exact Recording / Import / Export Estimate Formula
- Exact Bitrate 또는 Codec / Container
- Exact Temporary Multiplier
- Exact Warning Threshold
- Exact Low-storage UI Copy / Layout / Presentation
- Automatic Draft Cleanup
- Storage-based Quality Downgrade
- New Project Duration / Clip-count Cap
- Photos Save / Share Result File Lifecycle
- Performance Pass / Fail Threshold

ADR-020의 Transactional Media Commit / Recovery, ADR-021의 Logical Deletion / Active Media / Cleanup Safety, ADR-022의 1080p-class / 30 fps / SDR Working Media와 ADR-023의 Camera / Recording / Zoom / Permission / Orientation 계약을 변경하지 않는다.

---

## 3. Pending Decisions

다음 목록은 Pending Decision과 이후 해결된 항목의 이력을 함께 유지한다.

`Resolved by ADR-022`, `Resolved by ADR-023` 또는 `Resolved by ADR-024`로 표시된 High-level Policy는 확정되었으며 나머지 Pending Technical Detail은 임의로 구현 기준을 결정하지 않는다.

### HDR and Color

- HDR Source Import 정책 — Resolved by ADR-022: HDR Source Import 허용.
- Dolby Vision 처리 — High-level Policy Resolved by ADR-022: Source Import를 허용하고 SDR Working Media로 정규화하며 구체적인 Tone-mapping 구현은 Pending.
- HDR 유지 또는 SDR 변환 — Resolved by ADR-022: SDR Working Media로 변환하며 HDR Metadata 보존을 MVP requirement로 하지 않음.
- Export Color Space — MVP Export HDR vs SDR 방향은 Resolved by ADR-022: SDR이며 정확한 SDR Color Profile / Tagging은 Pending.

### SDR and Working Media Technical Details

- Working Media Codec — Pending, Before Phase 6.
- Working Media Container — Pending, Before Phase 6.
- 정확한 SDR Color Profile / Tagging — Pending, Before Phase 6.
- Low-resolution Source Upscaling Policy — Pending, Before Phase 6.
- 1080p-class Working Media의 정확한 Raster Dimension Rule — Pending, Before Phase 6.
- HDR / Dolby Vision Source의 Tone-mapping 구현 방법 — Pending, 관련 Normalization 구현 전 결정.

Working Media Codec / Container를 Export Codec / Container와 자동으로 동일하게 결정하지 않는다.

### Export

- H.264 또는 HEVC
- File Container
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

- Rear Camera Lens 정책 — Resolved by ADR-023: MVP 기본 1× Wide이며 0.5× Ultra Wide / Telephoto / Lens Selector는 제외.
- Rear Continuous Zoom — Resolved by ADR-023: Preview와 Active Recording에서 1× 이상 지원.
- Rear Maximum Zoom Product Quality Limit — Pending, Phase 3 Gate.
- Rear Zoom Interaction / Indicator / Visual Presentation — Pinch-to-zoom은 Primary Candidate이며 Final Structural UX는 Pending, Phase 3 Gate.
- Front Camera Zoom — Out of MVP by ADR-023.
- Front Camera 저장 영상의 Mirror Policy — Resolved by ADR-023: Preview와 Direct-recorded Result의 Mirrored Appearance 유지.
- Camera Permission의 Direct Recording 동작 — High-level Policy Resolved by ADR-023: Denied / Restricted이면 Recording 차단, Photos Import는 독립.
- Microphone Permission의 Direct Recording 동작 — High-level Policy Resolved by ADR-023: Denied / Restricted이면 Recording 차단, Video-only Fallback 없음, Photos Import는 독립.
- Orientation Mismatch와 Mid-record Rotation — High-level Policy Resolved by ADR-023: Start Gate 적용, Recording / Project Orientation 유지, 다음 Recording 전 재평가.
- 정확한 Orientation Detection API / Threshold / Debounce — Pending.
- Minimum Valid Clip Duration — Pending.
- Recording Interruption에서 Valid Partial Clip의 최종 처리 — Pending.
- Recording Error / Interruption Haptic — Pending.
- Tap to Focus 도입 시점
- Exposure Control 도입 시점
- Post-MVP Front Zoom / Advanced Lens Control 도입 시점
- Torch 도입 시점

### Storage

- Storage Strategy — High-level Policy Resolved by ADR-024: Operation-aware Storage Preflight를 사용한다.
- Fixed Global Free-space Threshold — ADR-024에 따라 Primary MVP Gating Strategy로 사용하지 않는다.
- Estimated Peak Additional Storage + Safety Reserve — High-level Policy Resolved by ADR-024.
- 정확한 Safety Reserve Bytes — Pending, 관련 Owning Phase Technical Gate.
- Recording Estimate Formula, Capture Codec / Bitrate 상수와 Finalization Overhead — Pending, Before Phase 4.
- Import Estimate Formula와 Temporary / Recovery-safe Overlap Multiplier — Pending, Before Phase 6.
- Export Snapshot 기반 Estimate Formula와 Temporary Multiplier — Pending, Before Phase 9.
- Storage Warning 기준과 Low-storage UI Presentation — Pending, Owning UX Gate.

### Design Details

- Recent Project의 List 또는 Grid Layout
- Imported Video Crop에서 Pinch to Zoom 지원 여부
- Recording Haptic의 정확한 Timing — 기존 Pending 이력을 유지하며 H04 사용자 승인으로 정상 Recording의 사용 시점과 의미를 다음과 같이 동기화한다.
  - Recording Start Haptic — Resolved: 사용하지 않으며 Record Button Tap 또는 Recording Start 성공에 Haptic을 제공하지 않는다.
  - Successful Recording Completion Haptic — Resolved: Manual Stop과 10-second Auto-stop 완료 시 동일한 "이 Clip의 Recording이 종료되었다."라는 의미의 subtle completion haptic을 제공하며 종료 직전 예고 신호가 아니다.
  - Visual Recording State / Circular Progress / Completion State는 주된 상태 전달 수단이며 Haptic은 이를 대체하지 않는 보조 Feedback이다.
  - Recording Error / Interruption Haptic — Pending.
  - 정확한 Haptic API / Style / Intensity / Sharpness / Pattern / Duration / Generator 구현과 Timing — 승인된 Completion 의미 안의 Native iOS Implementation Detail / Tuning으로 유지하며 이번 결정에서 특정 값을 확정하지 않는다.
- Camera Control의 정확한 Placement

Pending Decision이 확정되면 기존 ADR에 단순히 내용을 끼워 넣기보다 결정의 중요도에 따라 새로운 ADR을 추가한다.

---

## 4. Decision Change Policy

Accepted ADR의 내용이 변경되는 경우 기존 기록을 삭제하거나 과거의 결정을 현재 결정처럼 다시 작성하지 않는다.

중요한 방향 변경은 새로운 ADR로 기록하고 이전 ADR의 Status를 `Superseded`로 변경한다.

새 ADR에는 어떤 ADR을 대체하는지 명시한다.

이를 통해 Mellow의 제품 및 기술 방향이 왜 변경되었는지 추적할 수 있도록 한다.
