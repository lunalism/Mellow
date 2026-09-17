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

**Partial Supersession (ADR-042, 2026-09-17):** "선택된 … 구간을 기준으로" Working Media를 만든다는 Segment 전제와 Consequences의 "원본 Source 전체 범위 Re-trim" Pending은 ADR-042로 대체·해소되었다. Photos Source는 전체 Duration이 `1.0s <= duration <= 5.0s`일 때만 받아들이며 Source 전체가 Project-owned Working Media의 기준이고, 원본 전체 범위 Re-trim과 Source Reference 유지는 제공하지 않는다. Project-owned Media / Photos 원본 보존은 그대로 유효하다.

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

**Partial Supersession (ADR-038):** "MVP에서 사용자에게 노출되는 Undo는 가장 최근 Clip Delete 한 건"과 Anchor 기반 선택적 Undo 복원은 Editor Session Undo / Redo History(시간순 LIFO, Reorder + Delete, 이후 모든 편집)로 대체되었다. Logical / Physical Deletion 분리, Durable Pending Deletion, Physical Cleanup Safety, Process Termination 후 Undo 미복원, Late Result 차단은 그대로 유효하며 아래 원문은 당시 기록이다.

**Partial Supersession:** ADR-033에 따라 Recording Finalization은 더 이상 Project를 Commit 대상으로 갖지 않으므로 Late Recording Commit 차단 계약은 Project Materialization / Import 경로에만 적용되며, Project 삭제 / 대체는 Photos 원본을 절대 삭제하지 않는다. 아래 원문은 당시 기준의 기록이다.

**Implementation Note (Phase 5 STEP 12A, ADR-039, 2026-09-16):** Pending Clip의 Physical Cleanup은 Live Editor Session 동안 금지되고 Editor Route 제거 / App 시작 두 경계에서만 `ProjectMediaCleanupCoordinator`가 File-first → Metadata-finalize 순서로 수행하며, Thumbnail Consumer Gate, Editor-open / Composition Serialization, Active + Missing 보호, Per-Clip 실패 격리는 ADR-039가 확정한다. Orphan / Workspace Sweep은 STEP 12B로 남는다.

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

**Partial Supersession (ADR-042, 2026-09-17):** "선택된 최대 10초(→5초) Segment를 기반으로 하는 Project-owned Working Media"의 Segment 전제는 ADR-042로 대체되었다. Working Media의 기준은 전체 Duration이 `1.0s <= duration <= 5.0s`인 Photos Source 전체이며 Long-source Segment Selection은 존재하지 않는다. Non-goals의 "Import Re-trim / Source Reference"는 ADR-042로 해소되었다(원본 범위 Re-trim 없음). SDR / 30 fps / 1080p-class, Framing 영역 보존, Crop bake-in 금지, Validation과 나머지 Pending Technical Gate는 그대로 유효하다.

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
- Import Re-trim / Source Reference (이후 ADR-042로 해소: 원본 범위 Re-trim / Source Reference 없음)
- Performance Threshold

---

# ADR-023 — Camera Capture, Zoom, Permission, Mirroring, and Orientation Policy

**Date:** 2026-09-12

**Status:** Accepted

**Partial Supersession:** ADR-033이 Microphone 필수 Direct Recording(Denied / Restricted 시 Recording 차단, Video-only Fallback 없음)을 대체하여 Microphone을 선택 권한으로 하고 무음 Recording을 허용하며, Recording Start Gate를 upright Portrait 자세만 허용(Landscape / Face Up / Face Down / Unknown / Unstable 거부)으로 확정한다. Recording 중 자세 변경은 ADR-033(2026-09-14 Resolution)으로 확정되어 Clip Orientation이 Recording 전체 동안 Portrait으로 고정되고 자세 변경만으로 Stop / Restart하지 않으며 종료 후 자세를 재평가한다. 나머지 Lens / Zoom / Mirroring / Interruption 계약은 유지하며 아래 원문은 당시 기준의 기록이다. 아래 "Minimum Valid Clip Duration Pending"은 ADR-033(Direct Capture 1.0초)과 ADR-042(Imported Photos Source 1.0초)로 해소되었다.

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

**Clarification (ADR-042, 2026-09-17):** "Import Estimate는 선택된 최대 10초(→5초) Source Segment …"에서 Estimate의 기준 Source는 이제 전체 Duration이 5초 이하인 Photos Source 전체다(Segment Selection 없음). System PhotosPicker는 Photos Read 권한 없이 선택 File 전체를 Mellow 임시 영역으로 전송하므로 그 임시 복사본은 Operation Lifetime의 Transient Peak에 포함되고 Commit 이후 보관하지 않는다. 정확한 Formula / Reserve는 여전히 Phase 6 Technical Gate Pending이다.

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

**Implementation Note (Phase 5 STEP 13, ADR-040, 2026-09-16):** Phase 5의 Unavailable은 "Active Clip Metadata + Project-owned Committed 파일 없음 / 해석 불가"로만 좁혀 구현되었고(Corrupt / Unreadable 기존 파일은 이후 Decode Phase), 영속 Flag 없이 Editor가 매 Load마다 파생한다. Replace는 System PhotosPicker 1개 선택 → 새 Clip Identity(Model B)로 같은 논리 Slot을 채우며 Editor Session History에 참여한다. "Replacement Metadata Migration Decision"과 "Replacement Clip Identity Implementation" Pending은 ADR-040으로 해결되었다.

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
**Status:** Accepted — "Imported Video" 항목은 ADR-042에 의해 Partially Superseded

**Partial Supersession (ADR-042, 2026-09-17):** 아래 "Imported Video"의 "Photos Source Video의 전체 Duration은 제한하지 않으며 2분 또는 20분 Source도 선택할 수 있다"와 "사용자는 Source에서 원하는 구간을 자유롭게 선택 / Trim하며", Consequences의 "길이 제한 없는 Source … Segment를 구현·검증한다"는 **더 이상 현재 정책이 아니다**. 현재 정책은 `1.0s <= entire Photos source duration <= 5.0s`이며 Long-source Segment Selection은 제공하지 않는다. Direct Capture 항목, 비정수 Duration 허용, Camera Preset의 Import 미적용, Canonical Invariant `0 < effectiveClipDuration <= 5 seconds`, Photos 원본 보존 / Project-owned Working Media 방향은 그대로 유효하다. 아래 원문은 당시 기준의 기록이다.

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

**Partial Supersession (ADR-041, 2026-09-17):** "Camera에는 최근 / 마지막 Clip의 작은 Thumbnail 또는 동등한 Compact Project-content Access를 두고 탭하면 해당 Project의 Clip Review / Editor로 이동한다"와 위 ADR-033 Note의 "Compact Project-content Access는 단일 저장 Project 진입으로 재해석" 부분은 ADR-041이 대체한다: Camera Upper-trailing `Projects` Control이 Project 접근이고, Camera 좌하단 Compact Slot은 Direct-capture 피드백(Session-only 마지막 Recording)에 속하며 저장 Project Representative나 ProjectEditor 접근이 아니다. Camera에 Timeline / Dashboard를 두지 않는다는 결정과 Lightweight Editor 결정은 유지된다. 아래 원문은 당시 기준의 기록이다.

**Partial Supersession (ADR-037):** Lightweight Editor의 "Camera / Photos Library를 지원하는 Add Clip" 중 Editor Add Clip의 Acquisition Source는 System PhotosPicker로 확정되었으며 Editor `+`는 Camera를 열지 않는다. 아래 원문은 당시 기준의 기록이다.

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
- Phase 6: Photos Import와 Segment Selection을 구현한다. — **ADR-042 (2026-09-17):** Segment Selection은 제외되었다. Phase 6은 5초 이하 전체 Source의 Normalization-required Import를 구현한다.
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
- 이후 Photos Import는 Portrait / Landscape Source를 모두 허용하고 Source 길이를 제한하지 않으며 선택 Segment는 `0 < duration <= 5 seconds`를 만족한다. — **ADR-042 (2026-09-17):** "Source 길이를 제한하지 않으며 선택 Segment" 부분은 대체되었다. Photos Source는 전체 Duration이 `1.0s <= duration <= 5.0s`일 때만 받아들이며 Portrait / Landscape 허용은 유지한다.
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
- Imported Clip 최소 길이, Location Metadata, Multi-project 복원 시점은 이 결정에서 확정하지 않는다. (Imported Clip 최소 길이는 이후 ADR-042로 1.0초 확정.)
- 이 ADR은 구현이 아니며 Phase 4는 시작되지 않았다.

---

# ADR-034 — Phase 5 Clip Project Management Structural UX and Select-Clips Media Boundary

**Date:** 2026-09-14
**Status:** Accepted
**Partial Supersession:** 이 ADR의 §1 Projects Entry Presentation(Compact Native Bottom Sheet)만 ADR-035에 의해 전용 Pushed Projects 화면으로 Superseded되었으며, §3 `Add Clips`의 "Direct Camera 취득 / Photos 취득 각각 라우팅" 문구 중 Editor Add Clip의 Acquisition Source는 ADR-037에 의해 System PhotosPicker(현재 Project Append)로 확정되었다. §1의 Semantic Hierarchy(`Start New Project` / `Continue Editing` / 대체 확인)와 §2–§7의 나머지는 그대로 유효하다. 아래 원문은 당시 기준의 기록이다.

**Clarification (ADR-042, 2026-09-17):** §2의 "Phase 6 / 7 소유 유지" 목록 중 **Long-source Segment Selection과 임의 Source Trim / Re-trim(원본 범위)**은 어느 Phase도 소유하지 않는 제외 기능이 되었다. Photos Source는 전체 Duration `1.0s <= duration <= 5.0s`일 때만 받아들이며(1.0초 미만 거부는 Phase 6 구현 요구) 5초 초과 Source의 Typed `requires import preparation(.tooLong)` 거부(`영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`)는 Phase 6 이후에도 **최종 사용자 동작**이다(Phase 6이 이를 Segment Selection으로 바꾸지 않는다). HDR / Dolby Vision → SDR, 4K → 1080p-class, Frame-rate Normalization, Landscape / Transform 처리는 여전히 Phase 6 소유이며 §2의 Phase-5-ready Boundary 자체는 변경되지 않는다.

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

**Superseded by ADR-038 (2026-09-16):** Transient Bottom Snackbar와 "가장 최근 Delete 한 건" Undo, Undo Window Tuning은 Navigation Bar 우상단의 상시 Undo / Redo Session History로 대체되었다. Delete가 선택 Clip의 명시적 Action이고 확인 없이 즉시 적용된다는 점은 유지된다. 아래 원문은 당시 기록이다.

가장 최근 Clip Delete Undo Opportunity에 Transient Bottom Snackbar / Toast를 사용한다. 표현은 `Clip deleted` + `Undo`.

동작은 ADR-021 / F-MVP-025 Canonical: Delete 즉시 논리적 순서에서 제거, 가장 최근 Delete 한 건만 사용자-visible Undo, 새 Delete가 이전 Undo Opportunity 종료, Undo는 동일 Clip Identity / Media / Metadata 복원, Undo는 Unrelated Reorder를 되돌리지 않음, Process 종료 후 Undo 미복원, Physical Media 삭제는 안전 조건까지 지연. 정확한 Undo Window Duration은 Tuning으로 남긴다. Source-of-truth가 명시적으로 요구하지 않는 한 일반 Clip Delete 앞에 확인을 추가하지 않는다.

### 5. Unavailable Clip Structure

Unavailable Clip은 논리적 Strip 위치에 계속 보인다. Clear Placeholder Thumbnail, Color-only가 아닌 Unavailable State, 간결한 Unavailable 표시, 명시적 Replace, 명시적 Delete를 사용한다. 사라지거나 자동 삭제하거나 다른 Asset을 조용히 사용하거나 조용히 이동하거나 Healthy처럼 조용히 건너뛰지 않는다. 다른 Clip이 Unavailable해도 Healthy Clip은 선택 / Reorder 가능하다. Unavailable Clip 자체는 Video Preview가 없다. Replace / Delete Semantics는 ADR-026 / ADR-021을 따른다.

### 6. Camera Bottom-left Content Slot (Phase 4 → Phase 5 전환)

**Superseded by ADR-041 (2026-09-17):** 아래 "저장 Project 있음 → Project Representative Thumbnail + 저장 Project Editor 진입으로 승격" 항목은 제품 의도 Drift로 확인되어 폐기되었다. Camera 좌하단 Slot은 저장 Project 유무와 무관하게 Direct-capture 피드백(Session-only 마지막 Recording)에 속하고 Project 접근은 Upper-trailing `Projects` Control이며, Project Representative Thumbnail(§7)은 Projects 화면 같은 Project-oriented Surface에만 표시된다. 아래 원문은 당시 기록이다.

- **저장 Project 없음:** 현재 Phase 4 동작 유지 — Session-only `lastRecordingThumbnail`, Recording-success 시각 피드백, Project Identity 없음, Playable URL 없음, Non-navigable. Raw-video Playback으로 만들지 않는다.
- **저장 Project 있음:** 동일 Compact 영역을 Project-aware Content Access로 승격 가능 — 현재 Project Representative Thumbnail 표시, 탭 시 해당 저장 Project의 Editor / Clip Management Surface 열기. 저장 Project가 있으면 Project Representative Thumbnail이 Session-only Latest-recording 피드백보다 Semantic 우선한다. 이는 Tile을 "Play last recording"으로 바꾸지 않는다. 이 Control을 위해 Camera Staging Media를 보관하지 않는다.

### 7. Representative Thumbnail Semantics (유지)

Current Logical Clip Order → 첫 Healthy / Usable Clip → Representative Source. Reorder, Delete, Undo Restore, Successful Replacement, Availability Transition, Representative Media Identity Change 후 재평가한다. Usable Source가 없으면 Project Placeholder를 사용하고 Unrelated Stale Thumbnail을 재사용하지 않는다. Async Thumbnail 결과는 적용 전 Validity를 확인한다.

## Still Pending (이 ADR이 확정하지 않음)

- Unavailable-Clip Replacement Metadata Migration: 기존 Clip ID 유지 vs 새 Clip ID, Trim / Framing / Transform Preserve vs Reset, Thumbnail Regeneration 세부, 사용자-facing Reset 전달 — **Resolved by ADR-040 (2026-09-16):** 새 Clip ID(Model B), Trim Reset(`trimStart` 0 / `trimDuration` = Source), Framing nil, Thumbnail은 새 Identity로 정상 생성, Phase 5에는 사용자에게 알릴 기존 Trim / Framing이 없으므로 Reset 안내 없음. §5 Unavailable Clip Structure의 Presentation은 DESIGN §19 STEP 13 항목으로 확정되었다.
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

# ADR-037 — Project Editor Add Clip Uses PhotosPicker Acquisition

**Date:** 2026-09-15
**Status:** Accepted

**Implementation Note (Phase 5 STEP 11, 2026-09-16):** Editor `+`(`클립 추가`)는 Editor 전용 `PhotosVideoSelector` Session(Projects 화면의 Picker Host와 분리) → 기존 Pre-copy Admission / `Phase5ReadyMediaValidator` / `ProjectMediaStore` Workspace → `ProjectClipAppendCoordinator`(Validate ALL → Materialize ALL into `Projects/<현재 pid>/Media/`) → `VlogProject.appendClips`(마지막 Active Clip 뒤, Picker 순서, sortOrder 0…n-1) → `ProjectEditorModel.commitEdit(.add)`(한 번 Autosave + Read-back)로 구현되었다. 한 Picker Session의 Multi-select는 하나의 Atomic Edit이자 하나의 History Entry이며 첫 번째 새 Clip이 선택된다. Cancel / Non-ready / Transfer / Materialize / Persist 실패는 모두 All-or-nothing으로 현재 Project · History · Selection · 기존 Media를 그대로 두고 이 Operation이 만든 파일만 제거한다. Undo / Redo는 ADR-038을 따른다.

**Clarification (ADR-042 Revision 3, 2026-09-17):** 아래 "하나라도 Ready가 아니면 아무것도 Append하지 않고(All-or-nothing)"는 Phase 5 STEP 11 구현 당시의 기록이다. ADR-042 Revision 3 이후 Duration-ineligible 항목(1.0초 미만 / 5.0초 초과)은 Transaction 전에 제외되고 나머지 Accepted Set이 Atomic하게 Append된다(Phase 6 구현 요구); Accepted Set 안의 실패는 여전히 부분 Append를 남기지 않는다.

**Partially Supersedes:** ADR-030 Lightweight Editor의 "Camera / Photos Library를 지원하는 Add Clip"과 ADR-034 §3의 "Direct Camera 취득과 Photos 취득을 각각의 Boundary로 라우팅"하는 Add Clips 문구 중 **Editor Add Clip의 Acquisition Source만**. ROADMAP Phase 5의 "Add Clip Action으로 Camera에 다시 진입" 구현 과제를 대체한다. Lightweight Editor 구조, Ordered Timeline, Delete / Undo, Unavailable Replace, ADR-033의 Capture-first / Single-project 정책과 ADR-034 §2 Select-Clips Media Boundary는 변경하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

STEP 8 Immersive Editor Timeline은 Leading `+`(Add Clip) 자리를 가진다. 기존 Phase 5 Roadmap은 이 Action을 "Camera 재진입"으로 정의했지만, ADR-033 이후 Camera는 Capture-first이며 Recording은 어떤 Project에도 속하지 않는다. Camera로 라우팅하면 "현재 열린 Project가 촬영 결과의 소유자"라는 암묵적 결합이 생기고, 이미 STEP 6가 구현한 PhotosPicker Composition Bootstrap(명시적 사용자 선택, Broad Photos Read Permission 없음, Media Inspection, Phase-5-ready Validation, Pre-copy Storage Admission, Project-owned Materialization, Photos 원본 보존, Cancel / Failure 안전성)과 다른 두 번째 Acquisition Model이 생긴다.

## Decision

- Editor `+`는 **"이 Project에 Clip 추가"**를 뜻하며 System PhotosPicker를 연다. Camera를 열지 않는다.
- Flow: `ProjectEditor → + → PhotosPicker → 하나 이상 Video 선택 → 선택 항목 전부 Inspect / Validate → 모두 Phase-5-ready이면 Project-owned Copy Materialize → 현재 Project 끝에 Picker 선택 순서대로 Append → Persist / Autosave → Editor Timeline 갱신`. 하나라도 Ready가 아니면 **아무것도 Append하지 않고** 현재 Project는 변경되지 않는다(All-or-nothing).
- Phase-5-ready 규칙은 ADR-034 §2 / STEP 6 계약을 그대로 재사용한다(0 < duration ≤ 5s, Portrait, ≤1080p-class, ≤30 fps, SDR, Audio 선택; **ADR-042 이후** Import Eligibility 하한은 1.0초이며 1.0초 미만 거부는 Phase 6 구현 요구 — 현재 Validator는 미강제). Non-ready Media는 기존 `requires import preparation` UX를 받으며 조용한 Trim / Crop / Transcode / Normalize / HDR 변환 / Frame-rate 변경을 하지 않는다. Long-source Segment Selection, 4K → 1080p, HDR → SDR, Frame-rate Normalization, Import 편집 준비는 Phase 6 소유로 유지되며 Phase 5가 완전한 Photos Import를 구현했다고 주장하지 않는다. (**ADR-042:** Long-source Segment Selection은 이후 제외되었고 5초 초과 Source의 `.tooLong` 거부가 최종 동작이다; 나머지 Phase 6 소유 항목은 유지.)
- Append는 현재 Persisted Project P에 대한 **APPEND** Operation이다: 대체 Project 생성, Safe Atomic Replacement, 또 다른 Current Project 생성, 기존 Clip 삭제, 순서 Reset, Orientation 변경을 하지 않는다. 새 Clip은 현재 논리적 마지막 Clip 뒤에 Picker 선택 순서로 붙는다(`A → B → C` + `D → E` = `A → B → C → D → E`).
- Transaction 안전성은 STEP 6와 같은 원칙을 따른다: Workspace → Validate → Storage Admission → Materialize → Appended Project State 구성 → Persist → Read-back Verify → Cleanup. Commit 전 실패 시 P는 변경되지 않으며, Persistence 실패 시 부분 Append된 논리 Project를 노출하지 않고, Photos 원본은 건드리지 않는다.
- Picker Cancel: Project Mutation 없음, 새 Clip 없음, Error 없음, 이전 Selection 재사용 없음, Media 잔여물 없음. STEP 6의 Real-picker Session Isolation 수정을 유지한다.
- UI: 최종 Timeline은 `[ + ] [clip1][clip2][clip3] …`의 Leading Add Clip Control을 가진다. 이 Control은 기능이 구현된 뒤에만 Production에 나타나며 그 전에는 Dead Button도 빈 예약 Gap도 두지 않는다(STEP 8 V4.1 Production 표현 유지). 구현 시 같은 Timeline HStack 앞에 Prepend하며 Layout을 다시 설계하지 않는다.
- Camera Ownership: Camera 동작은 변하지 않는다. 일반 Camera Recording은 Photos에 저장되고 어떤 Project에도 자동으로 붙지 않으며 현재 Project 소유자를 추론하지 않는다. 사용자는 `ProjectEditor + → PhotosPicker`로 Project Media를 명시적으로 고른다(Capture ≠ Project). Camera로 촬영한 순간도 Photos 저장 후 같은 경로로 Project에 추가한다.

## Consequences

- Phase 5 Add Clip은 STEP 6의 Selection / Validation / Admission / Materialization Boundary를 재사용하고 Operation Semantics만 CREATE / REPLACE에서 APPEND-to-current로 바뀐다(ARCHITECTURE 62절 "Editor Add Clip Append Contract").
- ROADMAP Phase 5 구현 과제 13과 UI Test "Add Clip 진입" 문구를 PhotosPicker Append Semantics로 갱신한다.
- DESIGN / PRODUCT의 "Add Clip은 Camera와 Photos Library를 지원" 문구는 Editor `+`의 Acquisition Source가 PhotosPicker임을 명시하도록 보완한다.

## Non-goals

- Add Clip 구현 자체(이 ADR은 문서 정렬이며 코드 변경이 없다).
- Phase 6 Import / Normalization, Unavailable Replace Metadata Migration, Reorder / Delete / Undo 구현.
- Camera Content-slot / Representative Thumbnail 변경.

---

## 3. Pending Decisions

다음 목록은 Pending Decision과 이후 해결된 항목의 이력을 함께 유지한다.

`Resolved by ADR-022`, `Resolved by ADR-023`, `Resolved by ADR-024`, `Resolved by ADR-025`, `Resolved by ADR-026`, `Resolved by ADR-028` 또는 `Resolved by ADR-042`로 표시된 Policy / UX Structure는 확정되었으며 나머지 Pending Technical Detail은 임의로 구현 기준을 결정하지 않는다.

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

- Photos Source Duration Eligibility — Resolved by ADR-042: 전체 Source Duration이 `1.0s <= duration <= 5.0s`(양 끝 포함)일 때만 Import하며 1.0초 미만 / 5.0초 초과는 거부하고 Long-source Segment Selection은 제공하지 않는다.
- Imported Clip을 이후 원본 Source 전체 범위에서 다시 Trim할 수 있게 할지 여부 — Resolved by ADR-042: 제공하지 않는다.
- 현재 Materialized Segment 내부에서만 Re-trim할지 여부 — Resolved by ADR-042: Re-trim은 받아들여진 Project-owned Clip Media 범위 안에서만 가능하다(Phase 7).
- Source Reference를 함께 유지할지 여부 — Resolved by ADR-042: 유지하지 않는다.
- Imported Clip의 최소 길이 — Resolved by ADR-042(2026-09-17 사용자 승인): 1.0초. Phase 6 구현 요구사항(현재 Phase 5 구현은 미강제).
- 정확한 1.0초 / 5.0초 경계의 AVFoundation Duration 비교 정책 — Pending 구현 세부사항, Phase 6 Technical Gate(Product 경계는 확정).
- 1.0초 미만 Photos Source 거부의 사용자 안내 — Resolved by ADR-042 Revision 2(2026-09-17): `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`.
- 다중 선택의 Duration-ineligible 항목 처리와 통합 안내 — Resolved by ADR-042 Revision 3(2026-09-17): Per-item Filtering, `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` / `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` / `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`, Accepted Set Atomicity, Replace는 단일 후보.
- Phase 6 Normalization-required Import의 진입 / 진행 / 실패 / Retry Presentation 구조, Storage 부족 Presentation, Duration 외 Invalid Media의 다중 선택 처리 — Pending, Phase 6 Structural UX Gate(Segment Selection 아님).
- Import Durable Operation Identity / Recovery 깊이와 ADR-039 STEP 12B Orphan Predicate 확장 — Pending, Before Phase 6 Normalization 구현.

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
- Minimum Valid Clip Duration — Resolved by ADR-033: Direct Capture 1.0초 이상; Imported Clip 최소 길이는 Resolved by ADR-042: 1.0초.
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
- Import Estimate Formula와 Temporary / Recovery-safe Overlap Multiplier — Pending, Before Phase 6(ADR-042: 기준 Source는 5초 이하 전체 Source이며 Picker Transient 복사본을 Peak에 포함).
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
- Exact Unavailable Visual과 Replace UI — Resolved 2026-09-16 by ADR-040 / DESIGN 19절 STEP 13.
- Replacement Clip Identity와 Trim, Framing, Transform, Thumbnail Metadata Migration 및 Reset Communication — Resolved 2026-09-16 by ADR-040 (Model B 새 Identity, Trim / Framing Reset, 새 Thumbnail).
- Project Metadata Recovery Algorithm과 Exact Corrupted-project UI / Copy — Pending.

### Capture-First V1 (ADR-033)

- Recording 시작 후 Device 자세 변경 시 동작 — Resolved 2026-09-14 by ADR-033: Clip은 Recording 전체 동안 Portrait으로 고정되고 자세 변경만으로 Stop / Restart하지 않으며 종료 후 자세를 재평가한다.
- Recording Progress Ring의 정확한 색상 / 표현 — Pending, Phase 4 구현 / Physical Visual Review Polish이며 ADR 결정 대상이 아니다.
- Imported Clip의 최소 길이 — Resolved by ADR-042: 1.0초(Phase 6 구현 요구).
- Camera Projects Entry(`Select Clips` / `Load Last Saved` / 대체 확인)의 정확한 Copy와 Presentation — Structural UX Resolved by ADR-034(`Start New Project` / `Continue Editing` Hierarchy, 대체 확인 Cancel / Create New Project); Presentation은 ADR-035로 전용 Pushed `프로젝트` 화면(`Camera → 프로젝트 → ProjectEditor`)으로 확정, Bottom Sheet 아님; 화면 Content는 ADR-036으로 항상 두 개의 중앙 Action(`새 프로젝트 시작` / `기존 프로젝트 불러오기`, 후자는 저장 Project 있을 때만 Enabled, List / Card / Metadata 없음)으로 확정; 정확한 Localization Copy만 Polish로 Pending.
- Phase 5 `Select Clips` Project Composition과 Phase 6 Photos Video Import의 Media 소유 경계 — Resolved by ADR-034: Phase 5는 Phase-5-ready media만 Bootstrap하며 Non-ready Media는 부분 Commit 없이 Typed `requires import preparation` 결과로 처리하고 Segment Selection / Normalization / Trim은 Phase 6 / 7 소유로 유지.
- Phase 5 Project Editor Structural UX(Preview Shell, Ordered Thumbnail Strip, Selection, Delete / Undo Snackbar, Unavailable Clip 표현, Add Clips, Project Duration 배치) — Resolved by ADR-034.
- Editor Add Clip의 Acquisition Source — Resolved 2026-09-15 by ADR-037: System PhotosPicker로 Phase-5-ready Media를 현재 Project 끝에 All-or-nothing Append하며 Camera를 열지 않는다. (ADR-042 Revision 3: 다중 선택의 Duration-ineligible 항목은 Transaction 전에 제외되고 Accepted Set이 Atomic하게 Append된다 — Phase 6 구현 요구.)
- Camera Bottom-left Content Slot Phase 4 → Phase 5 소유 전환 — Resolved by ADR-034, **Superseded by ADR-041 (2026-09-17):** Slot은 Direct-capture 피드백에 남고 Project Representative는 Projects 화면이 표시한다; Editor 진입 승격은 폐기.
- Unavailable-Clip Replacement Metadata Migration(Clip Identity / Trim / Framing / Transform Preserve vs Reset, Thumbnail Regeneration, Reset 전달) — Resolved 2026-09-16 by ADR-040.
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

---

# ADR-038 — Editor Session Undo / Redo History

**Date:** 2026-09-16
**Status:** Accepted

**Partially Supersedes:** ADR-021의 "MVP에서 사용자에게 노출되는 Undo는 가장 최근 Clip Delete 한 건이며 새로운 Delete가 이전 사용자-visible Undo Opportunity를 종료한다"와 "Undo 복원 위치는 삭제 당시 이전 / 다음 인접 Stable Clip Anchor … Original Index Clamp"의 **사용자-visible Undo 모델**, ADR-034 §4 Delete / Undo Presentation의 **Transient Bottom Snackbar `Clip deleted` + `Undo`**와 "정확한 Undo Window Duration은 Tuning으로 남긴다"는 Pending 항목, F-MVP-025 / PRODUCT / ROADMAP의 "가장 최근 Delete 한 건만 Undo" 문구. ADR-021의 Logical / Physical Deletion 분리, Durable Pending Deletion, Physical Cleanup Safety, Process Termination 후 Undo 미복원, Late Result 차단과 ADR-034 §3의 "Delete는 선택 Clip의 명시적 Action"은 그대로 유지한다. 역사적 기록은 다시 쓰지 않는다.

## Context

Phase 5 STEP 10 최초 구현은 Delete 전용 Bottom Snackbar와 "가장 최근 삭제 한 건"만 Undo하는 모델이었고, 정확한 Undo Window(자동 소멸 시간)는 승인되지 않은 Gate로 남아 있었다. 이 모델은 (1) Delete만 되돌릴 수 있어 이미 구현된 Reorder나 이후 Phase 7 / 8의 Trim / Framing / Text / Sticker 편집과 확장되지 않고, (2) "Delete만 선택적으로 되돌리고 이후 Reorder는 유지"하는 Anchor 복원이 일반적인 편집 History의 직관(시간 역순)과 충돌하며, (3) Timer 기반 Snackbar는 값 결정(3 / 5 / 6 / 10초)이 임의적이고 접근성상 놓치기 쉽다.

## Decision

- Mellow Editor V1은 **Navigation Bar 우상단의 상시 Undo / Redo Control**(`arrow.uturn.backward` / `arrow.uturn.forward`, Accessibility Label `실행 취소` / `다시 실행`)로 **Editor 편집 History**를 제공한다. 두 Control은 구조적으로 항상 존재하며 History 유무 / Commit 진행 / Drag 중 여부에 따라 Enabled / Disabled된다. `Back  Project  Undo Redo` 구조를 유지하고 Preview Canvas와 V4.1 Dock Geometry를 바꾸지 않는다.
- History는 **시간순 LIFO**다. Undo는 가장 최근 성공한 편집을 되돌리고(Entry는 Redo Stack으로), Redo는 가장 최근 되돌린 편집을 다시 적용한다(Entry는 Undo Stack으로). Undo 뒤 **새로운 편집이 성공하면 Redo Stack 전체를 버린다**. Delete를 선택적으로 되돌리면서 이후 Reorder를 보존하는 동작은 더 이상 사용자 모델이 아니다(예: A B C D → Delete B → D를 앞으로 → Undo 한 번 = A C D, 두 번 = A B C D).
- 참여 편집은 우선 **Clip Reorder**와 **Clip Delete**이며 이후 Add Clip / Trim / Framing / Text / Sticker 등 모든 Editor Mutation이 같은 History 모델을 사용한다. 선택만 바꾸는 Tap, Thumbnail 상태, Navigation, 실패한 저장은 History가 아니다.
- **Undo와 Redo는 새로운 편집**이다: 각각 정확히 한 번 Autosave(Repository `update` + Read-back 검증)하며 실패 시 현재 State와 두 Stack을 그대로 두고 복구 가능한 Message(`실행 취소하지 못했어요.` / `다시 실행하지 못했어요.`)를 보인다. 복원은 현재 Project Identity(UUID / Orientation / createdAt)에 Clip 집합과 Selection을 다시 적용하며 `updatedAt`은 항상 앞으로만 간다.
- History는 **Editor Session-local**이다. Editor를 열면 비어 있고, 떠나거나 Process가 종료되면 사라지며, SwiftData에 저장하거나 Deletion Record / Timestamp로 재구성하지 않는다. 재진입 시 Project는 마지막 Autosave 상태 그대로이고 Undo / Redo는 Disabled다.
- History Entry는 편집 전후의 **영속 Editor State(Active Clip 집합, Pending-deleted Clip 집합, Selection)와 편집 종류**만 담는 값이다. Media / Image / Closure를 담지 않으므로 Session 동안 상한을 두지 않는다.
- **Delete-only Snackbar, Timer 기반 Undo Window, "가장 최근 삭제 한 건" 제한은 폐기**한다. Delete는 여전히 확인 없이 즉시 적용되며 Undo가 안전 장치다.
- **Durable Pending Deletion은 유지**한다: Delete는 Clip을 Active Timeline에서 제거하고 같은 Identity / Media / Metadata를 Pending-deleted로 영속화하며, Session History 안에서 Undo / Redo가 그 Clip을 같은 Identity로 오간다.
- **Implementation Note (STEP 12A, ADR-039):** "Session이 끝난 뒤의 Pending Deletion만 Cleanup 후보"는 구현에서 "Editor Route가 Stack에 있는 동안은 그 Project의 어떤 Pending Clip도 물리 정리하지 않는다"로 확정되었다. Session 안에서 Redo가 사라져 논리적으로 도달 불가능해진 Clip도 Session 경계(Back)까지 파일이 유지되며, Editor는 Cleanup을 위해 어떤 History도 유지하지 않는다.
- **Replace(ADR-040)도 History-capable Mutation이다(STEP 13):** 성공한 Replace 한 번 = History Entry `.replace`(`클립 교체`) 한 개. Before State = B Active(Unavailable) / D 없음 / Selection B, After State = B Pending / D Active / Selection D. Undo Replace는 `commitHistory`의 기존 "대상 Snapshot이 모르는 Durable Clip은 Pending으로 유지" 규칙으로 D를 Pending-deleted(파일 유지)로 남기고 B를 같은 Identity로 되살리며, Redo는 같은 D UUID / Path / 파일을 Active로 되돌린다(Picker / 복사 없음). Undo 뒤 새 편집으로 Redo가 사라진 D는 Session 경계까지 Pending으로 남아 STEP 12A가 회수한다.
- **Add Clips(ADR-037)도 History-capable Mutation이다(STEP 11):** 한 Picker Batch = 한 History Entry(`.add`). Add를 Undo하면 새 Clip은 Active Timeline에서 빠지되 물리 삭제되지 않고 같은 Pending-deleted(Inactive, Durable) 상태로 남아 Redo가 같은 UUID / Media Path / 파일 / Metadata를 되살린다(재복사 / 재선택 / 새 UUID 없음). History 복원은 현재 Project가 소유하지만 대상 State가 모르는 Clip을 절대 잊지 않고 Pending-deleted로 유지한다(Repository Omission Guard 유지). Undo Add 뒤 새 편집이나 Session 종료로 Redo가 사라진 Clip은 Durable Pending으로 남아 이후 Physical Cleanup Slice의 대상이 된다. `finalizeDeletedClip`(명시적 물리 Metadata 제거)은 Production에서 호출하지 않으며 Media 삭제 / Cleanup Scheduler / Timer는 없다. Session History에서 도달 가능한 Delete의 Media는 복구 가능해야 하고, Session이 끝난 뒤의 Pending Deletion만 이후 Cleanup Slice의 후보가 된다(ADR-021 안전 조건 유지).

## Consequences

- Reorder / Delete 및 이후 모든 편집이 하나의 예측 가능한 Undo / Redo 모델을 공유한다.
- Undo Window 값 결정이 불필요해지고 접근성(VoiceOver / Switch Control)에서 Undo가 상시 발견 가능하다.
- Delete-specific Anchor 복원(`VlogProject.restoreDeletedClip`)은 Editor 사용자 모델이 아니라 Domain-level Durable Recovery Primitive로만 남는다.
- Editor는 Session 동안 편집 State Snapshot을 보관하지만 Metadata 값만이라 메모리 부담이 없다.

## Non-goals

- History 영속화, Cross-session Undo, Project 삭제 Undo, Physical Cleanup 정책, Add Clip / Trim / Framing / Text / Sticker 편집 자체.

---

# ADR-039 — Deferred Physical Cleanup Boundaries

**Date:** 2026-09-16
**Status:** Accepted

**Clarifies / Extends:** ADR-021의 Logical / Physical Deletion 분리, Durable Pending Deletion, Physical Cleanup Safety, Process Termination 후 Reconciliation과 ADR-038의 "Session이 끝난 뒤의 Pending Deletion만 Cleanup 후보"를 Phase 5 STEP 12A의 실제 구현 경계로 확정한다. ADR-020의 Recovery Classification / Confirmed Orphan Contract, ADR-021의 Active Consumer 원칙, ADR-026의 Unavailable Clip 정책, ADR-033의 Safe Atomic Replacement는 변경하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

STEP 10 / 11 이후 Editor의 Delete와 Undo Add는 Clip을 Durable Pending(`VlogProject.deletedClips`)으로만 남기고 Media File은 절대 지우지 않았다(`finalizeDeletedClip` 경계만 존재, Production 호출 없음). ADR-021은 Physical Delete의 안전 조건(Undo Eligibility 종료, Active Consumer 없음, Late Commit 차단, Safe Classification)을 정의하지만 "언제", "누가", "어떤 순서로", "무엇과 직렬화하여" 지우는지는 구현에 열어 두었다. STEP 12 Design Review는 Editor Session 안에서 History Reachability를 매 편집마다 재계산해 즉시 정리하는 방식(Undo / Redo / Redo Invalidation / Reorder / Delete / Add마다 File IO)이 불필요하게 복잡하고 위험하다고 판단했고, 더 강한 단순 경계를 승인했다.

## Decision

1. **Live Editor Session 동안에는 그 Project의 어떤 Pending Clip도 물리적으로 정리하지 않는다.** Session 안에서 Eligibility가 바뀌어도(Undo Add 뒤 새 편집으로 Redo가 사라져 논리적으로 도달 불가능해져도) File IO는 Session 경계까지 기다린다. "Session이 살아 있다"는 Navigation 소유의 사실 — `.projectEditor(P)` Route가 Stack에 있음 — 로 판정하며 Editor History를 Cleanup을 위해 유지하지 않는다. Editor 위에 올라온 PhotosPicker / Sheet는 Route를 바꾸지 않으므로 Session 종료가 아니다.
2. **Cleanup Trigger는 정확히 두 곳이다.** (A) Editor Route가 Path에서 제거될 때(Back / Pop / Path Reset) 해당 Project 하나를 비동기로 Reconcile한다 — Navigation은 Disk IO를 기다리지 않는다. (B) App 시작 시 Persistence가 준비된 뒤 모든 Durable Project를 Reconcile한다 — Editor History는 Process를 넘지 않으므로 시작 시점의 Project는 History-free이며, 시작 Route가 이미 Editor라면 Live Session으로 보고 건너뛴다. Camera 시작 / Recording은 Cleanup을 기다리지 않는다.
3. **순서는 File-first → Metadata-finalize다.** Pending 재확인 → Canonical Owned Path 검증 → Media Reader Idle 대기 → File 삭제 → 부재 검증 → `finalizeDeletedClip`. 반대 순서(Metadata 먼저)는 금지한다: Crash 뒤에 남은 Pending Row는 발견 가능하지만 File 위에 남은 Row 없는 파일은 Orphan이 된다.
4. **Pending + File 이미 없음 = File 단계 완료.** Cleanup 경계에서 Canonical 파일이 없으면 실패가 아니라 Crash Recovery(파일 삭제 → Process 종료 → Row Pending)로 보고 Metadata를 Finalize한다.
5. **Active + File 없음 ≠ Cleanup.** `Project.clips`에 있는 Clip은 파일 유무와 무관하게 절대 Finalize / 삭제 / 수정하지 않는다. 이는 이후 Slice의 Unavailable Media / Replace 흐름(ADR-026)이다.
6. **Cleanup Eligibility(모두 충족해야 함):** Clip이 `deletedClips`에 Durable하게 존재, `clips`에 없음, 해당 Project의 Live Editor Session 없음, 같은 Lifecycle Gate 안(Composition / Replacement / Editor Load와 배타), 해당 Path를 읽는 Active Media Consumer 없음(Bounded 대기), `mediaRelativePath`가 정확히 `Projects/<projectID>/Media/<clipID>.mov`(Prefix가 아닌 완전 일치 — Workspace / 다른 Clip / 다른 Project / 임의 Root Path 거부), 그리고 File 삭제 → 부재 검증 → Finalize 순서를 따를 수 있음. 불확실하면 Preserve + Log + 다음 경계에서 Retry.
7. **Editor-open Serialization.** 새 Editor는 Project Snapshot을 읽기 전에 그 Project의 Lifecycle Gate를 기다린다(Cleanup이 파일은 지웠으나 Row는 아직 Pending인 중간 상태를 읽어 이후 Autosave로 Finalize된 Clip을 되살리는 Resurrection Race 차단). Route가 이미 Stack에 있으므로 대기 중에 새 Cleanup Pass는 시작되지 않는다.
8. **Shared Operation Serialization.** Cleanup ↔ Project Composition / Safe Atomic Replacement ↔ Editor Project Load는 하나의 실제 Async Critical Section(`ProjectLifecycleOperationGate`: Main-Actor FIFO Hand-off Lock, Suspension을 가로질러 유지)으로 직렬화한다. Boolean Flag(TOCTOU) 금지. Camera Recording과 Editor Add(Live Session 안이라 Cleanup 불가)는 Gate를 잡지 않는다. Safe Atomic Replacement 자체와 Replacement의 A 정리 소유권은 바꾸지 않는다 — 겹침만 막는다.
9. **Media Consumer Gate.** 현재 유일한 Production Media Reader는 `ClipThumbnailService`이며 In-flight Generation을 관찰하는 `awaitIdle(for:timeout:)`로 Cleanup에 참여한다. 대기는 Bounded이며(기본 3초, Policy) Timeout이면 파일 보존 + Row Pending + Log + 다음 경계 Retry, 사용자 Error 없음. Ready Cached Thumbnail은 Active Consumer가 아니다(Cache Purge 불필요). Request Ordering / Task Group 동작은 바꾸지 않는다. **이후 Playback / Export 등 Project Media를 읽는 모든 Consumer는 같은 Protection Contract(`ProjectMediaConsumerGating`)에 참여해야 하며, Cleanup은 알려주지 않은 Reader를 "없음"으로 가정하지 않는다.**
10. **Ownership.** `ProjectMediaCleanupCoordinator`(Core/Projects)는 Cross-resource Lifecycle Orchestration만 소유한다 — `reconcile(projectID:)` / `reconcileAll()`, Eligibility 판정, Consumer 대기, File 삭제 → 부재 검증 → Finalize, Clip별 실패 격리, Idempotent Retry, Nonfatal Log. Repository = Metadata, `ProjectMediaStore` = Filesystem(`removeCommittedMedia(_:projectID:clipID:)`: Canonical 완전 일치만, Missing = Success, 삭제 실패 / 잔존은 Throw). Coordinator는 Editor History, Repository 구현, Photos, UI Alert, Camera, Orphan Scan을 소유하지 않는다.
11. **Cleanup은 Maintenance이지 편집이 아니다.** `finalizeDeletedClip`은 InMemory / SwiftData 모두 Project `updatedAt`을 올리지 않아 Recent / 저장 Project Recency가 움직이지 않는다. Active Clip 거부, Save Rollback, 실패 시 Retryable Pending Row는 유지하며 이미 Finalize된 Row / 없는 Row는 Idempotent 성공이다.
12. **Per-Clip 실패 격리.** 여러 Pending Clip은 한 Project Pass 안에서 독립적으로 처리한다 — 한 Clip의 File 삭제 실패는 다른 Clip의 성공을 되돌리지 않고 다음 Clip으로 진행한다. Latest-only 동작 없음.
13. **No User-facing Cleanup Error.** 실패는 Pending 보존 + 재시도 + Diagnostic Log뿐이다(Popup / Snackbar / Editor Alert 없음).
14. **STEP 12B 명시적 유보.** Row 없는 Media 파일 Scan, Project Row 없는 Project Directory, 버려진 `ProjectWorkspace`, Root 광역 Sweep은 이 ADR의 범위가 아니며 12A가 실기기에서 검증된 뒤 별도 Slice(ADR-020 Confirmed Orphan Contract 적용)로 다룬다.

**Implementation Note (Phase 5 STEP 12B, 2026-09-16 — Startup Orphan Media + Workspace Recovery):** 위 14항의 유보 Slice는 새 ADR 없이 이 ADR의 구현으로 확정되었다(Design Review 승인 결정 A / B 포함).

- **Startup-only.** `ProjectStartupRecoveryCoordinator`(Core/Projects)는 App 시작 Maintenance에서만 실행된다. Editor 종료 / Add / Delete / Undo / Redo / Project Open / 일반 편집은 절대 Orphan Scan을 촉발하지 않는다. Crash가 만든 Orphan은 다음 실행이 회수한다(Timer / Background / Storage-pressure Scan 없음).
- **Startup Maintenance 순서(하나의 Task, Camera는 대기하지 않음):** Persistence / Store / Thumbnail 준비 → (1) 버려진 Canonical `ProjectWorkspace/<op>/` Sweep → (2) STEP 12A `reconcileAll()`(Known Pending Clip) → (3) Orphan Recovery: Row 없는 Canonical `Projects/<P>/` 전체 제거 → 존재하는 Project의 `Media/` 직속 Canonical `<UUID>.mov` 중 Durable 참조 없는 파일 제거. 각 단계 / 각 Project는 `ProjectLifecycleOperationGate`의 좁은 Section이며 Editor Load / Composition은 실행 중인 Section 뒤에만 줄을 선다.
- **Confirmed Ownership 없이는 삭제하지 않는다.** `ProjectMediaLayout`이 유일한 분류기다: UUID Round-trip(`UUID(uuidString:)` → `uuidString` 완전 일치; 소문자 / 중괄호 / 32-hex 거부), 정확한 `Projects` / `Media` / `ProjectWorkspace` Component, 소문자 `mov` 확장자, 기대 Type(Directory / Regular File) 일치, Symlink 거부(`attributesOfItem`, Link를 따라가지 않음), Root Containment. 그 밖의 모든 Filesystem Object(알 수 없는 파일 / 확장자 / 미래 Subdirectory / Sidecar / 철자가 다른 이름 / Hidden File)는 **보존 + Log**한다. "안 쓰이는 것처럼 보인다"는 삭제 근거가 아니다.
- **Durable Reference Set.** 존재하는 Project P에 대해 `P.durableClips`(Active + Pending)의 Clip ID 집합과 Media Path 집합을 모두 만들고, 후보 파일은 **ID와 Path 둘 다** 어느 Durable Clip에도 없을 때만 Orphan이다. Pending Clip Media(Delete / Undo Add)는 Orphan이 아니라 12A 소유이며, 순서와 무관하게 참조 집합만으로도 보호된다(Test로 고정).
- **Row 없는 Canonical Project Directory 전체 제거(승인 결정 A).** `Projects/<P>/`가 Canonical이고 Symlink가 아니며 Gate를 잡은 채 삭제 직전에 `repository.project(id:)`를 다시 읽어 여전히 nil이고 P에 Live Editor Session이 없을 때만 Directory 전체를 제거한다(`removeOrphanProjectDirectory`, Missing = 성공, 잔존 = Throw). 근거: Project UUID Directory가 V1의 Ownership 경계이고 Phase-5 Composition / Add는 Durable Operation Identity를 갖지 않으므로(Repository Row 자체가 Commit) Row 없는 Directory에는 Recoverable Operation이 존재하지 않는다 — ADR-020 Confirmed Orphan 조건 충족. **Future Compatibility Caveat:** 이후 Schema가 SwiftData Project Row 밖에 복구 가능한 Project-owned Durable State(예: Export Result Ledger)를 두게 되면 그 기능 출시 전에 이 Predicate를 확장해야 한다.
- **존재하는 Project는 Canonical Media만.** `Media/` Directory 자체, Project Directory, 알 수 없는 파일 / 확장자 / Subdirectory는 어떤 경우에도 제거하지 않는다.
- **Live Workspace Registry(승인 결정 B).** `ProjectMediaStore`(Actor)가 `liveWorkspaceIDs`를 보유한다: `beginWorkspace`가 등록하고 `discard`가 `defer`로 해제한다(삭제 실패여도 소유권은 끝나며 남은 Directory는 다음 시작의 Sweep 대상). Sweep은 Age Threshold 없이 Registry에 없는 Canonical Workspace만 제거하며 Registry 확인과 삭제가 같은 Actor 안에서 직렬화되어 Check-then-act Race가 없다.
- **Live Editor Session.** 12A와 같은 규칙: `.projectEditor(P)`가 Stack에 있으면 P의 Media Scan과 P Directory는 건너뛴다(Add가 Commit 전에 만든 파일을 Orphan으로 오판하지 않기 위함; Editor Load가 Gate 뒤에서 기다리므로 시작 Route가 Editor인 DEBUG 경우에만 실제로 발생).
- **Pre-delete Revalidation.** Gate를 잡고 있어도 삭제 직전에 Project를 다시 읽어 Row 존재 / 부재, Live Session, ID / Path 미참조를 재확인한다. 조건이 바뀌면 보존한다.
- **Metadata 무변경 · Failure Isolation · Idempotent.** Recovery는 어떤 Metadata도 쓰지 않는다(`updatedAt` 불변, Finalize 호출 없음). 후보별 do / catch — 실패는 보존 + Count + Log + 다음 실행 Retry, 사용자 표시 없음. 두 번째 실행은 아무것도 만들거나 다시 지우지 않는다. Crash 도중(파일 삭제 전 / 후, Directory 부분 삭제, Workspace 부분 삭제)의 어떤 상태도 Filesystem 자체가 Retry State이므로 Durable Marker가 필요 없다.
- **CaptureStaging 절대 제외.** 12B는 `Projects/`와 `ProjectWorkspace/`의 직속 자식(+ `Projects/<P>/Media/` 직속 자식)만 열거한다. `CaptureStaging/`, `tmp/ProjectMediaTransfer`, Photos, Container의 나머지는 열거조차 하지 않으며 `RecordingRecovery`(Phase 4)가 CaptureStaging의 유일한 소유자로 남는다.
- **STEP 11 즉시 Rollback은 그대로.** In-process Add 실패는 여전히 즉시 자기 파일을 지운다; 12B는 Process가 Rollback / Commit 전에 죽은 경우만 다룬다. Safe Atomic Replacement의 Live A 제거도 `compose` 소유 그대로이며 12B는 이후 시작에서 남은 Directory만 회수한다.
- **Unavailable Media 경계.** Row + Durable Clip + 파일 없음 = Unavailable Media(STEP 13, ADR-040 — Active면 Editor가 Unavailable로 파생, Pending이면 12A가 Metadata만 Finalize), 12B 미접촉. Row + Durable Clip + 파일 = 참조, 보존. Row + 참조 없음 + Canonical 파일 = Orphan 후보. Row 없음 + Canonical Directory = Orphan Directory 후보.
- **Diagnostics.** `ProjectStartupRecoveryReport`(Workspace / Directory / Media 제거·실패, 참조 보존, Noncanonical 보존, Live Skip Count)는 Test / DEBUG 전용이며 `-uiTestCleanupDiagnostics` Overlay에 합쳐진다. DEBUG Seam: `-uiTestSeedOrphanMedia` / `-uiTestSeedOrphanProjectDir` / `-uiTestSeedAbandonedWorkspace` / `-uiTestSeedNoncanonicalFixtures` / `-uiTestRemoveNoncanonicalFixtures` / `-uiTestRecoveryDelay=<ms>` / `-uiTestCrashAfterAddMaterialize`(Mellow Root 안에서만, Production UI 노출 없음).

## Consequences

- Editor 안의 모든 편집 경로(Undo / Redo / Reorder / Delete / Add)는 Cleanup을 전혀 알지 못하며 Media 안전성은 Navigation 경계 하나로 보장된다.
- Crash / Kill 뒤 남은 어떤 부분 상태(Pending + File 있음 / Pending + File 없음 / Finalize 실패)도 다음 시작 Pass가 수렴시킨다.
- Editor 진입은 진행 중인 Cleanup 뒤로 짧게 줄을 설 수 있다(Loading 상태 유지); Back은 절대 기다리지 않는다.
- Release Build에는 Cleanup Control / 표시가 없다. DEBUG UI-test Seam(`-uiTestCleanupDiagnostics`, `-uiTestCleanupDelay=<ms>`, `-uiTestReopenProjectsEntry`)만 존재한다.

## Non-goals

- Orphan / Workspace Sweep(STEP 12B), Unavailable Replace UI, Representative Thumbnail, Playback / AVPlayer, Trim / Framing / Text / Sticker / Full Preview / Export, Server / Background Scheduler, Storage-management UX.

---

# ADR-040 — Unavailable Clip and Replace Semantics

**Date:** 2026-09-16
**Status:** Accepted

**Clarifies / Extends:** ADR-026(Unavailable Clip / Replace 정책), ADR-034 §5(Unavailable Clip Structure)와 "Still Pending — Replacement Metadata Migration", ADR-021 / ADR-038의 Durable Pending Deletion + Session History, ADR-037의 Editor Acquisition Boundary, ADR-039의 "Active + File 없음 ≠ Cleanup"을 Phase 5 STEP 13의 실제 구현 계약으로 확정한다. 기존 ADR을 대체하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

STEP 12A / 12B 이후 Editor는 Pending Clip의 물리 정리와 Orphan 회수를 갖췄지만, "Active Clip인데 Project-owned 파일이 없다"는 상태는 ADR-039 §5가 명시적으로 미접촉으로 남긴 채 사용자에게 Thumbnail 실패 Placeholder(`film`)로만 보였다. ADR-026 / ADR-034는 Unavailable Clip이 위치를 유지하고 사용자가 Replace / Delete할 수 있어야 한다고 정했지만 Replacement Identity(같은 Clip ID vs 새 ID), Trim / Framing / Thumbnail 이전, 정확한 Presentation은 Pending Gate였다. Design Review에서 아래 결정이 승인되었다.

## Decision

1. **Unavailable은 파생 상태이며 영속하지 않는다.** SwiftData Flag / Migration 없음. `ProjectEditorModel`이 `ClipAvailabilityChecking`(Production: `CommittedMediaAvailabilityChecker` = `ProjectMediaStore`의 Read-only `committedMediaURL(for:)` Wrapper)으로 Editor Load와 Active Clip 집합이 바뀌는 모든 편집(Add / Delete / Undo / Redo / Replace) 뒤에 Active Clip마다 재파생한다(`availabilityByClipID`, Generation + Clip Identity / Media Path Guard로 Stale 결과 차단). Reorder / Selection만으로는 재평가하지 않는다. Timer / Polling / Directory Scan / AVAsset Decode / Photos 조회 없음. `repository.project(id:)`는 파일 유무와 무관하게 성공한다.
2. **Phase 5 Unavailable 범위 = Committed 파일 없음 / 해석 불가만.** Resolver의 문서화된 계약(`mediaMissing`, `pathEscapesRoot`)만 Unavailable로 분류하고 그 밖의 예기치 않은 오류는 보존 방향(Available)으로 처리한다. 존재하지만 Corrupt / AVAsset-unreadable / Decode 실패인 파일은 이 Slice에서 Unavailable이 아니며(이후 Playback / Decode Phase), 기존 파일의 Thumbnail 생성 실패는 기존 중립 Thumbnail-failure Presentation(`.unavailable`, `film`)을 그대로 쓴다 — 구조적 Unavailable(`.mediaUnavailable`, `video.slash`)과 분리된 상태다.
3. **Active Unavailable Clip의 구조적 의미.** Active로 남고, 정확한 논리 위치를 유지하며, Metadata `trimDuration`으로 Project Total에 계속 포함되고, 선택 / Reorder(STEP 9 경로 그대로) / History 참여가 가능하다. 절대 자동 삭제 / Skip / 대체 / Pending 전환 / Finalize / 12A·12B Cleanup / 자동 Project Rewrite를 하지 않는다. 알려진 Unavailable Clip에는 Thumbnail을 요청하지 않으며(Retry Storm 방지) 늦게 도착한 Thumbnail 결과가 Unavailable을 Ready로 바꿀 수 없다.
4. **Presentation(DESIGN §19 STEP 13).** Timeline Cell은 44 × 78 Geometry / 위치 / Duration Tag / Selected Outline을 유지하고 중립 `video.slash` Glyph만 다르다(빨간 처리 없음, Cell 안 Text 없음, Accessibility Label `Clip N of M, X.Xs, unavailable`). 선택된 Clip이 Unavailable이면 기존 Full Preview Canvas에 중립 Shell — `video.slash`, Title `클립을 사용할 수 없어요`, Message `파일을 찾을 수 없어요.`, Primary `클립 교체`(44pt Target, Workspace 일관 Capsule) — 를 보인다. Alert / Modal / 빨간 Card 없음. Delete는 기존 Dock Trash 하나뿐이며 Preview에 두 번째 Delete를 두지 않는다. Healthy Clip은 Replace를 노출하지 않는다.
5. **Replace 취득 = System PhotosPicker, 정확히 1개 Video.** Editor의 기존 Acquisition Stack(ADR-037: Editor 전용 `PhotosVideoSelector` Session, Pre-copy Admission, `Phase5ReadyMediaValidator`, `ProjectStorageGate`, `ProjectMediaStore` Workspace / Materialization, `ProjectClipAppendCoordinator.prepareClips`)을 그대로 재사용하며 두 번째 Import 시스템 / 새 Reserve를 만들지 않는다. 하나의 Picker Host가 Add(무제한)와 Replace(`maxSelectionCount` 1)를 Session 단위 Selection Limit으로 구분하고, Model이 반환 개수를 다시 검증한다(1개 초과 = 실패). Camera는 Replace Source가 아니며 Broad Photos 권한은 없다. Non-ready Source(5초 초과 등)는 Add / Select Clips와 같은 Typed Copy를 쓴다.
6. **Replace Identity = Model B(새 Clip).** `A B(unavailable) C` → Replace → `A D C`. `VlogProject.replaceClip(id:with:)`가 하나의 Domain Mutation으로 B를 기존 Deletion 규칙(Anchor 기록, Metadata / Media 불변)으로 Durable Pending에 옮기고 D(`id != B.id`, 같은 `projectID`, `sourceKind = .imported`, `sourceDuration = trimDuration = Source Duration`, `trimStart = 0`, `framing = nil`, Canonical `Projects/<pid>/Media/<D>.mov`)를 B의 정확한 Index에 넣은 뒤 `sortOrder`를 0…n-1로 정규화한다. 다른 Active Identity / 순서 / 기존 Pending Clip은 변하지 않는다. 잘못된 oldID, 다른 Project, Identity 충돌(oldID 포함), Pending 상태의 Replacement는 무변경으로 거부한다. 근거: Clip UUID는 Project-owned Canonical Media Path와 강하게 묶여 있어 새 UUID를 써야 기존 History / Pending Retention / 12A / 12B / Thumbnail Identity가 숨은 Media Stash나 Same-path 충돌 없이 그대로 동작한다.
7. **Replace는 일반 Editor History에 참여한다(ADR-038).** 성공 1회 = `.replace` Entry 1개(`클립 교체`), Autosave + Read-back 1회, Selection B → D. Undo: `A B(unavailable) C`, D는 Durable Pending(파일 유지), Selection B, Total은 B Metadata로 복귀, Picker / 복사 없음. Redo: 같은 D UUID / Path / 파일, B Pending, Selection D, Thumbnail Cache 재사용. Undo 뒤 새 편집은 Redo를 버리고 D는 Session 동안 Pending으로 남는다. 시간순 LIFO만 있으며 선택적 Replace Undo는 없다.
8. **Media Lifetime = Pending Retention + STEP 12A / 12B.** Session 중에는 어느 쪽 파일도 지우지 않는다. Editor 종료 시 Final State가 Replace면 12A가 B(Pending + 파일 없음)의 Metadata만 Finalize하고 D는 Active로 남는다; Undo된 채 종료면 12A가 D 파일 삭제 → Finalize하고 B는 Active Unavailable로 남는다. D Materialize 뒤 Commit 전에 Process가 죽으면 기존 12B가 Row 없는 D 파일을 회수한다. 새 Cleanup 메커니즘 없음.
9. **실패 Atomicity.** Picker Cancel / Transfer 실패 / Invalid / Preparation 필요 / Storage 부족 / Materialize 실패 / Domain 거부 / Persist 실패 / Read-back 불일치 — 모든 경우 B는 정확히 이전 그대로(위치 / Metadata / Total / Selection), History 무변경, Repository Update 0회, 기존 Media 불변이며 이 Operation이 만든 D 파일만 즉시 제거한다. Generic 실패 Copy: `클립을 교체하지 못했어요` / `다시 시도해주세요. 프로젝트는 그대로 있어요.` / `확인`.
10. **Transaction 직렬화.** Add와 Replace는 하나의 `acquisitionMode`(`.add` / `.replace(clipID)`)를 공유한다. 진행 중에는 Add / Delete / Reorder / Undo / Redo / 두 번째 Replace가 거부되어 Picker가 두 번 뜨지 않는다. Selection 변경은 막지 않으며 Replace 대상은 탭 시점의 Clip Identity다.
11. **DEBUG Seam / 실기기 Fixture.** `-uiTestUnavailableClips=<1-based positions>`는 Seeded Editor Route에서 해당 Clip Identity만 Unavailable로 파생하는 Fake Checker다(기존 Fixture는 기본 Available). `-uiTestRemoveActiveClipMedia=<clipUUID>`는 실기기 Fixture 전용 Exact-path Primitive로, 명시된 UUID가 어떤 Project의 Active Clip이고 Path가 Canonical과 완전히 일치할 때만 그 파일 하나를 `removeCommittedMedia`로 제거하며 Metadata를 건드리지 않는다. Directory 제거 / Container Wipe(`--remove-existing-content`) / Baseline ID Hard-code는 금지다.

## Consequences

- Unavailable Clip이 있어도 Project는 항상 열리고 Healthy Clip 편집은 영향을 받지 않으며, 사용자는 위치를 잃지 않고 Replace 또는 Delete로 직접 복구한다.
- Replace가 Add / Delete / Undo / Redo / Cleanup / Recovery와 같은 Domain / History / Media Lifecycle 위에서 동작해 별도 Stash나 Cleanup 경로가 생기지 않는다.
- `ClipThumbnailPresentation`에 `.mediaUnavailable`이 추가되어 Thumbnail 실패와 구조적 Unavailable이 UI / Accessibility에서 구분된다.
- Corrupt / Unreadable 기존 파일의 사용자 표현은 이후 Decode Phase의 결정으로 남는다.

## Non-goals

- Decode-level Corrupt / Unreadable 구조적 분류, Playback / AVPlayer, Trim / Framing / Text / Sticker UI, Full Preview / Export, Storage-pressure Cleanup, Broad Photos 권한, Camera를 Replace Source로 사용, 여러 Unavailable Clip의 Batch Replace, Representative Thumbnail Wiring.

---

# ADR-041 — Camera Content Slot Ownership

**Date:** 2026-09-17
**Status:** Accepted

**Partially Supersedes:** ADR-030의 "Camera 최근 / 마지막 Clip Thumbnail 또는 Compact Project-content Access → 탭 시 해당 Project의 Clip Review / Editor" 문장(및 그 ADR-033 Note의 "단일 저장 Project 진입" 재해석), ADR-034 §6 "Camera Bottom-left Content Slot"의 "저장 Project 있음 → Project Representative Thumbnail 표시 + 탭 시 저장 Project Editor 진입" 항목과 이를 인용한 ADR-035 / ADR-036 / ADR-037 Cross-reference, ROADMAP Phase 5 Gate 요약, ARCHITECTURE의 동일 문장, PRODUCT / FEATURES / DESIGN의 "Camera 최근 / 마지막 Clip Thumbnail → 해당 Project의 Clip Review / Editor" 문구. ADR-034 §7(Representative Thumbnail Semantics), §1–§5의 Projects / Editor 결정, ADR-033의 Capture-first / Project-independent Recording은 변경하지 않으며 역사적 기록을 다시 쓰지 않는다.

## Context

Phase 5 STEP 14는 ADR-034 §6 문구대로 Camera 좌하단 Slot을 "저장 Project Representative + Editor 바로가기"로 구현했고 자동 검증까지 통과했으나, 실기기 확인 직전에 그 문구가 원래 제품 의도에서 벗어났음이 확인되었다. 원래 의도는 Camera Chrome의 두 Affordance를 분리하는 것이다: Upper-trailing `Projects`는 Project 접근, 좌하단 Compact Slot은 방금 촬영한 Direct Capture의 피드백(이후 Latest Capture Review). Phase 4가 실제로 구현한 것도 후자(`lastRecordingThumbnail`, Session-only, Non-navigable)다.

## Decision

1. **Camera Upper-trailing `Projects` Control이 Canonical Project 접근이다**(ADR-035 / ADR-036 `프로젝트` 화면 → `기존 프로젝트 불러오기` / `새 프로젝트 시작`).
2. **Camera 좌하단 Compact Content Slot은 Direct-capture 경험에 속한다.** 저장 Project 유무는 이 Slot의 의미를 바꾸지 않는다.
3. 현재 Session에 성공한 Direct Recording이 있으면 Slot은 그 **Latest-capture Thumbnail**(Phase 4 `RecordingCoordinator.lastThumbnail`: Photos 저장 성공 후에만 발행, Session-only, 영속 / Playable URL / PHAsset 참조 없음)을 보일 수 있다. 없으면 Phase 4의 빈 Content 표현을 유지한다.
4. Slot은 **저장 Project Representative가 되거나 ProjectEditor 바로가기가 되어서는 안 된다.** Project Clip의 Raw Playback도 아니다.
5. **Project Representative Thumbnail(ADR-034 §7, ARCHITECTURE §56)은 Project-oriented Surface에 속한다** — 현재 Projects 화면 Visual(DESIGN §11 "저장 Project 있음: Representative Visual Contract"). Camera Capture 피드백에는 쓰지 않는다.
6. **Latest Capture Review(미래):** Camera Thumbnail 탭이 마지막 촬영 Review를 열 수 있으나, 구현 전에 Playback / Media Lifetime / Permission Architecture를 별도 승인해야 한다. 현재 Phase 4는 저장 성공 후 `CGImage` 하나만 유지하며 Staging Movie는 Photos로 이동 / 제거되므로 재생 가능한 Local URL도 Durable Photos Asset 참조도 없다. 결정 Gate에서 최소한 다음을 비교한다 — **Option A** Session-local Review Media(Bounded Latest-capture Artifact 보존, Broad Photos Read 권한 없음, 명시적 Cleanup / 교체 Lifecycle, 추가 임시 저장 공간) vs **Option B** Photos Asset Identity(생성된 PHAsset Identity 보관 → 재생 시 Fetch, Photos Read-access / Permission Architecture 필요, 삭제 / Unavailable Asset 동작). 이 ADR은 A / B를 선택하지 않는다.
7. **Persistent Multi-item Mellow Gallery는 Latest Capture Review가 함의하지 않으며** 별도 Product / Architecture Decision(Durable Capture History / Ledger, Media Ownership / Reference Model, Photos Authorization Model, Disappearance / Reconciliation, Thumbnail Ownership / Cache, Navigation, Retention / Deletion Semantics)이 필요하다. Latest Capture Review를 조용히 Gallery로 확장하지 않는다.
8. **Direct Camera Recording은 ADR-033대로 Project-independent다.** Recording은 Photos에만 저장되고 Project를 만들거나 변형하지 않으며 Project Representative 선택에도 영향을 주지 않는다.

## Consequences

- STEP 14는 "Project Representative Thumbnail Infrastructure + Projects-surface Presentation"으로 재범위된다: `ProjectRepresentativeModel`(파생 / Cache, Schema 변경 없음)은 유지되고 Camera Slot 결합 코드는 제거된다.
- Camera 좌하단 Slot은 Phase 4 구현 그대로(Non-navigable, `Last recording preview` / `Project content, empty`) 남는다.
- Latest Capture Review와 Gallery는 각각 별도 Gate로 남는다.

## Non-goals

- Latest Capture Review 구현, Playback, Photos Read 권한 변경, Gallery, Camera Chrome 재설계, ADR-034 §7 Representative Semantics 변경.

---

# ADR-042 — Whole-Source Photos Video Eligibility (1.0 s ≤ Source Duration ≤ 5.0 s)

**Date:** 2026-09-17
**Status:** Accepted

**Revision (2026-09-17, 사용자 승인):** 최초 초안의 Canonical Invariant `0 < entire Photos source duration <= 5 seconds`는 같은 날 사용자 승인으로 **Imported 최소 길이 1.0초**를 포함한 `1.0s <= entire Photos source duration <= 5.0s`로 확정되었다. 이 ADR의 본문은 확정된 Invariant를 기준으로 기술하며 "Imported Clip 최소 길이" Pending은 해소되었다. 1.0초 최소는 승인된 Product Policy이고 현재 Phase 5 구현(`Phase5ReadyMediaValidator`는 `0 < d`만 검사, `testShortClipsAreAcceptedWithoutCameraMinimum`이 0.4초를 Ready로 고정)은 아직 이를 강제하지 않으므로 Phase 6 구현 요구사항이다.

**Revision 2 (2026-09-17, 사용자 승인 — Below-minimum Copy):** 1.0초 미만 Photos Source 거부의 Canonical 사용자 안내가 Title `영상이 너무 짧아요` / Message `1초 이상의 영상을 선택해주세요.`로 확정되었다. 5.0초 초과 안내(`영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`)는 변경 없이 유지되며 두 안내는 의미상 구분된다. 이 Revision은 ADR-042 아래 명시적으로 Pending이던 UX 세부 하나를 완료할 뿐 Canonical Duration Policy를 바꾸지 않으므로 새 ADR을 만들지 않는다. 이 Copy는 아직 Production 코드에 존재하지 않으며(1.0초 미만 Validator / Alert 미구현) Phase 6 구현 요구사항이다. 다중 선택에서 Invalid 항목의 요약 / 혼합 Session Presentation, Normalization-required 진입 / 진행 / 실패 / Retry, Storage 부족 Presentation, 부분 성공 정책, Duration 비교 Tolerance는 이 Revision이 결정하지 않는다.

**Revision 3 (2026-09-17, 사용자 승인 — Multi-selection Per-item Duration Filtering):** Select Clips / Editor Add의 다중 선택에서는 선택 항목마다 전체 Source Duration을 검사하여 **Duration-ineligible 항목(1.0초 미만 또는 5.0초 초과)만 제외**하고 나머지 Duration-eligible 항목(Phase-5-ready와 Normalization-required 항목이 함께 있을 수 있음)으로 계속 진행한다. 제외 항목은 Materialize / Normalize / Persist / Append / Commit되지 않고 Photos 원본은 변경되지 않으며, 다른 항목이 Duration-ineligible이라는 이유만으로 사용자에게 유효 항목의 재선택을 강요하지 않는다. 선택 결과 안내는 항목별 반복 Alert가 아니라 **하나의 통합 안내**다 — 1.0초 미만만 제외: `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` · 5.0초 초과만 제외: `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` · 둘 다 제외: `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.` (항목 개수 표현은 정하지 않는다). 모든 선택 항목이 Duration-ineligible이면 아무것도 추가하지 않고(Select Clips: Project 미생성, Add: 기존 Project 무변경) 해당 통합 안내를 표시한다. **Replace는 단일 후보 Operation**이므로 이 Filtering 대상이 아니며 후보가 Duration-ineligible이면 Revision 2의 개별 안내(`영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.` / `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`)로 거부하고 기존 Clip과 Media를 그대로 보존한다(제거 / 교체로 표현하지 않는다). Transactional 경계: Duration-ineligible 항목은 Preparation / Commit Transaction에 들어가기 전에 걸러지고, 남은 **Accepted Set**에는 승인된 Atomicity 계약이 그대로 적용된다 — Accepted Set 안의 어떤 항목이라도 Preparation / Normalization / Materialize / Persist에 실패하면 부분 Project Mutation 없이 전체를 되돌린다(ADR-020 / ADR-037). 이 결정은 Duration-ineligible Photos Video에만 적용되며 Malformed / Unreadable / Unsupported 등 다른 Invalid Media 범주의 다중 선택 처리, Normalization 진행 / 실패 / Retry Presentation, Storage 부족 Presentation은 결정하지 않는다. Phase 6 구현 요구사항이며 현재 Phase 5 코드(`ProjectCompositionCoordinator` / `ProjectClipAppendCoordinator`: 첫 Non-ready 항목에서 전체 거부, 1.0초 최소 미강제)는 이를 아직 구현하지 않는다.

**Supersedes:** ADR-029 "Imported Video" 항목 중 **"Photos Source Video의 전체 Duration은 제한하지 않으며 2분 또는 20분 Source도 선택할 수 있다"**와 **"사용자는 Source에서 원하는 구간을 자유롭게 선택 / Trim하며"**(Long-source Segment Selection) 및 ADR-029 Consequences의 "Phase 6 Import와 Phase 7 Trim은 길이 제한 없는 Source … Segment를 구현·검증한다". ADR-006(이미 ADR-029로 Superseded)의 "10초보다 긴 Source Video에서는 … 구간을 선택한다"는 역사 기록 그대로 두되 현재 정책이 아님을 이 ADR이 다시 확인한다.

**Partially Supersedes / Clarifies:**
- ADR-007 Consequences의 "Imported Clip의 Re-trim을 원본 Source 전체 범위까지 허용할지 … 별도 결정이 필요하다" — 이 Pending은 **해소**된다(원본 전체 범위 Re-trim 없음, Source Reference 없음). ADR-007의 Project-owned Media / Photos 원본 보존 / Working Media 정규화 방향은 유지한다.
- ADR-022의 "선택된 최대 10초(→5초) Segment를 기반으로 하는 Project-owned Working Media" 문구 — Working Media의 기준은 이제 **선택 Segment가 아니라 5초 이하 Source 전체**다. SDR / 30 fps / 1080p-class / Framing 영역 보존 / Crop bake-in 금지 / Validation 계약은 그대로 유지한다. ADR-022 Non-goals의 "Import Re-trim / Source Reference"는 이 ADR로 해소된다.
- ADR-024 / ARCHITECTURE 62절의 "Import Estimate는 선택된 최대 5초 Source Segment …" — Import Estimate의 기준 Source는 5초 이하 전체 Source다(정확한 Formula / Reserve는 여전히 Pending).
- ADR-030 Roadmap Ownership "Phase 6: Photos Import와 Segment Selection을 구현한다"와 ADR-032 "Source 길이를 제한하지 않으며 선택 Segment는 …" — Segment Selection / 무제한 Source 부분만 대체.
- ADR-034 §2 / ADR-037의 "Long-source Segment Selection … Phase 6 / 7 소유 유지" — 해당 항목은 어느 Phase도 소유하지 않는 **제외 기능**이 된다. Phase 5 Select-Clips Media Boundary(Phase-5-ready media만 Bootstrap, Non-ready는 Typed `requires import preparation`)는 변경하지 않는다.
- `RULES.md` 6절 "Imported Video Source는 길이 제한 없이 선택할 수 있다", `AGENTS.md` Confirmed MVP Guardrails "Imported source video duration is unrestricted", PRODUCT / FEATURES(F-MVP-018 / F-MVP-019 / F-MVP-028) / DESIGN(15–16절) / ARCHITECTURE(5, 25, 37, 38, 40절) / ROADMAP(Phase 6–7, §10 Traceability, Before Phase 6–7 Gate)의 동일 취지 문장은 이 ADR과 같은 작업에서 정렬한다.

**Explicitly Unchanged:** ADR-029 Direct Capture(1s–5s Preset, 기본 3s, Manual Early Stop)와 Canonical Invariant `0 < effectiveClipDuration <= 5 seconds`, ADR-033 Direct Capture 1.0초 최소(별개 규칙) / Photos Add-only 권한 / Capture ≠ Project, ADR-020 / ADR-021 / ADR-024 / ADR-026 / ADR-039 / ADR-040의 Media Commit / Deletion / Storage / Unavailable / Cleanup / Replace 계약, ADR-016 Non-destructive Editing, ADR-034 §2의 Phase 5 Media Boundary, ADR-037 Editor Add Acquisition, Phase 5 Select Clips / Editor Add의 기존 Multi-select Session과 Accepted Set에 대한 Atomic Project Mutation 안전성(Revision 3: Duration-ineligible 항목은 Transaction 전에 제외되고 Accepted Set 안의 실패는 부분 Mutation을 남기지 않는다), ADR-041의 Latest Capture Review / Gallery 별도 Gate.

## Context

Phase 5 STEP 6 / 11 / 13은 사용자가 선택한 Photos Video를 `Phase5ReadyMediaValidator`로 검사하여 Duration이 5초를 초과하면 `requires import preparation(.tooLong)`으로 거부하고(`영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`), Project-owned Media 생성 · Clip Metadata Commit · 부분 Project Mutation 없이 Photos 원본을 그대로 둔다. 이 동작은 Select Clips(`새 프로젝트 시작`), Editor Add(`+`), Replace(`클립 교체`) 세 경로가 같은 Validator를 공유하여 이미 동일하게 구현·검증되어 있다.

Phase 6 Planning / Decision Gate Audit(2026-09-17)은 기존 문서가 여전히 "무제한 길이 Source에서 최대 5초 Segment를 선택"하는 Import를 Phase 6 요구사항으로 두고 있음을 확인했다. 이 요구는 (1) Segment Selection Structural UX Gate, (2) 원본 전체 범위 Re-trim / Source Reference 유지 결정, (3) Photos Read 권한 없이 System PhotosPicker가 전체 원본 File을 Mellow 임시 영역으로 전송하는 구조와 "전체 원본 복제를 전제로 하지 않는" Storage Estimate 문구 사이의 모순, (4) Selected Segment 기반 Normalization / Estimate / Recovery 복잡도를 함께 끌고 온다.

사용자는 Mellow의 Mini Vlog 정체성(짧은 순간을 여러 Clip으로 잇기)에 맞춰 **Photos Video도 그 자체가 5초 이하인 짧은 순간만 받아들인다**는 Product / UX 결정을 승인했다. ROADMAP 4.4절 기준 Level 3(Product / UX Change)이다.

## Decision

### Photos Video Source Eligibility (Canonical)

`1.0s <= entire Photos source duration <= 5.0s`

- Mellow는 **선택한 Photos Video의 전체 Duration**이 위 조건(양 끝 포함)을 만족할 때만 그 Video를 받아들인다. 정확히 1.0초와 정확히 5.0초는 Eligible이다.
- 1.0초 미만 Photos Source(예: 0.4초, 0.8초, 1.0초 미만의 모든 양수 Duration)는 거부한다. 5.0초를 초과하는 Photos Source도 거부한다. 거부된 Source는 Materialize / Normalize / Persist / Append / Replace / 부분 Commit 어느 것도 하지 않는다.
- 5초를 초과하는 Photos Source는 Mellow Project에 Import하지 않는다. 임의의 긴 Source에서 최대 5초 Segment를 골라 가져오는 기능은 **제공하지 않는다**(V1 / MVP 범위 밖).
- Phase 6은 Long-source Segment Selection UI를 추가하지 않으며, 이후 긴 원본을 다시 탐색하기 위한 Source Reference(Photos Asset Identity, App-owned 원본 복사본 등)를 보관하지 않는다.
- Imported Clip의 Re-trim(Phase 7)은 **받아들여진 Project-owned Clip Media 범위 안**에서만 가능하며 그 밖으로 확장할 수 없다.
- Camera Duration Preset(1s–5s, 기본 3s)은 Photos Import와 무관하며 Import에 적용하지 않는다.
- 전체 Source가 1.0–5.0초 범위 안에 있으면 1.3초, 2.7초, 4.5초, 5.0초 같은 비정수 Duration도 유효하며 정수 Duration을 요구하지 않는다. 0초 이하 / 읽을 수 없음은 Invalid Media, 1.0초 미만은 Below-minimum 거부, 5.0초 초과는 Above-maximum 거부다.
- **Duration 경계는 정확히 1.0초와 5.0초다.** 제품 한계를 "1초 - 1 Frame", "5초 + 1 Frame" 또는 "약 1–5초"로 재정의하지 않는다. 현재 Phase 5 구현이 5초 상한에 적용하는 1-frame(1/30초) Encoder Quantization 허용치와 5초 Clamp는 구현 세부사항이며, 정확한 Product 경계에 대한 AVFoundation Timescale / Frame-duration 비교 정책은 Phase 6 Technical Gate에서 검증 항목으로 다루되 Product 경계를 다시 열지 않는다.
- Imported 최소 1.0초는 Direct Capture의 1.0초 최소(ADR-033)와 값이 같지만 별개의 규칙이다. Camera 정수 Preset은 Photos Import에 적용하지 않는다.
- Duration-eligible Source도 여전히 Readable / Playable이어야 하며 그 밖의 승인된 Eligibility / Preparation 규칙(Phase-5-ready 경계, Phase 6 Normalization)을 따른다.

### System PhotosPicker와 거부 시점

System PhotosPicker는 Mellow가 Duration으로 항목을 미리 숨기거나 비활성화할 수 없으므로 사용자가 5초 초과 Video를 탭할 수 있다. "선택할 수 없다"는 것은 **Mellow가 Metadata Validation 후 해당 항목을 거부하고 Materialize / Normalize / Persist / Append / Replace / Commit 어느 것도 하지 않는다**는 뜻이다. Photos Read 권한을 새로 요구하지 않으며 Picker 밖에서 Library를 조회하지 않는다.

5초 초과 항목이 거부되면:

- Project-owned Media를 만들지 않는다.
- Clip Metadata를 Commit하지 않는다.
- 부분 Project Mutation이 없다. 다중 선택(Select Clips / Add)에서는 Revision 3에 따라 Duration-ineligible 항목만 제외하고 Accepted Set으로 계속 진행하며 Accepted Set의 Commit은 Atomic이다(Revision 3 이전 초안의 "하나라도 초과면 전체 거부"는 대체되었다).
- Photos 원본은 변경되지 않는다.
- 5.0초 초과: 기존 안내 `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`를 그대로 사용한다. 1.0초 미만: Canonical 안내 `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`(Revision 2)를 사용한다. 두 안내는 별개의 의미이며 그 밖의 다른 Duration 정책이나 제3의 Duration Alert를 만들지 않는다.
- Select Clips / Add / Replace 세 경로가 같은 Canonical Rule과 같은 Copy를 따른다.

### Duration 규칙의 구분

| 구분 | 규칙 |
| --- | --- |
| Direct Camera Capture | ADR-029 / ADR-033: 선택 Preset(1–5s) 이하, 1.0초 이상, 자동 / 수동 정지 |
| Photos Source Eligibility | 이 ADR: `1.0s <= 전체 Source Duration <= 5.0s`(양 끝 포함), Preset 무관, 비정수 허용; 1.0초 미만 거부(`영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`), 5.0초 초과 거부(`영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`) |
| Phase-5-ready Media | ADR-034 §2: 위 Eligibility를 만족하고 Portrait / ≤1080p-class / ≤30 fps / SDR이어서 Normalization 없이 그대로 Materialize 가능 |
| Phase-6 Normalization-required Media | Eligibility(Duration)는 만족하지만 4K / High-resolution, HDR / Dolby Vision, >30 fps, Landscape / Presentation Transform 등으로 Phase-5-ready 경계를 벗어나는 Media — Phase 6이 정규화 |
| Invalid Media | 읽을 수 없음 / Video Track 없음 / Duration 0 이하 → 거부(Below-minimum / Above-maximum 거부와 구분) |
| Phase 7 Trim | Project-owned Clip Media 범위 안에서의 비파괴 Metadata Trim(`0 < trimDuration <= 5s`, `trimStart + trimDuration <= sourceDuration`) |

### Phase 6 Consequences

Phase 6은 더 이상 무제한 길이 Source, Long-source Segment Selection, Segment Selection Structural UX Gate, 원본 전체 범위 Re-trim Decision, 선택 Segment 기반 Normalization / Storage Estimate / Recovery를 소유하지 않는다.

Phase 6은 새로운 별도의 Multi-selection Import 기능을 만들지 않는다. 기존 Select Clips / Editor Add Multi-select Session에는 Revision 3의 Per-item Duration Filtering이 적용된다: Duration-ineligible 항목(1.0초 미만 / 5.0초 초과)은 Transaction 전에 제외되고 통합 안내로 알리며, Duration-eligible 항목(Phase-5-ready + Normalization-required 혼재 가능)은 Accepted Set으로 계속 진행한다. Accepted Set 안에서 하나라도 Preparation / Normalization / Materialize / Persist에 실패하면 Project는 무변경이다(Accepted Set Atomicity). Duration 외 Invalid Media 범주의 다중 선택 처리는 결정되지 않았다.

Phase 6은 **Duration Eligibility를 이미 통과한 5초 이하 Source 중 Phase-5-ready 경계를 벗어나는 Media**의 Normalization(1080p-class / 30 fps / SDR, Source Presentation Transform과 Framing 가능 영역 보존, Project Fill + Crop bake-in 금지)과 ADR-020 / ADR-021 / ADR-024 계약(Transactional Commit, Recovery, Project Validity, Active Usage, Storage Safety)의 Import 적용을 소유한다. Normalization은 Duration Eligibility 검사 **이후**에만 시작한다.

### Phase 5 / Phase 7 Consequences

- Phase 5(현재 구현): 5.0초 초과 `.tooLong` 거부, 세 경로의 공통 Validator / Copy, Photos 원본 불변은 그대로 유효하다. 현재 구현의 다중 선택은 첫 Non-ready 항목에서 선택 전체를 거부한다(Revision 3의 Per-item Filtering 미구현). **현재 Phase 5 구현은 1.0초 미만 Source를 거부하지 않고 받아들인다**(`Phase5ReadyMediaValidator`는 `0 < d`만 검사). 이 문서 작업은 코드를 바꾸지 않는다.
- Phase 6(구현 요구): 세 경로(Select Clips / Add / Replace)에 1.0초 미만 거부를 추가하고 Validation 결과가 최소한 Below-minimum / Above-maximum / Normalization 필요 / Invalid Media를 구분하게 한다. Below-minimum의 Canonical Copy는 `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`(Revision 2)이며 세 경로가 같은 Copy를 사용한다. 5.0초 초과 Copy(`영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`)는 그대로 유지한다. 다중 선택(Select Clips / Add)에서는 Revision 3에 따라 Duration-ineligible 항목만 제외하고 통합 안내(`짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` / `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` / `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`)를 한 번 표시하며 Accepted Set으로 계속 진행한다; 개별 안내는 단일 항목 선택과 Replace에 쓰인다.
- Phase 7: Imported Clip Trim은 Recorded Clip Trim과 같은 모델(`trimStart` / `trimDuration`, Project-owned Media 범위 안)이며 "원본 Source 전체 범위 Re-trim" 선택지는 존재하지 않는다. F-MVP-028의 Pending은 해소된다.

## Rationale

- Mini Vlog 정체성과 일관성: Camera가 5초 이하 순간만 만들듯 Photos에서도 5초 이하 순간만 가져온다.
- Segment Selection UI, Source Reference, 원본 전체 범위 Re-trim, Selected-segment Estimate / Recovery라는 큰 복잡도와 미결정 Gate를 제거하고 Phase 6을 Normalization / 안전성에 집중시킨다.
- Photos Read 권한 없이 System Picker만 쓰는 ADR-033 권한 모델과 모순 없이 구현 가능하다(전체 File 전송 뒤 Metadata 검사 → 거부).
- 5.0초 상한 거부는 Phase 5가 이미 구현·검증했고, 1.0초 최소는 Camera 규칙과 같은 값이라 사용자 모델이 단순하다.

## Consequences

### Benefits

- Phase 6 범위가 명확해지고 Structural UX Gate 하나와 Re-trim / Source Reference Decision Gate가 사라진다.
- Import Storage Estimate가 "5초 이하 전체 Source + Normalization Output"으로 단순해진다.
- Recorded / Imported Clip의 Trim 모델이 동일해진다(F-MVP-020).

### Costs

- 사용자는 긴 Photos Video를 Mellow에서 바로 쓸 수 없다(Photos 앱 등에서 미리 잘라 와야 한다). 이는 의도된 제품 제한이다.
- 5초 초과 항목을 Picker에서 미리 숨길 수 없어 거부가 사후에 일어난다.

## Still Pending (이 ADR이 확정하지 않음)

- Working Media Codec / Container
- 정확한 SDR Color Profile / Tagging과 Tone-mapping 구현 방법
- Low-resolution Source Upscaling Policy와 1080p-class Working Media의 정확한 Raster Dimension Rule
- Import Storage Estimate Formula와 Safety Reserve(5초 이하 전체 Source 기준)
- Import Durable Operation Identity / Recovery 깊이와 ADR-039 STEP 12B Orphan Predicate의 확장 방식
- 정확한 1.0초 / 5.0초 Product 경계에 대한 AVFoundation Duration 비교 정책(Timescale / Frame-duration 허용치의 검증 방식 — 구현 세부사항, Product 경계는 확정)
- Phase-5-ready 경계를 벗어나는 항목별 Normalization 처리 범위(예: Landscape이지만 그 밖의 Working Contract를 만족하는 Source의 Re-encode vs Transform 보존 Copy) — Landscape Source가 Phase 6 경로로 들어온다는 사실은 ADR-034 §2로 확정
- Phase 6 Normalization-required Media의 Import 진입 / 진행 / 실패 / Retry Presentation 구조와 Import Storage 부족 Presentation(Structural UX Gate — Segment Selection 아님; 1.0초 미만 개별 안내 Copy는 Revision 2, 다중 선택 Duration Filtering과 통합 안내는 Revision 3으로 확정되어 제외)
- Duration 외 Invalid Media(Malformed / Unreadable / Unsupported)가 다중 선택에 섞였을 때의 처리와 안내(Revision 3은 Duration-ineligible 항목만 다룬다)

## Non-goals

- Phase 6 Production 구현(이 ADR은 문서 정렬이며 Swift / Xcode 변경이 없고 Normalization 구현을 시작하지 않는다).
- Photos Read 권한 도입, PhotosPicker 대체, Camera Preset 변경, Direct Capture 규칙 변경.
- Phase 7 Trim UX / Phase 8 Preview / Phase 9 Export 결정.
