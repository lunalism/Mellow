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
**Status:** Superseded by ADR-029

이 ADR의 아래 내용은 과거 결정 기록이며 현재 Duration 정책은 ADR-029가 대체한다.

Duration 외 기존 Photos Import / Media Safety, Pause / Resume 제외와 Progress Ring 방향은 ADR-029에서 유지한다.

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
**Status:** Superseded by ADR-029

이 ADR의 아래 내용은 과거 결정 기록이며 현재 Duration 정책은 ADR-029가 대체한다.

Duration 외 기존 Photos Import / Media Safety, Pause / Resume 제외와 Progress Ring 방향은 ADR-029에서 유지한다.

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

**Partial Supersession:** 이 ADR의 10초 Duration / Timer 참조만 ADR-029에 의해 Superseded되었으며 아래 원문은 당시 기준의 기록이다.

현재 Capture는 선택한 최대 Duration, Imported Segment와 공통 Clip 상한은 5초를 적용하고 나머지 결정은 Accepted 상태로 유지한다.

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

**Partial Supersession:** 이 ADR의 10초 Duration / Timer 참조만 ADR-029에 의해 Superseded되었으며 아래 원문은 당시 기준의 기록이다.

현재 Capture는 선택한 최대 Duration, Imported Segment와 공통 Clip 상한은 5초를 적용하고 나머지 결정은 Accepted 상태로 유지한다.

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

**Partial Supersession:** Text Overlay의 일괄 Post-MVP 분류만 ADR-030의 가벼운 Clip Text 승인으로 대체하며 아래 원문은 당시 기록이다.

나머지 Photo / Advanced Editing / Creative Feature 제외 정책은 유지한다.

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

**Partial Supersession:** ADR-033에 따라 Direct Camera Recording은 Project-owned Media로 Commit하지 않고 Staging → Photos Save Lifecycle을 따른다. 이 ADR의 Transactional Commit / Recovery 계약은 Photos Import와 이후 Project Media Materialization(Select Clips)에 계속 적용되며 아래 원문은 당시 기준의 기록이다.

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

**Partial Supersession:** ADR-033에 따라 Recording Finalization은 더 이상 Project를 Commit 대상으로 갖지 않으므로 Late Recording Commit 차단 계약은 Project Materialization / Import 경로에만 적용되며, Project 삭제 / 대체는 Photos 원본을 절대 삭제하지 않는다. 아래 원문은 당시 기준의 기록이다.

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

**Partial Supersession:** 이 ADR의 10초 Duration / Timer 참조만 ADR-029에 의해 Superseded되었으며 아래 원문은 당시 기준의 기록이다.

현재 Capture는 선택한 최대 Duration, Imported Segment와 공통 Clip 상한은 5초를 적용하고 나머지 결정은 Accepted 상태로 유지한다.

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

**Partial Supersession:** ADR-033이 Microphone 필수 Direct Recording(Denied / Restricted 시 Recording 차단, Video-only Fallback 없음)을 대체하여 Microphone을 선택 권한으로 하고 무음 Recording을 허용하며, Recording Start Gate를 upright Portrait 자세만 허용(Landscape / Face Up / Face Down / Unknown / Unstable 거부)으로 확정한다. Recording 중 자세 변경은 ADR-033(2026-09-14 Resolution)으로 확정되어 Clip Orientation이 Recording 전체 동안 Portrait으로 고정되고 자세 변경만으로 Stop / Restart하지 않으며 종료 후 자세를 재평가한다. 나머지 Lens / Zoom / Mirroring / Interruption 계약은 유지하며 아래 원문은 당시 기준의 기록이다.

**Partial Supersession:** 이 ADR의 10초 Duration / Timer 참조만 ADR-029에 의해 Superseded되었으며 아래 원문은 당시 기준의 기록이다.

현재 Capture는 선택한 최대 Duration, Imported Segment와 공통 Clip 상한은 5초를 적용하고 나머지 결정은 Accepted 상태로 유지한다.

## Phase 3 Gate Resolution — 2026-09-13

사용자는 Rear 1× Wide Camera에서 1.0×–2.0× Continuous Pinch-to-zoom과 양 끝 Clamp를 승인했다.

다른 Physical Lens로 전환하지 않고 Persistent Zoom Button / Slider를 제공하지 않으며 Gesture 중 작은 Transient Numeric Indicator만 허용한다.

Front Camera에는 User Zoom을 제공하지 않으며 Gesture Feel은 iPhone 12에서 조정할 수 있다.

Phase 3 Correction은 Camera Permission만 사용하고 Microphone Authorization / Input과 실제 Recording은 Phase 4에 남기며 아래 Direct Recording Permission 정책은 변경하지 않는다.

아래 원문의 Zoom Candidate / Maximum Pending은 이 Gate Resolution 이전 이력이며 새 범위를 Pending으로 해석하지 않는다.

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

**Partial Supersession:** 이 ADR의 10초 Duration / Timer 참조만 ADR-029에 의해 Superseded되었으며 아래 원문은 당시 기준의 기록이다.

현재 Capture는 선택한 최대 Duration, Imported Segment와 공통 Clip 상한은 5초를 적용하고 나머지 결정은 Accepted 상태로 유지한다.

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

# ADR-025 — Export Result, Photos Save, Share, and Artifact Lifecycle

**Date:** 2026-09-12

**Status:** Accepted

## Context

Export Rendering과 Photos Save는 별도 Failure Boundary이며 Successful Render 이후에도 Photos Save가 실패할 수 있다.

Save Retry와 Share를 위해 Valid Local Export Artifact가 필요하다.

Share 중 File Deletion Race를 방지해야 한다.

App Crash는 Render, Save와 Cleanup 경계 사이에서 발생할 수 있다.

Project Delete와 Export Consumer Lifecycle이 충돌할 수 있다.

Storage Pressure 때문에 Unresolved Result를 삭제하면 User Result Loss가 발생할 수 있다.

## Decision

Render Success와 Photos Save Success를 분리한다.

Successful Local Export Artifact를 Photos Save, Save Retry와 Share에서 재사용한다.

Photos Save Failure는 Render Success를 무효화하지 않는다.

Photos Save Failure 후 Save Retry와 Share를 제공한다.

Share Cancel은 Export Failure가 아니다.

Active Consumer가 존재하는 동안 Artifact Physical Delete를 Defer한다.

Photos Save에 성공하지 않은 Successful Artifact를 Done에서 silently discard하지 않으며 explicit user discard를 요구한다.

Project Delete는 External Photos Result를 삭제하지 않는다.

Crash 또는 Relaunch 시 Valid Unresolved Artifact는 Recovery Classification 대상이며 Cleanup은 Idempotent해야 한다.

동일 Artifact를 이유 없이 Re-render하지 않는다.

## Consequences

### Benefits

- Photos Save Failure에서도 User Result를 보호한다.
- 불필요한 Re-render를 방지한다.
- Share와 Save Retry를 같은 Artifact로 단순화한다.
- Artifact Lifecycle과 External Ownership이 명확해진다.
- Crash Recovery와 Project Delete 경합을 안전하게 처리할 수 있다.

### Costs

- Local Artifact와 Result State를 추적해야 한다.
- Unresolved Result가 Local Storage를 일시적으로 소비한다.
- Cleanup과 Recovery Reconciliation이 복잡해진다.
- UI가 Render와 Save 상태를 구분해야 한다.

## Non-goals

- Exact Export Codec, Container와 Bitrate
- Background Export
- Exact Photos Error-specific Copy
- Exact Result Screen Layout
- Exact Share Button Placement
- External App Final Delivery Guarantee
- Automatic Past-export Recovery UI

ADR-020의 Valid Artifact와 Partial / Incomplete Output 분류 및 Recovery Candidate 원칙, ADR-021의 Active Consumer, Deferred Physical Delete, Project Invalidation과 Late Async Result 원칙, ADR-024의 Storage Preflight와 User Media 자동 삭제 금지 원칙을 확장 적용한다.

---

# ADR-026 — Empty Project and Unavailable Media Behavior

**Date:** 2026-09-12

**Status:** Accepted

**Partial Supersession:** ADR-033에 따라 V1은 Recording으로 Project를 만들지 않고 편집 가능한 저장 Project를 최대 하나만 유지하므로 0 Clip Project는 V1 정상 흐름에서 생성되지 않는다. Unavailable Clip / Replace 정책은 유지하며 아래 원문은 당시 기준의 기록이다.

## Context

0 Clip Draft는 정상 사용자 Workflow 중 발생할 수 있다.

Media File은 Metadata와 독립적으로 Missing 또는 Corrupt될 수 있다.

Damaged Clip 하나 때문에 Project 전체를 잃게 하면 안 된다.

Silent Skip은 사용자가 의도한 Vlog 결과를 변경한다.

Automatic Deletion은 User Media Loss 위험이 있다.

Recovery Candidate와 True Missing 또는 Corrupt Media를 구분해야 한다.

User-controlled Replacement가 필요하다.

## Decision

0 Clip Project는 Valid Draft다.

Empty Project는 정상적으로 열리고 Recording과 Photos Import를 허용한다.

Empty Project는 Full Vlog Preview와 Export를 비활성화한다.

Unavailable Clip은 기존 Timeline Position을 유지한다.

Unavailable Clip은 자동으로 삭제하거나 자동으로 다른 Media로 대체하거나 Full Preview 또는 Export에서 조용히 생략하지 않는다.

사용자는 Unavailable Clip을 Replace 또는 Delete할 수 있다.

Healthy Clip은 계속 사용할 수 있다.

Unresolved Unavailable Clip은 Full Vlog Preview와 Export를 차단한다.

All-unavailable Project도 Draft로 유지하며 새 Direct Recording, Photos Import, Replace와 Delete를 허용한다.

Replacement는 기존 Unavailable Logical Slot을 유지한 채 Media Acquisition, Staging, Validation, 필요한 Normalization, Final Media와 Transactional Commit을 거치는 Operation이다.

Photos Import를 Replacement Source로 사용해도 Photos 원본은 수정하거나 삭제하지 않는다.

Replacement Failure는 기존 Placeholder를 보존한다.

Committed Clip Metadata 없이 존재하는 Media는 자동 User-visible Clip으로 노출하지 않고 ADR-020의 Recovery Candidate Classification을 적용한다.

Project-level Corruption은 다른 Draft에서 격리한다.

Filename Similarity, 다른 Project Media, Nearest Asset 또는 검증되지 않은 File을 이용해 Missing Media를 자동 대체하지 않는다.

## Consequences

### Benefits

- User Timeline을 보존한다.
- Damaged Media가 다른 Clip을 파괴하지 않는다.
- Recovery Behavior를 예측 가능하게 한다.
- Silent Changed Export를 방지한다.
- User-controlled Repair를 제공한다.
- Empty Project Workflow를 명확하게 한다.

### Costs

- Unavailable State UI가 필요하다.
- Replace Workflow가 필요하다.
- Preview와 Export Eligibility Logic이 증가한다.
- Replacement Metadata Migration Decision이 필요하다.
- Corrupted Project Isolation과 Recovery가 복잡해진다.

## Non-goals

- Exact Unavailable UI
- Exact Replace Screen
- Replacement Clip Identity Implementation
- Trim / Framing / Transform / Thumbnail Migration Policy
- Exact Project Metadata Recovery Algorithm
- Automatic Cloud Restore
- Silent Missing-media Substitution

ADR-020의 Recovery Candidate Classification, ADR-021의 Delete / Active Usage / Project Validity / Late Result, ADR-024의 Storage Failure와 User Media 자동 삭제 금지, ADR-025의 Export Artifact Lifecycle을 변경하지 않는다.

---

# ADR-027 — Phase 2 Home and Vlog Creation Structure

**Status:** Superseded by ADR-028

## Context

Phase 2의 Home / Recent 구현 전 Structural UX Gate를 사용자 승인으로 해결한다.

## Decision

- Recent는 iPhone 가독성과 Dynamic Type을 고려한 Single-column List를 사용하며 Phase 2에서 2-column Grid를 구현하지 않는다.
- Item은 Neutral Visual Placeholder, 기존 Domain의 자동 Project Name, Project Orientation / Aspect Ratio와 Clip Count만 표시한다.
- 추가 Creation / Modified Timestamp, Duration 또는 Speculative Metadata는 표시하지 않는다.
- Home 상단 가까이에 명확한 Primary `New Vlog` Action을 배치하며 Bottom-fixed / Floating Button은 사용하지 않는다.
- Orientation Selection은 Sheet가 아닌 전용 화면이며 `9:16 Portrait`와 `16:9 Landscape`를 명확히 표시한다.
- Orientation 선택 즉시 기존 Domain / Persistence Layer를 통해 Project를 저장하고 추가 Confirmation 없이 Camera Placeholder로 이동한다.
- Project Item Menu의 Delete에서 System Confirmation Alert를 거쳐 삭제하며 Phase 2에서 Swipe-to-delete는 사용하지 않는다.
- 0 Clip Project도 동일한 Recent Item에 Neutral Placeholder, 자동 이름, Orientation과 `0 clips`로 표시하며 별도 Card나 Draft Category를 만들지 않는다.
- 사용자-facing 용어는 `Recent`이며 `Draft`를 노출하지 않는다.

## Consequences

단일 열과 최소 정보 계층은 iPhone에서 가독성과 Dynamic Type 대응을 우선하며 Grid보다 한 화면에 표시하는 Project 수는 줄어든다.

현재 Placeholder 자리에 이후 Thumbnail을 표시할 수 있으며 Home 정보 구조는 유지한다.

## Non-goals

Camera Capture, Thumbnail Generation, Media File Management와 Phase 3 이후 기능은 이 결정으로 추가하지 않는다.

---

# ADR-028 — Format-first Launch and Dedicated Recent Projects

**Status:** Accepted

**Partial Supersession:** Launch의 Existing-project Continue Text Entry는 ADR-030에 의해, Format-first Launch / Orientation Chooser와 Format-first Creation은 ADR-032에 의해 V1 범위에서 Superseded되었으며 아래 원문은 Phase 2 당시 승인 기록으로 보존한다.

Naming, Persistence, Delete와 Immutable Orientation은 유지한다. ADR-033에 따라 Multi-project Recent Projects Grid / Browser는 V1 Primary Projects Flow에서 제외되고 Camera Projects Entry(`Select Clips` / `Load Last Saved`)로 대체되며 Browser 구조는 이후 Version을 위해 보존한다.

## Context

Physical-device Review 후 사용자가 Phase 2 Structural UX를 명시적으로 변경하여 ADR-027을 대체한다.

## Decision

- App Launch는 Orientation Chooser이며 별도 Home Dashboard와 중간 New Vlog Action을 제거한다.
- Header 없는 중앙 Format Prompt 아래 Portrait 9:16 / Landscape 16:9가 직접 생성 Action이 되며 최종 Visual Baseline은 `DESIGN.md` 6–7절을 따른다.
- 일반 Dynamic Type에서는 iPhone 12에 편안한 두 열을 사용하고 Accessibility Size에서는 세로 한 열로 전환한다.
- 선택 전에는 Project를 만들지 않으며 선택 즉시 기존 HomeModel / Domain / Repository로 저장한 뒤 추가 Confirmation 없이 Camera Placeholder로 이동한다.
- 저장된 Project가 있을 때만 선택지 아래 `Continue an existing project?` Text Action으로 전용 `Recent Projects` 화면에 진입한다.
- Recent Projects는 두 열의 Adaptive Thumbnail Grid이며 Accessibility Size에서는 한 열로 전환한다.
- Project Orientation과 무관하게 Placeholder의 외부 Geometry는 동일하며 내부 Shape로 비율을 표현할 수 있다.
- Phase 2는 Neutral Placeholder만 사용하고 실제 Thumbnail Generation이나 Media Infrastructure를 추가하지 않는다.
- 기존 자동 Project Name / Date, Orientation, Clip Count와 Item Menu만 표시하며 추가 Timestamp, Duration, Favorites와 Folder는 추가하지 않는다.
- Item Menu → Delete → System Confirmation Alert와 기존 Persistence / Ordering / Error Handling / Naming / Immutable Orientation을 유지한다.
- 0 Clip Project는 동일한 정상 Project Item에 `0 clips`로 표시하며 사용자에게 Draft 용어를 노출하지 않는다.
- Cream Background를 제거하고 systemBackground, label, secondaryLabel, secondarySystemBackground 등 Semantic Color로 Native Light / Dark Appearance를 자동으로 따른다.

## Consequences

새 Project 생성까지의 Interaction이 줄고 기존 Project 탐색은 별도 화면에서 수행한다.

2026-09-13 사용자가 최종 Phase 2 UX와 iPhone 12 Physical-device Validation을 승인했다.

ADR-028은 Accepted / Active로 유지하며 Typography와 Recent-only Date 표현을 포함한 최종 Visual Refinement는 `DESIGN.md`의 승인된 Baseline으로 기록한다.

## Non-goals

Domain / Persistence Architecture 변경, 실제 Camera / Thumbnail / Media 기능과 Phase 3 이후 기능은 포함하지 않는다.

---

# ADR-029 — Short Clip Duration Policy

**Date:** 2026-09-13
**Status:** Accepted

## Context

Phase 2 완료 후 사용자가 Mini Vlog의 짧은 순간과 리듬을 강화하는 Product Direction 변경을 승인했다.

여러 짧은 Clip이 하나의 이야기를 구성하고 하나의 Clip이 Vlog를 지배하는 경향을 줄이는 것이 Mellow Mini Vlog Camera의 방향이다.

## Decision

### Direct Capture

- Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration 선택을 제공하며 기본 선택은 `3s`다.
- 선택한 Preset은 다음 Recorded Clip의 Maximum이며 해당 시점에 자동 종료한다.
- 사용자는 선택한 Maximum 전에 수동 종료할 수 있으며 3s 선택 후 1.4초에 Stop하면 약 1.4초 Clip을 만든다.
- Preset은 정확한 정수 Output Duration을 강제하지 않는다.
- Duration 선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있고 Project-level 불변 속성이 아니다.
- Project Orientation은 9:16 Portrait / 16:9 Landscape의 기존 Project-level 불변 정책을 유지한다.

### Imported Video

- Photos Source Video의 전체 Duration은 제한하지 않으며 2분 또는 20분 Source도 선택할 수 있다.
- 사용자는 Source에서 원하는 구간을 자유롭게 선택 / Trim하며 사용 구간은 0초보다 길고 5초 이하다.
- 1.3초, 2.7초, 4.5초, 5.0초처럼 정수가 아닌 Duration도 허용하며 Camera Preset은 Imported Trim에 적용하지 않는다.
- Photos 원본 비파괴 보존과 Project-owned Working Media 방향은 유지한다.

### Canonical Invariant

Source와 관계없이 Mellow Vlog에서 사용하는 모든 Clip은 `0 < effectiveClipDuration <= 5 seconds`를 만족한다.

## Superseded Decisions

ADR-005의 최대 10초 자유 Recording / Preset 미제공 및 공통 Clip 상한과 ADR-006의 최대 10초 Imported Segment 정책을 대체한다.

ADR-007 / ADR-014 / ADR-022 / ADR-023 / ADR-024에서 참조하던 10초 Duration / Timer 기준도 대체하며 Media Ownership, 전체 Vlog 제한 없음, Normalization, Zoom / Permission / Interruption 및 Storage Safety 계약은 유지한다.

ADR-005 / ADR-006의 Duration 외 기존 Pause / Resume 제외, Progress Ring 방향, Photos Import와 Media Safety 정책은 유지한다.

ADR-028의 Phase 2 Structural UX는 변경하지 않는다.

## Rationale

1–5초 최대 Preset은 엄격한 1–3초보다 유연하면서 짧은 순간을 여러 Clip으로 연결하는 Short-form 정체성과 Mini Vlog의 리듬을 유지한다.

## Consequences

Phase 3 Camera Structural UX Gate에서 Duration Selector의 존재와 새 정책을 전제로 배치 / Interaction 구조를 승인하며 실제 Recording은 Phase 4가 소유한다.

Phase 4는 기존 Domain / Test의 Duration 기준을 정렬하고 Selector, 기본 3s, Manual Early Stop, 선택한 Maximum Auto Stop과 공통 5초 상한을 구현·검증한다.

Phase 6 Import와 Phase 7 Trim은 길이 제한 없는 Source와 정수 Preset에 구속되지 않는 `0 < duration <= 5 seconds` Segment를 구현·검증한다.

이 변경은 문서와 Product Decision만 기록하며 Swift / Xcode 파일을 수정하지 않고 Phase 3 또는 이후 구현을 시작하거나 완료하지 않는다.

## Open Details / Non-goals

Preset의 App Relaunch 이후 유지, Project별 기억 여부와 Preset 변경의 기존 Clip 영향은 이 결정에서 확정하지 않고 Phase 4 구현 전 Gate에 남긴다.

Selector Placement / Camera Control Layout은 Phase 3 Structural UX Gate에서 결정한다.

기존 승인된 Haptic, Audio, Circular Progress와 Countdown 정책은 변경하지 않으며 새로운 Animation / Timing / Haptic 동작을 만들지 않는다.

기존 Pending인 Interruption Partial Clip 처리와 Minimum Valid Clip Duration의 추가 하한은 해당 Gate에 남기되 공통 `0 < duration <= 5 seconds` Invariant를 완화하지 않는다.

---

# ADR-030 — Capture-to-Editor Structural UX

**Date:** 2026-09-13
**Status:** Accepted

**Partial Supersession (ADR-033):** `Camera → Short Clip Capture → Clip Review / Management → Editor → Export`를 하나의 Persisted Project 안에서 연결한다는 전제 중 Capture 단계는 Project에 속하지 않는다. Camera Clip은 Photos에 저장되고 Project는 이후 `Select Clips`에서 만들어지며 Compact Project-content Access는 단일 저장 Project 진입으로 재해석한다. Lightweight Editor 구조는 유지한다.

## Context

Mellow의 짧은 Clip을 Capture에서 Composition으로 빠르게 연결하고 단순한 배열과 명시적인 Control로 Editing 복잡성을 낮추기 위해 사용자가 구조를 승인했다.

## Decision

### Launch and Projects

- Format-first Launch와 중앙 `Choose your vlog format`, Portrait 9:16 / Landscape 16:9를 유지한다.
- 눈에 띄는 `Continue an existing project?` Text CTA를 제거하고 Upper Trailing 영역의 작은 Projects Button을 조용한 Secondary Access로 제공한다.
- Accessibility Label은 `Projects`이며 정확한 Iconography는 Phase 3 Visual 구현 세부사항이다.
- Projects는 기존 전용 `Recent Projects` Browser를 열며 기존 Project를 열기 전에 새 Format을 선택하도록 강제하지 않는다.
- Launch에는 Project Thumbnail, Metadata와 Recent Grid를 직접 표시하지 않는다.

### Camera → Clips → Editor

Format Selection → Camera → Short Clip Capture → Clip Review / Management → Editor → Export를 하나의 Persisted Vlog Project 안에서 연결한다.

Camera에는 최근 / 마지막 Clip의 작은 Thumbnail 또는 동등한 Compact Project-content Access를 두고 탭하면 해당 Project의 Clip Review / Editor로 이동한다.

Camera에 복잡한 Timeline이나 별도 Dashboard를 추가하지 않는다.

### Lightweight Editor

- 큰 Preview가 Primary Visual Focus이며 단순한 Ordered Clip Thumbnail Strip과 가벼운 Tools를 제공한다.
- Single Tap은 Clip 선택이며 관련 Clip Tools를 노출 / 활성화하고 Text Entry를 즉시 열지 않는다.
- Long Press + Drag는 Clip Reorder이며 Move Earlier / Move Later 같은 Non-drag Accessibility 대안을 제공한다.
- Clip을 선택한 뒤 발견하기 쉬운 명시적인 `T` Tool을 탭하여 해당 Clip의 Text를 추가 / 수정한다.
- Trim / Text / Delete Action과 Camera / Photos Library를 지원하는 Add Clip을 명시적으로 제공한다.
- Final Output Action을 명확히 제공하되 정확한 Label과 Export 구현은 Phase 9가 소유한다.
- Toolbar Geometry, Text Font / Position / Size / Duration / Animation 세부 정책은 이 결정에서 고정하지 않는다.
- Multi-track Timeline, Keyframe, Layer Stack, Professional NLE, 복잡한 Typography / Effect / Text Animation System과 Sticker는 추가하지 않는다.

## Superseded Scope

ADR-028의 Existing-project Launch Entry만 대체하며 원문은 Phase 2 승인 이력으로 보존한다.

Format-first Creation, 전용 Recent Projects Browser, Grid, Naming, Persistence, Delete와 Immutable Orientation 등 ADR-028의 나머지 결정은 유지한다.

ADR-019의 Text 일괄 Post-MVP 분류는 가벼운 Clip Text 범위에 한해 대체하고 그 외 MVP 제외 정책은 유지한다.

ADR-029의 Duration 정책은 변경하지 않는다.

## Roadmap Ownership

- Phase 3: Launch Projects Access와 Camera Shell / Structural Navigation이며 이후 Editor 기능을 선행 구현하지 않는다.
- Phase 4: 실제 Capture와 ADR-029 Recording 정책을 구현한다.
- Phase 5: 실제 Thumbnail / Clip Review, Selection, Long Press + Drag / Accessible Reorder, Delete / Add Clip과 Editor Shell을 구현한다.
- Phase 6: Photos Import와 Segment Selection을 구현한다.
- Phase 7: 기존 Trim / Framing과 함께 사용자가 승인한 가벼운 Text 입력 / 수정 UI를 구현하며 세부 Text 정책과 Metadata / Persistence 계약을 구현 전에 승인한다.
- Phase 8: Shared Individual / Full Preview에 승인된 Text 결과를 반영한다.
- Phase 9: 명확한 Final Output과 승인된 Text의 Export / Preview Parity를 구현한다.

## Transition and Non-goals

현재 Phase 2 Swift와 UI Test에는 조건부 Continue Text Entry가 남아 있으며 Phase 3에서 정렬한다.

이 결정은 Documentation-only Target이며 UI, Thumbnail, Text, Capture, Import와 Export를 지금 구현하지 않고 완료된 Phase 2를 다시 구현했다고 주장하지 않는다.

Phase 번호와 기존 Recording / Import / Trim / Preview / Export 경계는 유지하며 새 Text 소유권만 사용자 승인에 따라 Phase 7–9에 배정한다.

---

# ADR-031 — First-Run Permission Onboarding and Full-bleed Camera Foundation

**Date:** 2026-09-13
**Status:** Accepted

**Partial Supersession (ADR-033):** 첫 실행 권한 순서는 `Camera → Microphone → Photos Add`로 확장되며 각 권한은 설명 후 한 번에 하나씩 요청한다. Phase 3 구현의 Camera-only 요청은 Phase 3 당시 기준이며 Microphone / Photos Add 요청 추가는 Phase 4가 소유한다.

**Partial Supersession:** ADR-032가 `Onboarding → Format Selection → Camera` Navigation만 `Onboarding → Portrait Camera`로 대체한다. First-Run Permission Onboarding, Camera Permission 소유, 이른 Camera Foundation 준비와 Full-bleed Camera 방향은 유지하며 아래 원문은 승인 기록으로 보존한다.

## Context

Phase 3 이전 사용자 리뷰에서 첫 화면이 지나치게 무겁고 카메라 초기 진입이 느리며, 포맷 선택 전 권한/준비 상태가 흐릿하게 느껴지는 문제가 확인되었다.

## Decision

- 형식 선택 전에 첫 실행 전용 Permission Onboarding을 한 번 표시한다.
- Onboarding은 기능 동작 설명과 선택 동의를 위한 단계이며 실제 시스템 권한 요청과 분리한다.
- 카메라 권한은 Camera Shell 소유인 Phase 3에서 요청한다.
- Microphone, Photos, 위치 권한은 각각 기존 Owning Phase의 요청 타이밍을 따른다.
- Onboarding 완료는 프로젝트 저장과 분리되는 app-level 상태이며, 완료 후에는 첫 실행이 아닌 경우 다시 강제 표시하지 않는다.
- 기존 Camera 권한이 이미 허용/차단된 설치는 마이그레이션 시 기존 권한 상태를 바탕으로 Onboarding을 건너뛸 수 있다.
- 카메라 권한이 허용되면 형식 선택에서 Camera Foundation 준비 작업을 미리 시작할 수 있으나, 형식 선택 화면에서 실제 preview를 시작하지 않는다.
- Camera는 화면을 대부분 차지하는 Full-bleed Preview 구조로 유지하고, Project aspect ratio를 프레임 가이드 또는 외곽 마스킹으로 시각적으로 나타낸다.
- Portrait/Landscape 미리보기 카드를 작게 고정한 contained 프레임은 사용하지 않는다.
- 프로젝트 Orientation 고정과 phase 분리 규칙은 기존 결정 및 Safety 계약을 그대로 유지한다.

## Consequences

Permission 요청은 필요 권한으로 제한되며, 권한 체계는 camera/microphone/photos/location의 Owning Phase와 분리되어 유지된다.

이 결정은 Phase 3 Camera Foundation 구조로의 전환을 정당화하며, 실제 촬영/녹화 기능은 소유 Phase 이전에 구현되지 않는다.

## Non-goals

- 모든 권한을 Launch에서 즉시 요청하지 않는다.
- Preview를 표시하지 않을 상태에서 카메라를 실제 수집 상태로 실행하지 않는다.

Microphone/Import/Export Copy와 구체적인 안내 문구, 위치 권한의 후속 UX는 해당 Owning Phase가 소유한다.

---

# ADR-032 — Portrait-Only V1 and Direct-to-Camera Launch

**Date:** 2026-09-13
**Status:** Accepted

**Partial Supersession (ADR-033):** `Portrait Camera → Projects → Recent Projects` 구조와 Recording / Capture Phase가 소유하던 Atomic Creation 경계는 ADR-033의 Capture / Project 분리와 Camera Projects Entry(`Select Clips` / `Load Last Saved`)로 대체된다. Launch 시 빈 Project 미생성 Invariant는 Recording 성공에도 확장 적용된다.

**Supersedes:** ADR-028의 Format-first Launch / Orientation Chooser와 Format-first Creation을 V1 범위에서 대체하고, ADR-031의 `Onboarding → Format Selection → Camera` Navigation만 대체한다. ADR-029는 변경하지 않으며 ADR-030은 호환되는 범위에서 유지한다.

## Context

Phase 3 Camera Foundation의 iPhone 12 Physical Review 과정에서 사용자가 V1 제품 범위를 재확인했다.

Mellow의 핵심 가치는 앱을 열고 바로 짧은 순간을 촬영하는 것이며, Portrait 중심 사용에서 촬영 전 형식 선택은 불필요한 단계로 판단되었다.

## Decision

### Portrait-Only V1

- V1의 새 Capture는 `9:16 Portrait`만 사용한다.
- Landscape `16:9`의 새 Project 생성과 Camera Capture는 V1 이후로 유예한다.
- 이 결정은 Product Scope 축소이며 Domain / Schema Migration이 아니다.
- Domain, Persistence와 이후 Architecture는 Portrait 9:16과 Landscape 16:9를 계속 표현할 수 있다.

### Launch Experience

- 승인된 Splash Asset은 `MellowSplashLogo`이며 Catalog 위치는 `MellowApp/Resources/Assets.xcassets/MellowSplashLogo.imageset`이다.
- Launch 표현은 승인된 Camera-symbol Logo Artwork만 사용하고 Marketing Copy, Tagline, Loading 표시와 장식 Illustration을 두지 않는다.
- Native iOS Launch Screen / Launch Presentation에 `MellowSplashLogo`를 중앙 배치하며 인위적인 Timer나 강제 지연 없이 Application 상태가 준비되는 즉시 전환한다.
- Splash는 Brand Identity, Launch Continuity와 Onboarding / Camera로의 매끄러운 전환을 위한 것이며 시작을 의도적으로 지연시키지 않는다.
- 정확한 Logo 표시 크기와 Light / Dark Background 표현은 구현 Visual Review 세부로 남긴다.

### V1 Launch Flow

첫 실행은 다음과 같다.

`Splash → Permission Onboarding → Camera Authorization → Camera Foundation 준비 → Portrait Camera`

이후 실행은 다음과 같다.

`Splash → Portrait Camera`

- Format Chooser, Home Dashboard, New Vlog CTA와 Launch의 Recent 목록은 V1 Target UX에 두지 않는다.
- Camera가 기본 Application Surface가 된다.

### Projects Access

- Projects 진입은 Format Selection 화면에서 Camera Chrome으로 이동한다.
- 구조적 흐름은 `Portrait Camera → Projects → Recent Projects`다.
- Projects는 조용한 Secondary Action으로 유지하며 Camera가 시각적으로 우선한다.
- Camera에 Recent Grid를 직접 표시하지 않고 `Continue an existing project?` CTA도 사용하지 않는다.
- 전용 Recent Projects Browser는 유지한다.
- 선호 배치는 Camera Chrome의 Upper Trailing이며 정확한 SF Symbol, 크기, 간격과 Press 표현은 구현 Polish로 남긴다.

### Project Creation Invariant

- App Launch만으로 비어 있는 Vlog Project를 저장하지 않는다.
- Camera가 표시되었다는 사실이나 Onboarding 완료 자체도 Project 저장 사유가 아니다.
- 정확한 Atomic Creation 경계는 Recording / Capture 구현 Phase가 소유하며, 일반적인 실행에서 버려지는 0 Clip Project가 누적되지 않아야 한다.
- ADR-028의 `선택 즉시 저장` Creation Trigger는 Format Chooser와 함께 V1에서 사라지며 Launch 시점 생성으로 대체하지 않는다.

### V1 Orientation Behavior

- V1이 지원하는 Capture 자세는 upright Portrait다.
- Landscape이거나 적합하지 않은 자세에서는 승인된 조용한 `Rotate your iPhone` 안내를 표시하고 Capture를 사용할 수 없는 상태로 유지한다.
- Device Rotation으로 Project Orientation을 바꾸거나 Landscape Capture를 노출하거나 Landscape Project를 생성하지 않는다.
- Face Up / Face Down / Unknown / Unstable 처리는 기존 Camera Readiness 구조를 따른다.

### Existing Landscape Data

- 기존 개발 / Pre-release Store의 Landscape Project는 삭제, Migration, Orientation 변경 대상이 아니며 V1을 위해 Schema를 바꾸지 않는다.
- V1은 새 Landscape Project 생성을 노출하지 않는다.
- 기존 Landscape Project 열람에 필요한 호환 동작은 명시적인 Transitional / Future Decision으로 남긴다.
- 과거 개발 데이터를 이유로 V1이 완전한 Landscape Camera UI를 유지할 필요는 없다.

### Imported Media Orientation

- Portrait-only Capture는 Source Media의 Portrait 제한을 의미하지 않는다.
- 이후 Photos Import는 Portrait / Landscape Source를 모두 허용하고 Source 길이를 제한하지 않으며 선택 Segment는 `0 < duration <= 5 seconds`를 만족한다.
- Portrait 9:16 Project에 삽입할 때 비율 불일치는 승인된 Fill + Crop과 조정 가능한 Framing을 사용한다.

### Editor / Preview / Export

- V1의 Editor, Preview와 Export는 Portrait 9:16 Project를 대상으로 한다.
- ADR-030의 `Camera → Clip Review / Management → Editor → Export` 구조는 유효하다.

## Consequences

V1 사용자는 형식 선택 없이 실행 직후 Portrait Camera에 도달하며 Mellow의 Capture-first 정체성이 강화된다.

Landscape Capture UI는 V1 전달 범위에서 빠지지만 Orientation / Readiness Architecture와 Domain 표현은 재사용 가능한 상태로 남는다.

Phase 3의 Landscape Camera Layout, Control Rail, Landscape 전용 Physical Validation과 Accessibility Geometry 검증은 V1 필수 범위에서 제외된다.

현재 Phase 3 Swift 구현의 Format Chooser / Landscape Camera 구성은 이 문서 결정 이후 정렬 대상 이행 작업으로 추적한다.

### Phase 3 Physical Gate Resolution — 2026-09-14

- iPhone 12 Physical Review로 Portrait-only V1 Camera Baseline을 승인했다.
- Camera Surface는 9:16 Framing Guide / 외곽 Dim 없이 Edge-to-edge Live Preview를 사용하며 Portrait 9:16은 내부 Project / Output Policy로만 유지한다.
- Orientation Readiness는 Definite Posture(Portrait / Landscape)만 `Rotate your iPhone`을 표시하고 Face Up / Face Down / Unknown / Unstable은 마지막 Definite Posture를 보존하며, 첫 실행처럼 Stable Posture가 없으면 Portrait Interface Orientation을 Provisional Posture로 사용한다.
- Background → Foreground 복귀 시 약 0.5–1.0초의 Visible Preview 복구를 V1에서 허용하고 Scene `.inactive` 시점의 Session 정지 Policy를 유지한다.

## Non-goals

- Domain / Schema에서 Landscape를 제거하지 않는다.
- 기존 Landscape Project를 Migration하거나 변형하지 않는다.
- Recording, Editor, Preview, Export와 Photos Import 동작을 이 결정에서 구현하거나 재정의하지 않는다.
- Landscape 복원 시점은 이 결정에서 확정하지 않으며 Post-V1 Product Decision으로 남긴다.
- Splash의 정확한 Visual Spec과 Projects Control의 Iconography를 이 결정에서 확정하지 않는다.

---

# ADR-033 — Capture-First Recording, Photos Save, and Single-Project V1 Policy

**Date:** 2026-09-14
**Status:** Accepted

**Supersedes:** ADR-023의 Microphone 필수 Direct Recording 정책과 Recording Start Orientation Gate 중 Face Up / Face Down / Unknown / Unstable 처리의 미해결 부분, ADR-020 / ADR-021 / ADR-024의 "Direct Recording 결과를 Project-owned Media로 Commit한다"는 전제(Project Media Materialization 자체는 유지하고 Camera Recording에서 분리), ADR-026 / ADR-028 / ADR-030 / ADR-032의 V1 Multi-project Recent Projects Browser 요구, ADR-031의 Camera-only 첫 실행 권한 순서, 그리고 ADR-032 이후 Pending이던 "첫 Recording에서의 Project Atomic Creation" 가정을 대체한다. ADR-029의 1–5초 최대 Preset 정책은 그대로 유지하며 이 ADR은 1.0초 최소 Direct Capture 규칙을 추가한다.

## Context

Phase 3 Camera Foundation의 Physical Review 이후 사용자는 V1 제품 모델을 다음으로 확정했다.

짧은 순간을 먼저 촬영한다 → Photos에 저장한다 → 나중에 Vlog Project를 구성한다.

Camera Capture와 Vlog Project 구성은 서로 다른 책임이며, 사용자는 Mellow Project를 하나도 만들지 않고도 많은 순간을 촬영할 수 있어야 한다.

## Decision

### Capture / Project 분리

- `Recording a clip does NOT create a VlogProject.`
- App Launch, Camera 진입, Shutter Tap, Recording 성공, Photos Save 성공 중 어느 것도 Project를 만들지 않는다.
- Camera Clip은 Photos에 저장되는 독립적인 짧은 순간이며 Project 생성은 명시적인 Projects / Composition Flow에서만 일어난다.
- Project Domain / Schema Architecture는 제거하지 않는다.

### 첫 실행 Permission Onboarding

첫 실행은 `Splash → Permission Onboarding → Camera → Microphone → Photos Add → Portrait Camera`이며 각 Capability는 시스템 요청 전에 설명하고 한 번에 하나씩 요청한다. iOS 권한 Sheet를 동시에 띄우지 않는다.

- **Camera** — 필수. Denied / Restricted이면 Preview / Capture를 사용할 수 없고 기존 Settings Recovery Pattern을 사용하며 반복 요청 Loop를 만들지 않는다.
- **Microphone** — 선택. Authorized이면 Clip에 Audio가 포함되고, Denied / Restricted이면 Video Recording은 계속 가능하며 Clip은 무음으로 기록된다. Camera는 `mic.slash` 또는 동등한 SF Symbol로 Muted 상태를 조용히 표시하고 이 Control은 Camera를 시각적으로 지배하지 않는다. Microphone Control Tap은 `.notDetermined` → 권한 요청, `.denied` → Settings Recovery, `.restricted` → 사용 불가 설명, `.authorized` → 일반 Audio Capture 상태다. Microphone 거부는 Video Recording을 차단하지 않는다.
- **Photos** — Direct Camera Save Workflow에는 가장 좁은 권한인 Photos Add Only(Add-to-library) 권한을 사용하며 저장을 위해 Library Read 권한을 요구하지 않는다. Denied / Restricted이면 Preview는 유지될 수 있지만 필수 저장 위치를 완료할 수 없으므로 Video를 성공 Capture로 취급하지 않으며 Capture 시도 시 Settings / Recovery 경로를 제공한다. 이후 Photos Import는 System PhotosPicker 또는 해당 Phase에 적합한 권한 모델을 사용하고 전체 Library Read 권한을 미리 요구하지 않는다.
- **Location** — Phase 4에서 요청하지 않으며 미래 Location Metadata Capability가 소유하는 선택 권한으로 남긴다.

### V1 Single Saved Project

- `Mellow V1 retains only the most recently committed editable Project.`
- V1은 편집 가능한 저장 Project를 최대 하나만 유지하며 Multi-project Grid / Browser를 V1 Primary Projects Flow로 노출하지 않는다.
- 이는 V1 Product 동작 제한이며 Domain / Schema를 하나의 Project로 제한하는 파괴적 Migration이 아니다. 이후 Version은 Multi-project를 복원할 수 있다.

### Camera Projects Entry

- 저장 Project가 없으면 `Projects → Select Clips`이며 Clip 선택이 단일 저장 Project 생성을 시작한다. 빈 Recent Projects Browser를 보여주지 않는다.
- 저장 Project가 있으면 `Load Last Saved`(현재 저장된 편집 가능 Project 열기)와 `Select Clips`(선택 Clip으로 새 대체 Project 생성)에 해당하는 두 Primary Action을 제공한다.
- 정확한 사용자-facing Copy는 Localization / Polish로 남기되 위 Semantics는 Canonical이다.

### Safe Atomic Project Replacement

저장 Project A가 있는 상태에서 `Select Clips`로 새 Project를 만들면 `Creating a new project will replace your last saved project.`에 해당하는 명시적 확인(Cancel / Create New Project)을 요구하며 기존 Project를 즉시 삭제하지 않는다.

1. 기존 Project A는 온전히 유지된다.
2. 사용자가 Clip을 선택한다.
3. Project B의 Temporary Workspace를 만든다.
4. 필요한 선택 Media를 Materialize / Copy한다.
5. Project B와 Clip Metadata를 만든다.
6. Project B를 완전히 Persist한다.
7. B의 Commit 성공을 검증한다.
8. B를 새 단일 저장 Project로 승격한다.
9. 그 뒤에만 Project A와 A의 App-managed Editing Media를 제거한다.

B 생성이 완료 전에 실패하면 B의 Temporary / Copied Media와 부분 Metadata를 폐기하고 A를 그대로 보존한다.

`A failed replacement must never destroy the last valid saved Project.`

Project 삭제 / 대체는 Project Metadata와 Mellow-owned Editing / Materialized Copy만 제거할 수 있으며 사용자 Photos Library의 원본 Camera Clip이나 사용자가 선택한 다른 Photos 원본은 절대 삭제하지 않는다. 이 구현은 Phase 4 Camera Recording이 아니라 Project / Import / Composition Phase가 소유한다.

### Duration

- ADR-029의 `1s / 2s / 3s / 4s / 5s` 최대 Preset과 기본 `3s`를 유지하며 선택 Preset은 다음 Direct Camera Clip의 최대 길이이지 고정 출력 길이가 아니다.
- **Direct Capture 최소 길이는 1.0초다.** 유효한 Direct Camera Duration은 `1.0s <= actual duration <= selected maximum`이다.
- 3s Preset에서 1.4초 수동 종료 → 저장. 5s Preset에서 2.2초 Interruption → Finalization 성공 시 저장. 3s Preset에서 0.7초 수동 종료 → 폐기. 5s Preset에서 0.8초 Background → 폐기.
- 1초 미만 Clip을 1초로 반올림하지 않는다. Encoder / Timestamp Tolerance는 1.0초 경계 부근에 기술적으로 존재할 수 있지만 제품 규칙을 바꾸지 않는다.
- 이 최소 길이는 Direct Camera Capture에 적용되며 Imported Clip의 최소 길이를 자동으로 재정의하지 않는다.

### Shutter Interaction

- Idle에서 Shutter Tap → Recording 시작. Recording 중 Shutter Tap → Manual Early Stop 요청이며 실제 길이가 1.0초 이상이면 Finalize / Save, 미만이면 폐기.
- 선택한 최대 길이에 도달하면 자동 정지 후 Finalize / Save. Hold-to-record 요구는 없다.

### Recording Control Lock

Recording 중에는 Duration Picker, Camera Flip, Projects와 Capture를 불안정하게 할 수 있는 Navigation / Action을 비활성화하고 Shutter만 명시적 Manual Stop Control로 유지한다. 저장 성공 / 폐기 / 실패 후 일반 Control을 복원하며 Active Capture 중 선택 Maximum을 변경할 수 없다.

### Shutter Recording Progress

기존 Shutter를 Primary Recording Progress Surface로 사용한다. Shutter 주변 Circular Progress Ring이 `elapsed time / selected maximum duration`을 표현하며 큰 숫자 Timer, `00:02 / 00:03` Text, 큰 Duration Text나 별도 Timeline / Progress Bar를 추가하지 않는다. Ring 색상은 Visual 구현 결정으로 남긴다.

### Capture File Lifecycle

`Recording → Temporary Staging File → 정지 → Finalize → Media / Duration 검증 → Photos Save → 성공 → Staging File 삭제`

Temporary File은 Infrastructure이며 사용자의 Canonical Long-term Original이 아니다. Photos Save 성공 후 App 내부에 Camera Original 복제본을 무기한 보관하지 않는다.

### Save Failure Semantics

Camera Recording은 전체 Save 경로가 성공했을 때만 성공 Capture다. Recording은 성공했지만 Photos Save가 실패하면 성공으로 보고하지 않고, Project를 만들지 않고, 보이지 않는 Orphan Staging File을 무기한 남기지 않으며, 복구 가능한 Save Error를 표시하고, Staging Asset은 명시적 Recovery Policy에 따라서만 정리 / 보존한다.

`A successful Camera result must correspond to media that actually exists in Photos.`

### Background / Interruption

Recording 중 Mellow가 Inactive / Background가 되거나 System Event로 Capture가 중단되면 즉시 정지 / Finalization을 요청한다. 실제 길이가 1.0초 이상이고 Finalization이 성공하면 Photos에 저장하고, 1.0초 미만이면 폐기한다. Background에서 Active Camera Recording을 계속하지 않으며 이는 Interruption에 의한 Automatic Early Stop과 동일하게 취급한다.

### Crash Recovery

Hard Process Crash 시점까지의 저장을 보장하지 않는다. Crash가 남긴 Staging Media가 있으면 다음 실행에서 Best-effort로 검증하여 Playable / Complete이고 1.0초 이상이면 Photos Recovery Save를 시도하고, Corrupt / Incomplete이거나 1.0초 미만이면 Staging Artifact를 삭제한다. Photos Save가 실제로 성공하기 전에는 Recovery 성공을 보고하지 않는다.

### Recording Start Orientation Gate

Phase 3 Preview / Readiness 동작은 유지하되 Recording 시작은 물리적 자세가 upright Portrait일 때만 허용하고 Landscape / Face Up / Face Down / Unknown / Unstable에서는 시작을 거부한다. 출력 Orientation을 조용히 회전시키지 않으며 V1은 Portrait-only다. 이는 ADR-023에서 이월된 Recording-start Gate를 해결한다.

### Orientation During Active Recording — Resolved 2026-09-14

`A Mellow V1 Camera clip is Portrait for its entire recording lifetime.`

- Recording이 성공적으로 시작되면 해당 Clip의 Capture / Output Orientation은 Recording 전체 동안 Portrait으로 고정되며 시작 시점에 확정된다.
- 이후 Device가 Landscape / Face Up / Face Down / Unknown / Unstable로 바뀌어도 자세 변경만으로는 Recording을 Stop하거나 Restart하지 않고, Clip / Project Orientation을 바꾸지 않으며, Mid-clip에 Output을 회전시키지 않는다.
- Recording은 사용자의 Shutter Stop, 선택한 최대 Duration 도달, 또는 App Inactive / Background나 System Capture Interruption 같은 독립적인 Stop 조건에서만 끝난다. Background / Interruption Policy는 변경하지 않는다.
- 자세 변경 자체는 1.0초 규칙의 Stop 경로를 발생시키지 않는다. 다른 승인된 이유로 Stop되면 기존대로 1.0초 이상은 Finalize / Save, 미만은 폐기한다.
- Active Recording 중에는 `Rotate your iPhone`을 차단 상태로 사용하지 않으며 Modal Orientation 경고를 두지 않는다. Recording Progress와 Shutter Stop이 Primary로 유지된다. 선택적인 미세한 Non-blocking Hint는 과도하게 규정하지 않는다.
- Recording이 끝나면 즉시 물리 자세를 재평가하여 upright Portrait이 아니면 일반 `Rotate your iPhone` Readiness 안내를 복원하고 다음 Recording 시작을 막으며, upright Portrait으로 돌아오면 일반 Ready 상태를 복원한다.

### Recording State Model

`idle → preparing → recording → finishing → savingToPhotos → idle`, 실패 경로는 `any active state → failed / cleanup → idle`. Project 생성은 이 State Machine에 포함되지 않는다.

### Future Project Media Materialization

사용자가 이후 Photos Clip을 선택해 Project를 만들 때 Mellow는 안정적인 편집을 위해 해당 Media를 App-managed Project Storage로 Materialize / Copy할 수 있다. Project 삭제 / 대체 시 Mellow Editing Copy는 삭제될 수 있지만 Photos 원본은 유지된다. 구현은 이후 Project / Import Phase가 소유한다.

## Consequences

Phase 4는 Camera Recording, Photos Direct-save, 선택적 Microphone / Audio만 소유하며 Project를 만들지 않는다. Select Clips, 단일 편집 Project 생성, Load Last Saved, 대체 확인과 Safe Atomic Replacement는 Project / Composition Phase(Phase 5)가 소유하고 Import / Trim / Editor Phase의 기존 책임은 유지된다.

Recent Projects Browser와 Multi-project Domain 구조는 V1 Primary Flow에서 빠지지만 이후 Version을 위해 재사용 가능한 상태로 남긴다.

## Non-goals

- Recording Progress Ring의 정확한 색상은 이 ADR에서 확정하지 않으며 구현 / Physical Visual Review Polish로 남긴다.
- Imported Clip 최소 길이, Location Metadata, Multi-project 복원 시점은 이 결정에서 확정하지 않는다.
- 이 ADR은 구현이 아니며 Phase 4는 시작되지 않았다.

---

# ADR-034 — Phase 5 Clip Project Management Structural UX and Select-Clips Media Boundary

**Date:** 2026-09-14
**Status:** Accepted
**Partial Supersession:** 이 ADR의 §1 Projects Entry Presentation(Compact Native Bottom Sheet)만 ADR-035에 의해 전용 Pushed Projects 화면으로 Superseded되었으며, §1의 Semantic Hierarchy(`Start New Project` / `Continue Editing` / 대체 확인)와 §2–§7은 그대로 유효하다. 아래 원문은 당시 기준의 기록이다.

**Clarifies / Extends:** ADR-030의 Lightweight Editor / Ordered Thumbnail Strip 방향과 ADR-033의 Camera Projects Entry(`Select Clips` / `Load Last Saved`), Safe Atomic Replacement, Single Saved Project 및 Camera Compact Project-content Access를 Phase 5 구현 직전 Structural UX Gate 수준으로 구체화한다. ADR-021(Logical Deletion / Undo)과 ADR-026(Unavailable Clip / Replace)의 Accepted Semantics는 변경하지 않고 Presentation만 확정한다. 기존 ADR을 대체(Supersede)하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

STEP 0 Phase 5 Audit에서 두 가지가 확인되었다.

1. ADR-033이 정한 Camera Projects Entry / Editor 구조의 정확한 Copy·Presentation이 Pending Structural UX Gate로 남아 있어 Phase 5 UI 구현을 시작할 수 없었다.
2. Phase 5 `Select Clips`의 Project Composition과 Phase 6 Photos Video Import(긴 Source Segment Selection, HDR/Dolby Vision→SDR, 4K→1080p-class Normalization) 사이의 Media 소유 경계가 문서상 모호했다.

이 ADR은 위 두 Gate를 사용자 승인으로 해결하되, Phase 6/7이 소유한 Import·Normalization·Trim·Framing 책임과 ADR-021/026의 Replacement Metadata Migration 세부는 Pending으로 유지한다.

## Decision

### 1. Projects Entry UX (V1)

Camera `Projects`는 기존 Multi-project Recent Projects Browser 대신 Compact Native Bottom Sheet를 연다.

- **저장 Project 없음:** 단일 Primary Action `Start New Project`(ADR-033 `Select Clips` 의미). 사용 가능한 Media가 Commit되기 전에는 빈 Project를 만들지 않는다.
- **저장 Project 있음:** Primary `Continue Editing`(ADR-033 `Load Last Saved`, 가장 최근 Commit된 편집 가능 Project 열기), Secondary `Start New Project`(ADR-033 `Select Clips`, 대체 Project 생성 시작).
- 기존 Project 대체 전에는 `Creating a new project will replace your last saved project.` 의미의 Native 확인(Cancel / Create New Project)을 표시한다.
- 정확한 Localization Copy는 이후 Polish로 남기되 위 Semantic Hierarchy와 Interaction은 승인되었다.
- 기존 `Recent Projects` Multi-project Grid는 V1 Primary Projects Entry가 아니며 재사용 가능한 Domain / Persistence 구조는 Post-V1 복원을 위해 보존한다. Domain을 Single-project Schema로 파괴적으로 Migration하지 않는다.

### 2. Phase 5 / Phase 6 Select-Clips Media Boundary

Phase 5는 **Phase-5-ready media**로 Project를 구성한다. Phase-5-ready media는 Phase 6 편집/Normalization 없이 그대로 Project에 들어갈 수 있는 요구사항을 이미 만족하는 Media를 의미한다(특히 Duration / Format이 이미 Mellow Project 요구사항을 만족하는 Clip).

Phase 5가 할 수 있는 것: Project Bootstrap에 필요한 최소 System Selection Boundary 호출, 사용자 선택 Video 수신, 기본 Media 속성 검사, 이미 Usable한지 Validation, Usable Media를 App-managed Project Storage로 Materialize / Copy(ADR-020 Transactional Commit), Clip Metadata 생성, 단일 저장 Project 구성, 이전 저장 Project의 Safe Atomic Replacement. 이것은 Project Composition Bootstrap이며 완전한 Import 기능이 아니다.

Phase 5가 구현하지 않는 것(Phase 6 / 7 소유 유지): Long-source Segment Selection, 임의 Source Trim / Re-trim, HDR / Dolby Vision → SDR 변환, 4K / High-resolution → 1080p-class Normalization, Frame-rate Normalization, Crop / Framing, 고급 Source Transform, 완전한 Photos Import 편집 UI.

**Non-ready Media:** 선택 Media가 Phase 6 소유 기능을 필요로 하면 Phase 5는 조용히 자르거나 Transcode / Crop하거나 잘못된 Clip Metadata를 만들거나 Import가 성공한 것처럼 처리하지 않는다. Project는 지원되지 않는 Media로 부분 Commit되지 않는다. Phase 6 소유 Source에 대한 정확한 사용자-facing 처리는 소유 Flow가 준비된 후 구현하며, Phase 5 Test는 이를 Typed `requires import preparation` 결과로 표현할 수 있다. 임시 파괴적 동작을 만들지 않는다.

이 경계는 F-MVP-018~F-MVP-022(Photos Import)를 Phase 5-complete로 재정의하지 않는다.

### 3. Project Editor Structural UX (Shell only)

경량 Editor를 유지하며 Professional NLE처럼 만들지 않는다.

- **시각 Hierarchy:** (1) Navigation / Project-level Action, (2) Large Preview Surface, (3) Ordered Clip Thumbnail Strip, (4) Clip-level Action / Project Summary.
- **Large Preview Surface:** Phase 5는 Surface / Shell만 만든다. 실제 Playback을 구현하지 않으며 선택 Clip의 Representative Still / Placeholder를 표시할 수 있다. 실제 Effective Edited-result Playback은 기존 이후 Preview Phase(Phase 8) 소유다. Media를 Raw로 재생하는 Shortcut을 두지 않는다.
- **Ordered Thumbnail Strip:** Horizontal Ordered Strip, Clip당 한 항목, Thumbnail이 Primary Visual, Compact Duration Label, Single Tap 선택, 선택 Clip은 Color-only가 아닌 명확한 Selected State, Long Press + Drag Reorder, Accessibility 대안으로 Move Earlier / Move Later. Waveform, Track, Playhead Timeline, Keyframe, Layer, Multi-track 없음.
- **Clip Actions:** Delete는 선택 Clip의 명시적 Action, Add Clips는 명시적 Project-level Action. Trim / Framing / Text Control은 아직 구현하지 않으며 비기능 Control을 노출하지 않되 이후 Tool 확장 여지는 남긴다.
- **Project Total Duration:** Clip 조직 영역 근처에 조용한 보조 정보로 표시하며 Preview와 시각적으로 경쟁하지 않는다.
- **Add Clips:** Project / Clip Strip에 연결된 명확한 `Add Clips` Action. Direct Camera 취득과 Photos 취득은 각각의 기존/이후 소유 Boundary(§2)를 통해 라우팅하며 Phase 6 Import 편집을 선행 구현하지 않는다.

### 4. Delete / Undo Presentation

가장 최근 Clip Delete Undo Opportunity에 Transient Bottom Snackbar / Toast를 사용한다. 표현은 `Clip deleted` + `Undo`.

동작은 ADR-021 / F-MVP-025 Canonical: Delete 즉시 논리적 순서에서 제거, 가장 최근 Delete 한 건만 사용자-visible Undo, 새 Delete가 이전 Undo Opportunity 종료, Undo는 동일 Clip Identity / Media / Metadata 복원, Undo는 Unrelated Reorder를 되돌리지 않음, Process 종료 후 Undo 미복원, Physical Media 삭제는 안전 조건까지 지연. 정확한 Undo Window Duration은 Tuning으로 남긴다. Source-of-truth가 명시적으로 요구하지 않는 한 일반 Clip Delete 앞에 확인을 추가하지 않는다.

### 5. Unavailable Clip Structure

Unavailable Clip은 논리적 Strip 위치에 계속 보인다. Clear Placeholder Thumbnail, Color-only가 아닌 Unavailable State, 간결한 Unavailable 표시, 명시적 Replace, 명시적 Delete를 사용한다. 사라지거나 자동 삭제하거나 다른 Asset을 조용히 사용하거나 조용히 이동하거나 Healthy처럼 조용히 건너뛰지 않는다. 다른 Clip이 Unavailable해도 Healthy Clip은 선택 / Reorder 가능하다. Unavailable Clip 자체는 Video Preview가 없다. Replace / Delete Semantics는 ADR-026 / ADR-021을 따른다.

### 6. Camera Bottom-left Content Slot (Phase 4 → Phase 5 전환)

- **저장 Project 없음:** 현재 Phase 4 동작 유지 — Session-only `lastRecordingThumbnail`, Recording-success 시각 피드백, Project Identity 없음, Playable URL 없음, Non-navigable. Raw-video Playback으로 만들지 않는다.
- **저장 Project 있음:** 동일 Compact 영역을 Project-aware Content Access로 승격 가능 — 현재 Project Representative Thumbnail 표시, 탭 시 해당 저장 Project의 Editor / Clip Management Surface 열기. 저장 Project가 있으면 Project Representative Thumbnail이 Session-only Latest-recording 피드백보다 Semantic 우선한다. 이는 Tile을 "Play last recording"으로 바꾸지 않는다. 이 Control을 위해 Camera Staging Media를 보관하지 않는다.

### 7. Representative Thumbnail Semantics (유지)

Current Logical Clip Order → 첫 Healthy / Usable Clip → Representative Source. Reorder, Delete, Undo Restore, Successful Replacement, Availability Transition, Representative Media Identity Change 후 재평가한다. Usable Source가 없으면 Project Placeholder를 사용하고 Unrelated Stale Thumbnail을 재사용하지 않는다. Async Thumbnail 결과는 적용 전 Validity를 확인한다.

## Still Pending (이 ADR이 확정하지 않음)

- Unavailable-Clip Replacement Metadata Migration: 기존 Clip ID 유지 vs 새 Clip ID, Trim / Framing / Transform Preserve vs Reset, Thumbnail Regeneration 세부, 사용자-facing Reset 전달 — Replacement 구현 직전까지 Pending. 이는 Projects Entry / Editor Shell / 기본 Thumbnail / Selection / Reorder / Delete·Undo / Project-aware Camera Content Access를 Block하지 않고, Unavailable-media Replacement 구현 Slice만 Block한다.
- 완전한 임의 Photos Import / Normalization(Phase 6), Trim / Framing(Phase 7), 실제 Effective-result Playback / Full Vlog Preview(Phase 8), Export(Phase 9).
- Undo Window Duration, 정확한 Localization Copy, 정확한 Snackbar / Sheet Visual Tuning.

## Consequences

Phase 5는 Projects Entry Surface, Single Saved Project Lookup / Routing, Domain / Persistence Phase-5 Lifecycle State, Thumbnail Infrastructure, Editor Structural Shell, Selection, Reorder / Autosave, Delete / Most-recent Undo, Deferred Cleanup / Active Usage, Project Representative Thumbnail, Camera Content-slot → Project Access를 구현 가능(Definition of Ready)하다. 위 Still Pending 항목과 이후 소유 Phase의 책임은 유지된다.

## Non-goals

- 정확한 Localization Copy / Visual Tuning / Undo Window 값 확정.
- Replacement Metadata Migration 정책 확정.
- Phase 6 Import·Normalization, Phase 7 Trim / Framing, Phase 8 Preview, Phase 9 Export의 선행 구현.

---

# ADR-035 — Dedicated Projects Entry Screen

**Date:** 2026-09-15
**Status:** Accepted
**Partial Supersession:** 이 ADR의 Projects 화면 **가시 Content / Action Hierarchy**(저장 Project 없음 → 단일 `새 프로젝트 시작`, 있음 → Primary `이어서 편집` / Secondary `새 프로젝트 시작`)만 ADR-036에 의해 항상 두 개의 중앙 Action(`새 프로젝트 시작` / `기존 프로젝트 불러오기`)으로 Superseded되었다. 전용 Pushed 화면, `.projectsEntry` Destination, Back 동작, 대체 확인, ProjectEditor Destination은 그대로 유효하다. 아래 원문은 당시 기준의 기록이다.

**Partially Supersedes:** ADR-034 §1 Projects Entry UX의 **Presentation만**(Compact Native Bottom Sheet). ADR-034의 나머지 — Projects Entry Semantic Hierarchy, Select-Clips Media Boundary, Project Editor Structural UX, Delete / Undo, Unavailable Clip, Camera Content Slot, Representative Thumbnail, Replacement Metadata Migration Gate — 는 대체하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

Phase 5 STEP 5에서 ADR-034 §1의 Bottom Sheet Projects Entry를 구현하고(임시 Korean Copy `프로젝트` / `이어서 편집` / `새 프로젝트 시작` / 대체 확인) Simulator Visual Review를 진행했다. Review에서 다음이 확인되었다.

- Surface에 Primary Choice가 한두 개뿐이라 Sheet의 대부분이 빈 세로 공간으로 남는다.
- `Camera → Sheet → Replacement Alert`는 불필요한 Modal Stacking을 만든다.
- Camera Upper-trailing Projects Icon은 임시 Modal Action Surface보다 Project Workspace로의 Navigation으로 읽힌다.
- 전용 화면이 Hierarchy를 더 명확히 하고, Camera를 Dashboard로 만들지 않으면서도 이후 가벼운 Project 정보를 둘 여지를 준다.

사용자는 Projects Action이 별도 화면으로 이동하는 구조를 명시적으로 선호했다.

## Decision

Camera Projects Access는 App NavigationStack 안의 전용 Projects Destination(`.projectsEntry`)으로 **Push Navigation**한다. Canonical V1 Projects Entry에 Bottom Sheet를 사용하지 않는다.

Canonical 구조:

`Camera` → Upper-trailing Projects Icon 탭 → Pushed `프로젝트` 화면(표준 Back → Camera)

- **저장 편집 가능 Project 없음:** `새 프로젝트 시작`(단일 Primary Action). Media가 Commit되기 전에는 빈 Project를 만들지 않는다.
- **저장 편집 가능 Project 있음:** Primary `이어서 편집`, Secondary `새 프로젝트 시작`.
- **이어서 편집:** Projects 화면에서 `ProjectEditor(projectID)`로 Push한다. Projects 화면은 Stack 아래에 남아 Editor의 Back은 `프로젝트`로, 다시 Back은 Camera로 돌아간다(`Camera → 프로젝트 → ProjectEditor`). Editor는 Modal이 아니다.
- **저장 Project가 있을 때 새 프로젝트 시작:** 전용 Projects 화면 위에 이미 승인된 Native 확인을 표시한다 — Title `새 프로젝트를 시작할까요?`, Message `새 프로젝트를 만들면 마지막으로 저장한 프로젝트가 교체됩니다.`, Actions `취소` / `새 프로젝트 만들기`. 이로써 Modal Stacking은 `Camera → Projects 화면 → Alert` 한 단계가 된다.
- 화면은 Navigation Title `프로젝트`, 표준 Back, Semantic Light / Dark System Background, 짧은 Decision Page 구조를 가지며 Dashboard / Recent Grid / Placeholder Card / Metadata를 두지 않는다.
- 위 Korean Copy는 임시 V1 Copy이며 정확한 Localization은 이후 Polish다(ADR-034 Non-goal 유지).

### 구현 단계(Transitional)

`새 프로젝트 시작`이 실제 Composition Destination(Select-Clips Bootstrap)을 갖기 전까지 Production Camera Projects Icon은 기존 Transitional Recent Projects Path를 유지하고, 전용 Projects 화면은 DEBUG / UI-test Routing으로만 도달한다. Production 전환은 실제 New-project Composition Path와 함께 이루어진다. 이는 ADR-035의 Canonical 구조를 되돌리는 것이 아니라 Dead-end 없는 안전한 Staging이다.

## Explicitly Unchanged

이 ADR은 다음을 변경하지 않는다.

- Single Saved Project Policy(ADR-033 / ADR-034)
- Safe Atomic Replacement Semantics
- Phase 5 / Phase 6 Select-Clips Media Boundary(ADR-034 §2)
- Project Editor Layout / Semantics(ADR-034 §3)
- Delete / Undo Semantics(ADR-021 / ADR-034 §4)
- Representative Thumbnail Rules(ADR-034 §7)
- Camera Bottom-left Content Slot Rules(ADR-034 §6)
- Replacement Metadata Migration Gate(ADR-034 Still Pending)

## Consequences

- Phase 5 Projects Entry는 `AppRouter.Route.projectsEntry` Destination과 `ProjectsEntryView`로 구현하며 `.sheet` / Presentation Detent 기반 Projects Entry는 두지 않는다.
- ADR-034 §1의 Sheet 표현을 인용하는 Current-normative 요약(DESIGN / ARCHITECTURE / ROADMAP)은 전용 화면 Navigation으로 갱신한다.

## Non-goals

- Select-Clips Bootstrap / PhotosPicker / Media Materialization / Replacement Transaction 구현.
- Localization Architecture 도입.
- Projects 화면에 Project 정보 / Thumbnail / Metadata 추가.

---

# ADR-036 — Centered Two-Action Projects Entry

**Date:** 2026-09-15
**Status:** Accepted

**Partially Supersedes:** ADR-035의 Projects 화면 **가시 Content / Action Hierarchy만**. ADR-035는 전용 Pushed Projects 화면, `.projectsEntry` Navigation Destination, Back 동작, 대체 확인, ProjectEditor Destination에 대해 계속 Authoritative하다. ADR-034 §1의 Semantic(새 Project 시작 / 저장 Project 이어가기 / 대체 확인)은 유지되며 역사적 기록을 다시 쓰지 않는다.

## Context

ADR-035 이후 Phase 5 STEP 5 Visual Review에서 Projects 화면의 Content 개념이 두 차례 반복되었다: (1) 저장 Project 유무에 따라 단일 `새 프로젝트 시작` 또는 저장 Project Card + `이어서 편집`을 조건부로 보여주는 구성, (2) Empty-state 문구 + `최근 프로젝트` Section + 단일 Focal Project Card(Placeholder Thumbnail, Korean Display Name, Clip 수, 길이, Chevron) + `+ 새 프로젝트 시작`. 사용자는 Commit 전에 두 방향 모두 거부하고 V1 Projects 경험을 명시적으로 단순화했다.

핵심 제품 아이디어: Projects 화면은 Project 관리 화면이 아니라 **단순한 결정 화면**이다 — 새 Project를 시작하거나, 이미 저장된 Project를 불러온다. V1은 편집 가능한 저장 Project를 최대 하나만 유지하므로 Recent List, Project Card, 날짜 / 길이 / Clip 수 요약, 별도의 Recent Browsing 단계가 필요 없다.

## Decision

V1 Projects 화면은 **항상** 중앙(수평 + 수직)에 두 개의 선택을 같은 순서로 표시한다.

1. **`새 프로젝트 시작`** — Primary. 항상 Enabled. 저장 Project가 없으면 `.fresh` Intent를 보내고(STEP 5에서는 Project를 만들거나 PhotosPicker를 열지 않음), 저장 Project가 있으면 기존 승인된 대체 확인(`새 프로젝트를 시작할까요?` / `새 프로젝트를 만들면 마지막으로 저장한 프로젝트가 교체됩니다.` / `취소` / `새 프로젝트 만들기`)을 먼저 표시한 뒤 확인 시 `.replacingSaved(savedProjectID)`를 보낸다.
2. **`기존 프로젝트 불러오기`** — Secondary. 저장 편집 가능 Project가 있을 때만 Enabled이며, 탭 시 List / Card / 추가 확인 없이 가장 최근 저장 Project를 `ProjectEditor(projectID)`로 **직접** 연다(`프로젝트 → 기존 프로젝트 불러오기 → ProjectEditor`, Back은 `프로젝트` → Camera). 저장 Project가 없으면 **숨기지 않고** 같은 Geometry로 Disabled 상태(사용할 수 없음 Accessibility State, 탭 불가, 오류 없음)로 남는다.

표시하지 않는 것: `최근 프로젝트` / `마지막 프로젝트` Section, Project Card, Thumbnail Placeholder, Project 날짜 / 이름, Clip 수, 길이, `이어서 편집`, Recent Grid / List, Empty-state Title / 설명 문구(`아직 프로젝트가 없어요` 등), 설명용 Metadata. 두 Button 구조 자체가 선택지를 설명한다.

Presentation: Native NavigationStack(시스템 Back, 중앙 Inline Title `프로젝트`). Navigation Bar 아래 남은 영역을 Content Canvas로 보고 Action Group을 Geometry-aware Layout으로 그 안에 중앙 정렬한다(고정 Top Offset / 절대 좌표 없음). Dynamic Type로 Content가 넘치면 Clipping 대신 Scroll한다. 두 Action은 동일 Geometry(Rounded Rectangle, Radius 16, ~52pt, 중앙 Column 폭, Capsule / Edge-to-edge 아님)이며 Primary는 Semantic Strong Fill, Secondary는 Bordered + `.primary` Label, Disabled는 감소된 강조(Label / Border)이되 가독성을 유지한다.

## Explicitly Unchanged

Single Saved Project Policy, Safe Atomic Replacement, Phase 5 / Phase 6 Media Boundary, 대체 확인 Semantics, Project Editor Semantics, Camera Content-slot Semantics, Delete / Undo, Representative Thumbnail Rules, Replacement Metadata Migration Gate, ADR-035의 Navigation / Destination / Back 결정.

## Transitional

`새 프로젝트 시작`이 실제 Select-Clips Composition Destination을 갖기 전까지 Production Camera Projects Icon은 기존 Transitional Recent Projects Path를 유지하고 Projects 화면은 DEBUG / UI-test Routing으로만 도달한다(ADR-035와 동일).

## Non-goals

Select-Clips / PhotosPicker / Project 생성 / Replacement Transaction 구현, Localization Architecture, Projects 화면의 Project 정보 표시.

---

## 3. Pending Decisions

다음 목록은 Pending Decision과 이후 해결된 항목의 이력을 함께 유지한다.

`Resolved by ADR-022`, `Resolved by ADR-023`, `Resolved by ADR-024`, `Resolved by ADR-025`, `Resolved by ADR-026` 또는 `Resolved by ADR-028`로 표시된 Policy / UX Structure는 확정되었으며 나머지 Pending Technical Detail은 임의로 구현 기준을 결정하지 않는다.

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

- Export Rendering Success와 Photos Save Success의 Boundary — Resolved by ADR-025: Render Success는 Valid Local Export Artifact 생성과 Validation으로 판단하며 Photos Save Success와 별개다.
- Photos Save Failure Handling — High-level Policy Resolved by ADR-025: Render Success와 Local Artifact를 유지하고 Save Retry와 Share를 제공한다.
- Save Retry Artifact Reuse — Resolved by ADR-025: 동일 Valid Local Export Artifact를 사용하며 단순 Photos Save Failure 때문에 재Render하지 않는다.
- Share Artifact Reuse와 Share Cancel Handling — Resolved by ADR-025: Share는 동일 Artifact를 사용하고 Share Cancel은 Export Failure가 아니며 Artifact를 유지한다.
- Unsaved Result Done Behavior — Resolved by ADR-025: explicit discard confirmation이 필요하다.
- H.264 또는 HEVC
- File Container
- Video Bitrate
- Audio Format
- Audio Bitrate
- Background Export 정책
- 재Export가 필요한 경우의 Export Retry 세부 정책
- Exact Completion UI, Retry Button Placement와 Photos Save Error-specific UX

### Imported Media

- Imported Clip을 이후 원본 Source 전체 범위에서 다시 Trim할 수 있게 할지 여부
- 현재 Materialized Segment 내부에서만 Re-trim할지 여부
- Source Reference를 함께 유지할지 여부

### Camera

- Rear Camera Lens 정책 — Resolved by ADR-023: MVP 기본 1× Wide이며 0.5× Ultra Wide / Telephoto / Lens Selector는 제외.
- Rear Continuous Zoom — Resolved by ADR-023: Preview와 Active Recording에서 1× 이상 지원.
- Rear Maximum Zoom Product Quality Limit — Resolved by ADR-023 Phase 3 Gate Resolution: 1.0×–2.0×.
- Rear Zoom Interaction / Indicator / Visual Presentation — Resolved by ADR-023 Phase 3 Gate Resolution: Pinch, Gesture 중 Transient Numeric Indicator만 허용.
- Front Camera Zoom — Out of MVP by ADR-023.
- Front Camera 저장 영상의 Mirror Policy — Resolved by ADR-023: Preview와 Direct-recorded Result의 Mirrored Appearance 유지.
- Camera Permission의 Direct Recording 동작 — High-level Policy Resolved by ADR-023: Denied / Restricted이면 Recording 차단, Photos Import는 독립.
- Microphone Permission의 Direct Recording 동작 — Superseded by ADR-033: Microphone은 선택 권한이며 Denied / Restricted이면 무음 Video Recording을 허용하고 `mic.slash` 상태와 Settings Recovery를 제공한다.
- Orientation Mismatch와 Mid-record Rotation — Resolved by ADR-033: Start Gate는 upright Portrait만 허용하고, Recording 시작 후 자세 변경은 Stop / Restart / Orientation 변경 없이 Portrait Clip으로 계속되며 종료 후 자세를 재평가한다.
- 정확한 Orientation Detection API / Threshold / Debounce — Pending.
- Minimum Valid Clip Duration — Resolved by ADR-033: Direct Capture 1.0초 이상, Imported Clip 최소 길이는 별도 Pending.
- Recording Interruption에서 Valid Partial Clip의 최종 처리 — Resolved by ADR-033: 1.0초 이상이고 Finalization 성공 시 Photos 저장, 미만이면 폐기.
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

- Recent Project의 Layout과 Phase 2 정보 Hierarchy / 생성 / 삭제 구조 — Resolved by ADR-028.
- Imported Video Crop에서 Pinch to Zoom 지원 여부
- Recording Haptic의 정확한 Timing — 기존 Pending 이력을 유지하며 H04 사용자 승인으로 정상 Recording의 사용 시점과 의미를 다음과 같이 동기화한다.
  - Recording Start Haptic — Resolved: 사용하지 않으며 Record Button Tap 또는 Recording Start 성공에 Haptic을 제공하지 않는다.
  - Successful Recording Completion Haptic — Resolved: Manual Stop과 selected-maximum Auto-stop 완료 시 동일한 "이 Clip의 Recording이 종료되었다."라는 의미의 subtle completion haptic을 제공하며 종료 직전 예고 신호가 아니다.
  - Visual Recording State / Circular Progress / Completion State는 주된 상태 전달 수단이며 Haptic은 이를 대체하지 않는 보조 Feedback이다.
  - Recording Error / Interruption Haptic — Pending.
  - 정확한 Haptic API / Style / Intensity / Sharpness / Pattern / Duration / Generator 구현과 Timing — 승인된 Completion 의미 안의 Native iOS Implementation Detail / Tuning으로 유지하며 이번 결정에서 특정 값을 확정하지 않는다.
- Camera Control의 정확한 Placement
- 0 Clip Project Behavior — Resolved by ADR-026: Valid Draft로 유지하며 Recording과 Photos Import를 허용하고 Full Preview와 Export는 비활성화한다.
- Missing / Corrupt Clip Behavior — High-level Policy Resolved by ADR-026: Unavailable 상태로 기존 Position을 유지하고 자동 Delete / Skip 없이 Replace 또는 Delete를 허용한다.
- Automatic Skip of Unavailable Clip — Rejected by ADR-026.
- Automatic Delete of Unavailable Clip or All-unavailable Project — Rejected by ADR-026.
- User-controlled Replace — Accepted by ADR-026.
- Exact Unavailable Visual과 Replace UI — Pending, Owning UX Gate.
- Replacement Clip Identity와 Trim, Framing, Transform, Thumbnail Metadata Migration 및 Reset Communication — Pending, Before Replacement Implementation.
- Project Metadata Recovery Algorithm과 Exact Corrupted-project UI / Copy — Pending.

### Capture-First V1 (ADR-033)

- Recording 시작 후 Device 자세 변경 시 동작 — Resolved 2026-09-14 by ADR-033: Clip은 Recording 전체 동안 Portrait으로 고정되고 자세 변경만으로 Stop / Restart하지 않으며 종료 후 자세를 재평가한다.
- Recording Progress Ring의 정확한 색상 / 표현 — Pending, Phase 4 구현 / Physical Visual Review Polish이며 ADR 결정 대상이 아니다.
- Imported Clip의 최소 길이 — Pending, Phase 6.
- Camera Projects Entry(`Select Clips` / `Load Last Saved` / 대체 확인)의 정확한 Copy와 Presentation — Structural UX Resolved by ADR-034(`Start New Project` / `Continue Editing` Hierarchy, 대체 확인 Cancel / Create New Project); Presentation은 ADR-035로 전용 Pushed `프로젝트` 화면(`Camera → 프로젝트 → ProjectEditor`)으로 확정, Bottom Sheet 아님; 화면 Content는 ADR-036으로 항상 두 개의 중앙 Action(`새 프로젝트 시작` / `기존 프로젝트 불러오기`, 후자는 저장 Project 있을 때만 Enabled, List / Card / Metadata 없음)으로 확정; 정확한 Localization Copy만 Polish로 Pending.
- Phase 5 `Select Clips` Project Composition과 Phase 6 Photos Video Import의 Media 소유 경계 — Resolved by ADR-034: Phase 5는 Phase-5-ready media만 Bootstrap하며 Non-ready Media는 부분 Commit 없이 Typed `requires import preparation` 결과로 처리하고 Segment Selection / Normalization / Trim은 Phase 6 / 7 소유로 유지.
- Phase 5 Project Editor Structural UX(Preview Shell, Ordered Thumbnail Strip, Selection, Delete / Undo Snackbar, Unavailable Clip 표현, Add Clips, Project Duration 배치) — Resolved by ADR-034.
- Camera Bottom-left Content Slot Phase 4 → Phase 5 소유 전환 — Resolved by ADR-034: 저장 Project 없으면 Session-only 피드백 유지, 있으면 Project Representative Thumbnail + Editor 진입으로 승격(Raw Playback 아님).
- Unavailable-Clip Replacement Metadata Migration(Clip Identity / Trim / Framing / Transform Preserve vs Reset, Thumbnail Regeneration, Reset 전달) — Pending, Replacement 구현 직전(ADR-034가 다시 Open으로 만들지 않음).
- Multi-project 복원 시점 — Pending, Post-V1 Product Decision.

### Portrait-Only V1 Transition

- Landscape Camera Capture / 새 Landscape Project 생성의 복원 시점 — Pending, Post-V1 Product Decision by ADR-032.
- 기존 Landscape Project를 V1에서 열 때 필요한 Compatibility 동작 — Pending, Transitional Decision by ADR-032이며 V1이 완전한 Landscape Camera UI를 유지하는 근거로 사용하지 않는다.
- 새 Portrait Project의 정확한 Atomic Creation 경계 — Resolved by ADR-033: Recording은 Project를 만들지 않으며 Project는 `Select Clips`에서 Safe Atomic Replacement로 생성된다(Phase 5 소유).
- Splash의 정확한 Logo 표시 크기와 Light / Dark Background 표현 — Pending, Phase 3 구현 Visual Review.
- Camera Chrome Projects Control의 정확한 SF Symbol / 크기 / 간격 / Press 표현 — Pending, Phase 3 구현 Polish.

Pending Decision이 확정되면 기존 ADR에 단순히 내용을 끼워 넣기보다 결정의 중요도에 따라 새로운 ADR을 추가한다.

---

## 4. Decision Change Policy

Accepted ADR의 내용이 변경되는 경우 기존 기록을 삭제하거나 과거의 결정을 현재 결정처럼 다시 작성하지 않는다.

중요한 방향 변경은 새로운 ADR로 기록하고 이전 ADR의 Status를 `Superseded`로 변경한다.

새 ADR에는 어떤 ADR을 대체하는지 명시한다.

이를 통해 Mellow의 제품 및 기술 방향이 왜 변경되었는지 추적할 수 있도록 한다.
