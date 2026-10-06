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

Source Rotation / Presentation Transform을 올바르게 해석하며 Codec Alignment용 Padding이 필요하더라도 사용자-visible Framing 영역을 임의로 제거하지 않는다. — **ADR-047 Revision 1(2026-10-01):** V1 Working Media는 정렬용 Padding을 쓰지 않으며 짝수 정렬 나머지는 전체 Frame의 축별 Parity Resample(변당 최대 1 출력 Pixel)로 처리한다.

Normalization standardizes media characteristics, but does not commit the user's project framing.

Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 Editing으로 유지하고 실제 Crop Region / Position / Scale 및 Transform / Order는 Preview / Export Composition에서 적용한다.

MVP Preview는 SDR이며 Export는 1080p / 30 fps / SDR을 기준으로 하고 HDR Export는 MVP에서 제공하지 않는다.

Project Output은 고정된 Orientation에 따라 Portrait 9:16은 1080 × 1920, Landscape 16:9는 1920 × 1080을 사용한다.

Preview / Export Color Handling은 가능한 한 동일한 Composition 정의를 사용하며 동일한 Project State의 Framing / Transform / SDR Interpretation을 일치시킨다.

HDR Source라는 이유로 Preview는 HDR이고 Export는 SDR인 이중 기본 Pipeline을 두지 않는다.

HDR → SDR 변환 결과는 Final Working Media 등록 전에 Validation하며 심각한 Highlight Clipping, 잘못된 색 변환 또는 Source Orientation 손상 등 명백한 변환 실패를 정상 Media로 간주하지 않는다.

Normalization 구현은 Apple Native Framework를 우선하며 정확한 Tone-mapping Algorithm, Apple API 조합과 Variable Frame Rate 변환 구현은 이 ADR에서 강제하지 않는다.

Working Media Codec / Container, 정확한 SDR Color Profile / Tagging, Low-resolution Upscaling Policy와 정확한 Raster Dimension Rule은 Pending이며 Phase 6 구현 전 Technical Gate에서 해결해야 한다.

이 Gate가 해결되기 전에는 실제 Normalization Pipeline 구현을 시작하지 않으며 저해상도 Source의 항상 Upscale 또는 절대 Upscale하지 않음을 임의로 선택하지 않는다. — **ADR-045(2026-09-18) / ADR-047(2026-09-18):** Codec / Container / SDR Tagging / Scale-down Rule은 ADR-045로, Upscaling Policy는 ADR-047로 확정되었다(절대 Upscale하지 않음, `scale = min(1.0, 1080 / width, 1920 / height)`, 짝수 내림).

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
- 이후 Photos Import는 Portrait / Landscape Source를 모두 허용하고 Source 길이를 제한하지 않으며 선택 Segment는 `0 < duration <= 5 seconds`를 만족한다. — **ADR-042 (2026-09-17):** "Source 길이를 제한하지 않으며 선택 Segment" 부분은 대체되었다. Photos Source는 전체 Duration이 `1.0s <= duration <= 5.0s`일 때만 받아들인다. — **ADR-043 (2026-09-18, Revision 1):** "Landscape Source 허용"은 대체되었다. V1 Photos Import는 Presentation Geometry(preferredTransform 적용 후)가 `presentationHeight > presentationWidth`인 Portrait Source만 받아들이며 Non-portrait(Landscape / Square)은 Preflight에서 제외한다.
- Portrait 9:16 Project에 삽입할 때 비율 불일치는 승인된 Fill + Crop과 조정 가능한 Framing을 사용한다. (ADR-043: Portrait Presentation Source의 비율 불일치에 한한다.)

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

> **Revision 1 (2026-10-02, 사용자 승인 — ADR-050 OD-14 (a)):** 아래 "Safe Atomic Project Replacement"의 5–9단계는 역사 기록이며, 현재 계약은 그 절 끝의 Revision 1(B 삽입과 A Metadata 삭제를 하나의 Save로 Commit, "failed replacement" 불변식 범위 축소)이다.

> **Clarification (ADR-046, 2026-09-18):** Mellow 직접 촬영의 출력 Format은 QuickTime `.mov` · H.264 · SDR · 1080p 30 fps로 고정되며 Capture Session 구성 시 H.264를 명시 요청하고 불가 시 안전 실패한다(HEVC / ProRes Fallback 없음). 이 ADR의 Recording / Photos Save / Single-Project 정책은 변경되지 않는다.

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

**Revision 1 (2026-10-02, 사용자 승인 — ADR-050 OD-14 (a), 단일 Save 대체):** 위 1–9의 원문은 역사 기록으로 보존하며, 5–9는 다음으로 대체된다.

5. Project B와 Clip Metadata를 만들고, 저장 전에 B의 모든 Media 존재와 Metadata 변환을 확인한다.
6. Lifecycle Gate 안에서 A가 여전히 대체 대상인지 다시 확인한 뒤, B의 삽입과 A Metadata(A의 Active와 Pending-deleted Clip Row 포함)의 삭제를 하나의 명시적 Save로 함께 Commit한다.
7. B의 완전한 저장 상태와 A Metadata의 부재를 확인한다.
8. 확인되면 B가 새 단일 저장 Project다.
9. 그 뒤에만 A의 App-managed Editing Media를 제거한다. 확인할 수 없거나 결과가 미확정이면 B와 A의 Media를 제거하지 않는다.

- A가 그 사이 없어졌거나 대체 대상이 아니면 Target 무효화로 처리하며 B만 생성하는 동작으로 바꾸지 않는다.
- Commit 전에 실패한 대체는 A를 그대로 보존한다.
- **불변식 범위 축소:** `A failed replacement must never destroy the last valid saved Project.`의 "failed replacement"는 결합 Save가 Commit되기 전의 실패로 한정된다. 결합 Save가 Commit된 뒤에는 A Metadata가 이미 없으므로, 그 뒤의 확인 실패에서 A의 Media를 보존하는 것만으로는 A를 되살릴 수 없다; B를 확인할 수 없거나 B가 쓸 수 없는 Row라면 다음 시작의 기존 Orphan Recovery가 Row 없는 A Directory를 제거하여 A를 잃을 수 있다. 이 잔여 경우는 승인과 함께 받아들여졌다.
- 하나의 Save 호출은 SQLite Transaction 하나나 강제 종료 · 전원 손실 Atomicity를 보장하지 않는다. 근거는 Exploratory 재구성 경계 측정(`docs/evidence/phase-06/adr-050d-combined-save-report.md`)뿐이다.
- 이 Revision은 ADR-050 050-D 전체, 독립 Read 구현 방법(OD-10), 새 안내 Copy, Startup Cleanup 개정을 승인하지 않는다; 확인 방법과 확인 실패의 Presentation은 Pending이다.
- **구현 상태(2026-10-02):** Repository API `ProjectRepository.replaceProject(previousID:with:)`가 구현 · Test되었으나 어떤 Coordinator / UI에도 연결되지 않았다. 현재 Production Select Clips 경로(`ProjectCompositionCoordinator.compose`)는 여전히 두 Save(`create` → `deleteProject`)를 쓴다; 연결은 Pending이다. (2026-10-05 갱신: Select Clips `.replacingSaved`는 `replaceProject`에 연결되었고 두 Save Production 분기는 제거되었다 — ADR-050 050-D D8.5b.)

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

**Clarification (ADR-043 + Revision 1, 2026-09-18):** §2의 "Phase 6 / 7 소유 유지" 목록 중 Non-portrait Presentation Source(Landscape / Square, `presentationHeight > presentationWidth` 불만족)의 Crop / Framing / Transform 준비는 어느 Phase도 소유하지 않는다 — Non-portrait은 V1 미지원 입력으로 Preflight에서 Per-item 제외된다(Phase 6 구현 요구). Portrait 요구 자체(Non-portrait = Non-ready)는 유지된다.

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
- Phase-5-ready 규칙은 ADR-034 §2 / STEP 6 계약을 그대로 재사용한다(0 < duration ≤ 5s, Portrait, ≤1080p-class, ≤30 fps, SDR, Audio 선택; **ADR-042 이후** Import Eligibility 하한은 1.0초이며 1.0초 미만 거부는 Phase 6 구현 요구 — 현재 Validator는 미강제). Non-ready Media는 기존 `requires import preparation` UX를 받으며 조용한 Trim / Crop / Transcode / Normalize / HDR 변환 / Frame-rate 변경을 하지 않는다. Long-source Segment Selection, 4K → 1080p, HDR → SDR, Frame-rate Normalization, Import 편집 준비는 Phase 6 소유로 유지되며 Phase 5가 완전한 Photos Import를 구현했다고 주장하지 않는다. (**ADR-042:** Long-source Segment Selection은 이후 제외되었고 5초 초과 Source의 `.tooLong` 거부가 최종 동작이다; **ADR-043 Revision 1:** Non-portrait Presentation Source(Landscape / Square)의 준비도 제외되어 Preflight Per-item 제외가 최종 동작이다; 나머지 Phase 6 소유 항목은 유지.)
- Append는 현재 Persisted Project P에 대한 **APPEND** Operation이다: 대체 Project 생성, Safe Atomic Replacement, 또 다른 Current Project 생성, 기존 Clip 삭제, 순서 Reset, Orientation 변경을 하지 않는다. 새 Clip은 현재 논리적 마지막 Clip 뒤에 Picker 선택 순서로 붙는다(`A → B → C` + `D → E` = `A → B → C → D → E`).
- Transaction 안전성은 STEP 6와 같은 원칙을 따른다: Workspace → Validate → Storage Admission → Materialize → Appended Project State 구성 → Persist → Read-back Verify → Cleanup. Commit 전 실패 시 P는 변경되지 않으며, Persistence 실패 시 부분 Append된 논리 Project를 노출하지 않고, Photos 원본은 건드리지 않는다. — **ADR-050 분류 규칙 승인(2026-10-02)에 따른 개정:** Save가 성공한 뒤의 Read-back 실패 · 불일치는 Commit 전 실패가 아니라 "Commit됨 · 확인 안 됨"이며 참조 가능 Media를 보존하고 Rollback하지 않는다; Save 오류는 다시 읽은 상태로 분류한다(ADR-050 050-D D8.0). 순수 분류기만 구현되었고 현재 Production 코드는 아직 이 문구의 이전 동작이며 연결은 Pending이다.
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

`Resolved by ADR-022`, `Resolved by ADR-023`, `Resolved by ADR-024`, `Resolved by ADR-025`, `Resolved by ADR-026`, `Resolved by ADR-028`, `Resolved by ADR-042`, `Resolved by ADR-043`, `Resolved by ADR-044`, `Resolved by ADR-045` 또는 `Resolved by ADR-046`으로 표시된 Policy / UX Structure는 확정되었으며 나머지 Pending Technical Detail은 임의로 구현 기준을 결정하지 않는다.

### HDR and Color

- HDR Source Import 정책 — Resolved by ADR-022: HDR Source Import 허용.
- Dolby Vision 처리 — High-level Policy Resolved by ADR-022: Source Import를 허용하고 SDR Working Media로 정규화하며 구체적인 Tone-mapping 구현은 Pending.
- HDR 유지 또는 SDR 변환 — Resolved by ADR-022: SDR Working Media로 변환하며 HDR Metadata 보존을 MVP requirement로 하지 않음.
- Export Color Space — MVP Export HDR vs SDR 방향은 Resolved by ADR-022: SDR이며 정확한 SDR Color Profile / Tagging은 Pending.

### SDR and Working Media Technical Details

- Working Media Codec — Pending, Before Phase 6.
- Working Media Container — Pending, Before Phase 6.
- 정확한 SDR Color Profile / Tagging — Pending, Before Phase 6.
- Low-resolution Source Upscaling Policy — Resolved by ADR-047(2026-09-18): 절대 Upscale하지 않음; Envelope 안의 Source는 Presentation 크기 유지(짝수 내림만).
- 1080p-class Working Media의 정확한 Raster Dimension Rule — Resolved by ADR-045(Scale-down Bounding Box) + ADR-047(2026-09-18): `scale = min(1.0, 1080 / width, 1920 / height)`, Aspect 보존, 각 변 짝수 내림, 최소 출력 크기 없음. Render Geometry는 ADR-047 Revision 1(2026-10-01): Crop · Padding 없이 전체 Frame을 짝수 Raster에 Render하고 정렬 나머지는 변당 최대 1 출력 Pixel의 축별 Parity Resample로 처리한다.
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
- 정확한 1.0초 / 5.0초 경계의 AVFoundation Duration 비교 정책 — ~~Pending 구현 세부사항, Phase 6 Technical Gate(Product 경계는 확정).~~ Resolved by ADR-042 + ADR-045 §1 / §11: Source Eligibility는 정확히 `1.0 s ≤ source duration ≤ 5.0 s`(양 끝 포함)이며 정확한 Rational(`MediaTime`) 비교로 판정하고 Frame 기반 허용치를 적용하지 않는다(ADR-045 §7의 출력 Duration 허용 범위 `source <= output <= source + 1/30 s`는 Normalization 출력 Validation 규칙이며 Source Eligibility와 별개다).
- 1.0초 미만 Photos Source 거부의 사용자 안내 — Resolved by ADR-042 Revision 2(2026-09-17): `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`.
- 다중 선택의 Duration-ineligible 항목 처리와 통합 안내 — Resolved by ADR-042 Revision 3(2026-09-17): Per-item Filtering, `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` / `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` / `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`, Accepted Set Atomicity, Replace는 단일 후보.
- Landscape / Square(Non-portrait) Photos Source 처리 — Resolved by ADR-043 + Revision 1(2026-09-18): V1 미지원, Presentation Geometry `presentationHeight > presentationWidth` 기준 Preflight Per-item 제외, Non-portrait만 제외 시 `일부 영상이 제외되었어요` / `세로 형식이 아닌 영상은 추가할 수 없어요.` / 단일 후보 · Replace `지원하지 않는 영상이에요` / `세로 영상을 선택해주세요.` / 복합 사유는 기존 통합 안내; Square Pending 없음.
- Capture Codec 불변조건과 Photos Import Codec 경계 — Resolved by ADR-046(2026-09-18): Mellow 촬영 = QuickTime `.mov` · H.264 · SDR(명시 요청, Fallback 없음, 불가 시 안전 실패); Import는 H.264(`avc1` / `avc3`) · HEVC(`hvc1` / `hev1`) Family만, ProRes / ProRes RAW / MJPEG / 기타 / Unknown은 Preflight Unsupported(기존 Invalid / Unsupported Copy, Codec별 문구 없음); Preflight 순서 Duration → Invalid → Container → **Codec** → Orientation → Normalization. *(ADR-048(2026-09-30): Orientation 다음에 Working-raster Feasibility → Audio Facts 단계가 삽입되고 Normalization 사유 끝에 Audio Transcode가 추가되었다.)* ~~Production 구현(Step 1 Classifier, Capture Enforcement)은 미완.~~ 구현 상태(2026-10-02): Classifier Codec Family 판정 `efbcff9`(모든 Format Description 판정은 `da1f337`), Capture Enforcement `bfc4451`; Import 흐름 연결은 미구현.
- Phase 6 Working Media Technical Gate(Codec / Container 출력, SDR Tagging, Tone-mapping 메커니즘, Raster Scale-down, Cancellation Cleanup, HDR → SDR 기기 검증) — Resolved by ADR-045(2026-09-18): QuickTime H.264 High 8-bit 709 / 709 / 709, 1080p-class Portrait Bounding Box, ≤ 30 fps, Identity Transform, AAC Passthrough; Tone-mapping = AVFoundation Compositor(Composition 709); `.current` 획득 전제; AVE 단독 비신호; Contract는 Normalization 출력만; Duration +1 Frame 허용; Evidence Branch `spike/06-media-technical-gate` @ `04d83612`. **Pending 유지:** Upscaling Policy, Storage Formula / Reserve, Recovery 깊이, Retry / Progress 메커니즘. Phase 6 Production 구현은 미완. 구현 상태(2026-10-02): Working Media Contract · Plan(`75c2cb9`)과 Normalizer · Cadence Scheduler · Output Validator(`da1f337`) 구성요소 구현 · 검증; 사용자 Import 흐름 · Storage · Progress · Retry 연결은 미구현. — **ADR-048(2026-09-30):** AAC Passthrough는 AAC Source에만 적용되고 non-AAC는 AAC-LC 변환, Cadence Fallback과 Working-raster Feasibility 추가. — **ADR-049(2026-10-01):** Tone-mapping = 내장 Compositor는 Full-aperture Source에 유지; Non-full Clean Aperture는 SDR Rec.709만 Geometry 전용 정규화, 그 밖은 Preflight 거부.
- Photos Import Source Container Eligibility — Resolved by ADR-044(2026-09-18): 실제 Container가 QuickTime Movie인 Source만 V1 Import 허용(H.264 / HEVC 모두), MP4 / ISO BMFF / 기타 / Unknown Container는 신뢰성 있는 Inspection(확장자 아님) 기반 Preflight Per-item 제외(기존 Invalid / Unsupported 범주, `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.` / 복합 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`), Remux / Container 변환 없음; 단일 후보 / Replace의 Unsupported-media 안내 — Resolved by ADR-044 Revision 1(2026-09-18): `영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.`, Replace 후보 거부 + 기존 Clip · Media · Metadata · 순서 · Slot 보존.
- Phase 6 Normalization-required Import의 진입 / 진행 / 실패 / Retry Presentation, Storage 부족 Presentation, Preflight 판별 Invalid Media Filtering, 통합 안내 우선순위, Accepted Set 경계 — Resolved by ADR-042 Revision 4(2026-09-17): 자동 진입 + Blocking Preparation Sheet `영상을 준비하고 있어요` / `잠시만 기다려주세요.` / `2/5` Progress / `취소`, Runtime 실패 `영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.` / `다시 시도` / `취소`, Storage 부족 `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`, Invalid 제외 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`, 복합 제외 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`. Phase 6 Structural UX Gate 해결.
- Phase 6 Preparation의 Export Session / Cancellation API, Aggregate Progress 계산, Retry Source-handle 메커니즘, Filesystem Free-space API / Race 처리 — Pending, Phase 6 Technical Gate(구현 세부사항). (2026-10-06 갱신: D7b 참조 5항 — Aggregate Progress 계산이 결정되었다.)
- Import Durable Operation Identity / Recovery 깊이와 ADR-039 STEP 12B Orphan Predicate 확장 — Resolved by ADR-047(2026-09-18): Process 종료 후 Resume 없음, Durable Resumable Operation ID 없음, Workspace UUID는 Ephemeral, Repository Row가 Commit; 버려진 Workspace / 부분 출력은 기존 STEP 12B 시작 시 Sweep으로 정리(Predicate 확장 없음), 사용자는 Import를 다시 시작한다.
- Phase 6 Working Media Raster / Interrupted-Normalization Recovery — Resolved by ADR-047(2026-09-18): No Upscaling + No Resume(위 두 항목 참조).
- non-AAC Source Audio 처리와 Working Media Audio 설정 — Resolved by ADR-048(2026-09-30): Audio 없음 → 출력 Audio 없음(무음 합성 없음); AAC → Passthrough(Normalization 사유 아님); 알려진 non-AAC → 새 사유 `audioTranscode`(순서 HDR → Frame Rate → Raster → Audio Transcode, 유일한 사유 가능)로 AAC-LC 48 kHz, Mono 96 kbps / 2채널 이상 Stereo 128 kbps(2채널 초과는 명시적 Stereo Downmix); 알 수 없거나 모순된 Audio Facts → Preflight 기존 Invalid / Unsupported 범주 거부. Export Audio 결정 아님.
- 짝수 정렬 후 Portrait이 아닌 Working Raster(근사 정사각형 Portrait Source) — Resolved by ADR-048(2026-09-30): Orientation 판정은 그대로, Orientation 다음 · Normalization 사유 이전의 Working-raster Feasibility 단계가 ADR-047 알고리즘 결과 `outputHeight > outputWidth`를 요구하고 실패 시(예: 1080×1081 → 1080×1080) Preflight 기존 Invalid / Unsupported 범주로 거부; Crop / Pad / 늘리기 / 여백 우회 없음, 새 안내 없음.
- `minFrameDuration` 부재 시 출력 Frame Duration — Resolved by ADR-048(2026-09-30): 유효한 `minFrameDuration` → `max(minFrameDuration, 1/30)`; 없으면 유한하고 0보다 큰 Nominal Frame Rate로 `max(1 / nominalFrameRate, 1/30)`; 둘 다 없으면 `1/30`. 새 Normalization 사유 없음, 거부 사유 아님, 30 fps 초과 출력 없음.
- Non-full Clean Aperture Source의 정규화와 Tone-mapping 경로 — Resolved by ADR-049(2026-10-01): 사유 없음 → Fast-path Copy(Aperture 무관); 사유 + Full Aperture → ADR-045 §4 내장 Compositor; 사유 + Non-full + 신뢰성 있는 SDR Rec.709 → Geometry 전용 정규화(Crop · Padding 없음); 사유 + Non-full + HDR / Wide-color / SDR 미증명 → Preflight 기존 Invalid / Unsupported 범주 거부(새 안내 없음). Custom Compositor Pre-conversion은 Tone-mapping으로 승인되지 않음. ~~Production 구현은 미완.~~ 구성요소 구현 · 검증(`da1f337`, 2026-10-02), 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현.
- 여러 Video Format Description의 합의와 Normalization Transform Eligibility — Resolved by ADR-049 Revision 1(2026-10-01): 사유가 있는 항목만 모든 관련 Description의 Aperture 상태 · Geometry · (Case C에서) SDR Rec.709 증명이 합의해야 하고 Preferred Transform이 Translation · 1/4 회전 · Mirroring · 유한하고 0이 아닌 축 정렬 Scale로만 이루어져야 하며(Shear · 임의 각도 회전 · 비가역 · 비유한 거부), 실패 시 기존 Invalid / Unsupported 범주로 거부(새 안내 없음); 사유 없는 항목은 Fast Path 유지. ~~Production 구현은 미완.~~ 구성요소 구현 · 검증(`da1f337`, 2026-10-02), 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현.
- Source Frame Timing이 출력 Grid와 맞지 않을 때의 정규화 Video Sample Timing — Resolved by ADR-048 Revision 1(2026-10-01): `t_k = k × outputFrameDuration`(`t_k < E`)의 모든 Target에 정확히 한 Frame, Target 이하의 가장 최근 Rendering Frame 선택 · 새 Frame이 없으면 유지 · 미래 Frame / 보간 없음, Session은 `E`에서 종료, Audio 불변, 엄격한 Cadence Validator 유지. ~~Production 구현은 미완.~~ 구성요소 구현 · 검증(`da1f337`, 2026-10-02), 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현.
- 정규화 출력 Cadence의 검증 기준과 앞쪽 빈 Video 구간 — Resolved by ADR-048 Revision 2(2026-10-02): 정확한 Rational Presentation-time Grid(0 시작, 모든 인접 간격 정확히 `d`, `E`에서 끝나는 짧은 마지막 Sample 허용)가 권위 있는 증거이며 `nominalFrameRate` / `sampleCount / duration` 같은 평균 Rate는 진단용일 뿐 거부 조건이 아니다; 0 이하에 실제 Frame이 없으면 Typed Runtime 실패(검은 Lead-in · 미래 Frame 당김 없음, 새 Preflight 범주 · Copy 없음). ~~Production 구현은 미완.~~ 구성요소 구현 · 검증(`da1f337`, 2026-10-02), 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현.

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
- 정확한 Safety Reserve Bytes — Pending, 관련 Owning Phase Technical Gate. — **ADR-050 부분 승인(2026-10-02):** Import Reserve = 268,435,456 B(256 MiB) Accepted; Export Reserve는 Pending.
- Recording Estimate Formula, Capture Codec / Bitrate 상수와 Finalization Overhead — Pending, Before Phase 4.
- Import Estimate Formula와 Temporary / Recovery-safe Overlap Multiplier — Pending, Before Phase 6(ADR-042: 기준 Source는 5초 이하 전체 Source이며 Picker Transient 복사본을 Peak에 포함). — **ADR-050 부분 승인(2026-10-02):** Import 계산 정책(050-A Output Estimate, 050-B Metadata Estimate, 050-C Volume별 계산 · 256 MiB Import Reserve · Fail-closed)은 Accepted이며 Step 5B 순수 `ImportStorageEstimator`로 구현되었다(연결 없음); 검사 경계 연결, Phase 5 Admission 변경, Integration Gate는 Pending.
- Export Snapshot 기반 Estimate Formula와 Temporary Multiplier — Pending, Before Phase 9.
- Storage Warning 기준과 Low-storage UI Presentation — Pending, Owning UX Gate(Phase 6 Import Storage 부족 Presentation은 ADR-042 Revision 4로 확정: `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`; Recording / Export Presentation은 여전히 Pending).

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
8. **Shared Operation Serialization.** Cleanup ↔ Project Composition / Safe Atomic Replacement ↔ Editor Project Load는 하나의 실제 Async Critical Section(`ProjectLifecycleOperationGate`: Main-Actor FIFO Hand-off Lock, Suspension을 가로질러 유지)으로 직렬화한다. Boolean Flag(TOCTOU) 금지. Camera Recording과 Editor Add(Live Session 안이라 Cleanup 불가)는 Gate를 잡지 않는다. Safe Atomic Replacement 자체와 Replacement의 A 정리 소유권은 바꾸지 않는다 — 겹침만 막는다. (2026-10-02 갱신, 사용자 승인 — ADR-050 직렬화 전제조건: Home의 Project 삭제(`HomeModel.delete(_:)`, `async`; Alert는 표시 중인 Project를 넘기고 `confirmDeletion`은 이를 위임)와 Editor Add / Replace의 Target 재확인 → Materialize → Repository Commit(Commit하지 못한 파일 제거 포함 — 2026-10-02 갱신: Save 시도 전 실패에 한함, D8.0 "Save 뒤 Media 보존 수리")이 같은 `ProjectLifecycleOperationGate`를 잡는다; Picker 전송, 예약 공간 확인과 검증은 Gate 밖에서 실행되며 Workspace는 기존 Live-workspace Registry가 보호한다. Camera Recording은 여전히 Gate를 잡지 않으며, Editor의 동기 편집 Commit(Reorder · Delete · Undo · Redo)도 Gate 밖에 남는다.) (2026-10-05 갱신: Editor의 Reorder · Delete · Undo · Redo도 같은 Gate를 잡는다 — ADR-050 050-D D8.5c; Gate 없는 동기 예외는 없다.)
9. **Media Consumer Gate.** 현재 유일한 Production Media Reader는 `ClipThumbnailService`이며 In-flight Generation을 관찰하는 `awaitIdle(for:timeout:)`로 Cleanup에 참여한다. 대기는 Bounded이며(기본 3초, Policy) Timeout이면 파일 보존 + Row Pending + Log + 다음 경계 Retry, 사용자 Error 없음. Ready Cached Thumbnail은 Active Consumer가 아니다(Cache Purge 불필요). Request Ordering / Task Group 동작은 바꾸지 않는다. **이후 Playback / Export 등 Project Media를 읽는 모든 Consumer는 같은 Protection Contract(`ProjectMediaConsumerGating`)에 참여해야 하며, Cleanup은 알려주지 않은 Reader를 "없음"으로 가정하지 않는다.**
10. **Ownership.** `ProjectMediaCleanupCoordinator`(Core/Projects)는 Cross-resource Lifecycle Orchestration만 소유한다 — `reconcile(projectID:)` / `reconcileAll()`, Eligibility 판정, Consumer 대기, File 삭제 → 부재 검증 → Finalize, Clip별 실패 격리, Idempotent Retry, Nonfatal Log. Repository = Metadata, `ProjectMediaStore` = Filesystem(`removeCommittedMedia(_:projectID:clipID:)`: Canonical 완전 일치만, Missing = Success, 삭제 실패 / 잔존은 Throw). Coordinator는 Editor History, Repository 구현, Photos, UI Alert, Camera, Orphan Scan을 소유하지 않는다.
11. **Cleanup은 Maintenance이지 편집이 아니다.** `finalizeDeletedClip`은 InMemory / SwiftData 모두 Project `updatedAt`을 올리지 않아 Recent / 저장 Project Recency가 움직이지 않는다. Active Clip 거부, Save Rollback, 실패 시 Retryable Pending Row는 유지하며 이미 Finalize된 Row / 없는 Row는 Idempotent 성공이다.
12. **Per-Clip 실패 격리.** 여러 Pending Clip은 한 Project Pass 안에서 독립적으로 처리한다 — 한 Clip의 File 삭제 실패는 다른 Clip의 성공을 되돌리지 않고 다음 Clip으로 진행한다. Latest-only 동작 없음.
13. **No User-facing Cleanup Error.** 실패는 Pending 보존 + 재시도 + Diagnostic Log뿐이다(Popup / Snackbar / Editor Alert 없음).
14. **STEP 12B 명시적 유보.** Row 없는 Media 파일 Scan, Project Row 없는 Project Directory, 버려진 `ProjectWorkspace`, Root 광역 Sweep은 이 ADR의 범위가 아니며 12A가 실기기에서 검증된 뒤 별도 Slice(ADR-020 Confirmed Orphan Contract 적용)로 다룬다.

**Implementation Note (Phase 5 STEP 12B, 2026-09-16 — Startup Orphan Media + Workspace Recovery):** 위 14항의 유보 Slice는 새 ADR 없이 이 ADR의 구현으로 확정되었다(Design Review 승인 결정 A / B 포함).

**OD-12 최소 빈 Store 보호(2026-10-06, 소유자 결정 — 이 범위에 한정, 구현):** 기존 직렬화된 Startup Recovery Pass의 첫 Gate Section에서 Persisted Project Row와 Canonical Project Directory를 함께 읽는다. Row 읽기가 성공했고 Row가 0개인데 Canonical Project Directory가 1개 이상이면 그 Pass는 모든 Project Directory에 대해 Orphan Project Directory 제거와 Project Directory 안의 참조 없는 Media 제거를 둘 다 건너뛴다(Directory만 건너뛰는 것으로는 부족). Row를 읽을 수 없으면 모름으로 보고 같은 방식으로 건너뛰며 부재로 추론하지 않는다. Canonical 경로 · Symlink 규칙은 그대로이고 버려진 Workspace Sweep은 별도이며 바뀌지 않는다. 이 Guard는 Store Identity를 확립하지 않고 Metadata를 복구하지 않으며 부분적인 Store 손실(일부 Row만 사라짐)이나 비어 있지 않은 교체 Store를 막지 않는다; UI · 자동 복원 · Marker · Schema 변경은 없다. 그 결과 Row가 하나도 없는 Store에서는 빈 Project Folder도 남을 수 있으며 예외를 두지 않는다. 이 Guard는 Store가 비었을 때 Project Media를 보호하는 장치이며 D7a의 미해결 후보 보존 정책(Process 수명 한정)과 별개다. 구현: `ProjectStartupRecoveryCoordinator.recoverOrphans()`(`recentProjects()`로 Row를 읽고 실패는 모름; 보고 `skippedByEmptyStoreGuard` · `skippedRowsUnreadable`). 더 넓은 Startup Recovery 개정, Store Identity Marker(D8.7 (ii)), OD-13, 050-E는 해결되지 않았다.

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
- **STEP 11 즉시 Rollback은 그대로.** In-process Add 실패는 여전히 즉시 자기 파일을 지운다; 12B는 Process가 Rollback / Commit 전에 죽은 경우만 다룬다. (2026-10-02 갱신: Save 시도 뒤의 실패에서는 새 파일을 지우지 않고 보존한다 — ADR-050 050-D D8.0 "Save 뒤 Media 보존 수리"; Save 시도 전 실패만 기존대로 정리한다.) Safe Atomic Replacement의 Live A 제거도 `compose` 소유 그대로이며 12B는 이후 시작에서 남은 Directory만 회수한다.
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
6. **Replace Identity = Model B(새 Clip).** `A B(unavailable) C` → Replace → `A D C`. `VlogProject.replaceClip(id:with:)`가 하나의 Domain Mutation으로 B를 기존 Deletion 규칙(Anchor 기록, Metadata / Media 불변)으로 Durable Pending에 옮기고 D(`id != B.id`, 같은 `projectID`, `sourceKind = .imported`, `sourceDuration = trimDuration = Source Duration`, `trimStart = 0`, `framing = nil`, Canonical `Projects/<pid>/Media/<D>.mov`)를 B의 정확한 Index에 넣은 뒤 `sortOrder`를 0…n-1로 정규화한다. 다른 Active Identity / 순서 / 기존 Pending Clip은 변하지 않는다. 잘못된 oldID, 다른 Project, Identity 충돌(oldID 포함), Pending 상태의 Replacement는 무변경으로 거부한다. 근거: Clip UUID는 Project-owned Canonical Media Path와 강하게 묶여 있어 새 UUID를 써야 기존 History / Pending Retention / 12A / 12B / Thumbnail Identity가 숨은 Media Stash나 Same-path 충돌 없이 그대로 동작한다. — **Revision(2026-10-06, 소유자 결정 — Duration 배정만):** 위 `sourceDuration = trimDuration = Source Duration`은 Replacement D가 Fast-path 파일(Source 자체)일 때만 적용한다. D가 정규화된 항목이면 ADR-045 §7 아래 "정규화 항목의 Clip Metadata" 결정을 따른다: `sourceDuration` = 검증된 정규화 출력의 실제 Duration, `trimStart = 0`, `trimDuration` = 검증된 Accepted Source Duration(1.0–5.0초); 출력은 Trim 전체를 덮어야 하고 허용된 추가 출력은 Trim 밖에 남으며 Clamp나 Trim 연장은 없다. 이 Revision은 Duration 배정만 바꾸며 새 Identity(Model B), 같은 `projectID`, `sourceKind = .imported`, `framing = nil`, Canonical 경로, B의 정확한 Index와 Durable Pending 이동, `sortOrder` 정규화, 거부 규칙, §7 History, §8 Media Lifetime, §9 Atomicity(§9에 이미 적힌 ADR-050 D8.0 개정 포함; Save 시도 전 · `priorConfirmed` 정리 방식은 ADR-050 050-D D7a가 정한다)는 이 Revision으로 바뀌지 않는다.
7. **Replace는 일반 Editor History에 참여한다(ADR-038).** 성공 1회 = `.replace` Entry 1개(`클립 교체`), Autosave + Read-back 1회, Selection B → D. Undo: `A B(unavailable) C`, D는 Durable Pending(파일 유지), Selection B, Total은 B Metadata로 복귀, Picker / 복사 없음. Redo: 같은 D UUID / Path / 파일, B Pending, Selection D, Thumbnail Cache 재사용. Undo 뒤 새 편집은 Redo를 버리고 D는 Session 동안 Pending으로 남는다. 시간순 LIFO만 있으며 선택적 Replace Undo는 없다.
8. **Media Lifetime = Pending Retention + STEP 12A / 12B.** Session 중에는 어느 쪽 파일도 지우지 않는다. Editor 종료 시 Final State가 Replace면 12A가 B(Pending + 파일 없음)의 Metadata만 Finalize하고 D는 Active로 남는다; Undo된 채 종료면 12A가 D 파일 삭제 → Finalize하고 B는 Active Unavailable로 남는다. D Materialize 뒤 Commit 전에 Process가 죽으면 기존 12B가 Row 없는 D 파일을 회수한다. 새 Cleanup 메커니즘 없음.
9. **실패 Atomicity.** Picker Cancel / Transfer 실패 / Invalid / Preparation 필요 / Storage 부족 / Materialize 실패 / Domain 거부 / Persist 실패 / Read-back 불일치 — 모든 경우 B는 정확히 이전 그대로(위치 / Metadata / Total / Selection), History 무변경, Repository Update 0회, 기존 Media 불변이며 이 Operation이 만든 D 파일만 즉시 제거한다. Generic 실패 Copy: `클립을 교체하지 못했어요` / `다시 시도해주세요. 프로젝트는 그대로 있어요.` / `확인`. — **ADR-050 분류 규칙 승인(2026-10-02)에 따른 개정:** Save가 성공한 뒤의 Read-back 실패 · 불일치는 Commit 전 실패가 아니라 "Commit됨 · 확인 안 됨"이며 참조 가능 Media를 보존하고 Rollback하지 않는다; Save 오류는 다시 읽은 상태로 분류한다(ADR-050 050-D D8.0). 순수 분류기만 구현되었고 현재 Production 코드는 아직 이 문구의 이전 동작이며 연결은 Pending이다.
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

**Revision 3 (2026-09-17, 사용자 승인 — Multi-selection Per-item Duration Filtering):** Select Clips / Editor Add의 다중 선택에서는 선택 항목마다 전체 Source Duration을 검사하여 **Duration-ineligible 항목(1.0초 미만 또는 5.0초 초과)만 제외**하고 나머지 Duration-eligible 항목(Phase-5-ready와 Normalization-required 항목이 함께 있을 수 있음)으로 계속 진행한다. 제외 항목은 Materialize / Normalize / Persist / Append / Commit되지 않고 Photos 원본은 변경되지 않으며, 다른 항목이 Duration-ineligible이라는 이유만으로 사용자에게 유효 항목의 재선택을 강요하지 않는다. 선택 결과 안내는 항목별 반복 Alert가 아니라 **하나의 통합 안내**다 — 1.0초 미만만 제외: `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` · 5.0초 초과만 제외: `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` · 둘 다 제외: `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.` (항목 개수 표현은 정하지 않는다). 모든 선택 항목이 Duration-ineligible이면 아무것도 추가하지 않고(Select Clips: Project 미생성, Add: 기존 Project 무변경) 해당 통합 안내를 표시한다. **Replace는 단일 후보 Operation**이므로 이 Filtering 대상이 아니며 후보가 Duration-ineligible이면 Revision 2의 개별 안내(`영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.` / `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`)로 거부하고 기존 Clip과 Media를 그대로 보존한다(제거 / 교체로 표현하지 않는다). Transactional 경계: Duration-ineligible 항목은 Preparation / Commit Transaction에 들어가기 전에 걸러지고, 남은 **Accepted Set**에는 승인된 Atomicity 계약이 그대로 적용된다 — Accepted Set 안의 어떤 항목이라도 Preparation / Normalization / Materialize / Persist에 실패하면 부분 Project Mutation 없이 전체를 되돌린다(ADR-020 / ADR-037). 이 결정은 Duration-ineligible Photos Video에만 적용되며 Malformed / Unreadable / Unsupported 등 다른 Invalid Media 범주의 다중 선택 처리, Normalization 진행 / 실패 / Retry Presentation, Storage 부족 Presentation은 결정하지 않는다(→ Revision 4에서 확정). Phase 6 구현 요구사항이며 현재 Phase 5 코드(`ProjectCompositionCoordinator` / `ProjectClipAppendCoordinator`: 첫 Non-ready 항목에서 전체 거부, 1.0초 최소 미강제)는 이를 아직 구현하지 않는다.

**Revision 4 (2026-09-17, 사용자 승인 — Phase 6 Structural UX Contract 완결):** Normalization-required Import의 Presentation과 Accepted Set 경계가 다음과 같이 확정되어 Phase 6 Structural UX Gate는 **해결**되었다(Technical Gate는 그대로 Pending).
1. **자동 Normalization 진입:** Accepted Set에 Normalization-required 항목이 하나라도 있으면 선택 / Eligibility Filtering 직후 별도 확인 화면 없이 자동으로 Preparation을 시작하고 **Blocking Preparation Sheet**를 표시한다 — Title / Message `영상을 준비하고 있어요` / `잠시만 기다려주세요.`, 가시적 Progress, 다중 항목이면 현재 위치를 `2/5` 형태로 표시, `취소` Button. Accepted Set 전체가 Phase-5-ready이면 Sheet를 표시하지 않는다. 완전 성공 시 Sheet를 자동으로 닫고 Project 생성 / Add / Replace를 완료하며, 사전에 제외된 항목이 있었다면 승인된 통합 제외 안내를 한 번 표시한다. 별도 성공 Alert는 없다.
2. **사용자 취소:** `취소`는 진행 중인 Preparation Operation을 취소하고 그 Operation의 임시 / 부분 생성 Project-owned 후보 파일을 모두 제거하며, Select Clips는 Project를 만들지 않고 Add / Replace는 기존 Project를 변경하지 않으며(Replace의 기존 Clip 보존), 부분 Metadata / Media를 남기지 않고, 완료된 것처럼 제외 안내를 표시하지 않으며, 적절한 사전 Operation UI로 안전하게 복귀한다. 저수준 취소 메커니즘은 구현 사항이나 관찰 가능한 Cleanup / 무변경 보장은 확정이다.
3. **Runtime Preparation / Normalization 실패:** Preflight를 통과한 항목이 Preparation / Materialization / Normalization 중 실패하면 Per-item 제외가 아닌 **Operation 실패**로 취급한다 — Accepted Set Atomicity 유지, 성공한 부분 집합만 Commit하지 않음, 임시 / 부분 파일 제거, Project 무변경(Select Clips는 미생성), Replace의 기존 Clip 보존. 안내는 정확히 `영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.`, Primary `다시 시도`, Secondary `취소`. `다시 시도`는 필요한 Source Handle이 Live Operation / Session 안에서 여전히 유효할 때 같은 Accepted Set Operation을 다시 시도하고, `취소`는 Cleanup 후 Operation을 끝낸다. Source 접근이 더 이상 유효하지 않으면 Mutation 없이 안전하게 실패하며 Broad Photos 권한을 도입하지 않는다.
4. **Storage 부족 Preflight:** Materialization / Normalization 시작 전에 Estimated Required Space + 승인된 Safety Reserve를 검사하고, 부족하면 Media를 생성 / 부분 생성하지 않고 Project를 만들거나 변경하지 않으며(Replace의 기존 Clip 보존) 정확히 `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / Action `확인`를 표시한다. Estimate Formula, Reserve, Filesystem 측정 API, Race 처리는 Technical Gate이며 승인되지 않은 Settings Deep Link를 추가하지 않는다. (현재 Phase 5 구현의 Message `공간을 확보한 뒤 다시 시도해 주세요.`는 Phase 6 구현에서 승인 Message로 교체된다.)
5. **Preflight에서 판별 가능한 Duration 외 Invalid Media:** Preparation 전에 Malformed / Unreadable / Unsupported로 신뢰성 있게 분류되는 항목은 그 항목만 제외하고(Materialize / Normalize / Persist / Append / Replace 없음) 나머지 사용 가능한 항목으로 계속한다. 전부 제외되면 Select Clips는 Project 미생성, Add는 무변경이며 단일 Replace 후보는 거부하고 기존 Clip / Media를 보존한다. Duration 외 Invalid 항목만 제외되었을 때의 안내는 정확히 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`. 모든 Corruption / Decoding 실패를 Preflight에서 발견할 수 있다고 주장하지 않으며 Preparation 중 발견된 실패는 3항의 Runtime 실패 정책을 따른다.
6. **통합 제외 안내(완료된 선택 Operation당 최대 1회):** Duration 사유만 → Revision 3 안내(`짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` / `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` / `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`); Duration 외 Invalid 사유만 → `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`; 두 범주 모두 → 정확히 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`(Revision 3의 Both-duration 안내와 Title은 같고 Message가 다르다). 항목 개수 표현 없음. Preparation이 취소되거나 실패하면 취소 / 실패가 우선하며 완료되지 않은 Operation에 대해 제외 성공 안내를 표시하지 않는다.
7. **Accepted Set 경계:** Select Clips / Editor Add — 항목별 Validation / 분류 → Duration-ineligible 및 신뢰성 있게 Preflight 판별된 Invalid 항목 제외 → 남은 사용 가능 항목이 Accepted Set(Phase-5-ready + Normalization-required 혼재 가능) → Accepted Set에 Atomic Preparation / Commit 안전성 적용 → 실패 / 취소 시 아무것도 Commit하지 않고 성공 시 전부 Commit → 제외 항목은 Accepted Set Transaction에 들어가지 않는다. Replace — 후보는 하나이며 Preflight 거부 / 취소 / Runtime 실패 / Storage 부족 어느 경우에도 기존 Clip을 보존하고 완전히 성공한 Replacement만 Media와 Metadata를 Atomic하게 교체한다.
Revision 1–3과 역사 기록은 그대로 유지된다. 이 Revision은 Codec / Container / SDR / Tone-mapping / Raster / Storage Formula / Recovery 메커니즘, Export Session / Cancellation API, Aggregate Progress 계산, Retry Source-handle 메커니즘을 결정하지 않는다. **구현 상태:** Preparation Sheet, 취소, Retry, Storage Preflight Presentation, Invalid Media Filtering, 통합 안내는 모두 Production 코드에 존재하지 않으며 Phase 6 구현 요구사항이다.

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
| Phase-6 Normalization-required Media | Eligibility(Duration)는 만족하지만 4K / High-resolution, HDR / Dolby Vision, >30 fps 등으로 Phase-5-ready 경계를 벗어나는 **Portrait Presentation** Media — Phase 6이 정규화 (ADR-043 Revision 1: Non-portrait Presentation(Landscape / Square)은 Normalization-required가 아니라 Preflight 제외) |
| Invalid Media | 읽을 수 없음 / Video Track 없음 / Duration 0 이하 → 거부(Below-minimum / Above-maximum 거부와 구분) |
| Phase 7 Trim | Project-owned Clip Media 범위 안에서의 비파괴 Metadata Trim(`0 < trimDuration <= 5s`, `trimStart + trimDuration <= sourceDuration`) |

### Phase 6 Consequences

Phase 6은 더 이상 무제한 길이 Source, Long-source Segment Selection, Segment Selection Structural UX Gate, 원본 전체 범위 Re-trim Decision, 선택 Segment 기반 Normalization / Storage Estimate / Recovery를 소유하지 않는다.

Phase 6은 새로운 별도의 Multi-selection Import 기능을 만들지 않는다. 기존 Select Clips / Editor Add Multi-select Session에는 Revision 3의 Per-item Duration Filtering이 적용된다: Duration-ineligible 항목(1.0초 미만 / 5.0초 초과)은 Transaction 전에 제외되고 통합 안내로 알리며, Duration-eligible 항목(Phase-5-ready + Normalization-required 혼재 가능)은 Accepted Set으로 계속 진행한다. Accepted Set 안에서 하나라도 Preparation / Normalization / Materialize / Persist에 실패하면 Project는 무변경이다(Accepted Set Atomicity). Duration 외 Invalid Media 중 Preflight에서 신뢰성 있게 판별되는 Malformed / Unreadable / Unsupported 항목도 Revision 4에 따라 Per-item 제외되며, Preparation 중 발견된 실패는 Accepted Set 전체의 Runtime 실패로 처리된다(Revision 4 §3 / §5).

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
- ~~Low-resolution Source Upscaling Policy와 1080p-class Working Media의 정확한 Raster Dimension Rule~~ — Resolved by ADR-045(Scale-down) + ADR-047(No Upscaling, 2026-09-18)
- Import Storage Estimate Formula와 Safety Reserve(5초 이하 전체 Source 기준)
- ~~Import Durable Operation Identity / Recovery 깊이와 ADR-039 STEP 12B Orphan Predicate의 확장 방식~~ — Resolved by ADR-047(2026-09-18): No Resume, Predicate 확장 없음
- ~~정확한 1.0초 / 5.0초 Product 경계에 대한 AVFoundation Duration 비교 정책(Timescale / Frame-duration 허용치의 검증 방식 — 구현 세부사항, Product 경계는 확정)~~ — Resolved by ADR-042 + ADR-045 §1 / §11: Source Eligibility는 정확히 `1.0 s ≤ source duration ≤ 5.0 s`(양 끝 포함)이며 정확한 Rational(`MediaTime`) 비교로 판정하고 Frame 기반 허용치를 적용하지 않는다(ADR-045 §7의 출력 Duration 허용 범위 `source <= output <= source + 1/30 s`는 Normalization 출력 Validation 규칙이며 Source Eligibility와 별개다).
- Phase-5-ready 경계를 벗어나는 항목별 Normalization 처리 범위(Portrait Presentation Source에 한함; Landscape 예시는 ADR-043으로 해소 — Non-portrait(Landscape / Square)은 Preflight 제외)
- 구체적 Export Session / Cancellation API 조합, Implementation-specific Aggregate Progress 계산, `다시 시도`의 최종 Source-handle 유지 메커니즘, Filesystem Free-space API와 Race 처리(Revision 4의 관찰 가능한 UX / Cleanup / 무변경 보장은 확정, 메커니즘만 Pending) (2026-10-06 갱신: D7b 참조 5항 — Aggregate Progress 계산이 결정되었다.)

## Non-goals

- Phase 6 Production 구현(이 ADR은 문서 정렬이며 Swift / Xcode 변경이 없고 Normalization 구현을 시작하지 않는다).
- Photos Read 권한 도입, PhotosPicker 대체, Camera Preset 변경, Direct Capture 규칙 변경.
- Phase 7 Trim UX / Phase 8 Preview / Phase 9 Export 결정.

---

# ADR-043 — Portrait-Only Photos Import Eligibility

**Date:** 2026-09-18 (Revision 1: 2026-09-18)
**Status:** Accepted

## Revision 1 — Non-Portrait Presentation Completion (2026-09-18)

**Status:** Accepted (사용자 승인). 이 Revision은 최초 ADR-043이 명시적으로 Pending으로 남긴 Square Presentation 질문을 닫으며 Portrait-only 원칙은 바꾸지 않는다. 아래 내용이 정본이며, 이 Revision 아래의 최초 본문은 최초 승인된 Landscape 결정의 기록으로 보존된다(충돌 시 Revision 1 우선).

### Canonical Eligibility Predicate

- Orientation Eligibility는 Source의 `naturalSize`에 `preferredTransform`을 적용한 Presentation Geometry로만 판정한다: **`presentationHeight > presentationWidth`** 일 때만 Portrait Presentation이며 이후 Validation(Duration / Invalid / Phase-5-ready / Normalization-required)으로 진행한다.
- `presentationHeight < presentationWidth`(Landscape)와 `presentationHeight == presentationWidth`(Square)는 **모두 Unsupported**이며 별도 Product Feature나 별도 Import Category가 아니라 하나의 **Non-portrait Presentation**으로 취급한다.
- `naturalSize`만으로 Eligibility를 결정하지 않는다. 자연 크기 `1920×1080` + 90° preferredTransform → Presentation `1080×1920`은 Portrait이며 거부하지 않는다. 자연 크기 `1080×1920` + Identity Transform도 Portrait이다.
- Mirroring(Determinant < 0)만으로는 Portrait Source가 Non-portrait이 되지 않는다.
- Mellow V1은 Square Recording, Landscape / Square Project Composition, Non-portrait Import Normalization, Crop-to-portrait 변환, Padding, Rotation 안내, 변환 옵션 어느 것도 제공하지 않는다.
- Duration Eligibility(ADR-042), Preflight Invalid Media, Orientation Eligibility는 서로 독립적인 Preflight 분류다.

### Canonical Non-Portrait Filtering Semantics

- **Select Clips / Editor Add:** 후보마다 독립적으로 평가하고 Non-portrait 항목은 Materialize / Remux / Normalize / Persist / Append / 어떤 Project 변경보다 먼저 제외한다. 남은 Portrait Accepted 항목으로 재선택 강요 없이 계속한다. Accepted 항목이 없으면 Select Clips는 Project를 만들지 않고 Editor Add는 기존 Project를 바꾸지 않는다. Photos 원본은 변경되지 않는다.
- **Replace(단일 후보):** 후보가 Non-portrait이면 거부하고 기존 Clip · Media · Metadata · Slot을 보존하며 Materialize / Remux / Normalize / Persist / 부분 교체를 하지 않는다.
- **Accepted Set Atomicity(ADR-042 Revision 3 / 4)**는 신뢰성 있게 Preflight 판별되는 모든 제외(Duration / Invalid / Non-portrait)를 제거한 뒤의 Accepted Set에만 적용되며 변경되지 않는다.
- 제외된 후보는 임시 Media나 Project-owned Media를 만들지 않는다.

### Canonical Presentation Copy (Landscape / Square 공용 — 별도 Landscape / Square 안내 없음)

| 상황 | Title | Message |
| --- | --- | --- |
| Select Clips / Editor Add에서 Non-portrait Presentation이 유일한 제외 사유 | `일부 영상이 제외되었어요` | `세로 형식이 아닌 영상은 추가할 수 없어요.` |
| 단일 후보 선택 / Replace 후보가 Non-portrait | `지원하지 않는 영상이에요` | `세로 영상을 선택해주세요.` |
| Non-portrait + Duration-ineligible / 기타 Preflight-invalid 복합 제외 | `일부 영상이 제외되었어요` | `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.` |

- 완료된 Operation당 통합 제외 안내는 최대 1회, 항목 수 표시 없음, Landscape / Square 별도 Alert 없음.
- 취소 / Runtime 실패는 ADR-042 Revision 4대로 제외 성공 안내보다 우선한다.
- 승인된 단일 항목 Duration 거부 Copy(`영상이 너무 길어요` / `영상이 너무 짧아요`)는 바꾸지 않는다.
- 최초 ADR-043 본문의 Landscape 전용 Copy(`가로 영상이 제외되었어요` / `세로 영상만 추가할 수 있어요.`, `가로 영상은 사용할 수 없어요` / `세로 영상을 선택해주세요.`)는 이 Revision으로 **대체**되어 더 이상 유효하지 않다.

### Pending Closure

- "Square Presentation의 취급"은 이 Revision으로 해소되어 어떤 Pending / Open 목록에도 남지 않는다.
- ADR-042의 Structural UX(Preparation Sheet / 취소 / Runtime 실패 / Storage / Invalid Filtering / 통합 안내 우선순위)와 Technical Gate 결정은 변경되지 않는다.

### Implementation Status (Revision 1)

승인되었으나 **구현되지 않았다**. 현재 Phase 5 `Phase5ReadyMediaValidator`는 `height > width`가 아닌 Presentation(Landscape / Square 모두)을 `.orientation` Non-ready로 판정하고 첫 Non-ready 항목에서 선택 전체를 거부하며(`세로 영상을 선택해주세요` / `현재 프로젝트에서는 세로 영상을 바로 사용할 수 있어요.`) Replace도 같은 경로다. Per-item Non-portrait 제외, 위 Canonical Copy, Duration / Invalid / Orientation을 구분하는 Validation 결과 모델, ROADMAP Phase 6의 Orientation Eligibility Unit / Integration Test는 Phase 6 구현 요구사항이다. 이 Revision은 Swift / Test / Spike를 변경하지 않는다.

---

## 최초 승인 본문 (2026-09-18, Landscape 결정 — Revision 1로 보완됨)

**Supersedes / Clarifies:**
- ADR-032 "Imported Media Orientation"의 "이후 Photos Import는 Portrait / Landscape Source를 모두 허용하고 …"와 "Portrait 9:16 Project에 삽입할 때 비율 불일치는 승인된 Fill + Crop과 조정 가능한 Framing을 사용한다" 중 **Landscape Source 허용** 부분. Fill + Crop / Framing은 Portrait Presentation Source의 비율 불일치(예: 4:3 Portrait)에 대해 유지된다.
- ADR-034 §2 "Phase 5가 구현하지 않는 것(Phase 6 / 7 소유 유지)" 중 Landscape Presentation Source의 **Crop / Framing / Source Transform 준비**: Landscape Source는 이제 어느 Phase도 준비하지 않는 V1 미지원 입력이다. `Phase5ReadyMediaValidator`의 Portrait 요구 자체(Non-portrait = Non-ready)는 유지된다.
- ADR-037의 Phase-5-ready 규칙 인용 "(… Portrait …)"과 "Import 편집 준비는 Phase 6 소유" 중 Landscape 준비 부분.
- ADR-042 Revision 1 "Phase-6 Normalization-required Media" 표의 "Landscape / Presentation Transform"과 Revision 4 §1 / §5 / §7 및 "Still Pending"의 "Landscape이지만 그 밖의 Working Contract를 만족하는 Source의 Re-encode vs Transform 보존 Copy": Landscape는 Normalization-required가 아니라 **Preflight 제외**이며 해당 Pending은 해소된다. ADR-042의 Duration Eligibility, Per-item Filtering, 통합 안내, Accepted Set Atomicity, Preparation Sheet / 취소 / Runtime 실패 / Storage 계약은 그대로 유효하다.
- ADR-022 / ARCHITECTURE 38절의 "16:9 Source를 9:16 Project에 가져온다는 이유로 … 잘라 저장하지 않으며" 예시와 ADR-011 / FEATURES F-MVP-022 / DESIGN 17절의 "9:16 프로젝트에 16:9 영상" 예시: V1에는 해당 입력이 존재하지 않는다. Fill + Crop bake-in 금지, Framing 가능 영역 보존, Presentation Transform 해석 원칙은 Portrait Source에 대해 그대로 유지된다.
- ROADMAP Phase 6 Included "Landscape / Presentation Transform이 다른 Source 허용", Implementation Task 4 / 7, Integration Test "Landscape Source", "16:9 Source → 9:16 Project …", Physical / Measurement Scenario "Landscape, Aspect Mismatch", Technical Gate의 Landscape Re-encode 항목: 같은 작업에서 정렬한다.

**Explicitly Unchanged:** ADR-032 / ADR-033의 Portrait-only Direct Capture, ADR-042의 `1.0s <= entire Photos source duration <= 5.0s`, Portrait Source의 Raster Downscale / HDR → SDR / Frame-rate 변환 / ~~MP4 Remux~~(ADR-044로 제거) / Transform Bake / Audio 보존 / Transactional Safety / Photos 원본 불변, Landscape 16:9 Project의 Domain / Schema 표현(V1 이후 복원 결정).

## Context

Mellow V1은 Portrait 9:16 Project만 생성하고(ADR-032) Direct Capture도 Portrait으로 고정된다(ADR-033). 그동안 Photos Import 문서는 Landscape Source를 허용하고 Phase 6이 이를 Normalization-required 입력으로 준비(Transform Bake, Framing 가능 영역 보존)한 뒤 Phase 7 Framing으로 넘기도록 계획했다. Phase 6 Technical Device Spike(2026-09-18, LunaTestphone)에서 Landscape 처리는 Re-encode 여부 등 별도 결정을 필요로 하고 Portrait Project에서의 Fill + Crop 결과가 Mini Vlog 의도와 맞지 않음이 확인되었다. 사용자는 **Mellow V1이 Landscape Photos 영상을 지원하지 않는다**는 Product 결정을 승인했다.

## Decision

### Landscape 정의

Orientation은 Source의 `preferredTransform`을 적용한 **Presentation Geometry**로 판정한다. `presentationWidth > presentationHeight`이면 Landscape이며 V1 미지원 입력이다. 인코딩된 `naturalSize`가 `1920×1080`이라도 Transform 적용 후 `1080×1920`으로 표시되는 일반 iPhone 세로 영상은 Portrait이며 거부하지 않는다(ARCHITECTURE 44절 "naturalSize만으로 Orientation을 판단하지 않는다").

### Landscape Preflight 규칙

Landscape 항목에 대해서는 Materialize / Remux / Normalize / Project-owned Media 생성 / Clip Metadata Persist / Append / Replace 어느 것도 하지 않으며 Accepted Set Transaction에 들어가지 않고 Photos 원본은 변경되지 않는다. Landscape는 **Normalization-required가 아니라 Preflight 제외(Unsupported)**다.

### Select Clips / Editor Add (다중 선택)

Preflight에서 Landscape 항목만 제외하고 지원되는 Portrait 항목으로 계속 진행한다(재선택 강요 없음). 전부 Landscape이면 Select Clips는 Project를 만들지 않고 Add는 기존 Project를 변경하지 않는다. 완료된 선택 Operation당 통합 안내는 최대 1회이며, **Landscape가 유일한 제외 사유**이면 정확히 `가로 영상이 제외되었어요` / `세로 영상만 추가할 수 있어요.`를 사용한다. *(역사적 기록 — Revision 1로 대체: Non-portrait 공용 `일부 영상이 제외되었어요` / `세로 형식이 아닌 영상은 추가할 수 없어요.`)*

### Replace 및 단일 후보 선택

후보가 Landscape이면 Preflight에서 거부하고 기존 Clip · Media · 순서 · Metadata를 그대로 보존하며 정확히 `가로 영상은 사용할 수 없어요` / `세로 영상을 선택해주세요.`를 사용한다(제거 / 교체로 표현하지 않는다). *(역사적 기록 — Revision 1로 대체: `지원하지 않는 영상이에요` / `세로 영상을 선택해주세요.`)*

### 복합 제외 사유

Landscape가 Duration-ineligible 또는 다른 Preflight-invalid 항목과 함께 제외되면 기존 승인 통합 안내 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`를 그대로 사용한다. 취소 / Runtime 실패는 여전히 제외 성공 안내보다 우선한다.

### Accepted Set

Select Clips / Add의 Accepted Set은 Duration-eligible이고 Preflight-invalid가 아니며 **Portrait Presentation**인 항목으로만 구성된다(Phase-5-ready + Normalization-required 혼재 가능). Accepted Set Atomicity(ADR-042 Revision 3 / 4)는 변경되지 않는다.

### 범위

- V1 Photos Import에만 적용된다. Portrait-only Direct Capture 정책은 그대로다.
- Phase 6에서 Landscape Import Normalization을 제거한다.
- 1.0–5.0초 Duration 경계, Portrait Source의 Raster Downscale / HDR 변환 / Frame-rate 변환 / ~~MP4 Remux~~(ADR-044: V1에서 제거) / Transform 처리 / Audio 보존 / Transactional Safety / Photos 원본 불변은 바꾸지 않는다.
- ~~Square(정사각) Presentation은 이 ADR이 정하지 않는다.~~ — **Revision 1로 해소:** Square(`presentationHeight == presentationWidth`)는 Landscape와 함께 Non-portrait Presentation으로 Unsupported이며 Canonical Predicate는 `presentationHeight > presentationWidth`이다.

### 구현 상태

현재 Phase 5 구현은 Landscape Presentation을 `requires import preparation(.orientation)`으로 판정하고 첫 Non-ready 항목에서 선택 전체를 거부하며(`세로 영상을 선택해주세요` / `현재 프로젝트에서는 세로 영상을 바로 사용할 수 있어요.`) Replace도 같은 경로로 거부한다. Per-item Landscape Filtering과 위 전용 안내는 **승인된 Phase 6 구현 요구사항**이며 아직 구현되지 않았다. 이 ADR은 Swift / Test를 변경하지 않는다.

## Rationale

- V1 Project는 Portrait뿐이며 Direct Capture도 Portrait으로 고정되어 Landscape Source는 제품 흐름에 자연스러운 자리가 없다.
- Landscape를 Portrait Canvas에 Fill + Crop하면 대부분의 화면 영역을 잃어 Mini Vlog 의도와 어긋나며, Phase 6 / 7에 Re-encode 여부 · Framing 초기값 등 추가 결정을 요구한다.
- Preflight 제외는 이미 승인된 Per-item Filtering / 통합 안내 모델(ADR-042 Revision 3 / 4)에 그대로 얹히므로 Transaction 경계를 바꾸지 않는다.

## Consequences

- Phase 6 Normalization 대상은 Portrait Presentation Source의 4K / High-resolution, HDR / Dolby Vision, >30 fps, ~~기타 Codec 사유~~로 좁혀진다(ADR-044: Source Container는 Normalization 사유가 아니라 Preflight Container Eligibility — QuickTime만 허용; **ADR-046:** Codec도 Normalization 사유가 아니라 Preflight Codec Family Eligibility — H.264 / HEVC만, 그 밖은 Unsupported). Landscape Device Normalization Test는 요구되지 않는다.
- Phase 7 Framing은 Accepted Portrait Project-owned Media의 비율 불일치(예: 4:3 Portrait)에 대해서만 Fill + Crop을 다룬다(Revision 1: Square는 Import 대상이 아니다).
- Validation 결과 모델은 Non-portrait Presentation(Landscape / Square)을 Duration / Invalid와 구분되는 Preflight 제외 사유로 표현해야 한다(Revision 1).

## Still Pending (이 ADR이 확정하지 않음)

- ~~Square Presentation의 취급.~~ — Revision 1(2026-09-18)로 해소(Unsupported, Non-portrait Presentation).
- ADR-042 Still Pending의 나머지 Technical Gate(Codec / Container / SDR Tagging / Tone-mapping / Upscaling / Raster / Storage / Recovery / API / Progress / Retry) — 변경 없음(ADR-044: Source Container Eligibility는 해소, Working Media Container(출력)는 여전히 Pending).

## Non-goals

- Landscape Project 복원 시점(Post-V1), Landscape / Square Import의 향후 지원 방식, Phase 7 Framing UX, 구현.

---

# ADR-044 — QuickTime-Only Photos Import Container Eligibility

**Date:** 2026-09-18 (Revision 1: 2026-09-18)
**Status:** Accepted (사용자 승인)

## Revision 1 — Single-Item / Replace Unsupported-Media Copy (2026-09-18)

**Status:** Accepted (사용자 승인). 최초 ADR-044가 유일하게 Pending으로 남긴 단일 후보 / Replace 안내 Copy를 닫는다. 그 밖의 결정은 바꾸지 않는다.

### 승인 Copy

| 상황 | Title | Message |
| --- | --- | --- |
| 단일 선택 항목이 신뢰성 있게 Preflight 판별되는 Unreadable / Unsupported | `영상을 추가할 수 없어요` | `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.` |
| Replace 후보가 신뢰성 있게 Preflight 판별되는 Unreadable / Unsupported | `영상을 추가할 수 없어요` | `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.` |

적용 대상: 실제 Source Container가 QuickTime이 아닌 경우(MP4 / 기타 non-QuickTime / Unknown)와 ADR-042 Revision 4 §5의 Preflight 판별 Invalid / Unsupported 범주에 이미 속하는 그 밖의 Media. MP4 전용 문구는 없다.

### 다중 선택 안내와의 구분

위 Copy는 **단일 항목 / Replace(후보 하나)** 전용이다. 다중 선택(Select Clips / Editor Add)의 Per-item 제외 통합 안내는 그대로 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`(Invalid / Unsupported만), 복합 사유는 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`다. Non-portrait Copy(ADR-043)와 Duration Copy(ADR-042)는 변경되지 않으며 취소 / Runtime 실패는 계속 제외 성공 안내보다 우선한다.

### Replace 보존 의미

Replace 후보가 위 조건에 해당하면 후보를 거부하고 기존 Clip · Media · Metadata · 순서 · Slot을 그대로 보존하며 Copy / Materialize / Normalize / Persist / 부분 교체를 수행하지 않는다.

### Pending Closure / 구현 상태

- 최초 본문 §7 표의 "미확정" 행과 Still Pending 첫 항목은 이 Revision으로 해소되어 어떤 Pending / Open 목록에도 남지 않는다.
- 현재 Phase 5는 단일 항목 Invalid에 `영상을 열 수 없어요` / `선택한 영상을 읽을 수 없어요. 다른 영상을 골라 주세요.`를 표시한다(§10에 기록된 구현 사실). 위 승인 Copy와 QuickTime-only Per-item Filtering은 **승인되었으나 미구현**인 Phase 6 요구사항이며 이 Revision은 Swift / Test / Spike를 변경하지 않는다.
- 나머지 Technical Gate(Working Media Codec / Container(출력), SDR Tagging / Tone-mapping, Upscaling / Raster, Storage, Recovery, API / Progress / Retry, Cancellation / HDR 기기 검증)는 변경 없음.

---

## 최초 승인 본문 (2026-09-18 — Revision 1로 보완됨)

**Supersedes / Clarifies:**
- ADR-043 "Explicitly Unchanged"와 "범위"의 "Portrait Source의 … MP4 Remux …" 언급: MP4 Remux는 더 이상 Phase 6 범위가 아니다. Portrait-only 원칙(ADR-043 Revision 1)은 변경되지 않는다.
- ADR-043 Consequences의 "기타 Codec / 컨테이너 사유로 좁혀진다": Source **Container**는 Normalization 사유가 아니라 Preflight Container Eligibility다. Codec / Working-media 사유는 유지된다.
- ADR-042의 "Preflight에서 판별 가능한 Duration 외 Invalid Media"(Revision 4 §5): Unsupported Container는 이 기존 범주에 속한다(새 범주 아님).
- ROADMAP Phase 6 Technical Gate / Spike 계획 중 "MP4 → QuickTime Passthrough Remux" 기기 검증 항목: 제거(역사 기록은 보존하고 로컬 표시).

**Explicitly Unchanged:** ADR-042 Duration Eligibility / Per-item Filtering / 통합 안내 / Accepted Set Atomicity / Preparation Sheet / 취소 / Runtime 실패 / Storage 계약, ADR-043 Revision 1 Non-portrait Preflight, Phase 6 Normalization(4K / High raster, >30 fps, HDR / Dolby Vision → SDR, 기타 승인된 Working-media 불일치), Storage / Cancellation / HDR / Recovery Technical Gate, **Working Media Codec / Container(출력) Pending**(Source Container 결정과 별개), Export Codec / Container Pending, Photos 원본 불변.

## Context

Mellow V1의 설계 Workflow는 **iPhone에서 촬영 → Photos에서 선택 → Mellow 안에서 준비**다. iPhone Camera / Photos가 만드는 영상은 QuickTime Movie Container(H.264 또는 HEVC)이며 Mellow의 Project-owned Media도 QuickTime(`.mov`)이다. Phase 6 Technical Device Spike(2026-09-18, LunaTestphone)는 MP4 → QuickTime Passthrough Remux 경로를 후보로 조사했으나, 이 경로는 V1 Workflow 밖의 입력(타 기기 / 메신저 / 데스크톱 Export)을 위한 추가 Pipeline · 검증 · 실패 모드를 요구한다. 사용자는 **V1 Photos Import를 실제 Container가 QuickTime Movie인 영상으로 한정**하는 Product 결정을 승인했다.

## Decision

### 1. Actual-container Eligibility Rule

- 실제 Container가 **QuickTime Movie**이면 Container-eligible이며 다른 독립 Preflight 규칙으로 계속 진행한다.
- 실제 Container가 **MP4 / ISO Base Media**이면 V1 미지원이다.
- 그 밖의 non-QuickTime 또는 알 수 없는 Container도 V1 미지원이다.

### 2. File Extension Non-authority

- 파일 확장자만으로 Eligibility를 결정하지 않는다. Container 판정은 실제 File Type / Brand 등 신뢰성 있는 Media / Container Inspection으로 한다.
- `.mp4` → `.mov` 이름 변경은 파일을 Eligible로 만들지 않는다.
- `.mov` → `.mp4` 이름 변경은 신뢰성 있는 Inspection이 QuickTime임을 증명하면 파일을 Ineligible로 만들지 않는다.

### 3. QuickTime ≠ H.264-only

QuickTime Container-eligible Source는 지원되는 **H.264 또는 HEVC** Media를 담을 수 있다. Container Eligibility를 Codec 제한으로 해석하지 않는다(**ADR-046:** Codec Family Eligibility는 Container 다음의 별도 Preflight 단계이며 H.264 / HEVC 외 Codec은 Unsupported). Codec / 색 / 해상도 / 프레임레이트 적합성은 Phase-5-ready / Normalization-required 판정이 따로 다룬다.

### 4. Eligibility는 자동 수락이 아니다

Container-eligible QuickTime Source도 다음 독립 Preflight 규칙을 모두 통과해야 한다: 전체 Source Duration `1.0s <= duration <= 5.0s`(ADR-042), Portrait Presentation `presentationHeight > presentationWidth`(ADR-043 Revision 1), Readable / Usable, Protected 아님, 지원되는 Video / Audio 특성(**ADR-046:** Video Codec Family = H.264 / HEVC만; ProRes / ProRes RAW / MJPEG / 기타 / Unknown은 Preflight Unsupported)(**ADR-048:** Audio Facts를 신뢰성 있게 검사할 수 있어야 하며 짝수 정렬 후 Working Raster가 Portrait이어야 한다). 통과한 Source는 **Phase-5-ready**(Project-owned Media로 복사) 또는 **Phase-6 Normalization-required**(4K / High raster, 30 fps 초과, HDR / Dolby Vision, 기타 승인된 Working-media 불일치)다.

### 5. V1이 제공하지 않는 것

MP4 → QuickTime Remux, Passthrough Container 변환, 임의 Container 변환, Container 변환 안내 / 옵션, 사용자 선택 출력 Container. Unsupported-container 항목은 Copy / Remux / Normalize / Persist / Append / Replace 어느 Media Operation에도 들어가지 않는다.

### 6. Unsupported-container 동작

- **Select Clips / Editor Add:** 후보마다 독립 분류; MP4 · 기타 non-QuickTime · 신뢰성 있게 판별된 Unsupported-container 항목은 어떤 Media Operation / Project 변경보다 먼저 제외; 남은 Accepted QuickTime 후보로 계속; 남는 항목이 없으면 Select Clips는 Project 미생성, Editor Add는 무변경.
- **Replace:** Unsupported-container 후보는 거부하고 기존 Clip · Media · Metadata · Slot을 보존하며 부분 교체 없음.
- Photos 원본은 변경되지 않는다.
- **Accepted Set Atomicity**(ADR-042 Revision 3 / 4)는 신뢰성 있게 Preflight 판별되는 모든 제외(Duration / Non-portrait / Invalid-or-Unsupported) 이후의 Accepted Set에 그대로 적용된다.

### 7. Presentation Copy (기존 승인 범주 재사용, MP4 전용 Alert 없음)

| 상황 | Title | Message |
| --- | --- | --- |
| Select Clips / Editor Add에서 Unsupported-container(및 기타 Preflight Invalid / Unsupported)만 제외 | `일부 영상을 추가할 수 없어요` | `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.` |
| Duration / Non-portrait 등 다른 제외 사유와 복합 | `일부 영상이 제외되었어요` | `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.` |
| 단일 후보 선택 / Replace 후보가 Unsupported-container | ~~미확정~~ → Revision 1: `영상을 추가할 수 없어요` | `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.` |

완료된 Operation당 통합 안내 최대 1회, 항목 수 표시 없음, 취소 / Runtime 실패 우선(ADR-042 Revision 4). 승인된 Duration / Non-portrait Copy는 다시 열지 않는다.

### 8. ADR-042 / ADR-043과의 관계

Duration(ADR-042), Orientation(ADR-043 Revision 1), Container(ADR-044), Preflight Invalid Media는 서로 독립적인 Preflight 분류이며 어느 것도 Normalization 사유가 아니다. Unsupported Container는 ADR-042 Revision 4 §5의 "Preflight에서 판별 가능한 Invalid / Unsupported Media" 범주에 속한다.

### 9. 제거되는 계획

Phase 6 Included / Technical Gate / 구현 Task / Unit · Integration · Physical Device Test / Acceptance / Exit / Measurement Evidence / Traceability에서 MP4 Import와 MP4 → QuickTime Passthrough Remux를 제거한다. 역사 기록(Spike 조사, 이전 ADR 언급)은 보존하고 "ADR-044로 대체"를 로컬 표시한다.

### 10. 구현 상태

- **승인된 Product 정책:** 위 1–7항.
- **현재 Phase 5 동작:** `Phase5ReadyMediaValidator`는 Container를 검사하지 않으며(AVFoundation이 열 수 있는 파일을 그대로 판정) 첫 Non-ready / Invalid 항목에서 선택 전체를 거부한다. 단일 항목 Invalid는 `영상을 열 수 없어요` / `선택한 영상을 읽을 수 없어요. 다른 영상을 골라 주세요.`를 표시한다(구현 사실이며 이 ADR이 승인 Copy로 채택하지 않는다).
- **DEBUG Spike:** 현재 Spike는 `ftyp` Brand Sniffing과 MP4 → QuickTime Passthrough Remux 경로를 포함한다. 이는 Technical Gate 조사를 위한 **일회용 진단 코드**이며 Product 동작이 아니다; Spike 정리에서 제거될 예정이다.
- **미래 Phase 6 Production:** 신뢰성 있는 Container Inspection + Per-item Unsupported-container 제외 + 위 Copy는 **승인되었으나 미구현**인 Phase 6 요구사항이다. 이 ADR은 Swift / Test / Spike를 변경하지 않는다. — **구현 상태(2026-10-02):** 신뢰성 있는 Container Inspection은 `ImportSourceInspector`(`5416111`) · `ImportPreflightClassifier`(`efbcff9`)에, Per-item 판정 매핑은 `ImportSelectionPreflight`(`c570d5b`)에 구현되었으나 사용자 흐름과 Copy 표시 연결은 미구현이다.

### 11. 남은 Technical Device Spike Gate

ADR-044 이후 남은 Phase 6 Technical Device Spike Gate는 (1) Mid-run Cancellation과 임시 / Partial File 완전 Cleanup, (2) LunaTestphone에서 HDR / Dolby Vision → SDR 변환 검증뿐이다. MP4 Remux 기기 Test는 요구되지 않으며 Landscape / Square 변환 Test도(ADR-043) 요구되지 않는다.

## Rationale

- V1 입력원은 iPhone 촬영본이며 그 Container는 QuickTime이다. MP4 지원은 Workflow 밖 입력을 위한 별도 Pipeline과 검증을 요구한다.
- Remux는 Metadata / Transform / Audio 보존 증명이 필요한 추가 실패 표면이며 Phase 6 핵심(Normalization, Storage, Cancellation, HDR)에 집중하기 위해 제외한다.
- Unsupported Container를 기존 Invalid / Unsupported 범주로 다루면 새 Alert · 상태 · Transaction 경계가 생기지 않는다.

## Consequences

- Validation 결과 모델은 Unsupported Container를 Preflight Invalid / Unsupported 범주로 표현하되 확장자가 아닌 실제 Container Inspection에 근거해야 한다.
- Phase 6 Working Media는 QuickTime Source에서만 생성된다; Working Media Codec / Container(출력)의 Technical Gate는 그대로 Pending이다.
- Post-V1에서 MP4 / 기타 Container Import 재검토는 Out of Scope이며 Phase 6 Blocker가 아니다.

## Still Pending (이 ADR이 확정하지 않음)

- ~~단일 후보 선택 / Replace 후보가 Unsupported-container(또는 기타 Preflight Invalid / Unsupported)일 때의 정확한 안내 Copy~~ — Revision 1(2026-09-18)로 해소: `영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.`.
- Working Media Codec / Container(출력), SDR Tagging / Tone-mapping, Upscaling / Raster, Storage Formula / Reserve, Recovery, API / Progress / Retry — 변경 없음.

## Non-goals

- Post-V1 MP4 / 기타 Container Import, Container 변환 UX, Export Container, 구현.

---

# ADR-045 — Phase 6 Working Media Technical Gate Resolution

**Date:** 2026-09-18
**Status:** Accepted (사용자 승인 — Phase 6 Final Device Gate PASS, Phase 6 Ready to Close)

**Resolves:** ADR-022 / ADR-042 "Still Pending"의 Working Media Codec / Container(출력), 정확한 SDR Color Profile / Tagging, Tone-mapping 구현 방법, Raster Dimension Rule(Scale-down 범위), ROADMAP Phase 6 "Pending Technical Gate"의 동일 항목, Technical Device Spike의 남은 기기 Gate(Cancellation Cleanup, HDR / Dolby Vision → SDR).

**Explicitly Unchanged:** ADR-042 Duration / Per-item Filtering / Structural UX, ADR-043 Revision 1 Portrait-only, ADR-044 Revision 1 QuickTime-only 및 Copy, ADR-020 / 024 / 037 / 039 Commit · Storage · Recovery 계약, Low-resolution Upscaling Policy(Pending 유지), Import Storage Estimate Formula / Safety Reserve(Pending 유지), Recovery 깊이, Progress / Retry 메커니즘(Pending 유지), Export Codec / Container(Phase 9).

**이 ADR은 Phase 6 Production 구현 완료를 의미하지 않는다.** Technical Gate가 해결되어 구현을 시작할 수 있다는 결정이며, Production Pipeline · Per-item Filtering · Preparation Presentation은 여전히 미구현이다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. Production Pipeline의 구성요소 — Working Media Contract · Plan(Step 4A `75c2cb9`)과 `AVFoundationWorkingMediaNormalizer` · Cadence Scheduler · Output Validator(Step 4B `da1f337`) — 는 구현 · 검증되었다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). Per-item Filtering과 Preparation Presentation의 사용자 흐름 연결은 여전히 미구현이며 Phase 6은 완료되지 않았다.

## Context

Phase 6 Normalization 구현 전 Technical Gate 항목을 DEBUG 전용 Technical Device Spike(LunaTestphone iPhone 12, iOS 27.0, 2026-09-18)로 조사했다. Spike는 실제 AVFoundation Reader / Composition / Writer Pipeline, 결정적 Cancellation, 지속 JSON 기록, A/B 재생을 갖춘 일회용 진단 Harness이며 `spike/06-media-technical-gate` @ `04d836127ddb040676a7bec2972836a331d95fe7` 에 Evidence Baseline으로 보존된다(main에 병합하지 않음). 다섯 시나리오가 모두 PASS했고 사용자가 최종 HDR 결과를 A/B 시각 검증했다.

## Decision

### 1. Input Admission (독립 Preflight 판정 순서)

1. 전체 Source Duration `1.0s <= duration <= 5.0s`(ADR-042)
2. Readable / Video Track 존재 / Protected 아님(Preflight Invalid)
3. 실제 Container Brand — QuickTime Movie(`qt  `)만 허용, MP4 / ISO BMFF / 기타 / Unknown은 Unsupported(ADR-044; 확장자 비권위)
4. **(ADR-046 삽입)** Video Codec Family — H.264(`avc1` / `avc3`) 또는 HEVC(`hvc1` / `hev1`)만 허용, ProRes / ProRes RAW / MJPEG / 기타 / Unknown은 Unsupported
5. Presentation Orientation — `preferredTransform` 적용 후 `presentationHeight > presentationWidth`만 허용(ADR-043 Revision 1)
6. Normalization 사유 판정(아래 §2) — 위 1–5는 어느 것도 Normalization 사유가 아니며 서로 독립된 Verdict다. *(최초 본문은 1–5 순서였으며 ADR-046이 Codec 단계를 삽입했다.)* — **ADR-048(2026-09-30):** 5 다음에 Working-raster Feasibility와 Audio Facts 신뢰성 단계(기존 Invalid / Unsupported 범주)가 삽입되어 Normalization 사유 판정은 7단계가 되었다(ADR-048 Canonical Preflight Order). — **ADR-049(2026-10-01):** 사유 판정 뒤에 Aperture / Tone-map 경로 호환성 단계(8)가 추가되었다(ADR-049 Decision 3).

### 2. Fast Path vs Normalization

- **Phase-5-ready SDR QuickTime**(H.264 또는 HEVC — ADR-046의 Codec Family 정의, Rec.709 / Rec.709 / Rec.709, ≤ 8-bit, ≤ 1080p-class, ≤ 30 fps): Project-owned Media로 **복사(Fast Path)**, 재인코딩 없음. Codec Family 자체는 Normalization 사유가 아니며 H.264 / HEVC 외 Codec은 ADR-046에 따라 Preflight Unsupported다.
- **Normalization-required**: HDR / >8-bit(HLG 또는 PQ Transfer, Rec.2020 Primaries **또는** Matrix, bitsPerComponent > 8, 10-bit Profile(hvcC Main10 / avcC High10 계열), Dolby Vision `dvcC` / `dvvC` / `dvwC` Atom), 30 fps 초과, 1080p-class 초과 Raster. — **ADR-048(2026-09-30):** 신뢰성 있게 식별된 non-AAC Audio가 네 번째 사유 `audioTranscode`로 추가되었으며(순서: HDR → Frame Rate → Raster → Audio Transcode) Phase-5-ready는 Audio가 없거나 AAC인 경우만 해당한다.
- **AmbientViewingEnvironment / MasteringDisplayColorVolume / ContentLightLevel 단독은 HDR 판별 신호가 아니다.** AVE는 iPhone SDR 촬영본에도 존재한다.

### 3. Working Media Output Contract

- QuickTime Movie `.mov`
- H.264 High Profile, 8-bit(High 10 / 4:2:2 / 4:4:4 아님)
- Color Primaries / Transfer / Matrix = Rec.709 / Rec.709 / Rec.709, Video Range
- Raster: Presentation Frame 전체를 담는 1080p-class Bounding Box(긴 변 ≤ 1920, 짧은 변 ≤ 1080, Scale-down만, Crop / Pad 없음, 각 변 짝수 내림). ~~Low-resolution Source의 Upscale 여부는 여전히 Pending(Spike는 Upscale하지 않음).~~ — **ADR-047(2026-09-18):** 절대 Upscale하지 않는다(`scale = min(1.0, 1080 / width, 1920 / height)`, Envelope 안의 Source는 Presentation 크기 유지, 짝수 내림).
- Frame Rate ≤ 30 fps(`frameDuration = max(source minFrameDuration, 1/30)`) — **ADR-048(2026-09-30):** `minFrameDuration`이 없거나 0 이하이면 유한하고 0보다 큰 Nominal Frame Rate로 `max(1 / nominalFrameRate, 1/30)`, 둘 다 없으면 `1/30`.
- Presentation Transform은 Pixel에 Bake하고 출력 Transform은 Identity, 출력 Presentation은 Portrait
- Audio: AAC Passthrough(재인코딩 없음, Source Format Hint) — **ADR-048(2026-09-30):** Audio 없음 → 출력 Audio 없음(무음 합성 없음); AAC → Passthrough; 알려진 non-AAC → AAC-LC 48 kHz(Mono 96 kbps / 2채널 이상은 Stereo 128 kbps, 2채널 초과는 명시적 Stereo Downmix)로 변환; 알 수 없거나 모순된 Audio Facts → Preflight Invalid / Unsupported 거부.
- 출력에 HLG / PQ / Rec.2020 / Dolby Vision / MDCV / CLLI / AVE 신호가 남지 않는다.

### 4. Tone-mapping Mechanism

`AVAssetReaderVideoCompositionOutput` + `AVMutableVideoComposition`(colorPrimaries / colorTransferFunction / colorYCbCrMatrix = ITU_R_709_2, renderSize = Bounding Box, Layer Instruction으로 Transform Bake) → AVFoundation 내장 Compositor가 각 Frame을 Rec.709 SDR Working Color Space로 렌더링해 8-bit 420 Video-range Pixel Buffer를 제공 → `AVAssetWriterInput`(H.264, `AVVideoColorPropertiesKey` 709 / 709 / 709)이 태깅해 기록. **공개 메타데이터는 출력 형식과 HDR 신호 제거를 증명하지만 Tone-curve 품질은 증명하지 못한다** — 기기 A/B 시각 검증이 Acceptance Evidence다. — **ADR-049(2026-10-01):** 이 내장 Compositor 경로는 그대로 V1의 유일한 승인 Tone-mapping 메커니즘이며 Normalization이 필요한 Full-aperture Source(Case B)에 쓴다. Custom Compositor 앞의 Framework Pre-conversion은 이 메커니즘의 대체로 승인되지 않았다. Non-full Clean Aperture Source는 신뢰성 있는 SDR Rec.709일 때만 Tone-mapping 없는 Geometry 전용 경로로 정규화하고(Case C), Tone-mapping이 필요하거나 SDR이 증명되지 않으면 Preflight에서 기존 Invalid / Unsupported 범주로 거부한다(Case D).

### 5. 원본 획득 전제

`PhotosPicker`의 `preferredItemEncoding`은 반드시 `.current`다. `.automatic`이면 Photos가 HEVC / HDR 원본 대신 H.264 Rec.709 호환 Transcode를 전달하여 HDR 입력이 Preflight에 도달하지 못한다(Spike Run `C4DCC2C1`로 증명). Production Selector는 이미 `.current`이며 이는 테스트로 고정되는 불변조건이다.

### 6. SDR Output Contract 적용 범위

§3 Contract는 **Normalization 출력에만** 적용한다. Verbatim Fast-path Copy는 Phase-5-ready 규칙으로 이미 검증되었고 Source Transform / AVE를 그대로 보존하므로 Contract 대상이 아니다.

### 7. Duration 허용 범위

30 fps 재타이밍은 출력 Duration을 최대 1 Frame 늘릴 수 있다. 허용 범위: **`source duration <= output duration <= source duration + 1/30 s`**. 범위 밖은 Validation 실패다. 이 허용치는 Product Duration 경계(ADR-042)를 재정의하지 않는다.

**정규화 항목의 Clip Metadata(2026-10-06, 소유자 결정 — 이 범위에 한정):** 정규화된 Accepted 항목이 Clip이 될 때 `sourceDuration`은 검증된 정규화 출력 파일의 실제 Duration이고, `trimStart = 0`, `trimDuration`은 검증된 Accepted Source Duration(1.0–5.0초)이다. 출력은 그 Trim 전체를 덮어야 한다(`trimDuration <= sourceDuration`). 위 허용 범위가 허락하는 최대 1/30초의 추가 출력은 Trim 밖에 남으며 Clip의 사용 가능한 Duration을 늘리지 않는다. 기록된 출력 Duration을 5초로 Clamp하지 않고, Trim을 늘리지 않으며, Trim보다 짧은 출력을 조용히 받아들이지 않는다(그런 출력은 Save 전 실패다). 이 허용 범위와 Domain Trim 불변조건(`0 < trimDuration <= 5 s`, `trimStart + trimDuration <= sourceDuration`)은 바뀌지 않는다. Fast-path 항목은 기존대로 `sourceDuration = trimDuration = Source Duration`이다. 이 결정은 Select Clips · Editor Add · Editor Replace의 정규화 항목 모두에 적용한다(2026-10-06 소유자 확인; ADR-040 §6 Revision 참조). (구현 2026-10-06: 내부 `ImportAttemptCoordinator`가 새 Project · 대체 · Editor Add의 정규화 항목에 이 규칙을 적용하고 Trim보다 짧거나 허용 범위 밖의 출력은 Save 전 실패로 거부한다; 2026-10-06 확인에 따라 정규화 항목의 Editor Replace에도 같은 규칙을 적용한다.)

### 8. Cancellation / Output Ownership

- 취소 신호는 Idempotent Token 하나(사용자 취소와 내부 Trigger가 같은 경로)로 전달하며 첫 요청이 기록되고 이후 요청은 무해하다.
- Reader / Writer는 `cancelReading` / `cancelWriting`으로 종료한다.
- **Partial Output 제거는 그 파일을 만든 Normalization Operation의 책임**이며 반환 전에 수행하고 제거 후 존재 여부를 다시 확인한다.
- `finishWriting` 이후에 도착한 취소도 "취소됨 · Publish 없음"으로 처리하며 성공으로 바뀌지 않는다.
- 실패 경로도 동일한 Cleanup Evidence(Partial 존재 여부 / 제거 성공 / 제거 후 존재 여부)를 남긴다.

### 9. 원본 불변

모든 Operation 후 Source(앱이 받은 Transient 복사본)의 Byte 수와 Modification Time이 변하지 않았음을 확인한다. Photos 원본은 어떤 경우에도 변경되지 않는다.

### 10. Spike 처분

Spike는 일회용 진단 코드다. main에 병합하지 않으며 `spike/06-media-technical-gate` @ `04d836127ddb040676a7bec2972836a331d95fe7` 로 보존한다. Spike 파일을 Rename / Copy하여 Production 코드로 쓰지 않고 §11의 새 Abstraction으로 계약을 재구현한다.

### 11. Production 이관

**구현할 Abstraction(제안 위치 `MellowApp/Core/Projects/Import/`):**
- `ImportPreflightClassifier` — 순수(`Sendable`) 분류기. 입력은 `ImportSourceInspector`가 `AVURLAsset`에서 만든 Facts(Container Brand, Duration, Natural Size / Transform, Codec / Profile / bpc, Color Tags, HDR Atoms, Frame Rate, Readable / Playable / Protected). 출력은 Duration / Invalid / Container / Orientation / Normalization-required / Ready의 독립 Verdict.
- `WorkingMediaNormalizer` — §3 / §4 Pipeline. 주입된 Cancellation Token, 진행률은 Operation Result가 최종값을 직접 전달, 실패 · 취소 경로 모두 Cleanup Evidence 완성.
- `SDRWorkingMediaContract` — §3의 순수 검증기(§6 범위, §7 Duration 허용 범위 포함).

**Spike에서 복사하지 않을 설계(주의):** 진행률을 UI 상태에서 읽는 Race(Spike M1) 대신 Result가 최종값을 전달; Session UUID 대신 안정적 Clip / Media Identity; Non-Sendable Converter를 `Task.detached`에 그대로 캡처하지 않음; 실패 경로에서도 Cleanup Evidence 완성; Test Storage Directory를 명시 주입; 복원된 출력에 Classifier 문자열을 Verdict로 쓰지 않음; JSON 진단 기록 · A/B 재생 · Metrics Sampling · 35% Auto-cancel Toggle은 이관하지 않음.

**이관할 Production Test:** Duration 경계(1.0 / 5.0 포함, 허용치 없음); Orientation 6 Case + 혼합; Container 7 Case(개명 2 + HEVC); HDR Trigger Matrix + 709 HEVC Fast Path; Raster 짝수 내림 / No-upscale; frameDuration Ceiling; SDR Contract 수락 / 거부 Matrix; Cancellation Token Idempotency · 완료 후 취소 미Publish · Partial Cleanup Idempotency; Duration 허용 범위 경계; `.current` 불변조건.

## Device Gate Evidence (요약과 해시만 — Raw Media / JSON / Screenshot은 저장소에 넣지 않음)

Evidence Branch: `spike/06-media-technical-gate` @ `04d836127ddb040676a7bec2972836a331d95fe7`. 기기: LunaTestphone iPhone 12 (iPhone13,2), iOS 27.0. 모든 시나리오에서 Source Byte / mtime 불변, 이전 Evidence 보존.

| # | 시나리오 | Run / Record | Source → Output | 판정 · 실행 | 결과 |
| --- | --- | --- | --- | --- | --- |
| 1 | 4K30 SDR Raster Normalization | 기록 이전 Run(JSON 없음) | `F1DA0428-….mov` 11,531,294 B → `D7586D27-…-h264.mov` 4,355,325 B | Normalize(raster > 1080p) · Reader / Writer 108 v / 7 a · 0.88 s | **PASS** — 2160×3840 → 1080×1920, Transform Bake |
| 2 | 1080p60 → ≤30 fps Normalization | `2372D4D3-C1B3-4146-A343-D7D94F12901D` (schema 1, SHA-1 `e1367132…`) | `83E7CA5A-….mov` 9,300,189 B → `E3018749-…-h264.mov` 4,298,935 B | Normalize(frame rate > 30) · 94 v / 6 a · 0.78 s | **PASS** — 1872/600 → 1880/600 s(+0.4 Frame) |
| 3 | 결정적 35% Cancellation Cleanup | `CDA8EBBF-9756-461C-A9A0-1CD50BEE6041` (schema 2, SHA-1 `a591371b…`) | `F1DA0428-….mov` → 후보 `5DF56325-…-h264.mov` | Normalize + Auto-cancel 0.35 · 취소 요청 진행률 0.35185(39번째 Sample) · Reader / Writer `cancelled` | **PASS** — success=false, cancelled=true, Partial 없음, 후보 파일 부재, Run Leftover 0, Source 불변 |
| 4 | SDR H.264 QuickTime Fast-path Copy | `C4DCC2C1-0262-40D9-8AA8-4F937F9DC2C2` (schema 3, SHA-1 `e653c33b…`) | `C37B4967-….mov` 4,776,723 B → `C87C4FD7-…-copy.mov` 4,776,723 B, 양쪽 SHA-256 `b0fb3119…` | Ready QuickTime · Copy · 0.003 s | **PASS** — Byte-identical. 이 Source는 `.automatic` Picker가 HDR 촬영본을 H.264 709로 호환 Transcode한 것으로 §5의 근거. 기록의 `outputIsValidSDR=false`는 Copy에 Normalization Contract를 잘못 적용한 진단 결과이며 Copy 실패가 아니다(§6). |
| 5 | HEVC Main10 HLG Rec.2020 Dolby Vision → H.264 8-bit Rec.709 | `0A6A18C4-DA65-4FD7-B791-0B13120D8330` · Result JSON 7,620 B · SHA-256 `8e8aefe83184d90963e37f0ceaaff19ac71173cd87b33edb0e7dfec103af8b59` | `8AC82D3F-AD04-4762-907D-7CBDF3D1C360.mov` 3,978,911 B · SHA-256 `1c1466cf3464359894f5c31e62f11017020a5ffa14c25a2190b72911ee6c6dbf` → `CB748153-EF96-4011-9294-02402FB4002D-h264.mov` 4,684,006 B · SHA-256 `44c124b8363e624768b5df330a09e14ec0fb6b729fe7e4cf2fee905c9e584908` | Normalize(HLG transfer, Rec.2020 primaries / matrix, 10-bit, 10-bit profile, Dolby Vision `dvvC`) · Reader / Writer completed · 106 v / 10 a · 2.13 s | **PASS** — 출력 avc1 High L4.0, bpc n/a(8-bit), 709 / 709 / 709, MDCV / CLLI / AVE / DV 없음, Identity Transform, 1080×1920 Portrait, 29.72 fps, 2140/600 s(+1 Frame), AAC 48 kHz Stereo Passthrough, `outputIsValidSDR=true`, `outputSDRProblems=[]`, **사용자 A/B 전 항목 PASS**(방향 · Crop / 늘어짐 없음 · 구도 동일 · 하이라이트 · 그림자 · 색 · 피부 / 중립 · 움직임 · 오디오) |

관측 시간(0.78 / 0.88 / 2.13 s)은 Phase 13 Baseline Input이며 Threshold가 아니다.

## Remaining Non-blocking Items

- Tone-curve 품질은 단일 기기 · 단일 사용자 A/B로만 검증됨.
- 출력 Duration은 최대 +1 Frame(§7).
- Resource Metrics(Thermal / Footprint / Capacity)는 0.25 s Sampling Lower Bound.
- Storage Estimate Formula / Safety Reserve, Recovery 깊이, Retry / Progress UX 메커니즘, Low-resolution Upscaling Policy는 후속 구현 Gate. — **ADR-047(2026-09-18):** Recovery 깊이(No Resume)와 Upscaling Policy(No Upscaling)는 해소; Storage Formula / Reserve와 Progress / Retry 메커니즘은 여전히 Pending. — **ADR-050 부분 승인(2026-10-02):** Import 계산 정책(Formula와 256 MiB Reserve)은 Accepted되었고 순수 Estimator로 구현되었다(연결 없음); 검사 경계 연결과 Integration은 Pending. Progress / Retry 메커니즘은 Pending.
- 알려진 `ProjectEditorModelTests` Thumbnail Request-order Flake는 Phase 6 Spike와 무관하다.

## Non-goals

- Phase 6 Production 구현 자체, Export Codec / Container, Post-V1 Container / Orientation 확장, Tone-mapping 품질 계량화.

---

# ADR-046 — Canonical Capture Codec and Photos Import Codec Boundary

**Date:** 2026-09-18
**Status:** Accepted (사용자 승인)

**Clarifies:** ADR-033(Capture-first Recording — 촬영 출력 Codec 불변조건 추가), ADR-044 Revision 1(Container Eligibility와 Codec Eligibility의 분리), ADR-045 §1 / §2(Preflight 순서에 Codec Family 단계 삽입, "H.264 또는 HEVC" Fast Path 조건의 정확한 의미), ADR-043 Consequences의 "기타 Codec 사유" 표현(Codec은 Normalization 사유가 아니라 Preflight Eligibility).

**Explicitly Unchanged:** ADR-042 Duration / Per-item Filtering / Structural UX, ADR-043 Revision 1 Portrait-only, ADR-044 Revision 1 QuickTime-only 및 모든 승인 Copy, ADR-045의 Working Media 출력 계약 · Tone-mapping · Duration 허용 범위 · Cancellation / Ownership · `.current` 전제 · AVE 규칙 · Evidence, ADR-029 / ADR-033의 Recording Duration · Orientation · Permission · Interruption · Staging · Photos Save · Cleanup · Media Safety 계약, Export Codec(Phase 9, 별도 결정), Low-resolution Upscaling / Storage Formula / Recovery 깊이 / Retry · Progress 메커니즘(Pending 유지).

## 1. Context

Phase 6 Step 1(순수 Preflight Classifier)은 "그 밖의 조건은 모두 만족하지만 Video Codec이 H.264 / HEVC가 아닌 QuickTime Source"의 처리가 문서에서 정의되지 않아 BLOCKED되었다(ADR-043 Consequences는 "기타 Codec 사유"를 Normalization 대상으로, ADR-044 §4는 "지원되는 Video / Audio 특성"을 Preflight 규칙으로 서술). 동시에 Mellow 자체 Camera 촬영은 Codec을 명시하지 않아 기기 기본값에 의존하고 있었다. 승인된 V1 Workflow는 **Mellow / iPhone 촬영 → 짧은 세로 QuickTime Clip → Mellow 준비 / 편집**이며 Mellow는 범용 Media Transcoder로 확장하지 않는다.

## 2. Canonical Direct-Camera Invariant

Mellow가 제어하는 Camera Recording은 하나의 정본 Capture Format만 생성한다.

- 실제 Container: QuickTime Movie, 확장자 `.mov`
- Video Codec: **H.264**
- SDR(HDR / 10-bit Capture Format 사용 안 함)
- 이미 승인된 Capture Resolution / Frame Rate 계약(1080p, 30 fps)
- 호환되는 녹음 Audio를 승인된 Capture Format에 유지

Capture Session 구성 시 다음을 수행한다.

1. 실제 Video Connection의 `availableVideoCodecTypes`를 조회한다.
2. H.264 지원을 요구한다.
3. 그 Video Connection에 H.264 Output Settings를 **명시적으로** 적용한다.
4. Recording 시작 전에 설정이 적용되었음을 검증한다.
5. H.264를 구성할 수 없으면 Capture Setup을 **안전하게 실패**시킨다(기존 Typed Failure 경로).
6. HEVC / ProRes / ProRes RAW / 기타 Codec으로 **조용히 Fallback하지 않는다.**
7. Unknown / Default Codec으로 Recording을 시작하지 않는다.
8. 기존 Recording Duration · Orientation · Permission · Interruption · Staging · Photos Save · Cleanup · Media Safety 동작을 모두 보존한다.

이는 내부 불변조건이며 사용자 선택 설정이 아니다. Codec Picker나 Settings UI를 추가하지 않는다.

**근거:** 승인된 H.264 Working Media 방향과 일치; 기기 의존 Capture 기본값 제거; Mellow 촬영 Clip의 불필요한 Normalization 회피; Preview / 편집 / Export 호환 단순화; Clip이 최대 5초라 HEVC 대비 저장 공간 불이익이 실질적으로 작음.

## 3. Canonical Photos-Import Codec Eligibility

Photos Import는 실제 QuickTime Container(ADR-044) Source 중 Video Codec이 다음 Family에 속하는 것만 지원한다.

- **H.264 Family:** `avc1`, `avc3`, 신뢰성 있게 식별된 동등 H.264 Sample Entry
- **HEVC Family:** `hvc1`, `hev1`, 신뢰성 있게 식별된 동등 HEVC Sample Entry

그 밖에 적합한(QuickTime · Portrait · Duration · Readable) Source에 대해:

- 지원 SDR H.264 또는 SDR HEVC가 Ready 경계(Rec.709 / 709 / 709, ≤ 8-bit, ≤ 1080p-class, ≤ 30 fps) 안이면 **Fast Path**(복사).
- 지원 H.264 / HEVC에 승인된 Normalization 사유(HDR / Dolby Vision, High Bit Depth, 30 fps 초과, 1080p-class 초과 Raster)가 있으면 **Normalization**.
- **Codec Family 자체는 Normalization을 강제하지 않는다.** Ready 계약을 만족하는 HEVC는 그대로 Fast Path다.

iPhone Camera의 "High Efficiency" 설정이 HEVC를 만들므로 HEVC Import 지원을 유지한다.

## 4. Reliable Codec-Family Identification

- Codec Family는 Video Track Format Description의 Media Subtype(FourCC)과, 필요 시 Sample Description Extension Atom(`avcC` / `hvcC`)으로 판정한다.
- 파일 확장자, 파일명, Container Brand, Photos Metadata는 Codec 판정에 참여하지 않는다.
- 신뢰성 있게 식별할 수 없는 Codec(Format Description 없음, 알 수 없는 FourCC)은 **Unknown**으로 취급하며 Unknown은 Unsupported다.
- Profile / Bit Depth(`avcC` profile_idc 110 / 122 / 244, `hvcC` Main10 등)는 Codec Family 판정이 아니라 ADR-045 §2의 HDR / >8-bit Normalization 사유 판정에 사용한다.

## 5. Unsupported-Codec Filtering Semantics

V1에서 지원하지 않는 Import Codec: Apple ProRes 계열(`apch` / `apcn` / `apcs` / `apco` / `ap4h` / `ap4x` 등), Apple ProRes RAW 계열(`aprn` / `aprh` 등), Motion JPEG(`jpeg` / `mjpa` / `mjpb` 등), 기타 Codec Family, Unknown / 신뢰성 없이 식별된 Codec.

Unsupported Codec 항목은:

- Preflight에서 거부된다(Unsupported / Invalid Media 범주).
- Fast-path Copy에 들어가지 않는다.
- Normalization에 들어가지 않는다.
- Materialize / Persist / Append / Replace에 사용되지 않는다.
- 기존 승인 Invalid / Unsupported Media UX 계약을 사용한다: 다중 선택 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`(복합 사유 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`), 단일 후보 / Replace `영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.`(ADR-044 Revision 1).
- Photos 원본을 보존한다.
- Replace에서는 기존 Clip · Media · Metadata · 순서 · Slot을 보존한다.

**Codec별 사용자 안내 문구는 도입하지 않는다.**

## 6. Select Clips / Add / Replace

- **Select Clips / Editor Add:** 후보마다 독립 판정; Unsupported-codec 항목만 제외하고 지원 항목으로 계속; 전부 제외되면 Select Clips는 Project 미생성, Add는 무변경; 완료된 Operation당 통합 안내 최대 1회(ADR-042 Revision 4 우선순위 유지).
- **Replace(단일 후보):** Unsupported-codec 후보는 거부하고 기존 Clip을 보존하며 부분 교체 없음.
- Accepted Set Atomicity(ADR-042 Revision 3 / 4)는 모든 Preflight 제외(Duration / Invalid / Container / Codec / Non-portrait) 이후의 Accepted Set에 그대로 적용된다.

## 7. Relationship to ADR-044 (Container)

Container Eligibility(실제 `ftyp` Brand = QuickTime)와 Codec Family Eligibility는 **서로 다른 독립 검사**다. QuickTime Container 안에 ProRes가 있으면 Container는 통과하고 Codec에서 거부된다. MP4 안에 H.264가 있으면 Container에서 거부된다(Codec 판정에 도달하지 않음). 어느 쪽도 Remux / Transcode 경로를 만들지 않는다.

## 8. Relationship to ADR-045 (Normalization) — Canonical Preflight Order

ADR-045 §1의 순서에 Codec Family 단계를 삽입하여 **하나의 순서**를 모든 문서와 구현에 적용한다.

1. 전체 Source Duration `1.0s <= duration <= 5.0s`(ADR-042)
2. Readable / Video Track / Protected 아님(Preflight Invalid)
3. 실제 Container Brand — QuickTime만(ADR-044)
4. **Video Codec Family — H.264 또는 HEVC만(ADR-046); 그 밖은 Unsupported**
5. Presentation Orientation — `presentationHeight > presentationWidth`(ADR-043 Revision 1)
6. Normalization 사유 판정(ADR-045 §2: HDR / >8-bit, > 30 fps, > 1080p-class) — **ADR-048(2026-09-30):** 5와 이 단계 사이에 Working-raster Feasibility → Audio Facts 신뢰성 단계가 삽입되었고 Normalization 사유 끝에 Audio Transcode(non-AAC)가 추가되었다. 현재 Canonical 순서는 ADR-048을 따른다.

앞선 단계의 거부가 뒤 단계보다 우선하며, 1–5는 어느 것도 Normalization 사유가 아니다. Unsupported Codec은 Orientation 및 Normalization 사유보다 앞서 결정된다. ADR-045 §2의 "Phase-5-ready SDR QuickTime(H.264 또는 HEVC …)"는 이 Family 정의를 따른다.

## 9. Explicitly Unchanged

§상단 목록 참조. 특히 Working Media 출력은 여전히 H.264 High 8-bit 709 QuickTime이며 Export Codec은 별도 Phase 9 결정이다.

## 10. Current Implementation Audit (2026-09-18, 읽기 전용)

- Recording 메커니즘: `AVCaptureSession` + **`AVCaptureMovieFileOutput`**(`CameraSessionWorker.swift`), `movieFragmentInterval` 1 s, `maxRecordedDuration` 설정, `startRecording(to:recordingDelegate:)`.
- 출력 Container / 확장자: Staging URL은 `RecordingStagingStore`가 `<UUID>.mov`로 생성; `AVCaptureMovieFileOutput`은 QuickTime Movie를 기록한다.
- Video Codec: **명시적으로 구성하지 않는다.** `availableVideoCodecTypes` 조회, `setOutputSettings(_:for:)`, `AVVideoCodecKey` 어느 것도 없음 → `AVCaptureMovieFileOutput`의 기본 동작(`availableVideoCodecTypes.first`, 최신 iPhone에서 HEVC)에 의존하므로 **기기 기본값에 따라 HEVC가 기록될 수 있다.**
- HDR / Color: `isVideoHDREnabled` / `automaticallyAdjustsVideoHDREnabled` / `activeColorSpace` 미설정 → Session Preset `hd1920x1080`이 고른 Format에 따라 10-bit HDR이 기록될 가능성을 배제하지 못한다(검증 필요).
- Video Connection: `movieOutput.connection(with: .video)`는 `startRecording` 직전에만 얻어 `videoRotationAngle = 90` / Mirroring을 설정한다. Output Settings는 `configure(position:)`의 `session.addOutput(movieOutput)` 이후(Session Configuration 안, Recording 시작 전)에 같은 Connection에 적용하는 것이 자연스럽다.
- 실패 경로: `fail(.cameraUnavailable / .unsupportedConfiguration / .configurationFailed)` Typed Failure가 이미 존재하여 "H.264 불가 → 안전 실패"에 재사용할 수 있다.
- Resolution / Frame Rate / Audio: Preset `hd1920x1080`, `activeVideoMin/MaxFrameDuration = 1/30`, Zoom 1, Microphone Input 선택적(`attachAudioInputLocked`, 무음 Track 생성 없음).
- Tests: Capture Codec / 출력 Media를 검사하는 Test는 없음(`RecordingCoordinatorTests` / `CameraModelTests`는 `FakeCameraCaptureService` 기반).
- 촬영 결과의 이후 취급: Recording은 Photos에만 저장되고 Project에 붙지 않는다(ADR-033 / ADR-041). Mellow 촬영 Clip이 Project에 들어오는 유일한 경로는 Photos Import Preflight이며, 현재 `RecordingMediaInspector`는 Playable / Video Track / Duration만 검사하고 Codec을 가정하지 않는다.

**결론:** 현재 구현은 Codec 기본값에 의존하며 §2 불변조건을 만족하지 않는다 → ROADMAP Phase 6에 좁은 범위의 Direct-camera H.264 Enforcement Task와 회귀 Test를 추가한다.

## 11. Consequences for Phase 6

- Step 1 Blocker 해소: `ImportPreflightClassifier`는 Codec Family 단계(§8 4단계)를 갖고 Unsupported Codec을 Preflight 거부로 매핑한다.
- Facts Model은 Video Codec FourCC / Family / Profile Bit Depth를 표현한다(ADR-045 §11 `ImportSourceFacts`).
- Direct-camera H.264 Enforcement는 Step 1 검토 / 커밋 후 별도의 좁은 Production 변경으로 구현한다(Camera Behavior 회귀 Test 포함).
- Preparation Presentation, Copy, Accepted Set 계약은 변경 없음.

## 12. Post-V1 Non-goals

ProRes / ProRes RAW / MJPEG / 기타 Codec Import 지원, Codec 변환 옵션, Capture Codec 설정 UI, HEVC Capture 복원 — 모두 Post-V1이며 Phase 6 Blocker가 아니다.

## 13. Remaining Technical Implementation Details (Product 정책 재개방 아님)

- `AVCaptureMovieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)` 적용 시점(Configuration 안 vs Recording 직전)과 `outputSettings(for:)` 재검증 방법.
- SDR Capture Format 보장 방법(`automaticallyAdjustsVideoHDREnabled = false` + `isVideoHDREnabled = false` 또는 Format 선택)과 iPhone 12에서의 실제 Format 확인.
- Codec Family 동등 Sample Entry 목록의 정확한 FourCC 집합(구현 상수; Unknown은 항상 Unsupported).

---

# ADR-047 — Working-Media Raster and Interrupted-Normalization Recovery

**Date:** 2026-09-18 (Revision 1: 2026-10-01)
**Status:** Accepted (사용자 승인)

## Revision 1 — Even-Raster Parity Alignment Rendering (2026-10-01)

**Status:** Accepted (사용자 승인). 이 Revision은 Phase 6 Step 4B 독립 Review에서 드러난 좁은 모호성 하나를 닫는다: 원래 Decision 1은 Aspect 보존 · Crop 없음 · Padding 없음 · 각 변 짝수 내림을 함께 요구하지만, 계산된 변이 홀수일 때 짝수 내림은 출력 Aspect Ratio를 아주 조금 바꿀 수밖에 없어 네 요구를 동시에 정확히 만족할 수 없었다. V1은 그 나머지를 제한된 Parity 정렬 Resampling으로 처리한다. Decision 1의 Raster 공식 · No Upscaling, Decision 2의 No Resume / Recovery 결정, ADR-048은 바뀌지 않는다. 아래 내용이 Render Geometry의 정본이며 아래의 최초 본문은 보존된다(충돌 시 Revision 1 우선). 이 Revision은 Step 4B 구현 완료를 뜻하지 않는다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. 이 Render Geometry 규칙(전체 Frame, Crop · Padding 없음, 변당 최대 1 출력 Pixel의 축별 Parity Resample, 정확한 짝수 Raster)은 Step 4B(`da1f337`)로 구현 · 검증되었다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현이다.

### Render Geometry Rule

1. 목표 Raster 계산은 그대로 정본이다: `scale = min(1.0, 1080 / presentationWidth, 1920 / presentationHeight)`, 각 변을 `presentation × scale`로 내림한 뒤 양의 짝수로 내림한다(Decision 1).
2. Source Presentation Frame 전체를 보존한다.
3. Renderer는 Source Content를 어떤 경우에도 Crop하지 않는다.
4. Renderer는 Padding · Letterbox · Pillarbox · 합성 테두리를 추가하지 않는다.
5. 각 계산된 출력 변은 양의 짝수 정수로 내림한다(Decision 1 그대로).
6. 짝수 정렬이 홀수인 계산 변에서 1 Pixel을 줄이면 Renderer는 가로축과 세로축을 각각 독립적으로 Resample하여 Source Presentation Frame 전체를 계획된 정확한 짝수 Raster에 맞출 수 있다.
7. 이것은 제한된 Parity Quantization으로 승인된다.
   - 영향받는 출력 변을 최대 1 출력 Pixel만 바꿀 수 있다(내림된 계산 값 기준).
   - 짝수 크기 Encoding 요구를 만족하기 위해서만 존재한다.
   - 일반 목적의 늘리기(Stretch) 정책이 아니다.
   - 임의의 Aspect 왜곡을 정당화하는 데 쓰지 않는다.
   - 사용자가 고르는 Fill / Fit / Stretch 옵션이 되지 않는다.
   - 허용 한계는 백분율이 아니라 영향받는 변당 1 출력 Pixel이라는 절대값이다.
8. 이 규칙은 Crop · Padding · Upscaling · 최소 출력 해상도 · 해상도 선택 · 새 Normalization 사유 · 새 사용자 안내 Copy나 범주를 도입하지 않는다.
9. Classifier 동작은 바뀌지 않는다: 1080p-class를 초과하는 Presentation Raster만 Raster Normalization 사유를 만들고, 저해상도 Source는 확대하기 위해 정규화되지 않으며, 다른 사유로 정규화되는 저해상도 Source는 필요한 짝수 정렬을 제외하고 Source 크기 Raster를 유지한다.
10. **ADR-049(2026-10-01) 명확화:** 보존 대상 "Presentation Frame"은 Clean-aperture Presentation 사각형(Pixel Aspect Ratio · preferredTransform 적용)이다. Non-full Clean Aperture Source에 대해 이 규칙은 Geometry 전용 SDR 경로(ADR-049 Case C)로 만족시키며, 승인된 내장 Compositor로는 경계 Sample 손실 / Aperture 밖 번짐 없이 만족시킬 수 없는 Non-full HDR / Wide-color / SDR 미증명 Source는 Crop · Padding으로 우회하지 않고 Preflight에서 거부한다(ADR-049 Case D).

| Source Presentation | 계산된 변(내림) | 짝수 출력 | 렌더링 |
| --- | --- | --- | --- |
| 720×1280 | 720×1280 | 720×1280 | 그대로(Resample 없음) |
| 2160×3840 | 1080×1920 | 1080×1920 | 균일 0.5 축소 |
| 1080×1919 | 1080×1919 | 1080×1918 | 세로만 홀수: 전체 Frame을 세로 1919 → 1918로 Resample, 가로 1:1, Crop · Padding 없음 |
| 2160×3842 | 1079×1920 | 1078×1920 | 가로만 홀수: 전체 Frame을 1078×1920에 맞춰 축별 Resample, Crop · Padding 없음 |
| 719×1279 | 719×1279 | 718×1278 | 두 변 모두 홀수: 각 변 1 Pixel 정렬, 전체 Frame 유지 |

**Resolves:** ADR-045가 Pending으로 남긴 Phase 6 Step 4의 두 Blocker — (1) Low-resolution Source Upscaling Policy(1080p-class Working Media의 최종 Raster Sizing), (2) Import Durable Operation Identity / Recovery 깊이(Normalization 도중 Process 종료 이후의 복구 의미)와 ADR-039 STEP 12B Orphan / Workspace Predicate 확장 방식. ROADMAP Phase 6 "Pending Technical Gate", ARCHITECTURE 38절 / 84절, PRODUCT / FEATURES Open Question의 동일 항목.

**Clarifies:** ADR-020 / ARCHITECTURE 25절 Failure Boundary C / E / F의 V1 Import 적용 범위(Live Process 안의 Retry만 Recovery이며 Process 종료 이후는 Cleanup), ADR-039 Implementation Note의 "Phase-5 Composition / Add는 Durable Operation Identity를 갖지 않는다(Repository Row 자체가 Commit)"를 Phase 6 Import Normalization까지 확장, ADR-045 §3 Raster 규칙의 Upscale 부분.

**Explicitly Unchanged:** ADR-042의 `1.0s <= 전체 Source Duration <= 5.0s`(양 끝 포함) Eligibility · Per-item Filtering · 통합 안내 · Preparation Sheet · 취소 · Runtime 실패 · `다시 시도`(Live Session 안 Source Handle 유효 시) · Storage 부족 Presentation, ADR-043 Revision 1 Portrait-only, ADR-044 Revision 1 QuickTime-only Container, ADR-046 H.264 / HEVC-only Codec Family와 Direct-camera H.264, ADR-045의 HDR / >8-bit · >30 fps · >1080p-class Normalization 사유 · SDR / H.264 High 8-bit / Rec.709 / QuickTime `.mov` 출력 · Transform Bake + Identity · AAC Passthrough · Duration 허용 범위 · Idempotent Cancellation Token · Partial Output 제거 책임, ADR-020 / ADR-037 / ADR-040의 Accepted Set Atomic Commit과 Replace 보존, Photos 원본 불변, Export Codec / Container(Phase 9), Import Storage Estimate Formula / Safety Reserve(Pending 유지), Aggregate Progress / Retry Source-handle 메커니즘(Pending 유지).

**이 ADR은 Phase 6 Step 4 Production 구현을 의미하지 않는다.** 두 Blocker를 해소하여 `WorkingMediaNormalizer` / `SDRWorkingMediaContract` 구현을 시작할 수 있게 하는 결정이며 Normalizer · Preparation Operation · Presentation · Storage Preflight는 여전히 미구현이다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. Raster 공식(No Upscaling)은 Step 4A(`75c2cb9`)에, Normalizer와 Revision 1 Render Geometry(전체 Frame, Crop · Padding 없음, 정확한 짝수 Raster)는 Step 4B(`da1f337`)에 구현 · 검증되었다. Preparation Operation · Presentation · Storage Preflight는 여전히 미구현이다.

## Context

Phase 6 Step 3(`ImportSelectionPreflight`, `c570d5b`)까지 Preflight 계층은 완성되었고 다음 단위인 `WorkingMediaNormalizer`는 두 미결정에 막혀 있었다.

첫째, ADR-045 §3은 Scale-down Bounding Box 규칙만 확정하고 "Low-resolution Source의 Upscale 여부는 여전히 Pending"으로 남겼다. 720×1280 60 fps처럼 1080p-class 안에 들어오지만 다른 사유로 Normalization이 필요한 Source의 출력 크기를 정할 수 없었다.

둘째, ADR-020 / ARCHITECTURE 25절은 Media Commit Lifecycle에 Durable Operation Identity와 Relaunch 후 Recovery Candidate 보존을 요구하지만, Phase 5 STEP 12B(ADR-039)는 Composition / Add가 Durable Operation Identity를 갖지 않고 Repository Row가 곧 Commit이며 버려진 `ProjectWorkspace/<op>/`는 다음 시작에 Sweep된다는 모델을 확정했다. Phase 6 Normalization이 이 모델을 그대로 따를지(Cleanup) Relaunch 재개(Resume)를 추가할지가 결정되지 않았다.

사용자는 두 항목을 다음과 같이 승인했다.

## Decision 1 — Canonical Working-Media Raster (No Upscaling)

### Upscale 금지

- Phase 6 Normalization은 Source를 절대 확대하지 않는다.
- Presentation Raster(`preferredTransform` 적용 후)가 이미 1080p-class Portrait Envelope(짧은 변 ≤ 1080, 긴 변 ≤ 1920) 안에 들어오는 Portrait Source는 Codec이 요구하는 짝수 정렬을 제외하고 Presentation 크기를 그대로 유지한다.
- 예: 720×1280 → 720×1280, 1080×1440 → 1080×1440, 1080×1920 → 1080×1920.
- 1080×1920을 만들기 위해 늘리거나 자르거나 채우거나 Pixel을 합성하지 않는다.
- Project Presentation / Framing(Fill + Crop)은 이후 Composition의 책임이며 Normalized Media 파일은 전체 Portrait Frame을 보존한다(ADR-022 / ARCHITECTURE 38절 Spatial Normalization Contract 그대로).

### Scale-down Only — Canonical Formula

Portrait Presentation Raster `(width, height)`에 대해:

- `scale = min(1.0, 1080 / width, 1920 / height)`
- 출력 = `(width × scale, height × scale)`을 각 변 짝수로 **내림**한 양의 정수 크기
- Aspect Ratio를 보존하고 Source Presentation 크기를 초과하지 않으며 짧은 변 1080 / 긴 변 1920을 초과하지 않는다. — **Revision 1(2026-10-01):** Aspect 보존은 짝수 정렬 전 계산 기준이며, 정렬로 생기는 변당 최대 1 출력 Pixel 차이는 축별 Resampling으로 처리하는 제한된 Parity Quantization이다(Crop · Padding 없음, 위 Revision 1).
- Presentation Transform은 Pixel에 Bake하고 출력 Transform은 Identity다(ADR-045 §3 유지).
- 짝수 정렬은 영향받는 변마다 최대 1 Pixel만 제거하며 Upscale · Crop 정책 · Aspect-fill 어느 것도 아니다. — **Revision 1(2026-10-01):** "제거"는 출력 Raster 크기를 1 Pixel 줄인다는 뜻이며 Source Content를 잘라내는 것이 아니다; 전체 Presentation Frame을 그 크기로 Resample한다.
- V1에는 별도의 "최소 출력 크기"가 없다.
- **ADR-048(2026-09-30):** 짝수 정렬 결과가 엄격한 Portrait(`outputHeight > outputWidth`)이 아니면(예: 1080×1081 → 1080×1080) 그 Source는 Preflight의 Working-raster Feasibility 단계에서 기존 Invalid / Unsupported 범주로 거부되며 Normalization Plan에 도달하지 않는다. 늘리기 · Crop · Padding · 여백으로 우회하지 않는다.

| Source Presentation | scale | 출력 |
| --- | --- | --- |
| 720×1280 | 1.0 | 720×1280 |
| 1080×1440 | 1.0 | 1080×1440 |
| 1080×1920 | 1.0 | 1080×1920 |
| 2160×3840 | 0.5 | 1080×1920 |
| 1440×2560 | 0.75 | 1080×1920 |
| 1620×2160 | 0.6667 | 1080×1440 |
| 1080×1919(홀수) | 1.0 | 1080×1918 |

### Classifier와의 관계

- `ImportPreflightClassifier`의 Raster Normalization 사유는 여전히 1080p-class를 **초과하는** Presentation Raster에만 적용된다.
- 저해상도 자체는 거부 사유도 Normalization 사유도 아니다(Ready 조건을 만족하는 저해상도 SDR H.264 / HEVC는 Fast-path Copy).
- HDR / >30 fps 등 다른 승인 사유로 Normalization하는 저해상도 Source는 Presentation 크기를 그대로 유지한 채 정규화된다(확대 없음).
- 새 사용자 안내 · Alert · 해상도 선택 · Upscale 옵션 · 설정은 도입하지 않는다.

## Decision 2 — Interrupted-Normalization Recovery (No Resume)

### Resume 없음

Normalization(또는 Import Preparation Operation의 어느 단계) 도중 App이 종료·강제 종료·Crash되거나 그 밖의 이유로 Process를 잃으면:

- 중단된 Operation은 재개하지 않는다.
- Checkpoint 기반 이어가기, Durable Resumable Operation ID, Background Continuation 약속은 없다.
- 사용자가 그 Media를 여전히 원하면 Select Clips / Add / Replace를 다시 시작한다.
- In-process Run / Workspace UUID(현재 `ProjectMediaStore.beginWorkspace`의 `ProjectWorkspace/<UUID>/`)는 격리와 파일명을 위한 Ephemeral 값으로 쓸 수 있으나 Durable Resume 계약이 되지 않는다.

ADR-020 / ARCHITECTURE 25절과의 관계(V1 Import에 대한 Clarification):

- Boundary C(Staged 완료 후 Crash) / E(Normalization 도중 실패) / F(Final Media 생성 후 Metadata Persistence 실패)에서 "Recovery Candidate 보존"은 **Live Process 안의 같은 Accepted Set Retry(ADR-042 Revision 4 `다시 시도`)**를 위한 것이다.
- Process 종료 이후에는 Import Operation-owned Artifact 전체가 Recovery Classification상 Discardable Temporary Media이며 Recoverable Media 분류는 V1 Import에서 비어 있다.
- Boundary G(Metadata Persistence 성공 후 UI 갱신 전 Crash)는 Row가 곧 Commit이므로 Relaunch에서 Persisted Metadata가 Source of Truth이며 Resume가 없으므로 중복 생성도 없다.
- ADR-039 Implementation Note의 "Repository Row 자체가 Commit" 모델이 Phase 6 Import Normalization에도 그대로 적용되며 STEP 12B Orphan Predicate는 **확장하지 않는다**(Future Compatibility Caveat의 조건 — Row 밖의 복구 가능한 Durable State — 는 발생하지 않는다).

### Ownership과 Atomicity

- Operation Workspace로 복사된 Source 파일과 모든 Normalization 출력은 Accepted Set 전체의 준비가 성공하고 기존 Durable Project Commit 경계(Materialize → Project State → Persist → Read-back, ADR-020 / ADR-037)에 도달할 때까지 Operation Workspace 소유다. — **ADR-050 분류 규칙 승인(2026-10-02)에 따른 개정:** Save가 성공한 뒤의 Read-back 실패 · 불일치는 Commit 전 실패가 아니라 "Commit됨 · 확인 안 됨"이며 참조 가능 Media를 보존하고 Rollback하지 않는다; Save 오류는 다시 읽은 상태로 분류한다(ADR-050 050-D D8.0). 순수 분류기만 구현되었고 현재 Production 코드는 아직 이 문구의 이전 동작이며 연결은 Pending이다.
- 부분 · 임시 · 개별 완료 Workspace 출력은 어떤 경우에도 Committed Project-owned Media가 아니다.
- Process 종료는 Clip을 Append하거나 기존 Clip을 Replace하거나 Project Metadata를 바꾸거나 부분 결과를 노출하지 않는다.
- Replace는 전체 Replacement Operation이 승인된 Commit 경계에 도달하지 않는 한 기존 Clip · Media · Metadata · 순서 · Slot을 보존한다(ADR-040 / ADR-042 Revision 4 §7).
- Photos 원본은 변경되지 않는다.
- Operation에 영향을 주는 실패 또는 중단은 부분적으로 Commit된 Accepted Set을 남기지 않는다(ADR-042 Revision 3 / 4 Atomicity 그대로).

### 다음 시작 Cleanup

- 이후 시작에서 버려진 · 미Commit Normalization Workspace와 부분 출력은 Cleanup 후보다.
- 기존 시작 시 Sweep 경계(ADR-039 STEP 12B `ProjectStartupRecoveryCoordinator`: `liveWorkspaceIDs`에 없는 Canonical `ProjectWorkspace/<UUID>/` 제거 → Row 없는 Canonical `Projects/<P>/` 제거 → Durable 참조 없는 Canonical `Projects/<P>/Media/<UUID>.mov` 제거)를 재사용하며 Resumable Job Database를 정의하지 않는다.
- **이미 보장되는 것(구현 완료, Phase 5 STEP 12B):** Workspace 직속 파일을 포함한 버려진 Workspace Directory 전체 제거, Idempotency(Missing = 성공, 두 번째 실행 무작업), App-owned Root Containment · Canonical UUID Round-trip · Symlink 거부 · 기대 Type 일치 · Noncanonical 보존, Metadata 무변경, 후보별 Failure Isolation + Log + 다음 실행 Retry, Committed Media(Durable 참조) 보존, Photos / CaptureStaging / tmp 미열거.
- **Phase 6이 추가로 만족해야 하는 요구(미구현):** Normalizer의 중간 · 출력 파일이 Operation Workspace Directory **안에서만** 만들어져 기존 Predicate로 Cleanup되게 할 것(Workspace 밖 · Project Directory 안에 Normalization 임시 파일을 두지 않는다), Workspace 안의 하위 Directory를 쓴다면 Sweep이 Directory 전체 제거로 이를 포함함을 Test로 고정할 것, Fast-path / Normalized 출력의 Materialize(Rename)는 Accepted Set 전체 준비 완료 뒤에만 시작할 것. — **구현 상태(2026-10-02):** Normalizer 측 의무는 구현되었다(`da1f337`: 호출자가 준 Destination 하나만 만들고 소유하며 실패 · 취소 시 자기 소유 Output만 제거하고 Resume · Checkpoint가 없다). Operation Workspace 생성 · 연결과 시작 시 Sweep을 포함한 End-to-end 검증은 미구현이다.
- Cleanup은 Committed Project-owned Media나 Photos 원본을 절대 삭제하지 않으며 Missing 파일은 안전하게 처리한다.
- Symbolic Link · Traversal · Containment · Ownership 보호는 변경하지 않는다.
- Cleanup 실패는 기존 Recovery 메커니즘으로 Log / 다음 실행 Retry될 수 있으나 버려진 작업을 Resumable Import로 바꾸거나 Project를 변경하지 않는다.

### Foreground 취소는 별개

- Process가 살아 있는 동안의 사용자 `취소`는 기존 취소 경로(Idempotent Cancellation Token, `cancelReading` / `cancelWriting`, 만든 Operation의 Partial Output 즉시 제거 — ADR-045 §8, ADR-042 Revision 4 §2)를 사용한다.
- Process 종료는 비동기 Cancellation Handler 완료에 의존할 수 없으므로 시작 시 Cleanup이 버려진 Workspace의 Safety Net이다.
- 두 경로 모두 부분 출력을 Publish하지 않는다.

## Rationale

- Upscale은 Pixel을 합성할 뿐 정보가 늘지 않으며 iPhone 12 Encode 시간 · 저장 공간 · 열을 늘린다. Mini Vlog 의도에는 원본 화질 보존이 맞고 Project Canvas 적합은 Composition의 Fill + Crop이 이미 담당한다.
- Resume는 Durable Operation Record · Source Handle 보존(Photos Read 권한 없이는 Picker Transient 복사본에 의존) · 중복 Commit 방지 · Predicate 확장을 요구하는 반면, Import Source는 5초 이하이고 Normalization은 기기 측정에서 수 초 안에 끝난다(ADR-045 Evidence 0.78–2.13 s). 다시 선택하는 비용이 Resume 인프라의 위험보다 작다.
- 기존 STEP 12B Sweep이 이미 버려진 Workspace를 Idempotent하게 회수하므로 새 Recovery 메커니즘 없이 Media Safety 계약을 만족한다.

## Consequences

- `WorkingMediaNormalizer`의 `renderSize` 규칙과 `SDRWorkingMediaContract`의 기대 Raster 검증이 확정되어 Step 4를 시작할 수 있다.
- ROADMAP Phase 6 Task 6 / 13 / 14 / 15와 관련 Unit · Integration · Physical Test, Acceptance Criteria는 Resume 대신 Cleanup 의미로 정렬된다.
- Post-V1에서 Durable Resume / Background Normalization을 재검토할 수 있으나 V1 범위가 아니다.

## Still Pending (이 ADR이 확정하지 않음)

- Import Storage Estimate Formula와 Safety Reserve(5초 이하 전체 Source + Picker Transient 복사본 + Normalization Peak 기준)
- Implementation-specific Aggregate Progress 계산과 `다시 시도`의 Source-handle 유지 메커니즘, Filesystem Free-space API / Race 처리(구현 세부사항)

## Non-goals

- Phase 6 Step 4 Production 구현 자체, Export Codec / Container, Post-V1 Resume / Background 처리, 해상도 선택 UI.

---

# ADR-048 — Normalization Audio, Raster Feasibility, and Cadence Fallback

**Date:** 2026-09-30 (Revision 1: 2026-10-01, Revision 2: 2026-10-02)
**Status:** Accepted (사용자 승인)

## Revision 2 — Exact Cadence Validation and Leading-Gap Failure (2026-10-02)

**Status:** Accepted (사용자 승인, 2026-10-02 Asia/Seoul). 이 Revision은 Revision 1의 Cadence Grid를 구현하면서 드러난 Validation 해석 하나를 확정하고 Revision 1의 첫 Frame 규칙을 재확인한다. 충돌 시 Revision 2가 Revision 1과 최초 본문보다 우선하며, 둘은 Accepted 이력으로 보존된다. 이 Revision은 정책만 기록하며 미커밋 Step 4B 구현이 완료 · Review · Commit · Merge되었다고 주장하지 않는다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. 이 Revision의 정확한 Cadence Validation(평균 / Metadata Rate 거부 없음, 마지막 Target까지의 Grid 끝 규칙, 단일 Sample Grid)과 앞쪽 빈 구간 Typed 실패는 Task 29h와 후속 독립 Review 보정까지 포함해 Step 4B(`da1f337`)로 구현 · 검증 · Commit되었다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현이다. 실제 HDR 결과는 ADR-049 구현 상태 갱신에 기록되어 있다: `IMG_0130.MOV` · `da1f337` · LunaTestphone · 승인된 내장 Full-aperture 경로에서 소유자 시각 판정 PASS(일반 Dolby Vision 인증 아님).

**왜 Revision인가:** 두 결정 모두 Revision 1이 정한 정규화 출력 Cadence의 검증과 경계 조건에 관한 것이며 새 Normalization 사유 · 제외 범주 · Frame Duration 공식을 도입하지 않으므로 별도 ADR이 아니다.

### 배경 (관찰)

Revision 1에 따라 Session은 정확한 종료 시각 `E`에서 끝나므로 `E`가 Grid 지점 사이에 있으면 마지막 Sample의 Duration은 `d`보다 짧다. AVFoundation의 `nominalFrameRate`나 `sampleCount / duration` 같은 평균값은 이 짧은 마지막 Sample 때문에 30을 넘을 수 있다. 예: Sample 41개, Duration `801/600`초이면 약 30.71로 보이지만 모든 인접 Presentation Time 간격은 정확히 `20/600`이다. 1초급 Clip이 Grid 경계 바로 다음 한 Tick에서 끝나면 비슷하게 약 30.95로 보일 수 있다. 이 평균값은 출력 Cadence가 30 fps보다 빠르다는 뜻이 아니다.

### Decision 1 — 정확한 Timestamp가 Cadence의 권위 있는 증거다

세 개념을 구별한다.

1. **계획 Cadence:** `d = plan.outputFrameDuration`이며 `1/30`보다 빠르지 않다(Decision 3 불변).
2. **실제 Sample Cadence:** 출력 Presentation Time은 0에서 시작하는 정확한 Grid `t_k = k × d`를 따르고, 모든 인접 간격은 정확히 `d`이며, Session이 정확한 `E`에서 끝나므로 마지막 Sample만 `d`보다 짧을 수 있다.
3. **평균 / Metadata Rate:** `nominalFrameRate` 또는 `sampleCount / duration`은 짧은 마지막 Sample 때문에 30을 넘을 수 있으며 진단용 정보일 뿐이고 정확한 Cadence Grid를 무효로 만들 수 없다.

규칙:

- 정확한 Rational Presentation-time Grid 검증이 권위 있는 Cadence 증거다.
- Validator는 빠진 Target, 중복 Timestamp, Grid 밖 Timestamp, `d`가 아닌 간격, 미래 Frame 선택, 출력 Duration 위반을 거부해야 한다.
- Validator는 평균 또는 Metadata Frame Rate 값이 30 또는 30.5를 넘는다는 이유만으로 거부해서는 안 된다(`nominalFrameRate <= 30.5`, `sampleCount / duration <= 30.5` 또는 동등한 평균 Rate 상한은 출력 유효성 거부 조건이 아니다).
- 출력 계약은 여전히 `d`가 `1/30`보다 빠르지 않도록 제한한다.
- Metadata Nominal Rate는 진단용으로 기록할 수 있지만 유효한 정확한 Sample Timing을 무효화하지 않는다.
- ADR-045 §7의 정규화 출력 Duration 허용 범위는 바뀌지 않는다.
- 평균 Rate 통계를 맞추려고 Target을 빼거나, 짧은 마지막 Sample을 건너뛰거나, Session 종료를 앞당기지 않는다(Revision 1이 그 Sample을 요구한다).

### Decision 2 — 앞쪽 빈 Video 구간은 정규화 실패다

Revision 1의 첫 Frame 규칙을 재확인한다.

- Normalization이 필요한 Source는 Target 시각 0 이하에 실제 Rendering / Composition된 Video Frame을 제공해야 한다.
- 그런 Frame이 없으면(예: 앞쪽 Empty Edit) Operation은 Typed Normalization Error로 실패한다.
- 검은 Lead-in을 합성하지 않는다.
- 미래 Frame을 시각 0으로 당겨오지 않는다.
- Timeline을 조용히 줄이거나 옮기지 않는다.
- 이것은 현재 Accepted Set Atomicity 계약 아래의 Runtime 정규화 실패로 남으며, 이 Revision은 새 Preflight 거부 범주 · 안내 · 사용자 Copy를 추가하지 않는다.
- 일반 iPhone 카메라 Source에는 이런 앞쪽 Empty Edit가 없을 것으로 예상하지만 이는 보장이 아니며 보장으로 기술하지 않는다.

### 범위 경계

- 허용 Duration 한계, Normalization 사유, Raster 규칙, Audio 처리, Tone Mapping, Aperture 경로, 취소, Cleanup, 재시도, Copy, UI를 바꾸지 않는다.
- 새 Normalization 사유 · 제외 범주 · 안내 · 사용자 문자열을 도입하지 않는다.
- 이 Revision은 Step 4B를 완료로 만들지 않는다.

### 필요한 검증

- 짧은 출력이 Grid 지점 바로 뒤에서 끝나 평균 / Metadata Rate가 30.5를 넘지만 Presentation-time Grid가 정확하면 통과해야 한다.
- 정확한 Grid에 `2d` 간격이 있는 출력은 실패해야 한다.
- 첫 실제 Frame이 0 이후인 Source는 성공적인 Publish 전에 Typed Error로 실패해야 한다.
- 어떤 우회도 마지막 Target을 건너뛰거나 Session 종료를 앞당기지 않는다.
- 실제 기기 Cadence Evidence는 계속 `IMG_0130.MOV`다: Sample 137개, Presentation Time `0 … 2720/600`, 간격 `20/600`, 정확한 종료 `2722/600`.
- 실제 HDR 시각 A/B는 Pending이며 통과로 주장하지 않는다. — **결과(2026-10-02):** 위 문장은 작성 시점의 상태다. 이후 `IMG_0130.MOV` · 현재 Step 4B 구현(`da1f337`) · LunaTestphone · 승인된 내장 Full-aperture 경로에 한해 소유자 시각 판정 PASS(`PASS — HDR to SDR appearance is acceptable.`; 일반 Dolby Vision 인증 아님).

## Revision 1 — Deterministic Output Cadence Grid and Frame Hold (2026-10-01)

**Status:** Accepted (사용자 승인, 2026-10-01 Asia/Seoul). 이 Revision은 Phase 6 Step 4B의 정규화 출력 Timing 모호성 하나를 닫는다: Decision 3은 출력 Frame Duration을 정하지만, Source Frame Timing이 그 Grid와 정확히 맞지 않을 때 정규화된 Video Sample을 어느 Presentation Time에 두는지는 정하지 않았다. 아래 Scheduling Rule이 정규화 Video 출력 Timing의 정본이며 충돌 시 Revision 1이 우선한다. Decision 1–3과 Canonical Preflight 순서를 포함한 아래의 최초 본문은 Accepted 이력으로 보존된다. 이 Revision은 Step 4B가 구현되었거나 완료되었음을 뜻하지 않으며 이 규칙은 아직 구현되지 않았다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. 이 Cadence Grid와 Frame Hold 규칙은 Task 29g로 Step 4B(`da1f337`)에 구현 · 검증되었고 `IMG_0130.MOV` 실제 기기 재검증(Sample 137개, `0 … 2720/600`, `720/600` Hold, 종료 `2722/600`)을 통과했다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현이다. 실제 HDR 결과는 ADR-049 구현 상태 갱신에 기록되어 있다: `IMG_0130.MOV` · `da1f337` · LunaTestphone · 승인된 내장 Full-aperture 경로에서 소유자 시각 판정 PASS(일반 Dolby Vision 인증 아님).

**왜 Revision인가:** Decision 3이 정규화 출력 Cadence(`outputFrameDuration`)의 정본이며, 이 Revision은 그 Cadence를 실제 출력 Sample Timing으로 실현하는 방법만 확정한다. 새 Normalization 사유 · 새 제외 범주 · 새 Frame Duration 공식을 도입하지 않으므로 별도 ADR이 아니다.

### 실제 기기 Evidence (관찰)

Source는 실제 iPhone 카메라 촬영본 `IMG_0130.MOV` 하나다.

- QuickTime Container, HEVC Main10, HLG / Rec.2020
- 진짜 Dolby Vision 신호: `dvvC` Profile 8, Compatibility ID 4
- 신뢰성 있는 Full Aperture, Portrait Presentation
- 정확한 Duration `2722/600`, 계획 출력 Frame Duration `1/30`(ADR-049 내장 Compositor 경로)

관찰된 Source Timing:

- Video Sample 136개, Interval 135개 중 `20/600` 133개와 `21/600` 2개
- 누락된 Source Frame은 없다.
- 두 긴 Interval 때문에 뒤따르는 Source Sample이 명목 Grid에서 먼저 `1/600`, 그다음 `2/600` 늦어졌다.

LunaTestphone(iPhone 12, iOS 27.0)에서 승인된 내장 AVFoundation Tone-mapping 경로로 관찰된 동작:

- `AVAssetReaderVideoCompositionOutput`은 Sample 136개를 내보냈다.
- 각 Source Sample을 다음 `1/30` Grid 지점으로 올림하여 내보냈다.
- Grid 지점 36(시각 `720/600`)에는 Sample을 내보내지 않았으며 그 결과 `700/600`과 `740/600` 사이 Interval이 `40/600`이 되었다.
- Writer는 내보낸 136개 Sample을 모두 Append했고 거부한 Sample은 없었다.
- Encoding된 Presentation Time은 Composition 출력과 정확히 같았다.
- 결과는 엄격한 Cadence Validator 하나에서만 실패했고 Codec · SDR Rec.709 Tag · Raster · Identity Transform · HDR 신호 제거 · Audio · Duration · 사용 가능성은 그 밖에 모두 통과했다.
- 세 번의 실행이 같은 Presentation Time 순서를 재현했다.

이것은 LunaTestphone에서 이 Source로 관찰한 동작이며 보편적이거나 문서화된 AVFoundation 보장으로 취급하지 않는다. 로컬 SDK 문서는 `frameDuration`을 Rendering 간격 / 최대 출력 Frame Rate로만 설명하며 모든 Grid 지점에 Frame을 내보내도록 보장하는 Composition 설정을 문서화하지 않는다.

### Decision — Cadence Grid

정의:

- `d = plan.outputFrameDuration`(Decision 3으로 유도, 30 fps Ceiling 불변)
- `E` = 정확한 정규화 Session 종료 시각(기존 규칙 그대로)
- Target Video Presentation Time `t_k = k × d`, `k = 0`부터 시작, `t_k < E`인 모든 `k`

정규화된 Video 출력은 모든 Target `t_k`마다 정확히 하나의 Frame을 가진다.

### Frame 선택

각 Target `t_k`에 대해:

1. Presentation Time이 `t_k` 이하인 가장 최근의 Rendering / Composition 결과 Frame을 사용한다.
2. 앞선 Target 이후 새 Frame이 없으면 이전에 선택한 Frame을 이 Target에 유지(Hold)한다.
3. 미래 Frame을 더 이른 Target에 선택하지 않는다.
4. 보간 · Blend · 움직임 합성을 하지 않는다.
5. 첫 Target 이하에 Frame이 하나도 없으면 정규화는 안전하게 실패한다; 검은 Lead-in을 만들지 않으며 미래 Frame을 앞으로 당기지 않는다.
6. 인접 Target 사이에 입력 / Composition Frame이 여러 개 있으면 Target을 넘지 않는 가장 늦은 Frame을 사용하며 그보다 오래되어 대체된 Frame은 출력에서 빠질 수 있다.

용어:

- 내장 HDR / Wide-color 경로에서 유지되는 Frame은 승인된 AVFoundation Tone-mapping Composition이 이미 만든 가장 최근 Frame이다.
- SDR Aperture-geometry 경로에서 유지되는 Frame은 승인된 Geometry Renderer가 이미 만든 가장 최근 Frame이다.
- Cadence Scheduler는 Timing 선택만 수행하며 Tone Mapper나 Geometry Renderer가 되지 않는다.

### 출력 Duration

- Grid는 0에서 시작한다.
- `t_k < E`인 동안만 Target을 만든다.
- Writer Session은 기존의 정확한 정규화 종료 시각 `E`에서 끝난다.
- 따라서 마지막 Encoded Sample의 종단 Duration은 `d`보다 짧을 수 있다.
- 기존 출력 Duration 계약 `sourceDuration <= outputDuration <= sourceDuration + 1/30 s`(ADR-045 §7)는 그대로다.
- 마지막 Frame Interval을 채우기 위해 출력을 늘리지 않는다.

### Audio

- 이 규칙으로 Audio를 복제 · 보간 · 독립 재타이밍하지 않는다.
- 기존 AAC Passthrough / Transcode 규칙(Decision 1)은 바뀌지 않는다.
- 기존 Session 종료와 Audio / Video Duration Validation이 계속 우선한다.

### Validator

- Cadence Validator는 엄격하게 유지한다.
- 인접한 정규화 Video Presentation Time의 차이는 모두 정확히 `d`여야 한다.
- 가끔 생기는 `2d` Interval을 허용하지 않는다.
- Cadence 실패는 여전히 출력을 거부하며 기존 Owned-output Cleanup을 실행한다.
- **Revision 2(2026-10-02):** 이 엄격한 검사는 정확한 Presentation-time Grid에 대한 것이며, `nominalFrameRate` 같은 평균 / Metadata Rate가 30 또는 30.5를 넘는다는 이유만으로는 거부하지 않는다.

### 범위 경계

- 이것은 표준 고정 Frame Rate Scheduling이며 출력 계약의 완화가 아니다.
- 유지된 Frame은 빠진 Target Interval 동안의 가장 최근에 알려진 Image를 나타낸다.
- 새 시각 Content를 만들지 않는다.
- Source Eligibility와 Duration 제한을 바꾸지 않는다.
- 새 Normalization 사유 · 제외 범주 · 사용자 Copy · UI를 추가하지 않는다.
- Fast-path Copy에는 영향이 없다.
- 최대 30 fps 정책을 바꾸지 않는다.
- Custom HDR Tone Mapping을 승인하지 않는다.
- ADR-049의 내장 경로 / Geometry 전용 경로 선택을 바꾸지 않는다.
- Optical Flow나 Frame 보간을 도입하지 않는다.
- Resume / Checkpoint 동작을 만들지 않는다(ADR-047 Decision 2 불변).
- 정규화된 Working Media Video 출력에만 적용한다.

### 기록된 Fixture의 예

위 Evidence Source에 이 규칙을 적용하면 다음과 같다(계산 결과이며 이 Fixture에 한정된 값이다).

- Target 시각 `0/600`부터 `2720/600`까지 출력 Frame 137개
- 유지(Hold)되는 Grid 지점은 `k = 36` 하나이며 `720/600`에서 Frame 35가 재사용된다.
- 버려지는 Source / Composition Frame은 없다.
- Session Duration은 `2722/600`으로 유지된다.
- Audio / Video 종료 차이는 `1/600`으로 유지된다.
- 이 Fixture에서 유지된 Image의 최대 나이는 한 Frame Interval `20/600`이다.

이 Fixture의 최대 나이를 보편적 최대값으로 승인하지 않는다.

### 필요한 검증

- 순수 Cadence Scheduler Unit Test, Integration Test, LunaTestphone 실제 Media 재검증은 ROADMAP Phase 6 Unit Tests / Integration Tests / Physical Device Test에 기록된다.
- 진짜 Dolby Vision Source가 구조적으로 실행되었지만(Classification · Plan · 내장 경로 진입) Dolby Vision 시각 품질 승인은 출력 시각 Evidence가 완료될 때까지 Pending이며 통과를 주장하지 않는다. — **결과(2026-10-02):** 위 문장은 작성 시점의 상태다. 이후 `IMG_0130.MOV` · 현재 Step 4B 구현(`da1f337`) · LunaTestphone · 승인된 내장 Full-aperture 경로에 한해 소유자 시각 판정 PASS(`PASS — HDR to SDR appearance is acceptable.`; 일반 Dolby Vision 인증 아님).

## 최초 승인 본문 (2026-09-30 — Revision 1로 보완됨)

**Resolves:** Phase 6 Step 4A(순수 SDR Working-media Contract와 Normalization Plan Builder) 구현 중 발견된 세 Blocker — (1) AAC가 아닌 Source Audio의 처리(ADR-045 §3은 "AAC Passthrough"만 정의), (2) ADR-043 Portrait이지만 ADR-047 짝수 정렬 후 출력이 Portrait이 아니게 되는 근사 정사각형 Source(예: 1080×1081 → 1080×1080)의 처리, (3) `minFrameDuration`이 없는 Source의 출력 Frame Duration 유도(ADR-045 §3 `max(minFrameDuration, 1/30)`의 입력 부재).

**Clarifies:** ADR-043 Revision 1(Orientation 판정은 그대로 두고 별도의 Working-raster Feasibility 단계를 추가), ADR-045 §1 / §2 / §3(Canonical Preflight 순서, Phase-5-ready 조건과 Normalization 사유, Working Media Audio 계약, Frame Duration 유도), ADR-046 §8(Canonical Preflight 순서), ADR-047 Decision 1(짝수 정렬 결과가 Portrait이어야 한다는 요구의 소유 위치).

**Explicitly Unchanged:** ADR-042의 `1.0s <= 전체 Source Duration <= 5.0s` Eligibility · Per-item Filtering · 통합 안내 · Preparation Sheet · 취소 · Runtime 실패 · `다시 시도` · Storage 부족 Presentation과 Accepted Set Atomicity, ADR-043 Revision 1의 Orientation 판정식 `presentationHeight > presentationWidth`와 Non-portrait Copy, ADR-044 Revision 1 QuickTime-only Container, ADR-046 H.264 / HEVC-only Video Codec Family와 Direct-camera H.264, ADR-045의 Video 출력 계약(QuickTime `.mov` · H.264 High 8-bit · Rec.709 / 709 / 709 · Video Range · Transform Bake + Identity · 1080p-class Portrait Bounding Box) · Tone-mapping 메커니즘 · 출력 Duration 허용 범위 · Cancellation / Output Ownership, ADR-045 §2의 기존 Normalization Trigger(HDR / >8-bit, Nominal Frame Rate 기준 30 fps 초과, 1080p-class 초과 Raster), ADR-047의 Raster 공식과 No Resume, ADR-020 / ADR-037 / ADR-040의 Atomic Commit과 Replace 보존, Photos 원본 불변, Export Codec / Container / Audio(Phase 9), Import Storage Estimate Formula / Safety Reserve(Pending 유지), Aggregate Progress / Retry Source-handle 메커니즘(Pending 유지).

**이 ADR은 Production 구현을 의미하지 않으며 Phase 6 Step 4B를 시작하지 않는다.** Step 4B(`WorkingMediaNormalizer` AVFoundation Adapter)가 추측 없이 구현될 수 있도록 세 정책을 확정하는 Product / Architecture 완결 결정이다. Classifier · Inspector · Selection Preflight · Plan Builder는 이 ADR에 맞추어 이후 구현 Step에서 조정되며 현재 구현은 이 ADR의 새 규칙을 아직 반영하지 않는다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. Classifier · Inspector · Selection Preflight · Plan Builder는 Step 4A(`75c2cb9`)에서 이 ADR에 맞추어 조정되었고, Step 4B Normalizer(`da1f337`)는 Audio 계약 · Frame Duration 유도 · Revision 1 Cadence Grid · Revision 2 정확한 출력 Validation을 구현 · 검증했다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현이며 Phase 6은 완료되지 않았다.

## Context

Phase 6 Step 4A는 Normalization-required Accepted Item에서 결정적인 Normalization Plan을 만드는 순수 계층이다. 구현 중 세 입력이 기존 Accepted 문서로 결정되지 않음이 드러났다.

첫째, ADR-045 §3은 Working Media Audio를 "AAC Passthrough"로만 정의했다. 일부 촬영본 · 편집본 · 외부 영상은 LPCM / ALAC / APAC 등 AAC가 아닌 Audio를 가진 QuickTime H.264 / HEVC일 수 있으며, 이런 Source를 거부할지 · Audio를 버릴지 · 변환할지가 정해지지 않았다.

둘째, ADR-047의 각 변 짝수 내림은 변당 최대 1 Pixel을 제거하므로 높이와 너비의 차이가 1 Pixel 안팎인 Portrait Source를 정사각형으로 만들 수 있다. ADR-045 §3은 출력 Presentation이 Portrait이어야 한다고 요구하므로 이 Source를 어느 단계에서 어떻게 다룰지가 필요했다.

셋째, ADR-045 §3의 `frameDuration = max(source minFrameDuration, 1/30)`은 `minFrameDuration`이 없는 Source의 출력 Cadence를 정의하지 않았다.

사용자는 세 항목을 다음과 같이 승인했다.

## Decision 1 — Working-Media Audio

### Audio 없음

- Source에 Audio Track이 없으면 Normalized Output에도 Audio Track이 없다.
- 무음 Audio Track을 합성하지 않는다.

### AAC Source Audio

- 신뢰성 있게 AAC로 식별된 Source Audio(Audio Format ID `aac ` = `kAudioFormatMPEG4AAC`)는 Passthrough이며 재인코딩하지 않는다(ADR-045 §3 유지).
- AAC 자체는 Normalization 사유가 아니다.
- Video가 다른 승인 사유로 Normalization되더라도 AAC는 Passthrough한다.
- Passthrough AAC의 Timing은 Video Operation과 정렬되어야 하며 출력은 ADR-045 §7의 Duration 허용 범위(`source <= output <= source + 1/30 s`)를 만족한다.

### 알려진 non-AAC Source Audio

- 그 밖의 조건을 모두 만족하는 QuickTime H.264 / HEVC Source의 신뢰성 있게 식별된 non-AAC Audio(예: LPCM, ALAC, APAC, 그리고 `aac `가 아닌 다른 AAC 계열 Format ID를 포함한 그 밖의 알려진 Format)는 거부하지 않고 버리지 않는다.
- 이 Audio는 새 의미적 Normalization 사유 **`audioTranscode`**를 추가한다.
- Canonical Normalization 사유 순서는 다음과 같다: 1. HDR, 2. Frame Rate, 3. Raster, 4. Audio Transcode.
- non-AAC Audio는 유일한 Normalization 사유일 수 있다. 이 경우에도 출력은 ADR-045 §3의 Working Media 계약 전체를 만족한다(승인된 Audio-only Remux 경로는 없으며 Video도 Normalization Pipeline을 통과한다).
- Normalized Working Media Audio는 다음과 같다.

| 항목 | 값 |
| --- | --- |
| Codec | AAC-LC |
| Sample Rate | 48,000 Hz |
| Channel | 검사된 Source가 Mono(1채널)이면 Mono, 2채널 이상이면 Stereo(2채널 초과 Source는 명시적 Stereo Downmix) |
| Bitrate | Mono 96 kbps, Stereo 128 kbps |

- 이 규칙은 Working Media Normalization 규칙이며 Export Audio Format / Bitrate 결정(Phase 9)이 아니다.
- Audio 설정 UI · Codec 이름 안내 · Audio 전용 Alert를 도입하지 않는다.

### 알 수 없거나 모순된 Audio Facts

- Audio Track이 있다고 보고되었지만 Format / Sample Rate / Channel Facts를 신뢰성 있게 검사할 수 없으면 해당 항목은 Preflight에서 기존 Invalid / Unsupported Media 범주로 거부된다.
- 모순된 Inspection Facts(예: Audio Track이 없다고 보고되었는데 Audio Format Facts가 있음)는 조용히 보정하지 않고 같은 범주로 거부한다.
- Audio 전용 사용자 안내 · Codec 이름을 도입하지 않고 기존 단일 / 다중 / Replace Invalid-or-Unsupported Copy를 재사용한다(ADR-044 Revision 1, ADR-042 Revision 4).
- 거부된 항목은 Accepted Set에 들어가지 않으며 Source와 Replace 대상 기존 Clip은 변경되지 않는다.

### Runtime 실패

- 신뢰성 있는 Preflight를 통과한 뒤 실제 Decoder / Writer가 실패하면(AAC Passthrough 또는 AAC-LC 변환 포함) Operation 실패이며 ADR-042 Revision 4의 Accepted Set Atomicity를 따른다.
- Runtime 실패는 부분 Commit을 허용하지 않으며 Per-item 제외로 바뀌지 않는다.

## Decision 2 — Working-Raster Feasibility Gate

- ADR-043 Revision 1의 Orientation 판정 `presentationHeight > presentationWidth`는 바뀌지 않는다. 기하학적으로 Portrait인 Source는 계속 Portrait으로 분류된다.
- Orientation Eligibility 다음, Normalization 사유 판정 이전에 독립된 **Working-raster Feasibility** 단계를 둔다.
- 이 단계는 ADR-047의 정확한 Raster 알고리즘을 사용한다: `scale = min(1.0, 1080 / width, 1920 / height)`로 확대 없이 비율을 보존하며 1080×1920 안에 맞추고, 각 Scaled 변을 내림한 뒤, 각 변을 양의 짝수로 내림 정렬한다.
- 결과 출력 Raster는 엄격한 Portrait(`outputHeight > outputWidth`)이어야 한다.
- 짝수 정렬 결과가 정사각형(또는 Landscape)이 되면 해당 항목은 Preflight에서 Unsupported Working-raster Geometry로 거부된다.
- 이 거부는 기존 Invalid / Unsupported Media 범주로 분류되며 새 사용자 안내를 도입하지 않는다.
- 거부된 항목은 Accepted Set에 들어가지 않고 Normalization Plan Builder(`WorkingMediaPlanBuilder`)에 도달하지 않는다.
- 늘리기 · Crop · Padding · Upscale · 2 Pixel 여백 같은 우회를 하지 않는다.
- 이 항목을 Non-portrait Source로 재정의하지 않는다(Non-portrait Copy를 쓰지 않는다).
- 이 판정은 Fast-path 후보에도 동일하게 적용되는 독립 Preflight 단계다.

| Source Presentation | ADR-043 | 정렬 후 출력 | 결과 |
| --- | --- | --- | --- |
| 1080×1081 | Portrait | 1080×1080 | 거부(Working-raster Feasibility) |
| 1081×1082 | Portrait | 1080×1080 | 거부 |
| 2160×2162 | Portrait | 1080×1080 | 거부 |
| 1080×1082 | Portrait | 1080×1082 | 허용 |
| 1079×1080 | Portrait | 1078×1080 | 허용 |
| 2160×2164 | Portrait | 1080×1082 | 허용 |
| 1440×1444 | Portrait | 1080×1082 | 허용 |

## Decision 3 — Output Frame-Duration Derivation (Cadence Fallback)

30 fps Ceiling은 `1/30 s`다.

1. Source `minFrameDuration`이 수치이고 0보다 크면: `outputFrameDuration = max(sourceMinFrameDuration, 1/30)`.
2. 그렇지 않고 Nominal Frame Rate가 유한하고 0보다 크면: `nominalFrameDuration = 1 / nominalFrameRate`, `outputFrameDuration = max(nominalFrameDuration, 1/30)`.
3. 그 밖의 경우: `outputFrameDuration = 1/30`.

결과:

- 유효한 24 fps Source는 HDR / Raster / Audio 사유로 Normalization되어도 24 fps를 유지한다.
- 29.97 fps는 약 29.97 fps를 유지한다.
- 59.94 / 60 fps는 30 fps로 제한된다.
- 두 Timing Fact가 모두 없으면 결정적인 30 fps Fallback을 사용한다.
- `minFrameDuration`이 있으면 여전히 첫 번째 권위 있는 Cadence 입력이다.
- Timing Metadata 부재는 그 밖에 Eligible한 Source를 거부하지 않는다.
- 이 Fallback은 그 자체로 새 Normalization 사유를 만들지 않으며 기존 Nominal Frame Rate 기반 Normalization Trigger(ADR-045 §2)는 바뀌지 않는다.
- 어떤 출력도 30 fps를 초과하지 않는다. — **Revision 2(2026-10-02):** 이는 계획 Frame Duration `d`가 `1/30`보다 빠르지 않다는 뜻이며, 짧은 마지막 Sample 때문에 30을 넘을 수 있는 평균 / Metadata Rate(`nominalFrameRate`, `sampleCount / duration`)의 상한이 아니다.
- Rational 변환은 결정적이어야 하며 정확한 Timescale 선택은 구현 세부사항이다.
- **Revision 1(2026-10-01):** 위 공식은 그대로이며, 정규화된 Video 출력은 `t_k = k × outputFrameDuration`(`t_k < E`) Grid의 모든 Target에 정확히 한 Frame을 가지고 새 Frame이 없는 Target은 가장 최근 Frame을 유지한다(위 Revision 1 Cadence Grid 참조).

## Canonical Preflight Order (ADR-045 §1 / ADR-046 §8 대체 순서)

1. 전체 Source Duration `1.0s <= duration <= 5.0s`(ADR-042)
2. Readable / Video Track / Protected 아님(Preflight Invalid)
3. 실제 Container Brand — QuickTime만(ADR-044)
4. Video Codec Family — H.264 또는 HEVC만(ADR-046)
5. Presentation Orientation — `presentationHeight > presentationWidth`(ADR-043 Revision 1)
6. Working-raster Feasibility(ADR-048 Decision 2), 그다음 Audio Facts 신뢰성(ADR-048 Decision 1) — 둘 다 기존 Invalid / Unsupported Media 범주
7. Normalization 사유 판정 — HDR / >8-bit → Frame Rate(30 fps 초과) → Raster(1080p-class 초과) → Audio Transcode(non-AAC)

앞선 단계의 거부가 뒤 단계보다 우선하며 1–6은 어느 것도 Normalization 사유가 아니다. Normalization 사유가 하나도 없으면 Phase-5-ready Fast Path이며, 따라서 Phase-5-ready는 Audio가 없거나 AAC인 경우만 해당한다. — **ADR-049(2026-10-01):** 7 다음에 8. Aperture / Tone-map 경로 호환성 단계가 추가되었다: 사유 없음 → Aperture와 무관하게 Fast Path; 사유 있음 → Full Aperture는 내장 Compositor 정규화, Non-full + 신뢰성 있는 SDR Rec.709는 Geometry 전용 정규화, Non-full + HDR / Wide-color / SDR 미증명은 기존 Invalid / Unsupported 범주 거부. 1–7의 순서와 우선순위는 바뀌지 않는다.

## Rationale

- 사용자가 고른 영상의 소리를 조용히 잃거나 Codec 때문에 영상 전체를 거부하는 것보다 Working Media 안에서 AAC로 맞추는 편이 Mini Vlog 의도와 Media Safety에 맞다.
- 48 kHz AAC-LC와 Mono 96 kbps / Stereo 128 kbps는 5초 이하 Clip에서 저장 공간 영향이 작고 iPhone 12에서 널리 지원되는 단순한 고정값이다.
- 근사 정사각형 Source는 극히 드물며 늘리기 · 자르기 · 여백 없이 Portrait 계약을 지킬 방법이 없다. Plan 단계가 아닌 Preflight에서 거부해야 Accepted Set에 들어간 뒤 실패하는 경로가 생기지 않는다.
- Nominal Frame Rate는 이미 Normalization Trigger 입력이므로 `minFrameDuration` 부재 시 가장 가까운 권위 있는 Cadence 정보이며, 둘 다 없을 때 30 fps는 승인된 Ceiling이다.

## Consequences

- `ImportNormalizationReason`에 `audioTranscode` 사유가 추가되고 Canonical 순서가 HDR → Frame Rate → Raster → Audio Transcode가 된다(구현 대상).
- Preflight Classifier는 Orientation 다음에 Working-raster Feasibility와 Audio Facts 신뢰성 검사를 수행하며 두 거부는 기존 Invalid / Unsupported Exclusion 범주로 매핑된다(구현 대상).
- `WorkingMediaPlanBuilder`는 짝수 정렬 후 Portrait이 아닌 Raster를 받지 않으며 non-AAC Audio를 오류가 아닌 AAC-LC 변환 계획으로 표현한다(구현 대상).
- `WorkingMediaNormalizer`(Step 4B)는 이 ADR의 Audio 설정과 Frame Duration 유도를 그대로 적용한다. — **Revision 1(2026-10-01):** 출력 Video Sample Timing에는 Cadence Grid와 Frame Hold 규칙을 적용한다(구현 대상).
- ROADMAP Phase 6 Unit / Integration Test에 이 ADR의 Audio / Raster Feasibility / Cadence Case가 추가된다.

## Still Pending (이 ADR이 확정하지 않음)

- Import Storage Estimate Formula와 Safety Reserve
- Implementation-specific Aggregate Progress 계산과 `다시 시도`의 Source-handle 유지 메커니즘, Filesystem Free-space API / Race 처리(구현 세부사항)

## Non-goals

- Production 구현(Step 4A 조정, Step 4B Normalizer), Export Audio Format / Bitrate(Phase 9), Audio 설정 UI, Crop / Pad / Upscale 옵션, Resume / Background 처리, 새 사용자 안내 Copy.

---

# ADR-049 — Clean-Aperture Normalization and Tone-Mapping Eligibility Boundary

**Date:** 2026-10-01 (Revision 1: 2026-10-01)
**Status:** Accepted (사용자 승인)

## Revision 1 — Multi-Description Consensus and Normalization Transform Eligibility (2026-10-01)

**Status:** Accepted (사용자 승인). 이 Revision은 ADR-049를 반영한 Step 4B 구현의 두 번째 독립 Review(2026-10-01)가 드러낸 두 공백을 닫는다: (1) 경로 판정이 첫 번째 Video Format Description만 읽으므로 같은 Video Track의 뒤 Description이 다른 Aperture나 HDR 색을 가지면 승인되지 않은 경로로 Rendering될 수 있고, (2) Orientation Preflight(ADR-043)를 통과한 Preferred Transform이 Shear나 임의 각도 회전을 담으면 V1 Renderer가 Crop · Padding 없이 정규화할 수 없는데도 Preflight가 받아들여 Accepted Set 전체가 Runtime 실패로 끝날 수 있었다. ADR-049의 Case A–D, Tone-mapping 경계, 사용자 안내는 바뀌지 않으며 이 Revision은 Normalization 경로 판정의 입력 조건을 좁힌다. 아래 내용이 정본이며 아래의 최초 본문은 보존된다(충돌 시 Revision 1 우선). 이 Revision은 Step 4B 구현 완료나 승인을 뜻하지 않는다.

**왜 Revision인가:** 두 결정 모두 ADR-049 Step 8(Aperture / Tone-map 경로 판정)이 무엇을 근거로, 어떤 Source에 대해 경로를 고를 수 있는지를 정하는 같은 경계의 보완이다. 새 Normalization 사유 · 새 제외 범주 · 새 Tone-mapping 메커니즘을 도입하지 않으므로 별도 ADR이 아니다.

### Decision A — 모든 관련 Video Format Description의 합의

Normalization이 필요한 Source(사유가 하나 이상)에 대해서만 적용한다.

1. 선택된 Video Track의 Sample을 기술할 수 있는 모든 Video Format Description을 검사한다(첫 번째만이 아니다).
2. 모든 Description이 신뢰성 있는 Aperture 증거를 제공해야 한다(ADR-049 Decision 1의 판정 규칙을 Description마다 적용).
3. 모든 Description이 같은 Full / Non-full Aperture 상태로 분류되어야 한다.
4. Encoded Raster · Clean-aperture 사각형 · Pixel Aspect Ratio 해석이 하나의 Normalization Plan과 서로 호환되어야 한다.
5. Non-full Geometry 전용 경로(Case C)에서는 모든 Description이 각자 SDR Rec.709를 긍정적으로 증명해야 한다: Rec.709 Primaries, Rec.709 Transfer, Rec.709 Matrix, HLG 아님, PQ 아님, Rec.2020 Primaries / Matrix 신호 없음, Dolby Vision Configuration 없음.
6. 어떤 Description이라도 없거나, 신뢰할 수 없거나, 모순되거나, Aperture 상태를 바꾸거나, 계획된 Aperture Geometry를 바꾸거나, 필요한 색 증명에 실패하면 해당 항목은 기존 Invalid / Unsupported Media 범주로 거부된다 — 새 제외 범주 · 새 안내 · 새 Copy 없음, 어떤 Normalization Operation도 시작하지 않는다.
7. Runtime Normalizer는 Reader / Writer 작업 전에 같은 합의를 다시 확인하고 실제 Source가 더 이상 Plan과 맞지 않으면 안전하게 실패한다(Plan / Source 불일치).
8. Description이 하나인 Track은 같은 규칙의 원소 하나짜리 경우일 뿐이다.

### Decision B — Normalization Transform Eligibility

Normalization이 필요한 Source는 Preferred Transform이 다음으로만 이루어진 축 정렬 Affine Mapping으로 신뢰성 있게 표현될 때만 진행할 수 있다.

- Translation
- 1/4 회전 방향: 0°, 90°, 180°, 270°
- 선택적 가로 및 / 또는 세로 Mirroring
- 유한하고 0이 아닌 축 정렬 Scale — 균일 또는 비균일 모두 가능하되, Source가 선언한 Presentation Transform의 실제 일부일 때만. 선언된 Presentation Transform을 Bake하는 것(ADR-045 §3)은 Mellow의 새 늘리기 정책이 아니며 임의 왜곡을 허용하지 않는다.

추가 조건: 모든 Affine 성분이 유한하고, Transform이 가역이며, Presentation Geometry가 유한 · 양수 · 표현 가능하고, Shear · 임의 각도 회전 · 퇴화되었거나 0에 가까운 Basis · 모호한 Mapping이 없어야 한다. Translation과 Scale이 표준 카메라 값과 같을 필요는 없다. 구현은 일반적인 고정소수점 / Metadata 반올림 오차를 허용할 수 있으나 그 허용 오차는 눈에 보이는 임의 회전이나 Shear가 통과할 수 없을 만큼 좁아야 한다. 정확한 수치 허용 오차는 구현 세부사항이며 경계 양쪽에서 테스트해야 한다(이 ADR은 Product 정책으로서의 소수 임계값을 정하지 않는다).

Normalization 사유가 하나 이상이고 Transform이 다음을 담으면 거부한다: Shear, 임의 각도 회전, 유한하지 않은 값, 0이거나 비가역인 Basis, Crop · Padding · 합성 테두리 · Aperture 밖 번짐 없이는 정확한 출력에 Mapping할 수 없는 Geometry, 그 밖에 신뢰할 수 없는 Transform 증거.

이 거부는 기존 Invalid / Unsupported Media 범주로 매핑된다: 새 거부 범주 · 새 안내 · 새 Copy 없음, Reader / Writer / Output Operation 없음, 다중 선택은 기존 규칙대로 해당 항목만 제외, 단일 후보는 기존 Unsupported-media 결과, Replace는 기존 Clip과 Media를 보존. 이것은 좁은 V1 기술 경계이며 그 Source가 보편적으로 Invalid하다는 주장이 아니다.

ADR-043 Revision 1의 Orientation 판정(Presentation이 Portrait인가)과 이 Transform 경계(Normalization이 필요한 Source를 V1의 No-crop / No-padding 계약 아래에서 Rendering할 수 있는가)는 서로 다른 질문이다. Orientation 판정식과 그 결과는 바뀌지 않는다.

### Case A–D와의 관계

- **Case A — 사유 없음:** Fast-path Copy. Aperture와 Transform은 Normalization 사유를 만들지 않으며, Non-full Aperture · 여러 Description · 축 정렬이 아닌 Transform은 Mellow가 Rendering하지 않을 때 그 자체로 항목을 거부하지 않는다. 원본 Byte가 권위다.
- **Normalization 필요:** Case B / C / D를 고르기 전에 (1) 여러 Description의 Aperture 합의와 (2) Normalization Transform Eligibility를 먼저 요구한다. 그다음 Full Aperture → Case B 내장 AVFoundation 정규화, Non-full + 모든 Description에서 긍정적으로 증명된 SDR Rec.709 → Case C Geometry 전용 정규화, Non-full + HDR / Wide / Unknown 색 → 기존 Case D 거부, 신뢰할 수 없거나 모순된 Description 또는 부적격 Transform → 같은 기존 Invalid / Unsupported 거부 결과.
- Transform 경계는 두 Normalization Engine 모두에 적용된다. 내장 경로는 Scale 크기가 정확히 1이 아니라는 이유만으로 거부하지 않고 유효한 축 정렬 Scale을 Bake할 수 있다. Geometry 전용 경로는 Clean Aperture 전체를 ADR-047 출력 Raster에 충실히 Mapping하는 일부로 유효한 축 정렬 Scale을 Rendering할 수 있으며 여전히 HDR Tone-mapping을 하지 않는다.

### Canonical Preflight 배치(ADR-049 Step 8 보완)

ADR-048 Canonical Preflight Order의 1–7단계와 그 우선순위는 바뀌지 않는다. Step 8은 다음과 같이 정밀화된다.

1. 기존 Normalization 사유를 계산한다.
2. 사유 없음 → 즉시 Fast Path.
3. Normalization이 필요한 항목에 대해서만: 여러 Description의 Aperture / 색 합의를 확립하고, Normalization Transform Eligibility를 확립하고, 내장 경로와 Geometry 전용 경로 중 하나를 고르며, 그렇지 않으면 기존 Invalid / Unsupported Media로 거부한다.

앞선 단계의 거부가 여전히 우선하며 뒤의 어떤 Normalization 사유도 이 안전 경계를 뒤집지 않는다.

### 바뀌지 않는 것

- ADR-045 §4의 내장 Compositor가 유일한 승인 HDR / Wide-color Tone-mapping 메커니즘이다.
- Custom Compositor는 긍정적으로 증명된 SDR Rec.709에 대한 Geometry 전용이다.
- ADR-047 Revision 1: Clean Aperture 전체 보존, Crop · Padding · Aperture 밖 번짐 · Upscale 없음, 정확한 짝수 출력 Raster, 제한된 Parity Resample.
- 해상도 선택 · Fill / Fit / Stretch 옵션 · 새 Normalization 사유 · 새 Copy가 없다.
- ADR-042 / 043 / 044 / 046 / 048의 Eligibility 규칙과 안내, Accepted Set Atomicity, Replace 보존, Photos 원본 불변.

### 테스트 추적

Description 하나; 일치하는 여러 Description; 뒤 Description의 Full ↔ Non-full 변경; 뒤 Description의 SDR ↔ HLG / PQ / Rec.2020 / Dolby Vision 변경; 없거나 신뢰할 수 없는 뒤 Description; 축 정렬이 아닌 Transform을 가진 Case A의 Fast-path 유지; Identity / 1/4 회전 / Mirror / Translation 정규화; 유한한 축 정렬 Scale 정규화; 허용 오차 안의 미세 Metadata 오차; 허용 오차 밖의 눈에 보이는 Shear / 회전; 유한하지 않거나 비가역인 Transform; 거부 항목의 Media Operation 없음; 기존 Step 3 안내 / 범주 동작; Runtime Source / Plan 불일치.

## 최초 승인 본문 (2026-10-01 — Revision 1로 보완됨)

**Resolves:** Phase 6 Step 4B 독립 Review(2026-10-01)와 뒤이은 기기 Probe에서 드러난 Blocker — Source의 Clean Aperture가 Encoded Raster 전체가 아닐 때 ADR-045 §4의 승인된 Tone-mapping 경로(AVFoundation 내장 Compositor + Layer Instruction)를 유지하면서 ADR-047 Revision 1의 전체 Frame 보존(Crop · Padding 없음)을 동시에 만족할 수 없는 문제.

**Clarifies:** ADR-045 §1 / §4(Canonical Preflight 순서의 마지막 단계, Tone-mapping 경로의 적용 범위), ADR-047 Revision 1(Render Geometry가 보존하는 "Presentation Frame"은 Clean-aperture Presentation 사각형이며, Non-full Aperture Source의 정규화 경로), ADR-048 Canonical Preflight Order(사유 판정 뒤의 경로 판정 단계).

**왜 새 ADR인가:** 이 결정은 Clean-aperture Geometry · Normalization 필요 여부 · 신뢰성 있는 SDR Rec.709 증거 · 허용되는 Rendering / Tone-mapping 경로의 조합으로 정해지는 새로운 Layer 간 Eligibility 경계다. ADR-045의 Tone-mapping 메커니즘이나 ADR-047 Revision 1의 Render Geometry Rule 어느 한쪽의 Revision으로 표현할 수 없으므로 두 ADR의 역사적 본문을 고치지 않고 이 ADR이 둘을 명확히 한다.

**Explicitly Unchanged:** ADR-042의 `1.0s <= 전체 Source Duration <= 5.0s` Eligibility · Per-item Filtering · 통합 안내 · Preparation Sheet · 취소 · Runtime 실패 · `다시 시도` · Storage 부족 Presentation과 Accepted Set Atomicity, ADR-044 Revision 1 QuickTime-only Source Container, ADR-046 H.264 / HEVC Source Codec 경계, ADR-043 Revision 1 Portrait-only Presentation Eligibility, ADR-047의 No-upscale Raster 공식 · 짝수 변 규칙 · No Resume Recovery, ADR-047 Revision 1의 Parity Resample 규칙, ADR-048의 Canonical Normalization 사유 순서 · Audio 계약 · Cadence Fallback · Working-raster Feasibility, ADR-045의 Working Media 출력 계약 · Duration 허용 범위 · Cancellation / Output Ownership · Cleanup, Photos 원본 불변, Storage Estimate / Safety Reserve · Aggregate Progress · Retry Source-handle(Pending 유지), Export 결정(Phase 9), 기존 사용자 안내 Copy.

**이 ADR은 Phase 6 Step 4B 구현 완료를 뜻하지 않는다.** 현재 Step 4B Normalizer는 미커밋 상태이며 이 ADR을 아직 반영하지 않는다. Inspector · Classifier · Step 3 Selection Preflight · Step 4A Plan · Step 4B Normalizer는 이후 구현 Step에서 이 ADR에 맞춘다.

**구현 상태 갱신(2026-10-02):** 위 문장은 작성 시점의 상태다. Inspector · Classifier · Step 3 Selection Preflight · Step 4A Plan 경로 · Step 4B Normalizer는 이 ADR과 Revision 1에 맞추어 `da1f337`로 구현 · 검증 · Commit되었다(LunaTestphone `MellowTests` 693/693 · Debug / Release 기기 Build 성공 · 독립 Review 승인). 실제 iPhone 촬영본 `IMG_0130.MOV`(HEVC Main10 HLG / Rec.2020, Dolby Vision `dvvC` Profile 8 · Compatibility ID 4, Full Aperture)의 정규화 출력은 H.264 High SDR Rec.709이고 Sample 137개가 `0 … 2720/600`의 정확한 `20/600` Grid에 있으며 `720/600`에서 Frame을 유지하고 Video / Session은 `2722/600`, Audio는 `2721/600`에 끝나며 엄격한 Validator를 통과했다. 소유자 기기 시각 판정은 `PASS — HDR to SDR appearance is acceptable.`이며 이 판정은 이 Source · 현재 Step 4B 구현(`da1f337`) · LunaTestphone · 승인된 내장 Full-aperture 경로에만 해당하고 일반 Dolby Vision 인증이나 모든 HDR Source · 모든 기기에 대한 증명이 아니다. 사용자 Import 흐름(Select Clips / Editor Add / Replace) 연결은 미구현이며 Phase 6은 완료되지 않았다.

## Context

1. ADR-045 §4는 HDR → SDR Tone-mapping 메커니즘으로 `AVAssetReaderVideoCompositionOutput` + `AVMutableVideoComposition`(Rec.709 Composition 색 속성, Layer Instruction Transform Bake)의 AVFoundation 내장 Compositor를 승인했다.
2. 그 경로는 ADR-045 Technical Device Spike(LunaTestphone iPhone 12)에서 HDR 결과의 기기 A/B 시각 검증을 받았다.
3. ADR-047 Revision 1은 Presentation Frame 전체 보존, Crop 없음, Padding · 합성 테두리 없음, 정확한 양의 짝수 출력 Raster, 제한된 Parity Resample을 요구한다.
4. Step 4B 구현은 홀수 Clean Aperture Fixture에서 마지막 출력 행이 검게 남는 결함을 보였다. 이를 고치려고 도입한 Custom Compositor는 Framework가 Compositor 앞에서 HDR Frame을 SDR로 변환하는 경로(Pre-conversion)에 의존했고, 독립 Review는 이것이 승인된 ADR-045 §4 경로와 다르다는 점을 지적했다.
5. 사용자는 Custom Compositor의 Pre-conversion을 ADR-045 Tone-mapping의 대체로 승인하지 않았다. 이유: 명시적으로 승인된 ADR-045 경로와 다르다; 현재의 합성 HDR Test는 동등한 Tone-curve 동작을 증명하지 못한다; Dolby Vision 동작이 증명되지 않았다; 새 기기 A/B가 승인하지 않았다.

### Step 4B 기기 Probe (LunaTestphone iPhone 12, 2026-10-01, 관찰)

각 Clean-aperture 경계에 고유한 1 Pixel 밝기(위 250 · 아래 200 · 왼쪽 150 · 오른쪽 110, 내부 40, Aperture 밖 녹색)를 칠한 합성 H.264 Fixture를 ADR-045 §4 구성(Rec.709 Composition, Layer Instruction Transform Bake, renderSize = Presentation 크기)의 내장 Compositor로 렌더링하고 그 출력 Pixel Buffer를 재압축 없이 직접 읽었다.

| Source | 내장 Compositor 출력(관찰) |
| --- | --- |
| Full Aperture 1080×1920 | 네 경계 모두 보존(행 0 / 1919 = 248 / 199, 열 0 / 1079 = 146 / 109) |
| Encoded 1080×1920 안의 중앙 1080×1919 Aperture(원점 y 0.5) | 위 경계는 50% 가중으로 존재(144), 아래 경계 Sample(200)은 출력 어디에도 없음, 마지막 출력 행은 검정(0) |
| 같은 Source, 세로 뒤집기 Transform | 검정 행이 출력 맨 위로 이동 — 손실은 Source 공간에서 일어남 |
| Encoded 1920×1080 안의 1919×1080 Aperture, 90° 회전 | 마지막 출력 행 검정, 원본 오른쪽 경계 손실 |
| Encoded 1080×1920 안의 1000×1800 Aperture, 원점 (60, 100) | 경계 Pixel에 Aperture 밖 녹색이 섞임(위 217/255/216, 아래 169/212/170, 오른쪽 열 50/131/48) |

관찰에서 이끈 판단(추론): 뒤집기 / 회전이 손실 위치를 Source와 함께 옮기므로, 손실된 경계 정보는 이후 단계가 받기 전에 이미 없다. 따라서 내장 Compositor 뒤에 둔 Geometry 전용 단계는 없는 경계를 Crop하거나 Pixel을 만들어내지 않고는 복원할 수 없다. 또한 Full Aperture는 일반적인 iPhone / Photos Source에서 예상되는 경우지만, 모든 iPhone / Photos 자산이 Full Aperture라는 증거는 없으며 이 ADR은 그렇게 주장하지 않는다.

## Decision 1 — Canonical Aperture Facts

Inspector는 첫 번째 지원 Video Format Description에서 다음 Facts를 신뢰성 있게 얻는다. *(Revision 1: Normalization이 필요한 Source의 경로 판정은 선택된 Video Track의 모든 관련 Description이 이 Facts와 색 증명에서 합의해야 한다 — Revision 1 Decision A.)*

- Encoded Raster 크기(Encoded Sample 단위 너비 · 높이)
- Encoded Sample 좌표의 Clean-aperture 사각형(원점과 크기)
- Pixel Aspect Ratio
- Full / Non-full Aperture 판정

Clean-aperture Extension이 없으면 Core Media 규약대로 Clean Aperture는 Encoded Raster 전체이며 이는 신뢰성 있는 Full Aperture다.

### Full Aperture

신뢰성 있게 검사된 Clean-aperture 사각형이 Encoded Raster 전체를 덮을 때만 Full Aperture다: 원점이 Encoded Raster 원점과 같고, 너비가 Encoded 너비와 같고, 높이가 Encoded 높이와 같다. Core Media가 Rational Metadata를 부동소수로 바꾸는 표현 오차만 흡수하는 허용 오차(0.001 Encoded Sample 이하)를 쓸 수 있으며, 이 허용 오차는 0.5 Sample이나 1 Sample의 Aperture 차이를 숨기지 않는다.

### Non-full Aperture

신뢰성 있게 검사된 Aperture가 원점이나 크기에서 Encoded Raster 전체와 다르면 Non-full Aperture다. 중앙 정렬된 소수 원점의 홀수 Aperture, 정수 Offset Aperture, 더 작은 Clean Aperture, 그 밖의 잘린 Aperture Metadata가 모두 포함된다.

### 신뢰할 수 없는 Aperture 증거

형식이 잘못되었거나 유한하지 않거나 퇴화되었거나 Encoded Raster 밖에 있거나 얻을 수 없는 Aperture 증거로 신뢰성 있는 정규화 경로 판정을 할 수 없으면(Decision 3 Step 8) 해당 항목은 기존 Invalid / Unsupported Media 범주로 안전하게 거부된다. Filename · 확장자 · Photos Metadata로 Aperture Geometry를 분류하지 않는다.

Orientation · Working-raster Feasibility · Raster Plan이 쓰는 Presentation Raster는 기존과 같이 Clean-aperture Presentation(Pixel Aspect Ratio 적용, preferredTransform 적용 후)이며, ADR-047 Revision 1이 보존하는 "Presentation Frame"은 이 Clean-aperture Presentation 사각형이다.

## Decision 2 — Accepted V1 Path Matrix

| Case | 조건 | 경로 |
| --- | --- | --- |
| A | Eligible, Normalization 사유 없음 | 기존 Fast-path Copy(Full / Non-full 무관) |
| B | 사유 있음, 신뢰성 있는 Full Aperture | ADR-045 §4 내장 Compositor / Layer Instruction 정규화 |
| C | 사유 있음, Non-full Aperture, 신뢰성 있는 SDR Rec.709 | Geometry 전용 Custom Rendering 정규화 |
| D | 사유 있음, Non-full Aperture, HDR / Wide-color / SDR 미증명 | Preflight에서 기존 Invalid / Unsupported 범주로 거부 |

### Case A — Normalization 사유 없음

- 그 밖에 Eligible하고 Normalization 사유가 없는 Source는 기존 Fast-path Copy를 사용하며 QuickTime Source를 그대로 보존한다.
- Full / Non-full Aperture 자체는 Normalization을 강제하지 않으며 새 Normalization 사유를 추가하지 않는다.
- Aperture Metadata는 복사된 Media의 일부로 남는다.
- 그 밖에 Ready인 홀수 / Offset Aperture Source도 여기에 포함된다.
- *(Revision 1:)* 여러 Format Description이나 축 정렬이 아닌 Preferred Transform도 Case A 항목을 거부하지 않는다 — Mellow가 Rendering하지 않기 때문이다.

### Case B — Normalization 필요, Full Aperture

- 기존 사유가 하나 이상 있고 Full Aperture가 신뢰성 있게 증명되면 ADR-045 §4의 승인된 내장 AVFoundation Compositor / Layer Instruction 경로를 사용한다.
- 이 경로는 SDR과 이미 승인된 HDR / Wide-color 정규화를 모두 처리할 수 있다.
- 기존 H.264 High · 8-bit SDR · Rec.709 QuickTime 출력 계약과 ADR-047 Raster 규칙을 유지한다.

### Case C — Normalization 필요, Non-full Aperture, 신뢰성 있는 SDR Rec.709

- Geometry 전용 Custom Rendering 경로를 사용하며 이 경로에서는 HDR / Wide-color Tone-mapping이 일어나지 않는다.
- Renderer는 Clean Aperture 전체를 계획된 정확한 짝수 Raster에 매핑한다: Crop · Padding · 검은 테두리 · Aperture 밖 번짐 · 합성 가장자리 없음, Upscale 없음(ADR-047 Revision 1).
- 기존 Audio / Cadence / Raster 사유만이 Normalization 사유이며 Clean Aperture는 새 Normalization 사유가 아니다.

### Case D — Normalization 필요, Non-full Aperture, HDR / Wide-color / SDR 미증명

Normalization이 필요하고 Non-full Aperture이며 다음 중 하나에 해당하면 V1은 그 항목을 Preflight에서 기존 Invalid / Unsupported Media 범주로 거부한다: HLG, PQ, Rec.2020 Primaries 또는 Matrix, Dolby Vision Configuration, 그 밖에 HDR / Wide-color Tone-mapping이 필요함, 또는 Geometry 전용 경로를 위한 SDR Rec.709가 신뢰성 있게 증명되지 않음.

- Reader / Writer Operation이 시작되지 않는다.
- Copy · Normalization · Materialization · Persistence · Append · Replace가 일어나지 않는다.
- Photos 원본은 변경되지 않는다.
- Replace는 기존 Clip · Media · Metadata · 순서 · Slot을 보존한다.
- 부분 Workspace 출력이 없다.
- 새 사용자 범주가 없고 HDR · Aperture · Codec 전용 안내가 없으며 이미 승인된 Invalid / Unsupported Copy를 재사용한다.
- 다중 선택은 남은 Eligible 항목으로 계속하며 전부 제외 동작은 바뀌지 않는다.

이것은 좁은 V1 기술 경계이며 그런 Media가 본질적으로 Invalid하다는 판단이 아니다. Post-V1 지원은 별도로 승인된 변환 메커니즘과 새 기기 HDR / Dolby Vision 증거를 요구한다.

### 신뢰성 있는 SDR Rec.709-family 증거(Case C)

HDR Metadata가 없다는 사실만으로는 부족하며 다음 긍정적 Source 증거가 모두 필요하다(ADR-045 §2 / ADR-048 Facts와 같은 판정 기준).

- Color Primaries = Rec.709
- Transfer Function = Rec.709
- YCbCr Matrix = Rec.709
- HLG 아님, PQ 아님
- Rec.2020 Primaries / Matrix 아님
- Dolby Vision Configuration(`dvcC` / `dvvC` / `dvwC`) 없음
- 그 밖에 승인된 HDR 신호 없음

Unknown / 누락된 Color Facts는 SDR Rec.709 증거가 아니다. AmbientViewingEnvironment / MDCV / CLLI 단독은 ADR-045 §2대로 HDR 판별 신호가 아니며 이 판정을 바꾸지 않는다. 10-bit Source도 긍정적 Rec.709 색 증거가 있으면 SDR Rec.709일 수 있다 — Bit Depth 정규화 자체는 Tone-mapping이 아니며 "10-bit"를 HDR과 동일시하지 않는다.

## Decision 3 — Canonical Preflight Placement

ADR-048 Canonical Preflight Order의 1–7단계(Duration → Readable / Video / Protected → Container → Codec → Orientation → Working-raster Feasibility · Audio Facts → Normalization 사유 판정)는 바뀌지 않으며 그 뒤에 경로 판정 단계를 둔다.

8. *(Revision 1로 정밀화: 사유가 있는 항목은 경로 선택 전에 모든 Description의 합의와 Normalization Transform Eligibility를 먼저 요구하며 실패 시 같은 기존 범주로 거부)* Aperture / Tone-map 경로 호환성 — 사유가 없으면 Aperture와 무관하게 Fast-path Copy; 사유가 있으면 Full Aperture → 내장 Compositor 정규화, Non-full + 신뢰성 있는 SDR Rec.709 → Geometry 전용 정규화, Non-full + HDR / Wide-color / SDR 미증명(또는 신뢰할 수 없는 Aperture 증거) → 기존 Invalid / Unsupported 범주 거부.

- 앞선 단계의 거부가 이 단계보다 우선한다.
- 이 단계의 거부는 어떤 HDR / Raster / Audio 사유가 있더라도 그 사유로 뒤집히지 않는다.
- 다섯 번째 제외 범주나 새 안내를 추가하지 않는다.

## Decision 4 — Path Model and Implementation Contract

의미가 구분되는 네 결과(코드 이름은 달라도 된다): `fastPathCopy`, `normalizeBuiltInToneMap`, `normalizeSDRApertureGeometry`, 거부된 Invalid / Unsupported 조합.

- Step 4A의 출력 Raster 계산이 유일한 크기 권위다.
- Plan은 선택된 준비 경로를 결정적으로 담거나 유도해야 한다.
- Inspector는 신뢰성 있는 Aperture Facts를 수집한다.
- Classifier와 Plan은 일치해야 한다.
- Step 3은 Eligible 후보만 유지하고 새 거부를 기존 Invalid / Unsupported 범주로 매핑한다.
- Step 4B는 Plan / Source 불일치를 거부한다.
- 출력 Validation은 성공한 두 정규화 경로에서 동일하다.
- Remux 경로를 도입하지 않는다.
- 이 경로 구분은 승인된 계약이며 구현된 것이 아니다.

## User-facing Behavior

새 Copy를 도입하지 않고 기존 승인 동작을 재사용한다.

- 단일 항목 / Replace: `영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.`
- 다중 선택 Invalid / Unsupported만 제외: `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`
- 복합 제외: 기존 복합 Copy 그대로.

사용자 Copy는 Aperture · HDR · Dolby Vision · Rec.2020 · Tone-mapping을 언급하지 않는다.

## Tests and Acceptance

### 순수 Facts / Classifier / Plan Test

- Full Aperture, 중앙 소수 원점 홀수 Aperture, 정수 Offset Aperture, 형식 오류 / 얻을 수 없는 Aperture
- 사유 없는 Non-full Source는 Fast Path 유지
- 사유 있는 Full-aperture HDR과 Full-aperture SDR은 내장 경로
- 사유 있는 Non-full SDR Rec.709는 Geometry 전용 경로
- 사유 있는 Non-full HLG / PQ / Rec.2020 / Dolby Vision은 거부
- 사유 있는 Non-full Unknown / 미증명 색은 거부
- 긍정적 709 Facts를 가진 Non-full SDR 10-bit는 Eligible 유지
- 단계 우선순위, Step 3 Invalid / Unsupported 매핑, 단일 / 다중 / Replace 동작, 새 안내 범주 없음

### 실제 Media Test

- 내장 Compositor가 Full-aperture 경계를 보존
- Custom SDR Geometry 경로가 홀수 / Offset Clean Aperture를 보존
- Full-aperture HLG / PQ는 승인된 내장 경로 유지
- Non-full HDR은 AVFoundation Media Operation 전에 거부
- 성공한 정규화 경로 간 출력 계약 동일, Source 불변, 거부 항목 출력 없음

### 기기 Gate

- 최종 Step 4B 통합 후 기존 Full-aperture HDR 검증을 반복한다.
- Dolby Vision A/B는 진짜 승인된 Fixture가 있을 때까지 Pending이며 합성 Dolby Vision 증명을 주장하지 않는다. — **구현 상태(2026-10-02):** 이 Fixture 한정 Dolby Vision A/B 항목은 진짜 `dvvC` Profile 8 · Compatibility ID 4 신호를 가진 `IMG_0130.MOV`의 소유자 시각 판정 PASS(`PASS — HDR to SDR appearance is acceptable.`)로 충족되어 더 이상 Pending이 아니다. 이 판정은 이 Source · 현재 Step 4B 구현(`da1f337`) · LunaTestphone · 승인된 내장 Full-aperture 정규화 경로에 한정되며 일반 Dolby Vision 인증이 아니고 모든 Dolby Vision Profile · Metadata 변형 · 기기 · Aperture · Rendering 경로 · Source를 보장하지 않는다. 사용자 Import 흐름 통합과 Phase 6 전체는 완료되지 않았다.

## Rationale

- 승인되고 기기 A/B를 받은 Tone-mapping 경로를 바꾸지 않으면서 ADR-047 Revision 1의 Crop · Padding 금지를 지킬 수 있는 가장 좁은 경계다.
- SDR Rec.709 Source는 Tone-mapping이 필요 없으므로 Geometry 전용 경로가 Clean Aperture 전체를 정확히 매핑할 수 있다.
- Non-full Aperture이면서 Tone-mapping이 필요한 Source는 승인된 경로로는 경계를 잃거나 번지고, 다른 변환 경로는 승인된 증거가 없다. 경계를 잃은 Working Media를 조용히 만드는 것보다 기존 범주로 제외하는 편이 Media Safety와 Product 계약에 맞다.
- Fast-path Copy는 Source를 그대로 보존하므로 Aperture가 Normalization을 강제할 이유가 없다.

## Consequences

- `ImportSourceFacts`(또는 동등한 Inspector Facts)에 Encoded Raster · Clean Aperture · Pixel Aspect · Full / Non-full 판정이 추가된다(구현 대상).
- Classifier는 사유 판정 뒤 경로 판정 단계를 수행하고 Case D를 기존 Invalid / Unsupported Exclusion으로 매핑한다(구현 대상).
- Step 4A Plan은 준비 경로를 결정적으로 표현하고 Step 4B Normalizer는 두 정규화 경로를 구현한다(구현 대상).
- ROADMAP Phase 6 Unit / Integration / Device Test에 이 ADR의 Case가 추가된다.

## Still Pending (이 ADR이 확정하지 않음)

- Non-full Aperture HDR / Wide-color Source의 Post-V1 지원(별도 변환 메커니즘 + 기기 HDR / Dolby Vision 증거)
- Dolby Vision 기기 A/B(진짜 승인된 Fixture 필요) — **구현 상태(2026-10-02):** 이 Fixture 한정 Dolby Vision A/B 항목은 진짜 `dvvC` Profile 8 · Compatibility ID 4 신호를 가진 `IMG_0130.MOV`의 소유자 시각 판정 PASS(`PASS — HDR to SDR appearance is acceptable.`)로 충족되어 더 이상 Pending이 아니다. 이 판정은 이 Source · 현재 Step 4B 구현(`da1f337`) · LunaTestphone · 승인된 내장 Full-aperture 정규화 경로에 한정되며 일반 Dolby Vision 인증이 아니고 모든 Dolby Vision Profile · Metadata 변형 · 기기 · Aperture · Rendering 경로 · Source를 보장하지 않는다. 사용자 Import 흐름 통합과 Phase 6 전체는 완료되지 않았다.
- Fast-path Copy된 Non-full Aperture Media를 이후 Preview / Export Composition이 어떻게 렌더링하는지(Phase 7 / 9 소유, 이 ADR은 결정하지 않음)
- Import Storage Estimate Formula와 Safety Reserve, Aggregate Progress / Retry Source-handle 메커니즘

## Non-goals

- Production 구현, ADR-045 / ADR-047 본문 개정, 새 Normalization 사유, 새 사용자 범주 · Copy, Crop / Pad / Upscale 옵션, Remux, Custom Compositor Pre-conversion의 Tone-mapping 승인.

---

# ADR-050 — Import Storage Estimate, Safety Reserve, and Check Boundaries

**Date:** 2026-10-02
**Status:** Proposed — **부분 승인(2026-10-02, 사용자 승인):** Unit 050-A 전체, Unit 050-B, Unit 050-C의 계산 정책(Volume별 추가 쓰기 계산, 256 MiB Import Reserve, Unknown Capacity · 잘못된 Estimate 입력 · 산술 Overflow의 Fail-closed)만 Accepted다. 이 값들은 Policy Estimate이며 증명된 상한이 아니고, Reserve는 측정되지 않은 위험을 덮는다고 보장하지 않는다. **추가 부분 승인(2026-10-02, 사용자 승인):** OD-14 (a) — `.replacingSaved`의 단일 Save 대체와 그에 따른 ADR-033 Revision 1(B Media 존재 · Metadata 변환의 Save 전 확인, Lifecycle Gate 안 Target 재확인, A 소실 시 Target 무효화(B만 생성하는 Fallback 없음), 성공 · 미확정 결과의 Media 보존, B 완전 저장과 A Metadata 부재 확인 뒤에만 A Media 제거, Commit 뒤 A Metadata는 이미 없다는 잔여 위험의 명시적 수용). Accepted 050-B 두 Save Metadata 계산과 상수는 바뀌지 않는다. **추가 승인(2026-10-02, 사용자 승인) — 결과 처리 P1–P6 · P8(D8.5a):** Prior Snapshot 시점, Editor Reconciliation 차단, U1 / U2 정확한 문구, Save 오류 뒤 `completed` 처리, Projects 갱신과 Load 실패 = 모름, `priorConfirmed` 임시 경계, Select Clips의 `replaceProject` 연결이 Accepted(Production 미구현); P7(동기 Editor 변경)은 보류. **추가 승인(2026-10-02, 사용자 승인) — Lifecycle Gate 직렬화 전제조건 구현:** Home Project 삭제와 Editor Add / Replace의 Target 재확인 · Materialize · Commit을 공유 Gate로 직렬화(D6 구현 항목); 050-D의 다른 결정은 승인하지 않는다. **추가 부분 승인(2026-10-02, 사용자 승인) — OD-10 관측 구현 정책:** 관측마다 새 전용 `ModelContext`(Autosave 꺼짐, `includePendingChanges = false`), Save Context · 공유 Context Object 재사용 없음; 구현 정책이며 모든 공유 Cache를 우회하거나 모든 실패에서 독립적인 Durable 진실을 확립한다는 보장이 아니고, 여러 Fetch로 이루어져 원자적 Snapshot이 아니다. **추가 부분 승인(2026-10-02, 사용자 승인) — Save Outcome 분류 규칙(050-D D8.0):** Save 성공 + Intended 확인 → 완료; Save 성공 + 확인 불가 · 모순 → Commit됨 · 확인 안 됨(참조 가능 Media 보존, Rollback 금지); Save 오류 + Intended 확인 → 완료; Save 오류 + Prior 확인(만든 Project · Clip ID의 Store 전체 부재 확인 포함) → Commit 전 Rollback 대상; Save 오류 + 그 밖 → 미확정(참조 가능 Media 보존, `다시 시도` 금지); 명확화: Save 오류 뒤 완료에는 만든 모든 ID의 완전하고 일치하는 Store 전체 증거가 필요하다(D8.0). 이 규칙은 해당 Save / 확인 결과 의미만 개정한다(ADR-037 STEP 11 Note, ADR-040 §9, ADR-047 Ownership, ARCHITECTURE Commit 경계, ROADMAP Task 14의 Read-back · Persist 실패 분기). C0 / C0a의 Phase 5 Admission 변경, 검사 경계 연결과 부족 Presentation, 그 밖의 050-D(D8.1–D8.5의 결과별 처리 · Prior Snapshot 시점 · Gate 안 Prior Snapshot · 판정 연결 · Rollback 구현 · 새 안내 Copy · Retry · Startup Cleanup 개정 등; 2026-10-02 갱신: 이 가운데 D8.5a P1–P6 · P8로 Accepted된 부분은 제외), 050-E는 Proposed로 남는다. ADR-050 전체는 Accepted가 아니다. **추가 승인(2026-10-05, 사용자 승인) — Select Clips 한정 안내(D8.5b):** Save 전 Project 확인 실패, Projects Load 실패 · "모름" 상태, 대체 Target 무효, 그 밖의 Save 전 준비 실패의 Select Clips 문구와 처리; Editor Stale 상태 안내, U3 / U4, 그 밖의 미결 항목은 바뀌지 않는다. **추가 승인(2026-10-05, 사용자 승인) — Editor 결과 처리와 P7(D8.5c):** Reorder · Delete · Undo · Redo의 공유 Lifecycle Gate 직렬화(P7), Editor의 Save 전 정지 안내, 이 네 편집의 `priorConfirmed` 안내, 진행 중 표시 · Navigation 규칙; Rollback, 같은 Set Retry, 일반 Late Result 정책, Startup Cleanup 개정과 그 밖의 050-D · 050-E는 바뀌지 않는다. **추가 승인(2026-10-05, 사용자 승인) — 제한된 복구 계약(D7a):** Rollback 자격 · 같은 Set Retry · 취소 경계 · Target 무효화 규칙과 그 안내(문서만, 미구현); 050-C 검사 경계 · 부족 Presentation, Startup Cleanup · 빈 Store 보호(OD-12), 일반 Late Result 정책, 050-E는 바뀌지 않는다. **추가 승인(2026-10-06, 사용자 승인) — 050-C 실행 경계와 부족 안내:** C0 / C0a / C1 / C2 / C3 / CR의 위치 · 대상 Volume · 계산과 부족 안내, Phase 5 Admission 개정(문서만, 미구현); 용량 API 선택 · 신선도 보장, Startup Cleanup, 일반 Late Result, 050-E는 바뀌지 않는다.

이 ADR은 서로 독립적으로 검토 · 승인할 수 있는 다섯 Decision Unit(050-A–050-E)으로 나뉜 제안이다.

한 Unit의 승인은 다른 Unit이나 그 미해결 의존성을 해결하지 않으며, 이 ADR 전체에 대한 하나의 포괄적 승인으로 Import Storage Gate가 닫히지 않는다.

ROADMAP Phase 6 Pending Technical Gate의 "Import Storage Estimate Formula"와 "Photos Import / Normalization에 필요한 Safety Reserve 정책"은 계산 정책으로서만 부분 승인되었다(위 Status). 검사 경계 연결, Runtime Disk Full · Recovery-safe Cleanup · Retry Integration Test, iPhone 12 Peak Storage 확인을 요구하는 ROADMAP Phase 6 Exit Criteria와 Integration Gate는 그대로 열려 있다.

Accepted 상수와 계산은 Step 5B(2026-10-02)에서 순수 `ImportStorageEstimator`로 구현되었고 Picker · Normalizer · Repository · Coordinator · UI에 연결되지 않았다. 그 밖의 제안값은 Production 코드에 존재하지 않는다.

050-A / 050-B / 050-C / 050-E는 승인된 계약(ADR-020 / ADR-021 / ADR-024 / ADR-039 / ADR-040 / ADR-042 Revision 4 / ADR-047)의 문구를 바꾸지 않는다(단 050-C의 Phase 5 Admission 변경 제안(OC-4)은 사용자 승인된 ROADMAP "Project Materialization Storage Technical Gate — Resolved 2026-09-15"의 동작을 바꾸는 제안이다); 승인 문서가 정하지 않은 경우의 해석과 새 정책은 각 Unit에서 그렇게 표시한다.

**예외 — 050-D D1–D3은 승인된 문구의 개정 제안이다:** ADR-037 STEP 11 Implementation Note("Persist → Read-back Verify → Cleanup. Commit 전 실패 시 P는 변경되지 않으며"), ADR-040 §9("Read-back 불일치"에서도 "B는 정확히 이전 그대로 … 이 Operation이 만든 D 파일만 즉시 제거" + `클립을 교체하지 못했어요` / `다시 시도해주세요. 프로젝트는 그대로 있어요.`), ADR-047 Decision 2 Ownership과 ARCHITECTURE의 Commit 경계("Materialize → Project State → Persist → Read-back")는 Read-back을 Commit 경계 안에 두고 Read-back 실패를 "무변경 + 새 파일 제거"로 정한다. 050-D D2가 보이듯 Durable Save가 성공한 뒤에는 이 약속을 지킬 수 없고 그대로 따르면 Durable Metadata가 참조하는 Media를 지울 수 있다. 050-D D1–D3은 이 충돌을 해소하기 위한 개정 제안이며 승인되면 위 문구들의 개정이 함께 필요하다. 또한 050-D D8.5는 ADR-040 §9("Persist 실패"에서도 B 무변경 + D 파일 제거), ADR-037 STEP 11 Note(Persistence 실패 시 P 무변경), ROADMAP Phase 6 Task 14 주석(Metadata Persistence 실패 시 Rollback, Materialize된 파일 제거, Project 무변경)의 **Persist 실패 분기**에 대한 개정 제안이다: Save가 오류를 던졌더라도 다시 읽은 Durable 상태가 새 상태면 성공으로, 미확정이면 파괴적 정리 없이 보존으로 처리한다. 다시 읽은 상태가 확인된 이전 상태인 Save 오류는 위 문구와 ADR-042 Revision 4 §3을 그대로 따른다. 050-D D8.6의 "이전 Project A가 남는" 결과는 ADR-033 / ADR-034 V1 Single Saved Project의 Safe Atomic Replacement에서 벗어나는 결과다(OD-11 / OD-13). 050-D D8.7은 ADR-039 STEP 12B Startup Recovery의 Orphan Directory 판정에 빈 Store 보호를 더하는 개정 제안이다(OD-12).

이 ADR은 Production 구현, UI 연결, Encoder 설정 변경, Phase 6 완료를 의미하지 않는다.

## Context

ADR-024는 `Required Free Space = Estimated Peak Additional Storage + Safety Reserve`, Operation별 Estimate, 0이 아닌 Reserve, Commit된 Media 재계산 금지, 부족 시 해당 Operation만 차단, Quality Downgrade와 Clip-count Cap 금지를 확정했지만 Import의 Formula와 Reserve는 Phase 6 Technical Gate로 남겼다.

ADR-042 Revision 4는 관찰 가능한 UX를 확정했다: §2 취소, §3 Runtime Preparation / Normalization 실패(`영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.` / `다시 시도` / `취소`), §4 Materialization / Normalization 시작 전 Storage 부족(`확인`), §7 Accepted Set 경계.

ADR-047 Decision 2는 No Resume, 시작 시 Workspace Sweep, Accepted Set 전체 준비 뒤의 Materialize(Rename)를 확정했고, Boundary F의 "Recovery Candidate 보존"을 Live Process 안 같은 Accepted Set `다시 시도`를 위한 것으로 명확히 했다.

Materialization 이후 Metadata Persistence 실패 시의 Rollback 문구("Materialize된 파일 제거, Project 무변경")는 ADR-047 본문이 아니라 ROADMAP Phase 6 Task 14의 "ADR-047(2026-09-18)로 대체" 주석과 ROADMAP Phase 6 Integration Test 항목에 있다.

ROADMAP Task 13은 Live Process 안에서 Valid Source / Staging을 보존하여 `다시 시도`가 같은 Accepted Set을 재시도할 수 있게 하라고 요구하고, Integration Test는 "Retry 성공 시 전체 Commit"을 요구한다.

Phase 5 Storage Gate(ROADMAP "Project Materialization Storage Technical Gate — Resolved 2026-09-15")는 Phase 5 전용 100 MiB Reserve와 `ReceivedVideoFile.admit`의 File별 Pre-copy 검사를 확정했고 이 Reserve를 Import에 조용히 재사용하지 못하게 한다.

Phase 6 Step 5A Exploratory Evidence(`docs/evidence/phase-06/step-5a-import-storage-report.md`, Commit `0ef173b`, iPhone 12, iOS 27.0.1)는 다음을 관측했다.

- 정규화 출력은 Run당 File 하나이며 표본 추출 중 Intermediate 이름이 보이지 않았다; Workspace Peak = Source + 출력.
- 정규화 출력 Rate(Logical 전체 File Byte ÷ Source Duration): 실제 IMG_0130 1,787,583 B/s; 합성 Noise 최대 7,450,709 B/s(HLG 1080p30, Audio 없음), 7,203,486 B/s(1080p60); 합성 4K Noise 3,340,367–3,625,380 B/s(Run 간 약 8.5% 변동). Allocated 기준 최대값은 38,248,448 B ÷ 5 s = 7,649,690 B/s였다.
- 출력 24개의 Allocated − Logical은 203,031–1,006,513 B였다.
- 새 빈 Store에 대한 `create` + Read-back의 WAL 증가는 74,192 B Logical / 77,824 B Allocated였고 Clip 1개와 2개에서 같았다.
- `volumeAvailableCapacity`는 306개 측정에서 모두 26,992,640,000 B로 변하지 않았다; `statfs` 여유 공간은 1080p60 / HLG Run의 정규화 이후 30개 측정에서 26,951,680,000 B(−40,960,000 B)였다; `volumeAvailableCapacityForImportantUsage`는 한 Run 안에서는 한 번도 변하지 않았고 Run 사이에서만 네 값(37,230,774,904 / 37,271,734,904 / 37,281,000,672 / 37,240,040,672 B)을 보였다.

이 관측은 상한이 아니다.

Important-usage 값이 Run 안에서 변하지 않은 것이 Caching 때문인지, 갱신 단위 때문인지, Purgeable 공간 계산 때문인지는 이 Evidence로 알 수 없다; 이 값의 신선도(Freshness)와 쓰기 추적 여부는 증명되지 않았다.

Normalizer는 Average Bitrate를 요청하지 않으며, 요청하더라도 Average Bitrate는 File 크기 보장이 아니다.

IMG_0130 출력은 H.264 High Level 4.0을 신호했지만 합성 출력의 Level은 기록하지 않았으므로 Level 신호로부터 어떤 상한도 추론하지 않는다.

---

## Decision Unit 050-A — 정규화 출력 Estimate와 정책 Allowance

**Unit Status:** **Accepted(2026-10-02, 사용자 부분 승인)**. Policy Estimate이며 증명된 상한이 아니다. Step 5B(2026-10-02) 구현: `ImportStorageEstimator.normalizedOutput` / `remainingOutputBytes` — Passthrough의 `S_audio`는 호출자가 명시적으로 넘기며(Source File 전체 크기로 대체하지 않는다) Inspector Fact 연결은 Pending이다. (2026-10-05 갱신: `ImportSourceFacts.audioPayload` — 정규화 Passthrough와 같은 Track 선택(`ImportAudioTrackSelection`)과 같은 읽기 범위(설정 없는 Track Output, Asset 전체)의 압축 Sample 크기 합, Checked 산술, 측정 불가는 명시적 `.unavailable`(0으로 대체하지 않음), 취소는 별도로 전파 — 와 순수 대응 `ImportStorageEstimator.outputAudio(for:sourcePayload:)`(계획 기준: 없음 → 0, Transcode → Accepted 추정, AAC Passthrough → 측정값, 측정 없음 → `sourceAudioPayloadUnavailable` Fail-closed)가 구현되었다; 연결 없음. 측정은 AAC Passthrough가 가능한 Source(ADR-048 평가가 `passthroughAAC`이고 Duration이 최대 이하)에만 하며 그 밖은 "측정 안 함"이다. 미결 질문: 합성 AAC에서 측정값이 정규화 출력의 저장 Payload보다 작게 관측되었다(원인 미확인) — 아래 OA-4 참고.) (2026-10-05 추가 갱신: 이 질문은 OA-4 명확화로 해결 — `S_audio`는 선택된 같은 Track의 저장 Sample Data Byte와 Passthrough Reader 전달 Byte 가운데 큰 값이며 둘 다 유효해야 한다; 구현됨.)

정규화가 필요한 항목 j마다:

```
D_bound(j) = sourceDuration(j) + 1/30 s                         // ADR-045 §7 출력 Duration 허용 상한, 정확한 Rational
V(j)       = ceil(R_video × D_bound(j) × (1 + m))
A(j)       = 0                                                  // 출력 Audio 없음
           | S_audio(j)                                         // AAC Passthrough: Source Audio Track의 Sample Data Byte
           | ceil(R_tx × (D_bound(j) + 3136/48000 s))           // audioTranscode(AAC-LC 48 kHz)
E_norm(j)  = V(j) + A(j) + C_out
```

| 항목 | 제안값 | 성격 | 측정된 한계 |
| --- | --- | --- | --- |
| `R_video` | 7,500,000 B/s | 경험적 표본 통계(정책 선택으로 반올림) | 1080p-class 출력의 Logical 최대 관측 7,450,709 B/s(합성 Noise, Audio 없음)를 올린 값이다. Allocated 기준 관측 최대 7,649,690 B/s보다 작으며 관측된 24개 출력에서는 그 차이가 `C_out` 안에 들어갔으며 그 밖의 출력에 대해서는 보장하지 않는다. 실제 4K60 HDR / Dolby Vision · 고움직임 · 저조도 Source는 측정되지 않았다. 상한이 아니다. |
| `m` | 1/2 | 소유자 선택 정책 Margin | 측정에서 유도하지 않았다. 관측 사실은 같은 Source 출력의 Run 간 약 8.5% 변동과 미측정 Source 범주의 존재뿐이다. |
| `C_out` | 2,097,152 B / 출력 File | 소유자 선택 정책 Allowance | 관측 Allocated − Logical 최대 1,006,513 B(출력 38 MB 이하 24개)이다. 더 큰 출력의 여유분과 Passthrough Audio의 Sample Table 증가는 측정되지 않았다. |
| `S_audio` | Source에서 읽는 정확한 값 | Source Fact | AAC Passthrough는 Audio Bitstream을 그대로 복사하므로 Priming Packet을 포함한 Source Audio Payload가 출력 Audio Payload의 근거다. 현재 `ImportSourceFacts`에는 이 값이 없다. (2026-10-05: `ImportSourceFacts.audioPayload`로 추가 — 위 Unit Status 참고.) Container 증가분은 `C_out`에 포함되는 것으로 가정하며 측정되지 않았다. |
| `R_tx` | 32,000 B/s | 소유자 선택 정책 Allowance | ADR-048의 AAC-LC 요청값(Mono 96 kbps / Stereo 128 kbps = 16,000 B/s)의 2배다. 요청은 상한이 아니며 Transcode 출력은 측정되지 않았다. `3136/48000 s`는 AAC Encoder Priming 2,112 Sample과 마지막 Frame 1,024 Sample을 위한 정책상 시간 여유이며 측정되지 않았다. |

- 이전 초안의 "AAC Channel당 Frame당 6144 bit" 기반 Audio 상한은 철회한다. 그 값이 무엇을 제한하는지(NCC 정의, LFE / CCE, 960-sample Frame, Implicit SBR의 Sample Rate 보고)가 이 ADR에서 권위 있게 확인되지 않았기 때문이다.
- 정수 계산: `D_bound = (value × 30 + timescale) / (timescale × 30)`; `V = ceil(R_video × (value × 30 + timescale) × 3 / (timescale × 30 × 2))`; Transcode 항은 분모 48,000 × 30 × timescale로 통분한 뒤 올림 나눗셈한다. 모든 곱셈 · 덧셈은 Overflow 검사를 하며 Overflow, 0 이하 Timescale, 음수 값, 읽을 수 없는 `S_audio`는 통과가 아니라 부족(Fail-closed)으로 처리한다.
- Fast-path 항목의 Estimate는 0이다(ADR-047의 같은 Volume Materialize(Rename)).
- Estimate는 Clip 수에 선형이며 Clip-count Cap이 없다. Storage 부족을 이유로 Raster · Frame Rate · Bitrate · Audio를 낮추지 않는다.

예시(Unit 050-A만):

- IMG_0130(2722/600 s, AAC Passthrough): `D_bound = 2742/600 = 457/100 s`; `V = 7,500,000 × 457/100 × 3/2 = 51,412,500`; `E_norm = 51,412,500 + S_audio + 2,097,152 = 53,509,652 + S_audio B`. 관측 출력 8,109,669 B Logical(Audio 포함)이며 `S_audio`를 뺀 부분만으로도 약 6.60배다.
- 5.0 s 무음: `V = 7,500,000 × 151/30 × 3/2 = 56,625,000`; `E_norm = 58,722,152 B`. 관측 최대 출력 Allocation 38,248,448 B.
- 1.0 s 무음: `V = 7,500,000 × 31/30 × 3/2 = 11,625,000`; `E_norm = 13,722,152 B`.
- 5.0 s `audioTranscode`: `A = ceil(32,000 × 244,736/48,000) = 163,158`; `E_norm = 56,625,000 + 163,158 + 2,097,152 = 58,885,310 B`.

---

## Decision Unit 050-B — Metadata / WAL Estimate

**Unit Status:** **Accepted(2026-10-02, 사용자 부분 승인)**; Step 5B(2026-10-02) 구현 `ImportStorageEstimator.metadata`(연결 없음). 아래 상수는 측정점 안의 경험적 관측에 소유자 선택 정책 Margin을 더한 Accepted 정책값이며 증명된 상한이 아니다. Evidence: `docs/evidence/phase-06/adr-050b-metadata-wal-report.md`(Exploratory, Commit `0ef173b`, iPhone 12, iOS 27.0.1).

### 측정에서 확인한 Estimate 형태

- Metadata 비용은 Accepted Set 크기가 아니라 **Operation이 수행하는 Repository Save마다, 그 Save가 다시 쓰거나 지우는 Durable Clip Row 수**에 따라 커졌다.
- Add / Replace의 `update`는 기존 Durable Clip 전부(Active + Pending-deleted)를 다시 쓰므로 Row 수는 `D_existing + n`이다; Select Clips `create`는 `n`; `.replacingSaved`의 이전 Project 삭제 Save는 Cascade로 지우는 `D_replaced`다.
- 같은 Save도 Store에 이미 있는 Row가 많을수록 커졌다(n = 10 `create`: 빈 Store 74,192 B, 200-Row Project가 있는 Store 90,640–94,760 B, Warm Store 86,520–90,640 B). 이 Store 크기 효과는 아래 Formula에 별도 항이 없고 측정점(Store 최대 210 Clip Row) 안의 관측은 `W_save` Margin 안에 들어갔다. Draft 수에는 상한이 없으므로 그보다 큰 Store에서의 효과는 모델링되지 않았다. Reserve는 크기가 측정에서 정해지지 않은 정책값이므로 이 위험을 덮는다고 보장하지 않으며, 초과하면 Runtime 쓰기 실패(050-C / 050-D)가 처리한다.
- Read-back은 WAL에 쓰지 않았다.
- `create` / `update` Save는 SQLite Commit 2개, `deleteProject` Save는 1개였다. 따라서 Repository Save 하나는 SQLite Transaction 하나가 아니고 `.replacingSaved` Operation은 Save 2회 · SQLite Transaction 3개로 이루어진다. Operation을 하나의 Transaction으로 가정하지 않는다.
- 후속 Probe(`docs/evidence/phase-06/adr-050d-persistence-atomicity-report.md`, Exploratory)는 첫 Commit이 `Z_PRIMARYKEY` Page 하나만 바꾸고 Domain Row와 영구 이력 Row는 모두 두 번째 Commit에 있음을 관측했고, 관측한 경계(Save 직전, 각 Commit 직후, Transaction당 한 개의 중간 지점)에서 WAL Prefix로 재구성한 Durable 상태가 Save 전 상태 또는 완전한 새 상태뿐임을 관측했다(다른 중간 지점은 SQLite WAL Recovery 설계에 근거한 추론). 이것은 측정한 경우의 재구성 경계에 대한 관측이며 실제 Process 강제 종료, 전원 손실, 모든 Save 오류에 대한 보장이 아니다. Process 안의 Save 오류와 전원 손실은 관측하지 않았으므로 050-D D1의 "Save가 오류를 던지면 Commit되지 않은 것으로 본다"는 여전히 증명되지 않은 가정이다. 이 Unit은 050-D를 바꾸지 않는다.

### 제안 Formula

```
W_op = Σ_{Operation의 각 Repository Save s} (W_save + W_row × R_s)
```

| 경로 | Save와 `R_s` |
| --- | --- |
| Select Clips 새 Project | `create(B)` 1회: `R = n` |
| Select Clips `.replacingSaved` | `create(B)`: `R = n`; 이전 Project 삭제: `R = D_replaced` |
| Editor Add | `update` 1회: `R = D_existing + n` |
| Editor Replace | `update` 1회: `R = D_existing + 1` |

- `D_existing`과 `D_replaced`는 Active와 Pending-deleted Row를 모두 센다.
- 이 표는 현재 코드의 성공 경로 Save 수다. 050-D D2가 기록한 현재 Read-back 실패 보상 경로(`deleteProject(B)`)는 Save를 하나 더 하며(`R = n`) 050-D D3이 승인되면 없어진다; 이 Estimate는 성공 경로 기준이고 보상 Save는 Estimate에 넣지 않는다. Reserve는 크기가 측정에서 정해지지 않은 정책값이므로 이 위험을 덮는다고 보장하지 않으며, 초과하면 Runtime 쓰기 실패(050-C / 050-D)가 처리한다.

| 상수 | 제안값 | 성격 | 관측과 Margin |
| --- | --- | --- | --- |
| `W_save` | 196,608 B (192 KiB) / Save | 경험적 관측 + 소유자 선택 정책 Margin | 작은 `R`(≤ 10)에서 관측 최대 Save당 WAL 증가는 94,760 B(이미 200 Row가 있는 Store에 n = 10 `create`)였고, Container를 닫을 때의 Checkpoint로 DB File이 최대 53,248 B 커졌다. 두 값의 합 148,008 B 대비 약 1.33배다. Operation 도중 Checkpoint는 관측되지 않았다. |
| `W_row` | 512 B / Durable Clip Row | 경험적 관측 + 소유자 선택 정책 Margin | 같은 경로 · 같은 n의 양 끝 측정점 사이 기울기(각 끝의 Run 최대 / 최소 조합)는 약 173–325 B / Row였다: create n 1 → 200: 248–269, Add D 0 → 200: 185(n = 1) · 206(n = 10), Replace D 10 → 200: 173–282, 이전 Project 삭제 D 10 → 200: 282–325. 최대 325 대비 약 1.57배다. 같은 Scenario의 Run 간 차이가 최대 5 Frame(20,600 B)이므로 기울기 자체가 Page 단위 잡음을 포함한다. |

- 측정한 모든 단계(Section B, 3 Run씩)에서 관측 WAL 증가는 이 Formula 값의 47% 이하였다.
- 이전 초안의 `W_base = 4 MiB` 고정 Allowance는 이 형태로 대체를 제안한다.

### 한계(증명된 상한이 아닌 이유)

- 측정점은 `D` ≤ 200, `n` ≤ 10, Store 최대 210 Clip Row다. 그 밖으로 외삽하여 상한을 주장하지 않으며 Clip-count Cap을 두지 않는다; Formula는 Row 수에 선형으로 커질 뿐이다.
- Operation 도중의 Checkpoint, Auto-checkpoint 임계값(`wal_autocheckpoint`는 얻지 못했다), 동시 Reader로 인한 Checkpoint 지연과 WAL 무한 증가, 기존의 큰 Store / 큰 WAL(App의 실제 WAL은 약 1 MB였다), Disk Full 중 Save는 측정하지 않았다. 이 잔여 위험은 Estimate 밖에 있다. Reserve는 크기가 측정에서 정해지지 않은 정책값이므로 이 위험을 덮는다고 보장하지 않으며, 초과하면 Runtime 쓰기 실패(050-C / 050-D)가 처리한다.
- 기존 WAL은 Occupancy다. WAL은 Checkpoint 전까지 Operation 사이에 계속 커질 수 있으며, 그 누적분은 다음 Operation의 Capacity 측정값에 반영된다.
- Thumbnail은 현재 Memory 전용(`ClipThumbnailService` `BoundedThumbnailCache`)이므로 Allowance가 없다.

---

## Decision Unit 050-C — Capacity와 Transfer Admission

**Unit Status:** 부분 승인(2026-10-02, 사용자 승인). **Accepted — 계산 정책만:** Occupancy / Additional 분리와 Volume별 추가 쓰기 계산, `Reserve_import = 256 MiB`, Unknown Capacity · 잘못된 Estimate 입력 · 산술 Overflow의 Fail-closed, `Additional + Reserve = U`는 통과. Step 5B(2026-10-02) 구현: `ImportStorageEstimator.requirement` / `check`(주입 가능한 Capacity 입력, 연결 없음). **구현됨 · 연결 없음(독립 승인 정책이 아님):** `NSFileWriteOutOfSpaceError` / `ENOSPC` / `AVError.diskFull`(Underlying 포함)의 Typed 분류 `ImportWriteFailureClassifier`; 그 Logging과 Presentation 연결은 Proposed다. **Proposed 유지:** 검사 경계 C0 / C0a / C1 / C2 / C3 / CR의 연결, 부족 Presentation 대응, Phase 5 Admission 변경, Provider / Transfer 해석. (2026-10-06 갱신: 검사 경계 · 부족 안내 · Phase 5 Admission 개정 · Provider / Transfer 해석은 아래 "050-C 실행 경계 승인"으로 Accepted — 미구현.)

### Occupancy와 Additional

- **Occupancy:** 검사 시점에 이미 Volume에 존재하는 모든 Byte(Commit된 Media, Replace 대상 기존 Clip Media, 다른 Draft, System Provider File, 이미 Adopt된 Source, 이미 쓰인 출력, Store / WAL). Occupancy는 Capacity 측정값에 이미 반영된 것으로 간주하며 Required에 더하지도, Capacity에서 빼지도 않는다.
- **Additional:** 검사 시점 이후 이 Operation이 끝나기 전에 해당 Volume에 새로 Allocate될 수 있는 Byte의 추정 Peak.
- **검사:** 각 검사는 그 단계의 쓰기 대상 Directory가 속한 Volume 하나에 대해서만 수행하고 `Additional(그 Volume) + Reserve_import ≤ U(그 Volume)`일 때만 통과한다. U는 그 시점에 읽은 `volumeAvailableCapacityForImportantUsage`다(2026-10-06: 현재 코드가 읽는 값을 설명할 뿐 용량 API의 선택이나 신선도 보장으로 승인된 것이 아니다). 한 Volume의 쓰기를 다른 Volume의 Capacity에 청구하지 않는다.
- U의 신선도는 증명되지 않았다(Context). 검사는 부족을 줄이는 장치일 뿐이며 Runtime Disk Full 처리를 대체하지 않는다.
- 삭제 예정 File, Provider File의 해제, Replace로 대체될 기존 Media에 대해 공간을 미리 차감(Credit)하지 않는다.
- Replace의 기존 Clip Media는 Commit까지 보호되는 Occupancy이며 새 Allocation으로 다시 계산하지 않는다. 대체 후보는 단일 항목 Accepted Set과 같은 Formula를 쓴다.
- APFS Clone에 기대지 않는다: 모든 Mellow Copy는 Source의 Logical 크기 전체를 그 Copy 대상 Volume의 Additional로 계산한다. 같은 Volume Rename은 Data Byte를 새로 쓰지 않는 것으로 계산하지만 실패할 수 있는 연산으로 다룬다.
- Unknown / 읽을 수 없는 Capacity, Overflow, 음수, 읽을 수 없는 Source 크기는 통과가 아니라 부족이다. Log에는 전체 Path 없이 Typed 사유를 남긴다.

### Import Safety Reserve

- `Reserve_import = 268,435,456 B (256 MiB)`. 0이 아니며 Phase 5의 100 MiB 상수를 재사용하지 않는 Import 전용 상수다.
- 이 값은 측정에서 유도하지 않은 소유자 선택 정책이다. Reserve가 흡수하려는 것은 Estimate 초과, 동시 System / 다른 App 쓰기, Filesystem Metadata, W를 넘는 WAL 증가, 신선도가 증명되지 않은 U와 실제 여유 공간의 차이다. 이 중 어느 것도 이 Evidence로 크기가 정해지지 않았다.
- Tradeoff: 값이 클수록 거의 가득 찬 기기에서 실제로는 성공했을 Import가 더 자주 차단된다. 값이 작을수록 Runtime Disk Full이 더 자주 난다. 대안: 200 MiB(209,715,200 B) 또는 512 MiB(536,870,912 B).

### 검사 경계

> 2026-10-06: 아래 표의 경계는 "050-C 실행 경계 승인"으로 Accepted(미구현)되었다; C3은 정규화 출력이 모두 끝난 뒤 Materialize 직전에 Metadata + Reserve만 검사하며 Save 전 Target · 파일 · Metadata 확인을 대체하지 않는다.

| 경계 | 시점 | 대상 Volume | Additional | 부족 시 |
| --- | --- | --- | --- | --- |
| C0 | Mellow의 Picker Transfer 복사 직전, Importing Closure 안, File마다 | `tmp/ProjectMediaTransfer`의 Volume | `N_k` | 초기 Preflight 부족 |
| C0a | `adopt`가 Rename에 실패하여 Copy Fallback을 하기 직전(Fallback이 일어날 때만) | Mellow Root의 Volume | `N_k`(Transfer 복사본은 이때 Occupancy) | 초기 Preflight 부족 |
| C1 | Accepted Set 분류 뒤, 제외 항목 Source 삭제 뒤, 첫 Attempt의 어떤 정규화 · Materialize보다 먼저 | Mellow Root | `Σ_{정규화 j} E_norm(j) + W` | 초기 Preflight 부족 |
| C2 | Attempt 안에서 두 번째 이후 각 정규화 항목 시작 직전 | Mellow Root | 아직 시작하지 않은 정규화 항목의 `Σ E_norm + W`(이미 쓰인 출력은 Occupancy) | Attempt 중 부족 |
| C3 | Attempt 안에서 Materialize 직전 | Mellow Root | `W`(Materialize는 같은 Volume Rename) | Attempt 중 부족 |
| CR | `다시 시도`가 새 Attempt를 시작하기 직전, 050-D의 Retry 전제조건 확인 뒤 | Mellow Root | C1과 같은 계산(보존된 Source는 Occupancy) | Retry 전 검사 부족 |

- `N_k`는 Closure 안에서 Provider File을 `stat`한 실제 Logical 크기다.
- 현재 `adopt`는 같은 Volume에서도 `moveItem`의 어떤 오류에 대해서든 Copy Fallback을 한다. C0a는 그 Fallback이 실제로 일어날 때만 검사하므로 정상 경로에서 `N_k`를 두 번 계산하지 않는다. C0a는 현재 코드에 없는 구현 의존성이다.
- 첫 정규화 항목은 C1이 막 검사했으므로 C2를 생략할 수 있다.

### 부족 Presentation(ADR-042 Revision 4 보존)

> 2026-10-06: 2항 가운데 C2 / C3 부족의 안내(원인 비표시, R4 §3)만 "050-C 실행 경계 승인"으로 결정되었다(미구현) — Durable Commit 전 Runtime Disk Full은 Runtime 쓰기 실패로 따로 처리된다. 3항(CR 부족)은 위 권장안(R4 §3 재표시)도 대안(R4 §4 + 종료)도 채택되지 않았고, R4 밖의 새 CR 부족 안내로 결정되었다(미구현); 4항의 `outOfSpace` 분류는 구현 · 연결 없음이며 별도로 승인된 Logging · Presentation 정책이 아니다.

1. **초기 Preflight 부족(C0, C0a, C1):** R4 §4 그대로 — Media 미생성, Project 무변경, Replace 기존 Clip 보존, `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`. §4에는 `다시 시도`가 없으므로 Operation이 끝나고 그 Operation의 Transfer File · Workspace를 Discard한다. 아직 Attempt가 시작되지 않았으므로 Retry Source를 없애는 것이 아니다.
2. **Attempt 중 부족(C2, C3, Durable Commit 전 Runtime Disk Full):** Preparation이 이미 시작되었으므로 R4 §4가 아니라 R4 §3의 Runtime 실패로 분류하고 050-D의 Pre-commit Rollback을 따른다. 새 Copy를 만들지 않으며 그 결과 사용자는 원인이 저장 공간임을 이 안내에서 알 수 없다(→ 소유자 선택).
3. **Retry 전 검사 부족(CR):** 승인 문서가 정하지 않은 경우다. 권장안은 실패한 Retry Attempt로 보고 R4 §3을 다시 표시하며 Retry Source를 보존하는 것이다("Retry 재실패 시 동일 정리"). 대안인 R4 §4 표시 + Operation 종료는 R4 개정이다. 어느 쪽도 기존 Copy를 근거로 Retry Source를 Discard하거나 `다시 시도`를 없애지 않는다.
4. **Runtime 쓰기 실패의 분류:** `NSFileWriteOutOfSpaceError`(640), POSIX `ENOSPC`(28), `AVError.diskFull`(−11807) 또는 이를 Underlying Error로 가진 오류는 내부 Typed `outOfSpace`로 분류해 Log한다. Accepted Set 이전의 Transfer 복사 · Adopt 실패는 Attempt도 Retry Source도 없으므로 R4 §3이 아니라 현재 Selection 실패 경로를 쓴다(이 경로의 Phase 6 Copy는 미정).

### Phase 5 Admission 변경(제안)

> 2026-10-06: C0 · C0a로 Accepted(미구현) — Phase 5 Admission의 100 MiB Reserve와 크기를 읽지 못한 File의 처리가 개정된다. 현재 코드는 아직 Phase 5 Admission(100 MiB)을 쓴다. Phase 5 Commit 직전 최종 Guard(추가 0 + 100 MiB)의 퇴역 시점은 이 승인에 명시되지 않았다. (2026-10-06 갱신: D7b 참조 3항 — 최종 Guard 퇴역은 흐름별로 결정되었다.)

(2026-10-06: 이 문단 끝의 "Phase 5 Reserve는 … 연결 단계에서 적용을 멈춘다"는 승인되지 않았다 — Commit 직전 최종 Guard의 퇴역 시점은 미명시로 남는다.) C0은 세 경로가 공유하는 `ReceivedVideoFile` Closure 안의 검사이며 Task 23이 세 경로를 같은 경로로 통합하므로, 승인되어 연결되면 Phase 5 Admission의 동작을 바꾼다: Reserve가 100 MiB에서 256 MiB가 되고, 크기를 읽지 못한 File이 현재처럼 0 B로 통과하지 않고 거부되며, C0a가 추가된다. Phase 5 Reserve는 Phase 6 Import 경로가 Select Clips / Add / Replace를 대체하는 연결 단계에서 적용을 멈춘다. (2026-10-06 갱신: D7b 참조 3항 — 전역이 아니라 흐름별 퇴역으로 결정되었다.)

### Provider File vs Mellow Transfer File

> 2026-10-06: 해석 확인됨 — Provider 자신의 File은 Mellow 소유 Disk 사용으로 계산하지도 건드리지도 않는다("050-C 실행 경계 승인" C0).

`ReceivedTransferredFile.file`은 System 소유이며 Mellow는 열거 · 수정 · 삭제하지 않고 Additional로 계산하지 않는다(C0 시점에 이미 존재하는 Occupancy). Mellow의 `tmp/ProjectMediaTransfer/<UUID>.<ext>` 복사본은 Mellow 소유이며 C0에서 Logical 크기 전체를 계산한다. ADR-024 Clarification과 ROADMAP의 "Picker Transient 복사본"은 이 Mellow 소유 복사본으로 해석한다(해석 확인 필요).

### 050-C 실행 경계 승인(2026-10-06, 사용자 승인 — 문서만, 미구현)

이 절은 050-C의 검사 경계와 부족 안내만 Accepted로 기록한다. Production 구현은 없다. 050-A · 050-B · 050-C 계산 정책과 상수, D7a, D8.0은 바뀌지 않는다. 용량 API의 선택이나 그 신선도 보장, Startup Cleanup 개정(OD-12), 일반 Late Result 정책, 050-E는 포함되지 않는다. (2026-10-06 갱신: Select Clips에 연결 구현 — D7b 구현 항목.)

| 경계 | 위치 | 대상 Volume | 요구량 | 부족 시 |
| --- | --- | --- | --- | --- |
| C0 | Mellow의 Picker Transfer 복사 직전, File마다 | `tmp/ProjectMediaTransfer`의 Volume | Source Logical Byte + 256 MiB Import Reserve | 초기 부족 안내 |
| C0a | `adopt`가 Move 실패 뒤 Copy로 넘어가기 직전에만 | Mellow Root의 Volume | Source Logical Byte + Import Reserve | 초기 부족 안내 |
| C1 | Accepted Set 분류 뒤 · 준비 시작 전 | Mellow Root | 남은 정규화 출력 + 작업 Metadata + Import Reserve | 준비를 시작하지 않음, 초기 부족 안내 |
| C2 | 두 번째와 그 뒤 각 정규화 항목 직전 | Mellow Root | 아직 쓰이지 않은 모든 출력 + 작업 Metadata + Import Reserve | R4 §3 실패 안내(아래) |
| C3 | Materialize 직전(모든 정규화 출력이 끝난 뒤) | Mellow Root | 작업 Metadata + Import Reserve | R4 §3 실패 안내(아래) |
| CR | 모든 Retry Attempt 시작 전(이전 정리 · 복원 확인과 Source · Target 확인 뒤) | Mellow Root | 새 Work Set으로 C1과 같은 요구량(남은 정규화 출력 + 작업 Metadata + Import Reserve) | CR 부족 안내(아래) |

- **C0:** 크기 · 용량을 읽을 수 없거나 산술 Overflow면 Fail-closed다. Phase 5 Admission(이전 100 MiB Reserve와 크기를 읽지 못한 File의 이전 처리 포함)을 명시적으로 개정한다. Provider 자신의 File은 Mellow 소유 Disk 사용으로 계산하지도 건드리지도 않는다.
- **C0a:** 두 Volume을 하나의 용량 읽기에 함께 청구하지 않고 APFS Clone을 가정하지 않는다. 기존 Move / Copy Fallback 정책은 이 결정으로 바뀌지 않는다.
- **C2:** 이미 쓰인 출력과 이미 Disk에 있는 Source는 다시 청구하지 않는다.
- **C3:** Save 전 Target · 파일 · Metadata 확인을 대체하지 않는다.
- **CR:** 실패해도 Attempt를 시작하지 않으며 유효한 보존 Source를 버리지 않는다.
- **계산과 신선도:** Estimate · Allowance · Reserve는 따로 유지하며 같으면 통과, 모름 · 무효 · Overflow는 Fail-closed다. 작업 Metadata 입력은 적절한 직렬화 경계 안에서 얻거나 다시 확인한다. 용량 재검사는 Admission 검사이며 읽은 값의 신선도나 쓰기 중 충분한 공간을 보장하지 않는다; Runtime 쓰기 실패는 따로 처리된다. 새 용량 API를 고르지 않으며 그 신선도가 증명되었다고 말하지 않는다.

**안내:**

- C0 / C0a / C1 부족: 기존 ADR-042 R4 §4 저장 공간 부족 확인 문구(`저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`).
- C2 / C3 부족: Rollback이 확인되고 Retry 자격이 성립한 뒤에만 기존 R4 §3 준비 실패 문구와 `다시 시도` / `취소`. 복원 · 정리가 실패하면 대신 Accepted D7a U3를 쓰며 Retry를 결코 제공하지 않는다.
- CR 부족(ADR-042 R4 밖의 새 안내): `저장 공간이 부족해요` / `기기의 저장 공간을 확보한 후 다시 시도해주세요.` / Actions `다시 시도` / `취소`. `다시 시도`를 누를 때마다 자격을 다시 확인하고 CR을 다시 실행하며 자동 반복은 없다. Source는 그 Operation의 Retry 상태가 유효한 동안에만 보존되며 취소는 D7a에 따라 그 상태를 끝낸다.
- Retry 시점의 Source 무효 · Target 무효 거부 안내는 미결이다. (2026-10-06 갱신: D7b 참조 1항으로 결정.)
- 성공 또는 미확정 Save 결과는 D8.0 처리를 그대로 따르며 이 부족들은 Save 뒤 파괴적 Rollback을 결코 허용하지 않는다.

**구현(2026-10-06, 내부 · 연결 없음):** C1 / C2 / C3 / CR 경계 검사기 `ImportAttemptBoundaryChecker.check(_:workSet:capacity:)`가 구현되었다 — 기존 `ImportStorageWorkSet.requirement()`와 `ImportStorageEstimator.check`를 그대로 쓰고, 경계와 Work Set이 맞지 않으면(C1 / CR에 쓰인 출력, C2에 이미 쓰인 정규화 출력이 없거나(Ready 항목은 세지 않음) 남은 정규화가 없음, C3에 쓰이지 않은 출력) 용량을 읽지 않고 통과시키지 않으며, 주입된 용량 읽기의 취소는 그대로 전파하고 다른 읽기 실패 · 음수 · nil은 모름(Fail-closed)으로 다루며, 출력 · Metadata · Reserve를 따로 담은 결과와 경계별 실패 경로(C1 초기 부족, C2 / C3 Attempt 실패, CR Retry 용량 거부)를 제안할 뿐 Retry를 허용하거나 Rollback · 정리 성공을 주장하지 않는다. C0 / C0a 연결은 미구현이고, Phase 5 최종 Guard 퇴역 시점, Startup Cleanup, Source · Target 무효 Retry 거부 안내, 일반 Late Result는 그대로 미결이다.

**구현 상태:** 경계 연결, 부족 안내, Phase 5 Admission 개정은 모두 미구현이다(2026-10-06: C0 / C0a와 그 부족 안내는 아래 갱신대로 구현); 현재 코드는 Phase 5 Admission(100 MiB Reserve, File별 Pre-copy 검사)과 Commit 직전 최종 Guard를 그대로 쓴다. (2026-10-06 갱신: C0 / C0a는 구현되어 현재 Phase 5 선택 흐름(Select Clips · Editor Add · Replace)에 연결되었다(2026-10-06): `ReceivedVideoFile.receive`가 Transfer 복사 직전 실제 Logical 크기로 Transfer Directory Volume의 `Source + 256 MiB Import Reserve`를 검사하고(`ImportTransferCopyGate`; 크기 · 용량 불명 · 잘못된 입력 · Overflow는 거부, 같으면 통과; Provider 파일은 계산 · 변경하지 않음), `ProjectMediaStore.adopt`는 Rename이 실패해 Copy로 넘어갈 때만 쓰기 전에 Mellow Root Volume을 한 번 읽어 같은 요구량을 검사한다(Rename 성공 시 용량을 읽지 않음, 두 Volume을 한 읽기에 청구하지 않음); Adopt가 실패하면 그 Operation의 Mellow 소유 Transfer 복사본도 제거한다. 거부는 세 흐름 모두 R4 §4 확인 문구(`저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`)를 쓰고 취소는 따로 남는다. Phase 5 Commit 직전 최종 Guard(100 MiB, 추가 0)와 그 기존 문구는 바꾸지 않았고 퇴역 시점은 미결이다. 내부 정규화 Coordinator · Retry Controller는 여전히 연결되지 않았다. iPhone 12 실제 Picker Transfer · Adopt 검증은 남아 있다.) (2026-10-06 갱신: C1 / C2 / C3은 내부 `ImportAttemptCoordinator`에 연결 · Test되었다 — C1은 Admission Gate Section, C2는 두 번째 이후 정규화 직전의 짧은 Gate Section, C3은 Commit Section에서 매번 Fresh Read의 Metadata로 Work Set을 다시 만든 뒤 검사한다; 사용자 흐름 · CR · 부족 안내 연결은 미구현.) (2026-10-06 추가 갱신: CR은 Retry Attempt의 같은 Admission 지점에서 C1 대신 실행되도록 내부 `ImportRetryController` 경로에 연결 · Test되었다; 사용자 흐름 · 안내 연결은 미구현.) 계산(`ImportStorageEstimator`, `ImportStorageWorkSet`)은 구현 · 연결 없음이다. **남은 명확화:** Phase 6 경로가 세 흐름을 대체할 때 Phase 5 Commit 직전 최종 Guard(추가 0 + 100 MiB)를 퇴역할지는 이 승인에 명시되지 않았다. (2026-10-06 갱신: D7b 참조 3항 — 최종 Guard는 흐름별로 Phase 6 전환 때 퇴역한다.) (2026-10-06 추가 갱신: Select Clips는 C1 / C2 / C3 / CR과 그 안내로 전환되어 최종 Guard를 쓰지 않는다; Editor Add / Replace는 그대로 최종 Guard를 쓴다.)

### 예시(050-A와 050-B 제안 상수)

- C1, 새 Project(`.replacingSaved` 아님), Mixed(Ready 5 s + IMG_0130): `W = 196,608 + 512 × 2 = 197,632`; `0 + 53,509,652 + S_audio + 197,632`; Required `53,509,652 + 197,632 + 268,435,456 = 322,142,740 + S_audio B`.
- C1, 새 Project(`.replacingSaved` 아님), 5.0 s 무음 정규화 항목 10개: `W = 196,608 + 512 × 10 = 201,728`; `10 × 58,722,152 = 587,221,520`; Required `587,221,520 + 201,728 + 268,435,456 = 855,858,704 B`. 두 번째 항목 직전 C2: `9 × 58,722,152 + 201,728 + 268,435,456 = 797,136,552 B`.
- 같은 10개를 기존 Project(Durable Clip 200개)를 대체하는 `.replacingSaved`로 만들 때: `W = (196,608 + 512 × 10) + (196,608 + 512 × 200) = 201,728 + 299,008 = 500,736`; C1 Required `587,221,520 + 500,736 + 268,435,456 = 856,157,712 B`.
- C1, 기존 Durable Clip 40개 Project에 5.0 s 무음 정규화 항목 3개 Add: `W = 196,608 + 512 × (40 + 3) = 218,624`; `3 × 58,722,152 = 176,166,456`; Required `176,166,456 + 218,624 + 268,435,456 = 444,820,536 B`.
- C3: `W + 268,435,456 B`(위 Add 예시에서 `218,624 + 268,435,456 = 268,654,080 B`).
- C0, 149,619,684 B Source: Transfer 대상 Volume에서 `149,619,684 + 268,435,456 = 418,055,140 B`. C0a(Fallback이 일어날 때만): Mellow Root Volume에서 같은 418,055,140 B.

---

## Decision Unit 050-D — Transaction, Rollback, Retry, Target 무효화

**Unit Status:** Proposed. 수치와 무관하게 독립 승인 가능한 정확성 규칙이다. (2026-10-05 갱신: D4–D7 가운데 D7a에 적힌 복구 계약만 Accepted — 미구현; 나머지는 Proposed로 남는다.) D1–D3은 승인된 문구(ADR-037 STEP 11 Note, ADR-040 §9, ADR-047 Decision 2 Ownership, ARCHITECTURE Commit 경계)의 개정 제안이다(이 ADR 서두의 예외 참조). 승인되지 않은 Presentation 세 가지(아래 표시)는 별도 소유자 선택이다.

**범위 밖:** ADR-038 Undo / Redo도 `update` + Read-back 검증과 실패 시 현재 State 유지라는 같은 Pattern을 쓰며 Save 성공 뒤 Read-back 실패에서 In-memory 상태와 Store가 어긋날 수 있다. 이 ADR은 Undo / Redo를 다루지 않으며 별도 검토 대상으로 남긴다.

### D1. Durable Commit 경계

- **Durable Commit = 해당 경로의 Repository Save가 오류 없이 반환된 것.** Select Clips(새 Project)는 `repository.create(B)` 안의 `ModelContext.save()`, Editor Add / Replace는 `repository.update` 안의 `ModelContext.save()`다.
- Save 오류만으로 Commit 여부를 정하지 않는다. Save 오류 뒤에는 D8의 Save Outcome 판정(다시 읽은 Durable 상태)을 따른다. 이는 ADR-040 §9, ADR-037 STEP 11 Note, ROADMAP Task 14의 Persist 실패 분기에 대한 개정 제안이다(서두의 예외). 확인된 이전 상태로 판정된 Save 오류는 그 문구와 ADR-042 Revision 4 §3을 바꾸지 않고 따른다.
- **Pre-commit 실패:** Durable Save 반환 전에 일어난 모든 실패 — 정규화, C2 / C3 부족, Materialize(부분 포함), Target 무효화, 취소, 그리고 D8이 "확인된 이전 상태"로 판정한 Save 오류. D4 Rollback을 적용한다. D8이 "확인된 새 상태"나 "미확정"으로 판정한 Save 오류에는 D4를 적용하지 않는다.
- **Post-commit 실패:** Durable Save가 성공한 뒤의 모든 실패 — Read-back 조회 실패, Read-back 불일치, Committed Media 존재 확인 실패, `.replacingSaved`의 이전 Project 삭제 실패, UI 갱신 전 중단. **Read-back 실패는 Save 실패를 증명하지 않는다.** Accepted Set 전체가 한 Save로 Commit되었으므로 Atomicity는 이미 성립했으며, Post-commit 실패는 Rollback 대상이 아니다. 이는 Read-back을 Commit 경계 안에 두는 승인 문구와 충돌하며 그 개정 제안이다(서두의 예외).

### D2. 관찰된 현재 동작과 실패 Trace(이 ADR이 코드를 바꾸지 않음)

- **Select Clips(새 Project / `.replacingSaved`):** `create(B)` Save 성공 → `repository.project(id:)`가 던지거나 Clip 수가 다르거나 Committed File 하나가 보이지 않음 → 현재 코드는 `try? repository.deleteProject(id: B)`를 결과와 무관하게 실행하고 이어서 `removeProjectMedia(B)`를 호출한다. 삭제 Save가 실패하면 Durable B Row가 남은 채 그 Media가 모두 지워진다. `.replacingSaved`에서는 이 경로가 이전 Project A 삭제보다 먼저 반환하므로 A와 B가 함께 남고, 최신 순서 정책상 B(Media 없음)가 현재 저장 Project가 된다. 사용자에게는 `프로젝트를 만들지 못했어요`가 표시되며 B가 남았다면 이 문장은 거짓이다.
- **Editor Add / Replace:** `update` Save 성공 → Read-back 불일치 또는 조회 실패 → `commit`이 In-memory Project를 이전 상태로 되돌리고 실패 안내를 표시 → 호출자가 `appender.discard`로 새 Clip File을 지운다. 결과: Durable Row가 지워진 File을 참조하고(다음 열기에서 Unavailable Clip), In-memory 상태는 Store와 다르다. 이후의 모든 Edit은 저장된 새 Clip ID가 들어오는 상태에 없으므로 `update`의 `missingDurableClip` 검사에서 실패하며 Editor를 다시 열 때까지 계속된다. Replace에서도 같은 일이 대체 Clip D에 일어난다.
- **보상 수단 없음:** `update`는 저장된 Clip이 빠진 상태를 `missingDurableClip`으로 거부하므로 "이전 상태로의 Update"는 불가능하고, Undo는 새 Clip을 Pending-deleted로 남길 뿐 Rollback이 아니다.

### D3. 가장 작은 수정(제안)

- Durable Save가 성공한 뒤에는 그 Save가 참조하는 어떤 Media도 지우거나 옮기지 않는다(Read-back · 존재 확인 실패 포함).
- Post-commit 확인 실패는 Rollback이 아니라 **"Commit됨 · 확인 안 됨"** 상태로 다룬다: Row를 지우지 않고, Media를 보존하며, Workspace의 남은 Source만 Discard한다. Persisted Row가 Source of Truth다(ADR-047 Boundary G와 같은 원리).
- Editor는 이 상태에서 In-memory Project를 이전 상태로 되돌리지 않고 Store에서 다시 읽으며, 다시 읽기도 실패하면 Editor를 Reload가 필요한 상태로 두어 추가 Edit을 막는다. (2026-10-02 갱신: P2(D8.5a)로 대체 — 자동으로 다시 읽지 않고 Reconciliation 필요 상태로 모든 변경을 막으며 프로젝트 화면으로 돌아가 다시 연다.)
- `.replacingSaved`는 B가 확인되지 않은 동안 A를 지우지 않는다(현재처럼 A 보존). 이때 A와 B가 함께 남는 것은 Media 안전상 허용하지만 ADR-033 / ADR-034 V1 Single Saved Project의 Safe Atomic Replacement에서 벗어난 결과이며 그 처리는 D8.6의 소유자 선택이다.
- 이 상태에서 `프로젝트에 변경사항이 저장되지 않았어요`, `프로젝트를 만들지 못했어요`, `프로젝트는 그대로 있어요`를 쓰지 않는다; 사실이 증명되지 않았거나 거짓일 수 있기 때문이다. 이 상태의 Presentation은 D8.5의 U1 제안이며 소유자 선택(UX)이다. (2026-10-02 갱신: U1 문구는 D8.5a P3로 Accepted — 미구현.)
- Read-back이 `invalidPersistedMetadata` 등으로 던진 경우 보존된 B는 읽을 수 없는 Row일 수 있고, 최신 순서 정책상 현재 저장 Project가 되어 Projects 화면을 막을 수 있다. 이 경우는 D8.3의 "미확정"(Domain 변환 오류)으로 처리하며 D8.5의 U2 제안을 쓴다. (2026-10-02 갱신: 이 일괄 규칙은 승인되지 않았다 — D8.5a P3; D8.0대로 Save 성공 + 확인 불가는 `committedUnverified`다.)
- 이 수정은 Phase 5 코드에도 같은 위험이 있음을 보여 주지만 이 ADR은 코드를 바꾸지 않는다; 수정의 구현 시점은 별도 결정이다.

### D4. Durable Commit 전 Rollback-to-Workspace

> 2026-10-05: 아래 Rollback 자격 · 복원 · 실패 처리는 D7a로 Accepted되었다(미구현). 1–3항과 5–6항은 D7a와 일치하며 7항의 Rename-back은 D7a 1항(Ready 파일을 원래 Workspace 경로로 복원)과 일치한다; ROADMAP Task 14 문구의 해석 확인(OD-4)은 그대로 남는다. 4항(새 Project의 빈 `Projects/<P>/` 제거)은 D7a에 명시되지 않아 Proposed로 남는다; 5항의 Presentation은 D7a 안내로 결정되었다.

**소유와 경로**

- Operation Workspace `ProjectWorkspace/<op>/`는 Live Registry(`liveWorkspaceIDs`)에 등록된 Operation 소유다.
- Retry Source는 Adopt된 Source File `ProjectWorkspace/<op>/<S>.<ext>`이며 Adopt 시 Logical 크기를 기록한다.
- Attempt 출력은 Attempt별 하위 Directory `ProjectWorkspace/<op>/attempt-<n>/`에만 쓰며 Operation이 만든 경로를 그대로 사용한다(열거로 찾지 않는다). ADR-047은 Workspace 하위 Directory를 허용하며 Sweep이 Directory 전체 제거로 이를 포함함을 Test로 고정해야 한다.
- Materialize 후보는 `Projects/<P>/Media/<C>.mov`이며 Clip ID `<C>`는 Attempt마다 새로 만든다.
- 각 Ready 항목의 Restoration Record는 `(원래 Workspace 경로, Materialize 경로, 기록된 Logical 크기)`다.

**Rollback 규칙(Pre-commit 실패 시)**

1. **정규화 출력 후보:** Materialize 경로가 이 Attempt의 Canonical 경로와 정확히 같고 `lstat` 기준 일반 File(Symlink 아님)이며 Root 안에 있을 때만 제거하고 부재를 확인한다. 정규화 항목의 Retry Source는 Workspace를 떠난 적이 없다. Materialize 후보는 새 Recovery 정책으로 보존하지 않는다.
2. **Ready 항목:** 같은 경로 · Type 검사 뒤, 원래 Workspace 경로가 비어 있고(충돌 보호), Workspace가 여전히 Live이고 Symlink가 아닌 실제 Directory일 때 같은 Volume Rename으로 원래 경로에 되돌린다. 되돌린 뒤 원래 경로의 File이 존재하고 기록된 크기와 같으며 Materialize 경로가 비었음을 확인한다.
3. **부분 Materialize(항목 k / n에서 실패):** 1..k−1은 1–2항을 적용하고, 항목 k는 원래 경로와 Materialize 경로를 모두 확인하여 File이 어느 쪽에 있는지 판정한 뒤 1–2항을 적용한다.
4. **Project Directory:** 새 Project는 모든 항목의 1–3항이 확인된 뒤에만 비어 있는 `Projects/<P>/`를 제거하며, Restoration이 끝나지 않은 Ready File이 들어 있는 동안 `removeProjectMedia`를 호출하지 않는다. 기존 Project(Add / Replace)의 Directory는 제거하지 않으며 이 Attempt가 만든 정확한 Clip ID의 File만 다룬다.
5. **Restoration 실패**(충돌, Rename 오류, Workspace 소실, 크기 불일치): Mellow 자신의 Filesystem 연산 실패로 Mellow 소유 Retry Source를 잃은 것이다. 이것은 R4 §3의 "Source 접근이 더 이상 유효하지 않음"(외부 Source Handle의 무효화)으로 분류하지 않는다. Materialize 경로의 File은 1항 규칙으로 제거를 시도하고, 제거도 실패하면 Row 없는 Canonical Media로서 기존 STEP 12B Orphan Recovery가 다음 실행에서 회수한다. 그 Operation의 `다시 시도`는 같은 Accepted Set을 만들 수 없으므로 제공할 수 없으며, 이 내부 실패의 Presentation은 승인 문서에 없다(**소유자 선택**).
6. **비용 한정:** 같은 Volume Rename은 보통 Data Block을 새로 Allocate하지 않지만 Directory Metadata 갱신이 필요하며 실패할 수 있다. 이 설계는 "추가 비용 0"이나 무조건적 계약 보존이 아니라, Filesystem 연산이 성공하는 한 같은 Accepted Set Retry를 가능하게 하는 설계다.
7. **승인 문구와의 관계:** ROADMAP Task 14의 "Materialize된 파일 제거, Project 무변경"을 "Project 위치에서 제거"로 해석하면 Rename-back이 이를 만족하면서 Task 13과 ADR-047 Boundary F의 Retry Source 보존도 만족한다. 이 해석은 소유자 확인이 필요하다. 대안인 Hard-link Materialize(Workspace 이름을 Commit까지 유지)는 Restoration 실패 경로를 없애지만 ADR-047의 "Materialize(Rename)" 문구 개정이 필요하므로 이 ADR이 제안하지 않는다.

### D5. 취소

> 2026-10-05: D7a 3항으로 대체 · Accepted(미구현) — Save 호출 직전까지 받은 취소는 Restoration 없는 제거가 아니라 D7a 1항의 확인된 Rollback 뒤에 끝난다.

- 취소는 Durable Save 호출 전까지 받는다. Materialize 이후의 취소는 R4 §2대로 Operation을 끝내므로 Restoration 없이 D4 1항 규칙으로 Materialize 후보 전부(Ready 포함)를 제거 · 확인하고 Workspace를 Discard한다.
- Save는 MainActor에서 동기로 실행되므로 Save 도중 취소가 끼어들 지점이 없다. 마지막 취소 확인 지점은 Save 직전이다. Save가 성공한 뒤 도착한 취소는 Rollback을 일으키지 않으며 Operation은 성공이다(Editor Add / Replace의 되돌리기는 기존 Undo 경로이며 Select Clips 새 Project에는 Undo가 없다).

### D6. Target 무효화

> 2026-10-05: Target 무효화의 확인 시점 · 거부 · 후보 정리 규칙은 D7a 4항으로 Accepted(미구현). 후보 정리는 D7a 1항의 Rollback 규칙(Ready 파일 복원 포함)을 따르므로 아래 2번째 항목의 "D4 1항 규칙으로 … (Restoration 없음)"은 대체된다. 아래의 Late Result 폐기와 Retry Source Discard 문구는 일반 Late Result 정책과 함께 미결로 남는다.

- Lifecycle Gate 안에서 Materialize 직전과 Durable Save 직전에 Target을 확인한다: Add / Replace는 Project Row 존재와 Orientation, Replace는 대상 Clip이 같은 Identity로 여전히 Active인지. (2026-10-06 갱신: D7b 참조 4항 — Late Result · Navigation의 일부가 결정되었다.)
- Target이 무효이면 Materialize하지 않거나 D4 1항 규칙으로 후보를 제거하고(Restoration 없음), 삭제된 Project의 `Projects/<P>/`를 다시 만들지 않으며, Operation을 끝내고 `다시 시도`를 제공하지 않는다. Retry Source는 소비자가 없으므로 Discard한다.
- 삭제된 Project에 대한 결과는 Late Result로 버린다(ROADMAP Task 15). 살아 있는 Editor에서 Replace 대상이 사라진 경우의 안내는 승인 문서에 없다(**소유자 선택**).
- 구현 의존성: 현재 `materialize`는 Destination Directory를 만들어 주므로 Row 없는 Project Directory를 다시 만들 수 있고, `HomeModel`의 Project 삭제와 Editor Add / Replace는 Lifecycle Gate를 사용하지 않는다.
- **구현(2026-10-02, 사용자 승인 — 직렬화 전제조건만):** Home의 Project 삭제(`HomeModel.delete(_:)`, `async`; Alert는 표시 중인 Project를 넘기고 `confirmDeletion`은 이를 위임)와 Editor Add / Replace의 Target 재확인 → Materialize → Repository Commit(Commit하지 못한 파일 제거 포함 — 2026-10-02 갱신: Save 시도 전 실패에 한함, D8.0 "Save 뒤 Media 보존 수리")이 같은 `ProjectLifecycleOperationGate`를 잡는다; Picker 전송, 예약 공간 확인과 검증은 Gate 밖에서 실행되며 Workspace는 기존 Live-workspace Registry가 보호한다. Gate 안에서 Materialize 전에 Repository를 다시 읽어 Project Row가 없거나 읽을 수 없으면, 또는 Replace 대상이 Editor와 Store 모두에서 같은 Identity의 Active Clip이 아니면 Materialize하지 않고 끝낸다(Directory 재생성 없음, Save 없음, 기존 `addFailed` / `replaceFailed` 안내 재사용). 알려진 차이: 그 안내의 "다시 시도해주세요. 프로젝트는 그대로 있어요."는 Project가 삭제된 경우 사실과 다르고 D6(`다시 시도` 없음)와 OD-8(삭제된 Project는 안내 없음) 제안과도 어긋나며, 이 임시 재사용을 바꾸는 것은 소유자 결정이다. Gate를 기다린 삭제는 Alert가 잡은 Project에만 적용되고, 끝난 뒤의 Recent 복귀는 확인 시점 이후 Navigation이 바뀌지 않았거나 현재 경로가 삭제된 Project의 Route를 담고 있을 때만 일어난다(기존 `openedProject` Identity 확인 유지; 나중의 무관한 Navigation은 되돌리지 않음). 결과 판정 연결 전 필수 후속: (1) Target 무효 시 재사용 중인 `addFailed` / `replaceFailed` 안내 문구의 소유자 결정, (2) Save 뒤 Media 삭제 결함(`.replacingSaved`에서 A 삭제 실패에도 A Media를 지우는 기존 코드 등) 수정 — 2026-10-02 수리됨(D8.0의 "Save 뒤 Media 보존 수리" 항목; 안내 · 다시 읽기는 Pending). 이 Slice는 둘 다 해결하지 않으며 모든 Editor 변경을 직렬화하지도 않는다(동기 Reorder · Delete · Undo · Redo Commit은 Gate 밖). (2026-10-05 갱신: 모든 Editor 변경이 이제 같은 Gate 안의 하나의 내부 Commit을 쓰며, 재사용되던 `addFailed` / `replaceFailed`의 Target 무효 안내는 D8.5c의 정지 안내로 대체되었다.) Materialize부터 Commit까지는 같은 Gate Section이므로 Save 직전의 별도 재확인은 두지 않았다(Orientation 불변은 기존 `update`가 강제). 이것은 D6 · OD-7의 나머지(Retry 없음 안내, Late Result 폐기, 사라진 Replace 대상 안내)를 승인하지 않는다. Prior Snapshot 시점, `observePersistedState` · 분류기 · `replaceProject` 연결, Save 결과별 처리, Rollback, Retry, 취소 정책, Late Result 처리, 안내 Copy는 Pending · 미승인이다. (2026-10-02 갱신: Prior Snapshot 시점 · Save 결과별 처리 · U1 / U2 문구 가운데 D8.5a P1–P6 · P8에 적힌 부분은 Accepted — 미구현; Rollback · Retry · 취소 · Late Result · U3 / U4는 미결.)

### D7. 같은 Accepted Set Retry

> 2026-10-05: 시작 조건과 정리 실패 시 Retry 금지는 D7a 2항으로 Accepted(미구현). 4항(CR 검사)의 연결과 부족 Presentation은 050-C 결정과 함께 미결이다. (2026-10-06 갱신: CR 위치 · 계산 · 부족 안내는 "050-C 실행 경계 승인"으로 Accepted — 미구현.)

`다시 시도`는 다음이 모두 확인될 때만 새 Attempt를 시작한다.

1. 이전 Attempt Directory와 이전 Attempt의 Materialize 후보가 제거되었고 부재가 확인됨(Operation이 만든 정확한 경로, Symlink 아닌 실제 Directory, Workspace 안).
2. 모든 Retry Source가 존재하고 `lstat` 기준 일반 File이며 기록된 Logical 크기와 같음.
3. Target이 유효함(D6).
4. CR 검사 통과(050-C).

- 1이 실패하면(정리 실패) 미해결 Artifact 위에 새 Attempt를 시작하지 않는다. 2가 Mellow 자신의 연산 실패 때문에 실패하면 D4 5항과 같은 내부 실패다. 두 경우 모두 R4 §3의 외부 Source 무효 조항으로 분류하지 않으며 Presentation은 D4 5항과 같은 **소유자 선택**이다. 남은 Workspace는 Best-effort Discard 뒤 기존 시작 시 Sweep(ADR-047)이 회수한다.
- 2가 외부 원인(예: Live Session 밖의 Source Handle 무효)이라면 R4 §3의 "Source 접근 무효 → Mutation 없이 안전 실패"가 적용된다. V1 Import의 Retry Source는 Mellow 소유 File이므로 이 경우는 Process 안에서 생기지 않을 것으로 예상하지만 확인되지 않았다.
- 4가 실패하면 050-C의 Retry 전 검사 부족 처리를 따른다.

### D7a. Accepted 제한된 복구 계약(2026-10-05, 사용자 승인 — 문서만, 미구현)

이 절은 D4–D7 가운데 아래 규칙만 Accepted로 기록한다. Production 구현은 없다. D8.0 분류 규칙, D8.5a–c의 Accepted 처리, 050-B Estimate, 정책 상수는 바뀌지 않는다. 050-C 검사 경계 연결과 부족 Presentation, Startup Cleanup · 빈 Store 보호(OD-12), 일반 Late Result · Navigation 정책, OD-13, 050-E는 이 승인에 포함되지 않는다. (2026-10-06 갱신: Select Clips에 연결 구현 — D7b 구현 항목; Editor Add / Replace는 미전환.)

1. **Rollback 자격:**
   - Save 시도 전의 실패나 받아들인 취소는 그 Operation이 Materialize한 자기 후보를 되돌릴 수 있다.
   - Save 시도 뒤에는 `priorConfirmed`일 때만 Rollback할 수 있다; Save 성공, `committedUnverified`, `indeterminate`는 파괴적 Rollback을 결코 허용하지 않는다.
   - Ready 파일은 원래 Workspace 경로로 되돌리고, 실패한 Attempt가 소유한 정규화 출력은 제거한다; 실패한 항목을 포함한 부분 Materialize도 다룬다.
   - 기존 Workspace 파일을 덮어쓰지 않고, Symlink를 따라가지 않으며, 관계없는 Media를 건드리지 않는다.
   - Workspace를 다시 쓸 수 있다고 선언하기 전에 복원과 제거를 확인한다.
   - 복원이나 정리가 실패하면 Retry를 막고, 풀리지 않은 파일은 안전하게 보존하며, 정리가 성공한 것처럼 말하지 않는다.
2. **같은 Set Retry:**
   - Retry는 새 Picker 선택이 아니라 같은 Accepted Set과 유효한 보존 Source를 쓴다.
   - 확인된 복원 · 정리, 유효한 Source, 유효한 Target이 모두 성립한 뒤에만 시작한다.
   - 새 Attempt마다 새 Storage Work Set(`ImportStorageWorkSet`, 단일 Attempt 모델)을 만든다.
   - 용량 재검사 연결과 부족 Presentation은 별도의 미결 050-C 결정이며, 그것 없이 Retry가 Production 준비가 되었다고 보지 않는다. (2026-10-06 갱신: 그 결정은 "050-C 실행 경계 승인"으로 Accepted되었으나 미구현이다.)
   - Process 종료 뒤 재개는 없고 Durable Journal도 없다(ADR-047).
3. **취소 경계:**
   - 취소는 Save 호출 직전까지 받는다; 마지막 취소 확인과 동기 Save 호출 사이에 `await`을 두지 않는다.
   - Save 호출이 시도되면 관측 · 분류를 끝내며, 취소만으로 참조 가능 Media의 정리를 허용하지 않는다.
   - `completed`는 성공이다(오류를 던진 뒤 `completed`로 확인된 Save 포함).
   - `priorConfirmed`에서 이미 취소가 요청되어 있었다면 확인된 Rollback 뒤 Retry를 제공하지 않고 끝낸다.
   - 미확정 결과는 Accepted U1 / U2 처리를 그대로 따른다.
4. **Target 무효화:**
   - 공유 Gate 안에서 Save 전에 감지하고 Operation을 거부한다; Retry도, B만 생성하는 Fallback도 없다.
   - Add / Replace는 Materialize 전에 확인하고, 필요하면 Save 전에 다시 확인한다.
   - 후보 준비 뒤 · Save 전에 무효화되면 그 Operation 자신의 후보만 D7a 1항의 Rollback 규칙으로 정리한다.
   - Save 시도 뒤의 오류는 D8.0을 따르며 오류 이름만으로 Commit되지 않았다고 추론하지 않는다.
   - 일반 Late Result · Navigation 정책은 넓히지 않는다(미결로 남는다).
5. **안내:**
   - 성공한 취소: 안내나 제외 성공 안내 없이 준비 화면을 닫는다.
   - 확인된 Rollback 뒤 Retry 자격이 있는 준비 실패: 기존 ADR-042 R4 §3 문구와 `다시 시도` / `취소`.
   - Source 복원 · 정리 실패(Commit되지 않았음이 확정된 경우에만): `영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 영상을 다시 선택해주세요.` / Action `확인`; `다시 시도` 없음.
   - 기존 Editor의 Project 없음 · Replace Clip 없음 Reconciliation 안내(D8.5c)와 Select Clips 대체 Target 무효 안내(D8.5b)는 바뀌지 않는다.
   - 미확정 Save 결과는 Accepted U1 / U2를 쓰며 "저장되지 않았어요"를 쓰지 않는다.
   - 이 미래의 준비 · Retry 규칙은 복구 통합이 구현되기 전까지 현재 구현된 D8.5a P6 확인 전용 경로를 조용히 대체하지 않는다.

**구현(2026-10-05, 내부 · 연결 없음):** D7a 1항의 Rollback 실행기 `ProjectMediaStore.rollBackAttempt(_:)`가 구현되었다 — Attempt가 기록한 정확한 Record(`ImportRollbackRecord`: 정규 Materialize 경로, Ready 파일의 Workspace 이름 · 기록 크기 또는 정규화 출력)만 다루고, Ready 파일은 덮어쓰지 않고 원래 Workspace 경로로 되돌리며, 소유한 정규화 출력과 Attempt 자신의 Workspace 하위 Directory를 제거하고, Symlink · 소유 경로 밖 · Live가 아닌 Workspace를 거부하며, 모든 결과를 확인해 `verifiedClean` 또는 Record별 사유를 담은 `unresolved`(Retry 금지)를 돌려준다; 한 Record가 실패해도 나머지를 처리한다. 호출자가 D7a 자격과 직렬화를 먼저 확립해야 하며 실행기는 오류에서 자격을 추론하지 않는다. 빈 Project Directory는 제거하지 않는다(D4 4항 미결). Coordinator · UI · Save 분류 · Retry · Startup Cleanup에 연결되지 않았고 ROADMAP Task 14 해석(OD-4)도 그대로 남는다.

**구현(2026-10-06, 내부 · 연결 없음): 단일 Attempt Coordinator.** `ImportAttemptCoordinator.run(_:events:)`가 이미 분류된 Accepted Set · 일치하는 Plan · Live Workspace · 명시적 Target(새 Project / 현재 저장 Project 대체 / Editor Add / Editor Replace) 하나로 Attempt 하나를 실행한다. Gate 소유는 명시적이다: 입력 확인(Source가 Workspace의 직접 자식인 일반 파일이고 크기가 Preflight Fact와 같으며 중복 없음)은 Gate 밖, Admission Section은 OD-10 Fresh Read로 Target을 확인하고 그 읽기의 Metadata로 `ImportStorageWorkSet`을 만든 뒤 C1을 검사하며, 준비(Attempt 자신의 Workspace 하위 Directory, Accepted 순서의 정규화)는 Gate 밖에서 실행하고 결과가 그 항목의 것이며 ADR-045 §7 범위 안이고 Trim을 덮을 때만 출력을 기록한다. 두 번째 이후 정규화 직전마다 짧은 Gate Section에서 Target을 다시 읽고 현재 Metadata로 C2를 검사한다. Commit Section은 Target 재확인 → 현재 Metadata로 C3 → 대상 경로가 비어 있음을 `lstat`으로 확인한 뒤에만 소유 Record를 기록하고 기존 Store 규칙으로 Materialize → Domain 값과 Expectation → 모든 새 Media가 기대 크기의 일반 파일인지 확인 → Target 재확인 → 마지막 취소 확인과 `await` 없는 단일 Save(`create` / `replaceProject` / `update`) → 관측 · D8.0 분류 → `priorConfirmed`의 Rollback 또는 `completed` 대체의 A Media 제거 순서이며, Section 안의 Helper는 Gate를 다시 잡지 않는다. 기존 계산 · 분류 · Rollback(`ImportStorageWorkSet`, `ImportAttemptBoundaryChecker`, `ProjectSaveOutcomeClassifier`, `rollBackAttempt`)을 그대로 쓴다. 결과는 Typed이며(`refused` / Rollback이 붙은 `failedBeforeSave` / Rollback이 붙은 `notSaved` / `completed` / `committedUnverified` / `indeterminate`) Rollback 결과에 보존 Source Fact(이름 · 기록 크기)와 취소 요청 여부를 담지만 Retry를 허용하지 않는다. 정규화기가 `cleanupFailed`를 보고하면 Attempt Directory를 증거로 남기고 정리를 `unresolved`로 보고한다. 정규화 항목의 Editor Replace는 ADR-040 §6 Revision(2026-10-06)대로 같은 정규화 Clip Metadata 규칙을 쓴다. Store에는 `createAttemptDirectory(named:in:)`, `workspaceFileByteCount(_:in:)`, `mediaNode(_:)`가 추가되었다. CR · Retry 조정, Picker, 안내 Copy, 진행률 정책, Durable Journal, AppEnvironment · View 연결, C0 / C0a, Phase 5 최종 Guard 퇴역, Startup Cleanup 개정, 일반 Late Result는 구현하지 않았다. C2의 매번 다시 읽는 현재 Metadata는 050-C의 신선도 요구를 충족한다. 남은 명확화: 확인되지 않은 Rollback이 Row 없는 `Projects/<B>/`에 남긴 복원 실패 파일을 현재 Startup Recovery가 제거할 수 있다(OD-12와 D7a의 "풀리지 않은 파일 보존"의 관계 미결); 새 Project Rollback 뒤 빈 `Projects/<B>/`는 D4 4항대로 미결로 남는다.

**Retry 자격 분류(2026-10-06, 소유자 승인 — 이 분류에 한정):** 같은 Set Retry는 확인된 Rollback(`verifiedClean`), 받아들인 취소 없음, 유효한 보존 Source, 유효한 Target이 모두 성립할 때만 시작하며, 자격이 있는 직전 결과는 `notSaved`(`priorConfirmed`), C2 또는 C3 부족, `cleanupFailed`가 아닌 `normalizationFailed`, `normalizationResultRejected`, `materializationFailed`, `mediaVerificationFailed`, `attemptDirectoryUnavailable`뿐이다. `completed`, `committedUnverified`, `indeterminate`, 첫 Admission 거부(C1), Source · Target 무효화, 취소, 풀리지 않은 정리, `inconsistentPreparation`, `inconsistentWorkSet`, `metadataInvalid`, `destinationOccupied`는 자격이 없다. Retry Admission은 Coordinator의 기존 직렬화 Admission 지점에서 C1 대신 CR(같은 요구량)을 실행하며 Source → Target → 용량 순서를 지킨다(앞선 "C1 재실행" 제안을 명시적으로 다듬은 것). 이 분류는 Retry 거부 안내, Startup Cleanup, 빈 Directory 처리, 일반 Late Result 등 다른 복구 결정을 해결하지 않는다. (2026-10-06 갱신: D7b 참조 — 2항이 Save 전 Attempt 도중의 Target 읽기 불가를 자격 목록에 더한다.)

**Retry Admission 명확화(2026-10-06, 소유자 승인 — Retry 거부에 한정):** (A) Retry 시점에 Target을 읽을 수 없으면 무효가 증명된 것이 아니라 모르는 상태이므로 별도의 Typed `targetUnavailable`로 돌려주고 직전 자격 Rollback 증거 · 보존된 유효 Source · Retry 대기 상태를 유지한다; 이후의 명시적 Retry가 CR 전에 Source와 Target을 다시 확인하며 자동 반복은 없다. 확인된 Target 부재 · 변경은 그대로 `targetInvalid`이고 Retry 자격을 끝내며, Stale · 불일치 상태를 읽기 불가로 재해석하지 않는다. 이 명확화는 첫 Admission이나 Save 뒤 미확정 결과에는 적용하지 않는다. (B) CR의 `invalidEstimate` · `invalidBoundaryState`는 용량 거부가 아니라 별도의 Typed 결함 결과로 Retry 자격을 끝내며, 풀리지 않은 파일 · 증거는 보존하고 Workspace는 기존 확인된 증거가 안전한 정리를 허용할 때만 놓는다; 부족하거나 모르는 CR 용량은 그대로 용량 거부이며 대기 상태를 유지한다. 계산, D8.0, 경계 검사기의 실패 구분은 바뀌지 않는다. (C) C2 / C3의 모르는 용량은 승인된 Admission 실패 경로를 따르며 확인된 Rollback과 다른 모든 자격 조건 뒤에만 Retry할 수 있고, 결정적인 정규화 오류는 기존 승인 분류를 유지한다. 풀리지 않은 파일의 Startup 처리는 미결이다. (2026-10-06 갱신: D7b 참조 — 2항이 A를 Save 전 Attempt 도중으로 넓히고 1항이 Retry 거부 안내를 정한다.)

**구현(2026-10-06, 내부 · 연결 없음): Retry Controller.** `ImportAttemptRequest`에 Admission 방식(`.initial` / `.retry`)이 추가되어 `.retry`는 같은 Admission Gate Section에서 C1 대신 `crBeforeRetry`를 검사한다(Controller는 용량을 읽지 않는다). `ImportRetryController`는 한 Operation의 원래 Accepted Set · Plan · Workspace · Target을 유지하고 순수 `ImportRetryEligibility.evaluate`와 명시적 상태(`idle` / `running` / `awaitingRetry` / `succeeded` / `uncertain` / `ended` / `retainedUnresolved`)를 쓴다. 진행 상태는 어떤 `await`보다 먼저 예약되고 중복 요청은 `busy`이며, Gate를 잡지 않은 채 `run()`을 호출한다. 부족하거나 모르는 CR 용량(`capacityRefused`)과 읽을 수 없는 Target(`targetUnavailable`)은 직전 자격 증거를 그대로 둔 채 대기 상태를 유지하고(자동 반복 없음), 확인된 Source · Target 무효(`sourceInvalid` · `targetInvalid`)와 CR 결함(`retryAdmissionDefect`)은 Typed 결과로 Retry 자격을 끝낸다. 취소는 Controller가 소유한 Attempt Task로만 전달되며(`cancel()` / `requestCancellation()`; 호출자 Task의 취소는 전달되지 않음) `cancel()`은 결과 처리와 Workspace 해제가 끝난 뒤에 반환한다. 실행 중 취소는 그 Attempt의 결과와 Rollback 처리를 기다린 뒤에만 소유를 놓으며 `completed`는 늦은 취소에도 성공이다. Workspace는 증거에 따라서만 놓는다: `completed`와 미확정 Save 뒤(Workspace 파일은 Durable Row가 참조할 수 없고 Project Media는 건드리지 않음), 확인된 정리 뒤, 변경이 없었을 때만 놓고, 복원 · 정리가 풀리지 않았거나 증거를 보존해야 하면 `retainedUnresolved`로 계속 소유한다(deinit이나 무조건 종료 정리 없음). 같은 Process의 확인된 Rollback 증거와 Coordinator의 현재 Source · Target 확인을 쓰며 파괴적 Rollback 실행기를 검증 질의로 다시 돌리지 않는다. UI · Picker 연결, Retry 거부 안내, C0 / C0a, 최종 Guard 퇴역, Startup Cleanup, 빈 Directory 처리, 일반 Late Result는 미구현 · 미결이다(2026-10-06 갱신: 미해결 후보의 Process 수명 한정 보존, 빈 Directory를 Startup Cleanup에 맡기는 처리, OD-12 최소 빈 Store 보호는 결정 · 구현되었다; 더 넓은 Startup Recovery와 일반 Late Result는 미결). (2026-10-06 갱신: D7b 참조 — Retry 거부 안내와 흐름별 최종 Guard 퇴역이 결정되었다.)

**D7a 1항 명확화 — 미해결 후보의 보존 범위(2026-10-06, 소유자 결정):** 풀리지 않은 Rollback 후보, 보존된(`retainedUnresolved`) Workspace, 정리 증거는 Process 수명 동안 보존하며 `retainedUnresolved`인 동안 Discard하지 않는다. Process가 끝난 뒤에는 기존 Startup Cleanup(ADR-039 STEP 12B, ADR-047 Workspace Sweep)이 이 참조되지 않은 후보를 승인된 규칙대로 회수할 수 있다. Resume, Durable Journal, Quarantine, Marker를 두지 않는다. 이 명확화는 미해결 후보에 관한 것이며 저장된 Row가 참조하는 Media를 지울 권한이 아니다. 새 Project의 빈 `Projects/<B>/`(D4 4항)는 Process 안에서 제거하지 않고 기존 Startup Cleanup에 맡기며(ADR-039 STEP 12B의 OD-12 최소 빈 Store 보호가 적용될 수 있음) 이것은 선택된 처리이지 구현 Blocker가 아니다. 그 Guard가 적용되는 Pass(Row 0개)에서는 빈 Folder뿐 아니라 `Projects/<B>/Media/` 안의 참조 없는 미해결 후보 Media도 회수되지 않으며 Row가 생길 때까지 남을 수 있다.

**남은 안내 공백(결정되지 않음):** 복원이 확인된 뒤 `다시 시도` 시점에 보존 Source가 더 이상 유효하지 않거나(외부 원인 포함, R4 §3의 "Mutation 없이 안전하게 실패"), Retry 시점에 Target이 무효이거나(Select Clips와 Editor의 기존 안내가 그 시점에도 적용되는지), CR 용량 검사가 부족한 경우(050-C)의 Retry 거부 안내는 승인 문서에 없다. (2026-10-06 갱신: CR 부족 안내는 "050-C 실행 경계 승인"으로 결정되었다; Source 무효 · Target 무효 Retry 거부 안내는 그대로 미결.) D4 4항(새 Project의 빈 Directory 제거)도 명시적으로 승인되지 않았다(2026-10-06 갱신: Process 안 제거는 하지 않고 기존 Startup Cleanup에 맡기기로 결정 — 위 D7a 1항 명확화). (2026-10-06 갱신: D7b 참조 — Source 무효 · Target 무효 · Target 확인 불가 Retry 거부 안내가 결정되었다.)

### D7b. Live 연결 결정(2026-10-06, 소유자 승인 — Phase 6 Import 흐름 연결에 한정; 결정 기록, 구현은 흐름별)

이 절은 Phase 6 Import를 사용자 흐름에 연결하기 위한 소유자 결정 다섯 가지만 Accepted로 기록한다. D8.0 분류 규칙, D7a, 050-A / 050-B / 050-C 계산 정책 · 경계, ADR-042 Revision 4의 기존 문구, OD-12 결정은 바뀌지 않는다. 더 넓은 Startup Recovery, Store Identity Marker, OD-13, 050-E는 포함되지 않는다.

**이 절이 좁히거나 넓히는 기존 규칙:** 2항은 위 "Retry 자격 분류"의 자격 목록("…뿐이다")에 Save 전 Attempt 도중의 Target 읽기 불가(`verifiedClean` 뒤)를 더하고 "Retry Admission 명확화" A를 Attempt 도중으로 넓힌다. 2항은 전환된 흐름의 Commit Section 재확인에서 Target을 읽을 수 없을 때 D8.5b의 `확인` 전용 정지(Select Clips)를 Retry 대기 안내로 대체하고, Editor Add / Replace가 전환되면 그 두 흐름에 한해 D8.5c의 Prior 읽기 불가 정지를 대체한다(Reorder · Delete · Undo · Redo는 D8.5c 그대로). 첫 Admission Section의 Target 읽기 불가는 그대로 D8.5b(Select Clips) / D8.5c(Editor) 안내를 쓴다. 3항은 050-C의 "Phase 5 Commit 직전 최종 Guard 퇴역 시점" 미명시를 흐름별로 정한다. 4항은 D6 · D7a가 미결로 둔 Late Result · Navigation 정책 가운데 여기 적힌 부분만 정하며 그 밖의 일반 Late Result 정책은 미결로 남는다.

1. **Retry 거부 안내:**
   - 보존 Source 무효: Title `영상을 다시 선택해주세요` / Message `선택한 영상을 더 이상 사용할 수 없어요.` / Action `확인`. Retry 자격이 끝난다.
   - 확인된 Target 무효: 실제 Target에 맞는 기존 Accepted 안내를 쓴다 — Editor는 D8.5c의 Project Row 부재 안내(`프로젝트를 찾을 수 없어요`)와 상태 변경 안내(`프로젝트를 다시 확인해주세요`; 사라진 Replace 대상 Clip도 이쪽), Select Clips는 D8.5b의 대체 Target 무효 안내(`프로젝트를 교체하지 못했어요` / `교체하려던 프로젝트를 찾을 수 없어요.` / `확인`). Retry 자격이 끝난다.
   - Target 확인 불가(읽기 실패): Title `프로젝트를 확인하지 못했어요` / Message `잠시 후 다시 시도해주세요.` / Actions `다시 시도` / `취소`. 유효한 보존 Source와 Retry 대기 상태를 유지하며 자동 반복은 없다. `취소`는 D7a 3항대로 그 Operation의 Retry 상태를 끝낸다.
2. **Attempt 중 Target 읽기 불가:** Save 시도 전, Target 읽기 불가는 확인된 Rollback(`verifiedClean`), 유효한 Source, 받아들인 취소 없음이 모두 성립할 때만 Retry 대기로 들어갈 수 있다(위 1항의 Target 확인 불가 안내). 풀리지 않은 정리는 그대로 Retry 불가 · 보존(`retainedUnresolved`)이고, 확인된 부재 · 변경은 그대로 Target 무효다. D8.0은 바뀌지 않으며 Save 뒤의 미확정 결과를 Target 확인 불가로 해석하지 않는다. (2026-10-06 Retry Admission 명확화 A를 Save 전 Attempt 도중으로 넓히는 결정이다.) 풀리지 않은 정리의 안내는 D7a 5항의 U3이다. Accepted 항목이 모두 Ready여서 Sheet가 없을 때도 같은 대기가 적용되어 Alert만 표시된다.
3. **Phase 5 Commit 직전 최종 Guard(추가 0 + 100 MiB):** Select Clips · Editor Add · Replace 흐름마다 그 흐름이 Phase 6 Coordinator와 그 Accepted 검사(C0 / C0a / C1 / C2 / C3 / CR)로 완전히 전환될 때 그 흐름에서만 퇴역한다. 전환되지 않은 흐름과 관계없는 경로에는 남기며 전역으로 제거하지 않는다.
4. **Navigation과 늦은 Presentation:** Preparation이 진행되는 동안 Back과 Editor 변경을 막고 `취소`가 지원되는 유일한 나가기다. 시작한 Route가 외부에서 제거되면 그 Operation의 늦은 Navigation과 Alert를 표시하지 않되 안전한 결과 분류와 정리는 끝까지 수행한다. 화면이 사라졌다는 이유로 확인된 Save를 되돌리지 않는다. Operation · Route Identity를 쓰며 Sheet 표시나 일반적인 View 사라짐이 Operation을 무효로 만들지 않는다. Route 제거 시 이 결정을 넘는 자동 취소를 추가하지 않는다.
5. **Preparation 진행률:** 정규화가 필요한 항목만 센다. 같은 가중치: `aggregate = (끝난 정규화 항목 수 + 현재 항목 진행률) / 정규화 항목 수`. 위치는 현재 정규화 항목의 순번 / 정규화 항목 수(예: `2/5`)이며 ADR-042 R4 §1대로 정규화 항목이 여럿일 때만 표시한다. 실제 정규화기의 Bounded 진행률을 쓰며 Timer나 만들어 낸 진행률을 쓰지 않는다; 잘못되거나 순서가 어긋난 Callback은 안전하게 처리하고(항목 진행률은 `0...1`로 Clamp, 한 항목 안에서 감소하지 않음) 이전 Attempt의 Callback이 Retry에 영향을 주지 못하게 한다. Attempt마다 진행률을 초기화한다. 정규화가 100%가 되어도 Save 성공을 주장하지 않으며 Attempt 결과가 정해질 때까지 Sheet를 유지한다. Accepted 항목이 모두 Ready이면 Sheet를 표시하지 않는다.

**미결로 남는 것(이 결정이 정하지 않음):** Select Clips 새 Project Target의 확인된 무효(새 Project Identity 확보 실패 — 승인된 전용 안내 없음); 시작 Route가 제거된 채 Retry 대기 중인 Operation(안내가 표시되지 않아 `취소`할 수 없고 Workspace는 Process 수명 동안 보존됨); Save 호출 뒤의 `취소`는 D7a 3항대로 결과를 바꾸지 않는다(`completed`는 성공); "보존 Source 무효"는 Coordinator의 Typed Source 무효 결과(사라짐 · 크기 변경)를 원인과 무관하게 가리킨다.

**4항 명확화 — 시작 Route 제거(2026-10-06, 소유자 승인):** (1) Attempt가 진행 중일 때 시작 Route가 제거되면 Attempt를 자동으로 취소하지 않고 Save 분류와 안전한 결과 처리를 끝내되 늦은 Alert · Navigation은 표시하지 않는다. (2) 명시적 `다시 시도`를 기다리는 동안 Route가 제거되면 그 대기 상태를 Controller의 취소 · 정리 경로로 끝낸다. (3) Route 제거 뒤 끝난 Attempt의 결과가 원래 Retry 가능한 것이면 접근할 수 없는 Retry 대기로 들어가지 않고 같은 안전한 경로로 끝낸다. (4) `retainedUnresolved` Workspace와 증거는 보존한다; Route 제거는 추가 삭제, 미확정 Save 뒤 Rollback, 완료된 Save의 되돌림을 허용하지 않는다. (5) 종료 처리 뒤(`retainedUnresolved` 포함) Presentation의 Operation 차단을 풀며 보존해야 할 파일은 놓지 않는다; Projects 화면이 재실행 때까지 막혀 있지 않는다. (6) 일반적인 Picker · Sheet 표시나 View 사라짐은 Route 제거가 아니며 Operation · Route Identity 검사를 유지한다. 이 명확화는 4항의 "자동 취소 금지"를 Retry 대기(사용자가 응답할 수 없는 경우)에 한해 좁힌다.

**구현(2026-10-06, Select Clips만 연결 — Needs Device Test):** Projects 화면의 Select Clips가 Phase 6 경로로 전환되었다: Workspace → System 선택(C0 / C0a) → `ImportSelectionPreflight`(1.0–5.0초 양 끝 포함, Per-item 제외, 단일 선택은 Single-candidate 안내) → 제외 항목의 Mellow 소유 복사본 제거 → `ImportRetryController`(C1, Gate 밖 준비와 C2, C3 · 단일 Save · 관측 · 분류, `다시 시도` 때 CR) → 안내. Select Clips에서는 이전 Phase 5 Commit 직전 최종 Guard와 `Phase5ReadyMediaValidator` / `compose` 경로가 Production에서 더 이상 쓰이지 않으며(3항; `ProjectCompositionCoordinator.compose`와 그 Test는 제거 일정이 정해질 때까지 남는다), Editor Add / Replace는 전환되지 않아 기존 경로와 최종 Guard를 그대로 쓴다. Select Clips의 `priorConfirmed`는 이제 D8.5a P6 확인 전용 안내 대신 D7a의 확인된 Rollback 뒤 R4 §3 `다시 시도` / `취소`를 쓴다. 진행률은 정규화기의 `videoFrameScheduled`(쓰인 Cadence Target / 계획된 Target 수)에서 오며 Video Frame이 끝나 100%가 되어도 Audio · 쓰기 마무리 · Save가 남을 수 있으므로 Sheet는 결과가 정해질 때까지 유지된다. Route Identity는 `AppRouter`의 Projects Route 세대 값이며 Sheet · Picker · Editor Push는 그것을 바꾸지 않는다. 진행 중 · Retry 대기 중에는 Back과 `기존 프로젝트 불러오기`를 막는다. 확인된 성공 뒤의 통합 제외 안내는 `확인`을 누른 뒤 새 Project Editor로 이동한다. 새 Project Identity 확보 실패(미결 항목)는 임시로 D8.5b의 "그 밖의 Save 전 준비 실패" 안내를 쓴다. 첫 Attempt의 Source 무효는 D8.5b의 같은 안내를, Retry Attempt(Admission 또는 Materialize 재확인)의 Source 무효는 1항의 안내를 쓴다. Accepted 항목이 모두 Ready이면 Sheet 없이 진행되며 그동안 Back은 숨겨진다(별도 진행 표시 없음). 시작 Route 제거는 아래 "4항 명확화"대로 처리된다(Router가 Projects Route 제거를 알리고 Model이 자기 Operation · Route Identity로 판단). iPhone 12 실제 Picker · 정규화 검증은 남아 있다.

**Editor Add / Replace 결정(2026-10-06, 소유자 승인):** (1) `completed`(증거로 확인된 Throw Save 포함)이면 확인된 Project · 선택 · 정확히 하나의 History 항목을 함께 적용하고, 성공한 Add만 Editor에서 통합 제외 안내를 최대 한 번 보인다. 실패 · 취소 안내가 우선하며 Route 제거 뒤의 늦은 안내는 보이지 않는다. (2) Retry Admission에서 확인된 Project 변경은 Retry를 끝내고 D8.5c의 재확인 처리(`프로젝트를 다시 확인해주세요`)를 쓴다. Project가 없으면 기존 Project 없음 처리를 쓴다. 읽을 수 없는 Target은 별도로 유지되며 승인된 Retry 대기 정책을 따른다. (3) Editor Route 제거 시 Import 결과 처리와 Attempt 정리가 끝난 뒤에야 기존 Editor 종료 Pending Clip 정리가 공유 Gate를 통해 실행된다. 그 정리는 저장된 상태를 읽고 대상이 되는 Pending-deleted Clip만 다루며, retainedUnresolved 후보 · Workspace · 증거는 보존된다. Operation 완료를 기다리는 동안 Gate를 잡지 않는다.

**구현(2026-10-06, Editor Add / Replace 연결 — Needs Device Test):** 공유 `ImportOperationPresenter`(Sheet 진행률 · Retry 안내 · Controller 경유 취소 · Route 제거)를 Select Clips에서 추출해 Select Clips와 Editor가 함께 쓴다(Select Clips 동작 · 문구 불변). Editor Add / Replace는 Workspace → System 선택(C0 / C0a) → `ImportSelectionPreflight`(Add 여러 항목은 Per-item 제외, Replace와 한 항목은 Single-candidate) → 제외 복사본 제거 → `ImportRetryController`(Target `.add` / `.replaceClip`, C1 · C2 · C3, 단일 `update`, 관측 · 분류, Retry 때 CR)로 진행되며, Production에서 Add / Replace의 Phase 5 Validator · Materialize 경로와 Commit 직전 100 MiB 최종 Guard는 더 이상 쓰이지 않는다(Phase 6 서비스가 없는 Test 전용 구성과 STEP 12B 충돌 복구 UI Test Seam에는 남는다). 선택부터 종결 처리까지(Retry 대기 포함) 변경 · 선택 · Drag · Back이 막히고, `completed` 전까지 마지막으로 확인된 Timeline이 보인다. Add는 Accepted Set 순서를, Replace는 ADR-040 Identity · 같은 Index · Pending-deleted · ADR-040 §6 Revision 길이 규칙을 따른다. 불확실 Save는 Media를 보존하고 기존 U1 / U2 잠금으로 들어간다. 첫 Admission에서 읽을 수 없는 Target은 D8.5c 재확인 처리를, Retry Admission에서 읽을 수 없는 Target은 Retry 대기를 쓴다. Editor Route Identity는 `AppRouter`의 Route별 세대 값(`.projectEditor(id)`)이며, Router의 Editor Route 제거 알림은 해당 Project의 Import가 진행 · 대기 중이면 대기 중 Retry를 끝내고 Operation이 끝날 때까지(Gate 없이) 기다린 뒤 기존 Editor 종료 정리를 예약한다. 진행 중 Attempt는 Route 제거로 취소되지 않는다. Route Identity와 이 대기 등록은 Picker를 열기 전에 잡히며, Picker가 떠 있는 동안 Route가 제거되면 아직 전송이 시작되지 않은 선택 세션은 취소로 끝나고(Host View가 사라져 닫힘 알림이 오지 않을 수 있으므로) 이미 시작된 전송은 끝까지 진행되지만, 제거된 Route에서는 늦은 Picker 결과나 Preflight 결과로 Attempt를 시작하지 않고 전송된 복사본을 Workspace와 함께 정리한다. 같은 Project의 Editor Route 중 하나만 제거된 경우에는 Editor 종료 정리 없이 해당 Import에만 Route 제거를 알린다. 새 문구 · 저장 상수 · 복구 정책은 추가하지 않았다. 독립 Review(2026-10-06)의 지적은 모두 반영되었고, 재검토와 Picker 단계 · DEBUG Repository 연결에 대한 집중 재검토에서 차단 문제는 남지 않았다. iPhone 12 실제 Picker · 정규화 검증은 남아 있다.

### D8. Save Outcome 판정(Save 오류 또는 확인 실패 뒤)

**근거의 범위:** `docs/evidence/phase-06/adr-050d-persistence-atomicity-report.md`(Exploratory)에서 DB File과 잘린 WAL로 재구성한 경계는 측정한 경우에 완전한 이전 상태 또는 완전한 새 상태로 다시 열렸다. 이것은 실제 Process 강제 종료, 전원 손실, 모든 Save 오류에 대한 보장이 아니다. 따라서 이 절은 Save 오류를 Commit 여부의 증거로 쓰지 않고, 다시 읽은 Durable 상태로 결과를 정한다.

#### D8.0 Accepted 분류 규칙(2026-10-02, 사용자 부분 승인)

- Save 성공 + Intended 상태 확인 → 완료.
- Save 성공 + 확인 불가 또는 모순 → Commit됨 · 확인 안 됨: 참조 가능 Media를 보존하고 Rollback을 결코 허가하지 않는다.
- Save 오류 + Intended 상태 확인 → 완료.
- Save 오류 + Prior 상태 확인(이 Operation이 만든 Project · Clip ID가 Store 전체에 없다는 확인 포함) → Commit 전 Rollback 대상.
- Save 오류 + 그 밖의 모든 관측 → 미확정: 참조 가능 Media를 보존하고 `다시 시도`를 금지한다.
- 이 규칙은 해당 Save / 확인 결과 의미만 개정한다. 실제 독립 Read 방법(OD-10), Lifecycle Gate 연결, Rollback 구현, 안내 Copy(U1–U4), Startup Cleanup 개정은 Proposed다. (2026-10-02 갱신: OD-10 구현 정책은 아래 OD-10 항목대로 Accepted · 구현되었고 그 연결은 Pending이다.) (2026-10-05 갱신: Select Clips에 연결 — D8.5b; Editor 연결은 Pending.) (2026-10-02 갱신: U1 / U2 문구는 D8.5a P3, `priorConfirmed` 문구는 P6으로 Accepted — 미구현; U3 / U4는 Proposed.)
- **명확화(2026-10-02, 사용자 승인 — 리뷰 F3 (a)):** Save가 오류를 던진 뒤 "완료"는 Intended 상태 확인에 더해, 이 Operation이 만든 모든 Project · Clip ID에 대한 Store 전체 증거가 완전하고 Intended 상태 · 소유와 일치할 것(Project ID는 자기 자신만, Clip ID는 의도한 소유 Project만 보유)을 요구한다. 그 증거가 없거나 일부이거나 읽을 수 없거나 모순되면 미확정이다. 만든 ID가 없는 Operation에서는 이 요구가 대상 없이 충족되지만 Intended 상태 전체 비교는 여전히 필요하다. Save 성공 뒤에는 이후 관측과 무관하게 Rollback이 금지된다.
- **명확화(2026-10-02, 사용자 승인 — 만든 ID가 없는 Operation):** 이 Operation이 Project · Clip ID를 하나도 만들지 않으면 "Prior 확인"에 필요한 만든 ID의 Store 전체 부재 확인은 대상 없이 충족된다. Prior 상태 전체 비교와 그 밖의 모든 해당 검사(구조 검사, 구분 불가 검사, 읽기 · 관측 검사)는 여전히 필요하다. 이 명확화는 Save가 오류를 던진 경우에만 적용되며 Save 성공 뒤의 Rollback을 허가하지 않는다. 050-D의 다른 부분의 승인 범위는 넓히지 않는다.
- 빈 Expectation이나 구조가 맞지 않는 Expectation(양쪽 Project ID 불일치, Intended에 없는 소유자 등)은 완료나 Prior 확인을 낳지 않는다(Save 성공이면 Commit됨 · 확인 안 됨, Save 오류면 미확정).
- **OD-10 승인(2026-10-02, 사용자 승인 — 구현 정책):** 관측마다 기존 `ModelContainer`의 새 전용 `ModelContext`(Autosave 꺼짐, 해당 Fetch에 `includePendingChanges = false`)를 쓰고 Save Context나 공유 `mainContext`의 Object를 다시 쓰지 않는다. 이것은 구현 정책이며 모든 공유 Cache를 우회하거나 모든 실패에서 독립적인 Durable 진실을 확립한다는 보장이 아니다. 관측은 여러 개의 개별 Fetch이며 원자적 Store Snapshot이 아니므로, 한 시점을 나타내려면 호출자가 Lifecycle Gate로 Project 변경과 직렬화해야 한다(연결은 Pending). 구현: `SwiftDataProjectRepository.observePersistedState(for:)`(연결 없음) — 관측마다 같은 Container의 새 `ModelContext`(Autosave 꺼짐, 해당 Fetch에 `includePendingChanges = false`)를 쓰고 Save Context나 공유 `mainContext`의 Object를 다시 쓰지 않는다; Expectation의 모든 Project ID를 `.absent` / `.present` / `.unreadable`(Fetch 실패 또는 Domain 변환 실패)로 관측하고, 만든 Project · Clip ID를 Store 전체에서 정렬된 Bounded Batch(500)로 조회하여 보유 Project를 보고한다(소유 Project가 없는 Clip Row는 `unownedClipHolder`); 실패한 Batch의 ID는 빠진 것으로 남고 성공한 Batch의 충돌은 그대로 보고된다; 만든 ID가 없으면 그 조회를 하지 않는다; Metadata를 바꾸지 않는다.
- **Proposed로 남는 D8 부분:** D8.1(적용 시점), D8.2 가운데 OD-10 구현 정책을 넘는 부분(예: 별도 `ModelContainer` 대안), D8.3의 Prior Snapshot 시점과 Gate 안 순서, D8.4(동시 변경 · Gate 적용), D8.5의 결과별 Media · Workspace 처리와 안내(U1–U4), D8.7–D8.8. 이 절들 가운데 D8.0의 다섯 규칙과 명확화에 해당하는 분류 의미만 Accepted다. D8.6(두 Save 처리)은 승인되지 않았고 OD-14 (a)로 대체되었으며 그 안의 Save 2 규칙도 승인되지 않았다; D8.6a의 OD-14 (a) 승인 범위는 바뀌지 않는다. (2026-10-02 갱신: D8.1 · D8.3 · D8.4 · D8.5 · D8.6a 가운데 D8.5a P1–P6 · P8에 적힌 부분은 Accepted되었고 나머지는 Proposed로 남는다; P7은 보류.)
- **Save 뒤 Media 보존 수리(2026-10-02, 사용자 승인 — 이미 Accepted된 D8.0 보존 규칙 적용; 분류기 · 관측 Helper · `replaceProject` 연결 없음):** Select Clips `compose`는 Save 시도 전 실패(Materialize 실패, 값 생성 실패)에서만 B Directory를 지우고, `create`가 오류를 던지거나 성공한 뒤 확인 읽기가 실패하면 B Row를 지우지 않고 B Media를 보존한다; 두 Save `.replacingSaved`는 B 확인 뒤 A 삭제 호출이 반환되고 다시 읽은 결과가 A Row 부재를 확인할 때만 A Media를 지우며, 삭제 오류나 읽기 오류면 A Media를 보존한다; Editor Add / Replace는 Save 시도 뒤(`update` 오류 또는 확인 실패) 새 파일을 지우지 않고, Save 시도 전 실패(Target 거부, Domain 적용 실패)만 기존대로 정리한다. 보존된 파일 가운데 참조되지 않는 것은 기존 Startup Recovery(Row 없는 Project Directory, 참조 없는 Canonical Media; Live Editor는 건너뜀)가 다음 실행에서 정리하며, 실행 중 Cleanup은 Pending-deleted Clip만 다루므로 보존된 파일을 지우지 않는다. 남은 의존성: 실패 안내는 그대로이며 사실과 다를 수 있다(B가 저장되었는데 Select Clips가 실패 안내를 보이거나, Editor가 저장된 변경을 되돌린 것처럼 보임 — D8.5 안내 결정 Pending); Editor는 Save 시도 실패 뒤 이전 메모리 상태로 돌아가므로 Store에 변경이 남았으면 이후 편집이 `missingDurableClip` 등으로 거부될 수 있다(데이터 손실은 없음; 다시 읽기 · 갱신 계약은 D8.5 / D8.4 Prior Snapshot과 함께 Pending); Select Clips 확인 실패 뒤 화면 상태 갱신, 결과 판정 연결(관측 · 분류기), Startup Cleanup 개정(ADR-039 STEP 12B 빈 Store 보호 등)은 Pending이다. `.replacingSaved`에서 B의 Save가 오류를 던졌지만 반영되었거나 Save 뒤 확인이 실패하면 B Row는 보존되고 A는 건드리지 않으므로 A와 B가 함께 저장된 상태로 남을 수 있다(Single Saved Project에서 벗어남, A가 B 뒤에 가려짐) — 이 처리는 OD-13 / D8.5와 함께 Pending이다. (2026-10-02 갱신: 안내와 Editor 처리는 D8.5a P2 · P3 · P6으로 Accepted — 자동 다시 읽기 대신 Reconciliation 필요 상태와 프로젝트 화면으로 돌아가 다시 열기; 미구현.) (2026-10-05 갱신: 이 문단의 Select Clips 부분 — `create` 확인 읽기와 두 Save `.replacingSaved` — 은 D8.5b의 단일 Save · 관측 · 분류로 대체되었다; Editor 부분은 그대로다.)
- **구현(2026-10-02, 연결 없음):** `MellowApp/Core/Persistence/ProjectSaveOutcome.swift` — `ProjectStateSnapshot`(Identity · Orientation · 두 Timestamp · Active Clip 순서와 모든 Field · Pending-deleted Clip을 ID 기준 집합으로 · 소유 일관성; 소유와 중복 없음은 `VlogProject.init`이 이미 보장), `ExpectedProjectState`(`.absent` = 확인된 부재), `ProjectSaveExpectation`(Private Init; 검증된 Factory `create` / `replace` / `update`만 생성하며 `replace`는 같은 Project ID나 A의 Clip ID 재사용을, `update`는 서로 다른 Project ID를 `ProjectSaveExpectationError`로 거부; DEBUG 전용 `debugUnvalidated`는 구조 검사 Test용), `ObservedProjectRecord`(`.absent` / `.present` / `.unreadable`), `PersistedStateObservation`(호출자가 보고한 관측이며 Cache 독립 Read의 증거가 아님; Store 전체 Identity 조회 결과는 없으면 `nil`), `ProjectSaveOutcomeClassifier.classify`, 결과 `ProjectSaveOutcome`(`completed` / `committedUnverified` / `priorConfirmed` / `indeterminate`)과 진단 사유(`invalidExpectation` 포함). Repository 읽기 · Filesystem · Coordinator · UI 연결은 없다.

#### D8.1 언제 적용하는가

- Repository Save가 오류를 던졌을 때.
- Save는 성공했지만 Read-back이 실패하거나 Intended 상태와 다를 때.
- **Save 성공 뒤에는 파괴적 Rollback이 없다(검토 후속 1, 2026-10-02):** Save가 오류 없이 반환되었다면, 나중의 읽기가 Prior와 같아 보이더라도 D4 Rollback · Restoration · 후보 제거를 하지 않는다. 확인된 이전 상태에 따른 Rollback은 Save가 오류를 던진 뒤 D8.3의 확인(새 ID 부재 포함)을 거친 경우에만 가능하다. Save 성공 뒤의 모순된 읽기(Prior와 같음, Intended와 다름, 읽기 · 변환 실패)는 모두 "Commit됨 · 확인 안 됨"으로 처리하여 참조 가능한 Media를 보존하고 Reload 전까지 추가 Edit을 막는다.
- Save 성공과 Read-back 일치는 정상 완료이며 이 절이 필요 없다.

#### D8.2 독립 Persisted-state Read

**상태(2026-10-02):** OD-10 "같은 Container의 새 `ModelContext`"가 구현 정책으로 Accepted되어 `observePersistedState(for:)`로 구현되었다(D8.0의 OD-10 항목). 아래의 별도 `ModelContainer` 대안은 승인되지 않았다.

- 실패한 `ModelContext`나 그 Object · Cache를 다시 쓰지 않는다. 현재 `SwiftDataProjectRepository.saveOrRollback`은 Save 실패 시 Rollback 뒤 새 `ModelContext`를 만든다.
- **제안:** 같은 `ModelContainer`에서 새 `ModelContext`를 만들고 `includePendingChanges = false`인 Fetch로 대상 Project Row를 읽는다.
- **한계:** 같은 Container의 Context들은 같은 Persistent Store Coordinator를 공유하므로 Coordinator 수준 Cache로부터 완전히 독립인지는 이 ADR이 확인하지 않았다.
- **대안(소유자 선택):** 같은 Store URL에 별도 `ModelContainer`를 열어 읽는다(독립 Coordinator; 열기 비용과 동시 열기 동작은 검증되지 않음). Schema 매핑을 우회하는 원시 SQLite 읽기는 제안하지 않는다.
- 다음 Process 시작의 Startup Recovery 읽기는 새 Process의 읽기이며 D8.7의 최종 정리 경로다.

#### D8.3 비교 기준

- **Prior Snapshot:** Operation 시작 시, Lifecycle Gate 안에서 Target 확인(D6)과 같은 Section에서 독립 Read로 얻은 대상 Project의 Domain 값. Select Clips 새 Project는 "B Row 없음"이 Prior다; `.replacingSaved`는 "A 값 + B Row 없음"이다.
- **Intended Snapshot:** Save에 넘긴 `VlogProject` 값(삭제 Save는 "대상 Row 없음").
- **비교 항목:** `VlogProject` Domain 전체 동등성 — Project ID, Orientation, `createdAt`, `updatedAt`, Active Clip의 ID 순서와 각 Clip의 모든 Field(`sortOrder`, `sourceKind`, `mediaRelativePath`, Duration, Trim, Framing, `createdAt`), Pending-deleted Clip 집합과 각 Deletion Record. 이에 더해 모든 Clip Row가 그 Project에 속하고, 이 Operation의 새 Clip ID가 다른 Project에 나타나지 않아야 한다.
- **판정:**
  - 읽기 성공이고 Intended와 같음 → **확인된 새 상태**.
  - (Save가 오류를 던진 경우에만) 읽기 성공이고 Prior와 같으며, 같은 독립 Read에서 이 Operation의 새 Clip ID와 새 Project ID(Select Clips의 B)가 Store 어디에도 없음이 Fetch로 확인됨 → **확인된 이전 상태**. 이 확인 없이는 파괴적 Rollback(D4)을 하지 않고 미확정으로 본다.
  - 그 밖의 모든 경우 → **미확정**: 둘 다와 다름(일부 Clip만, 순서 · Field 불일치, 다른 Project에 새 Clip ID), 읽기 오류, Domain 변환 오류(`invalidPersistedMetadata` 등), 상태가 서로 모순됨, Prior와 Intended가 같아 구분할 수 없음.
- 추측으로 미확정을 이전 또는 새 상태로 바꾸지 않는다.

#### D8.4 동시 변경

- Prior Snapshot 읽기부터 Save와 판정 읽기까지를 같은 Lifecycle Gate Section 안에서 실행한다.
- 현재 Home의 Project 삭제와 Editor Add / Replace는 Gate를 쓰지 않는다; 이것들이 Gate를 쓰는 것이 이 판정의 선행 의존성이다. (2026-10-02 갱신: 이 선행 의존성은 구현되었다 — D6의 구현 항목. Prior Snapshot을 같은 Section에서 읽는 것과 판정 연결은 Pending이다.)
- Gate 안에서도 예상 밖 값이 보이면 미확정이다.

#### D8.5 결과별 처리와 안내(제안 — 새 안내는 모두 소유자 결정)

| 결과 | Media · Workspace | `다시 시도` | Editor / 화면 | 안내 |
| --- | --- | --- | --- | --- |
| 확인된 이전 상태 | D4 Pre-commit Rollback(Ready Rename-back, 정규화 출력 제거) | 가능(R4 §3) | 이전 상태 유지 | R4 §3 그대로(`영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.`); 이 경우 "저장되지 않았어요"는 확인된 사실이다 (2026-10-02: 이 행은 Proposed로 남는다; 이번 Slice의 임시 경계는 D8.5a P6 — Rollback · Retry 없음, 확인 전용 문구) (2026-10-05: 확인된 Rollback 뒤 Retry 자격이 있으면 R4 §3 문구와 `다시 시도` / `취소` — D7a로 Accepted, 미구현; 복구 통합 전까지 구현된 P6 경로가 유지된다) |
| 확인된 이전 상태 + Restoration 또는 정리 실패(D4 5항, D7) | D4 5항대로; 새 Attempt 없음 | 없음 | 이전 상태 유지 | **새 안내 제안 U3:** `영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 영상을 다시 선택해주세요.` / `확인` (2026-10-05: D7a 5항으로 Accepted — Commit되지 않았음이 확정된 경우에만, Retry 없음, 미구현) |
| 확인된 새 상태(Save가 오류를 던졌지만 Durable 새 상태) | 참조된 Media 보존; Workspace의 남은 Source Discard | 없음 | Durable 값으로 갱신 | 정상 완료로 처리(R4는 별도 성공 Alert 없음); 오류는 Log에만; "저장되지 않았어요" 금지 |
| Save 성공 + 확인 불가(Commit됨 · 확인 안 됨, D3) | 참조 가능 Media 보존; Workspace의 남은 Source Discard; A 보존(`.replacingSaved`) | 없음 | Editor는 Reload 필요 상태, 추가 Edit 차단 | **새 안내 제안 U1:** `저장 확인이 필요해요` / `변경사항은 저장되었지만 지금은 확인하지 못했어요. 프로젝트를 다시 열어 확인해주세요.` / `확인` (2026-10-02: 문구는 D8.5a P3로 대체, Editor 처리는 P2) |
| 미확정 | 이 Operation이 `Projects/` 아래에 둔 모든 File 보존; Rename-back · 후보 제거 · A 삭제 등 파괴적 정리 금지; 어떤 Durable Row도 참조할 수 없는 Workspace 안의 File만 Discard 가능 | 없음(중복 Commit 위험) | Editor는 Reload 필요 상태, 추가 Edit 차단 | **새 안내 제안 U2:** `저장 결과를 확인하지 못했어요` / `영상이 저장되었는지 지금은 알 수 없어요. 같은 영상을 다시 추가하기 전에 프로젝트를 확인해주세요.` / `확인` (2026-10-02: 문구는 D8.5a P3로 대체, Editor 처리는 P2) |
| Target 무효(D6) — 삭제된 Project | 후보 제거, Workspace Discard | 없음 | 해당 화면 없음 | 안내 없음(Late Result 폐기, Log만) |
| Target 무효(D6) — 살아 있는 Editor | 후보 제거, Workspace Discard | 없음 | Editor 유지 | **새 안내 제안 U4:** Add `영상을 추가하지 못했어요` / `프로젝트를 찾을 수 없어요.` / `확인`; Replace `클립을 교체하지 못했어요` / `교체하려던 클립을 찾을 수 없어요.` / `확인` |

- U1 문구의 "저장되었지만"은 Save 성공 = Durable Commit(D1)에 근거한다. U2–U4는 "저장되지 않았어요", "그대로 있어요", 성공적인 `다시 시도`를 주장하지 않는다. U3의 "저장되지 않았어요"는 확인된 이전 상태에서만 쓴다.
- U2의 대안(소유자 선택): `다시 확인` Action을 더해 D8.2 읽기를 다시 하고, 확정되면 위 표의 해당 결과를 적용한다. 이 기록은 Process 안 Memory에만 있으며 Process가 끝나면 D8.7이 처리한다. (2026-10-02 갱신: D8.5a P3가 U2 Action을 `프로젝트 화면으로` / `확인`으로 정했으므로 이 대안은 채택되지 않았다.)

#### D8.5a Accepted 결과 처리(2026-10-02, 사용자 승인 — P1–P6, P8 Accepted, P7 보류)

이 절은 D8.1–D8.5 · D8.6a 가운데 아래 항목만 Accepted로 기록한다. Production 구현은 아직 없다(Accepted 동작이며 미구현). (2026-10-05 갱신: Select Clips 부분 — P1 · P4 · P5 · P6 Select Clips · P8과 U1 / U2 Select Clips — 은 D8.5b대로 연결되었다; Editor 부분 — P1 Editor 정지 · P2 · U1 / U2 Editor · P6 Editor Add / Replace — 과 P7은 미구현이다.) (2026-10-05 추가 갱신: Editor 부분과 P7은 D8.5c대로 결정 · 연결되었다.) D8.0 분류 규칙은 바꾸지 않는다. Rollback(D4 · OD-4), 같은 Set Retry(D7), U3(OD-5), U4와 Target 무효 안내(OD-8), Late Result 처리, Startup Cleanup 개정(OD-12), OD-13, 050-E는 이 승인에 포함되지 않으며 Proposed · 미결로 남는다. (2026-10-05 갱신: Rollback, 같은 Set Retry, U3, 취소 경계, Target 무효화 규칙은 D7a로 Accepted — 미구현; Late Result, OD-12, OD-13, 050-E는 그대로 미결.)

- **P1 — Prior Snapshot 시점(Accepted):** Prior Snapshot은 Accepted Fresh-read 정책(OD-10)으로 Lifecycle Gate 안에서 Materialize 전에 읽는다. Save, 관측, 분류(D8.0)는 Gate를 놓기 전에 끝낸다. Editor의 메모리 상태가 Prior와 다르거나(Stale Editor) Prior를 읽을 수 없으면 Materialize 전에 멈춘다. 이 정지의 안내는 정해지지 않았다(소유자 결정 대기); Prior를 읽을 수 없을 때 Project가 그대로라고 말하지 않는다. (2026-10-05: Select Clips의 Prior 읽기 불가 안내만 D8.5b로 결정되었다; Editor의 Stale · Prior 읽기 불가 정지 안내는 미정.) (2026-10-05 추가: Editor 정지 안내는 D8.5c로 결정.)
- **P2 — Editor Reconciliation(Accepted):** 결과가 `committedUnverified` 또는 `indeterminate`이면 Editor는 저장되지 않는(Non-persisted) "Reconciliation 필요" 상태가 되고 Add, Replace, Delete, Reorder, Undo, Redo 등 모든 Editor 변경을 막는다. 자동 Reload는 하지 않으며 메모리의 이전 상태를 저장 결과로 보여 주지 않는다. 사용자는 프로젝트 화면으로 돌아가고, 기존 Gate 안 Load로 다시 열면 빈 History의 새 Editor Session이 만들어진다. 다시 열기가 실패하면 기존 Unavailable 상태로 남는다. 다시 열기 성공은 지금 읽을 수 있는 Project가 있다는 사실만 뜻하며 앞선 Save의 결과를 확정하지 않는다. 이 차단은 P7(동기 변경의 결과 처리 연결)이 보류된 동안에도 모든 변경에 적용된다.
- **P3 — U1 / U2 문구(Accepted, 정확한 문구):**
  - U1 Editor: `저장 확인이 필요해요` / `변경사항은 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 열어 확인해주세요.` / Action `프로젝트 화면으로`
  - U1 Select Clips: `저장 확인이 필요해요` / `새 프로젝트는 저장되었지만 지금은 확인하지 못했어요. 프로젝트 화면에서 다시 확인해주세요.` / Action `확인`
  - U2 Editor: `저장 결과를 확인하지 못했어요` / `변경사항이 저장되었는지 지금은 알 수 없어요. 프로젝트 화면에서 다시 열어 확인해주세요.` / Action `프로젝트 화면으로`
  - U2 Select Clips: `저장 결과를 확인하지 못했어요` / `새 프로젝트가 만들어졌는지 지금은 알 수 없어요. 다시 만들기 전에 프로젝트 화면에서 확인해주세요.` / Action `확인`
  - U1은 `committedUnverified`, U2는 `indeterminate`에만 쓴다. "읽을 수 없는 B Row = 미확정"이라는 일괄 규칙(OD-3 제안, D3의 Read-back `invalidPersistedMetadata` 항목)은 승인하지 않는다: D8.0대로 Save 성공 + 확인 불가는 `committedUnverified`, Save 오류 + 결정적이지 않은 증거는 `indeterminate`다. 분류 규칙은 바뀌지 않는다.
- **P4 — Save 오류 뒤 `completed`(Accepted):** Save가 오류를 던졌어도 D8.0의 모든 증거 요구가 충족되어 `completed`이면 정상 성공으로 처리하고, 오류는 Log에만 남기며 실패 Alert를 보이지 않는다.
- **P5 — Projects 화면 갱신(Accepted):** `completed`가 아닌 Save 결과 뒤 Projects 상태를 다시 읽는다. Load 실패는 "모름"이며 "저장 Project 없음"이 아니다: 이후의 Load가 성공할 때까지 Project 만들기와 열기를 막는다. Load를 다시 시도하는 명시적 `다시 불러오기` Action을 둔다(화면 표시 Callback에만 기대지 않는다). 성공한 빈 결과는 새 Project 만들기를 허용할 수 있다. "모름" 상태의 제목 · 설명 문구는 정해지지 않았다(소유자 결정 대기; Action 이름만 Accepted). (2026-10-05: D8.5b로 결정.)
- **P6 — `priorConfirmed`의 임시 경계(이 Slice에 한한 Accepted):** 후보 파일은 기존 Startup Recovery를 위해 남긴다. 이 Slice에는 Rollback-to-Workspace와 같은 Set Retry가 없다. 안내는 `다시 시도해주세요` 없는 확인 전용 문구를 쓴다:
  - Select Clips: `프로젝트를 만들지 못했어요` / `새 프로젝트가 저장되지 않았어요.` / `확인`
  - Editor Add: `영상을 추가하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요.` / `확인`
  - Editor Replace: `클립을 교체하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요.` / `확인`
  - 이 "저장되지 않았어요" 주장은 Save가 오류를 던진 뒤의 `priorConfirmed`에만 쓰며 Save 성공이나 `indeterminate`에는 절대 쓰지 않는다. D8.5 표의 "확인된 이전 상태" 행(D4 Rollback, `다시 시도` 가능, R4 §3 문구)은 Proposed로 남는다.
- **P7 — 동기 Editor 변경(보류):** Reorder · Delete · Undo · Redo의 Gate 없는 동기 처리 예외는 승인하지 않는다. 그 결과 처리 연결은 별도의 범위 제한 Task에서 감사 · 결정한다. 이것이 미결인 동안 Editor 결과 처리 연결이 완료되었다고 말하지 않는다. (2026-10-05 갱신: P7은 D8.5c로 Accepted — 공유 Gate 직렬화, Gate 없는 동기 예외 없음.)
- **P8 — Select Clips 대체 연결(Accepted):** 이후 구현 Slice에서 Select Clips `.replacingSaved`를 Accepted 단일 Save `replaceProject` 계약(OD-14 (a), ADR-033 Revision 1)에 연결한다: Gate 안에서 A 재확인 → B 파일과 Metadata를 Save 전에 확인 → `replaceProject` → 관측 · 분류 → `completed`이고 A Row 부재가 확인된 경우에만 A Media 제거. Target 무효는 B만 만드는 생성으로 바뀌지 않는다. 이 Slice를 구현할 때 기존 두 Save Production 분기를 제거한다. Accepted 050-B의 보수적 두 Save Metadata Estimate는 바꾸지 않는다.

#### D8.5b Select Clips 추가 안내와 결과 처리 연결(2026-10-05, 사용자 승인 — Select Clips 한정)

이 절은 Select Clips에만 적용되는 소유자 결정 네 가지를 기록하고 D8.5a의 Select Clips 부분 구현을 적는다. Editor Stale 상태 · Editor Prior 읽기 불가 정지의 안내, U3(OD-5; 2026-10-05: D7a로 결정), U4(살아 있는 Editor의 Target 무효, OD-8), P7, Rollback(D4 · OD-4), 같은 Set Retry(D7), Late Result 처리, Startup Cleanup 개정(OD-12), OD-13, 050-E는 이 결정에 포함되지 않으며 미결로 남는다. D8.0 분류 규칙과 Accepted 050-B의 보수적 두 Save Metadata Estimate는 바뀌지 않는다.

- **Save 전 Project 확인 실패(Prior 읽기 불가):** `프로젝트를 확인하지 못했어요` / `프로젝트 화면에서 다시 확인해주세요.` / Action `확인`. 프로젝트 화면에 머물며 Project 상태를 다시 읽는다; 다시 읽기가 실패하면 "모름"으로 남고 부재로 추론하지 않으며 자동 반복 재시도는 없다.
- **Projects Load 실패 · "모름" 상태:** `프로젝트를 불러오지 못했어요` / `저장된 프로젝트를 확인할 수 없어요. 다시 불러와주세요.` / Action `다시 불러오기`(D8.5a P5의 Action).
- **대체 Target 무효:** `프로젝트를 교체하지 못했어요` / `교체하려던 프로젝트를 찾을 수 없어요.` / Action `확인`. 프로젝트 화면에 머물며 B만 만드는 생성으로 바뀌지 않는다. (2026-10-05 추가 결정: 이 결과 뒤에도 Projects 상태를 정확히 한 번 다시 읽는다; 다시 읽기 실패는 "모름"이며 Composition은 자동으로 다시 시도하지 않는다.)
- **현재 대체 대상 판단(2026-10-05 추가 결정):** "A가 여전히 현재 저장 Project인가"는 Accepted Fresh-read 정책(OD-10)과 기존 현재 Project 순서(`recentProjects()`와 같은 정렬 · 모든 Row 변환)로 판단하며 Shared Context의 `recentProjects()`를 쓰지 않는다. 현재 Project를 믿을 수 있게 정할 수 없으면 Fail-closed로 위 첫 문구(Save 전 Project 확인 실패)에서 멈춘다. 이것도 Cache 독립성이나 원자적 Snapshot을 보장하지 않으며 Lifecycle Gate 직렬화가 여전히 필요하다.
- **대체 호출의 `projectNotFound`(2026-10-05 추가 결정):** Repository 대체 호출이 시도된 뒤의 오류는 이름(`projectNotFound` 포함)과 관계없이 D8.0 분류를 따르며 오류 이름만으로 Commit되지 않았다고 추론하지 않는다. Save 전 Target 무효 처리는 Save가 시도되지 않았음을 구현이 증명할 수 있을 때만 쓸 수 있고 문구를 바꾸기 위한 최적화로 추가하지 않는다. D8.0은 넓어지지 않는다.
- **그 밖의 Save 전 준비 실패:** `영상을 준비하지 못했어요` / `영상을 다시 선택해주세요.` / Action `확인`.

**구현(2026-10-05, Select Clips만 연결):**

- `ProjectCompositionCoordinator.compose`: 저장 공간 확인과 Media 검증은 Lifecycle Gate 밖에서 실행한다(Workspace는 기존 Live-workspace 보호를 받는다). 한 Gate 구간 안에서 B ID의 부재와 (대체 시) A를 OD-10 정책의 `observePersistedProject(id:)`로 Materialize 전에 읽고(읽을 수 없음 ≠ 부재), `observeCurrentProjectID()`(같은 OD-10 Fresh-read, 기존 현재 Project 순서; 읽기 · 변환 실패 = 읽을 수 없음)로 A가 여전히 현재 저장 Project인지 다시 확인한 뒤, Materialize → B 값과 Expectation(`create` / `replace`) 생성 → B Media 존재와 Expectation 구조 확인 → `create` 또는 `replaceProject` 한 번 → `observePersistedState(for:)` 관측과 D8.0 분류를 마친 다음 Gate를 놓는다. 두 Save 분기는 제거되었다. 호출하는 Helper는 Gate를 다시 잡지 않는다.
- 결과 처리: `completed`(Save 오류 뒤 포함)는 B로 이동하고 오류는 Log에만 남긴다(P4); 대체이면 관측에서 A Row 부재가 확인된 경우에만 A Media를 지우며 그 정리는 확인된 결과를 바꾸지 않는다. `committedUnverified` → U1 Select Clips, `indeterminate` → U2 Select Clips, `priorConfirmed` → P6 Select Clips 문구이며 셋 모두 Media를 보존하고(후보 파일은 기존 Startup Recovery의 몫) Rollback · `다시 시도`가 없다. Prior 읽기 불가 → 위 첫 문구, Target 무효 → 위 셋째 문구, 그 밖의 Save 전 실패(작업 공간 · 전송 · Materialize · Metadata) → 위 넷째 문구이며 이 경우의 B 자체 Directory 정리는 기존대로다. `completed`가 아닌 Save 결과, Prior 읽기 불가, 대체 Target 무효 뒤에는 Projects 상태를 정확히 한 번 다시 읽으며 Composition을 자동으로 다시 시도하지 않는다. (2026-10-06 갱신: Select Clips의 Production 경로는 D7b 구현 항목으로 대체되었다 — `priorConfirmed`는 D7a의 확인된 Rollback 뒤 `다시 시도`를 쓴다.)
- `ProjectsEntryModel` / `ProjectsEntryView`: Load 결과를 성공(저장 Project 있음 · 없음)과 "모름"으로 구분하며, 성공한 Load 전까지 만들기 · 열기를 막고, "모름" 상태에서 위 둘째 문구와 `다시 불러오기` Action을 보인다.
- Repository: `ProjectRepository`에 OD-10 관측 세 가지(`observePersistedProject(id:)`, `observePersistedState(for:)`, `observeCurrentProjectID()`)를 추가했고 SwiftData 구현은 기존 전용 Context 정책을 그대로 쓴다.
- 구현상의 한계: Gate 안 재확인 직후 `replaceProject`가 `projectNotFound`를 던지는 경우도 위 결정대로 D8.0 분류(관측 결과)에 따른다(Save 전 Target 무효로 바꾸지 않음). 현재 Project 판단은 모든 Row를 변환하므로 무관한 Row 하나를 읽을 수 없어도 대체가 Fail-closed로 멈춘다. Disposable Store에서의 기기 검증은 남아 있다.

#### D8.5c Editor 결과 처리와 P7(2026-10-05, 사용자 승인)

이 절은 Editor에 대한 소유자 결정을 기록한다. D8.0 분류 규칙, D8.5a P2 · P3 · P4 · P6의 Accepted 내용, 050-B Estimate는 바뀌지 않는다. Rollback-to-Workspace, 같은 Set Retry, 일반 Late Result · 취소 정책, Startup Cleanup 개정, OD-13, 050-E는 이 결정에 포함되지 않으며 미결로 남는다. (2026-10-05 갱신: Rollback-to-Workspace, 같은 Set Retry, 취소 경계는 D7a로 Accepted — 미구현; 일반 Late Result 정책과 Startup Cleanup 개정은 그대로 미결.)

- **P7 — 직렬화(Accepted):** Reorder · Delete · Undo · Redo는 Editor Add / Replace와 같은 공유 Lifecycle Gate를 쓴다. Prior 관측, Expectation 생성, Save, 저장 상태 관측, 분류가 그 Gate 안에서 실행된다. Gate 없는 동기 예외는 승인하지 않는다. Gate를 잡은 상태를 전제로 하는 내부 Commit 하나를 쓰며 Add / Replace는 Gate를 두 번 잡지 않는다.
- **Save 전 정지:** Fresh Prior가 Editor의 기준 상태와 정확히(전체 상태) 같지 않거나 읽을 수 없으면 `프로젝트를 다시 확인해주세요` / `프로젝트 화면에서 다시 열어 확인해주세요.` / Action `프로젝트 화면으로`; Project Row가 없으면 `프로젝트를 찾을 수 없어요` / `프로젝트 화면에서 다시 확인해주세요.` / Action `프로젝트 화면으로`. 모든 변경을 막고 프로젝트 화면으로 돌아가 다시 열어야 한다. 읽을 수 없을 때 저장 상태가 그대로라고 말하지 않는다.
- **Reorder · Delete · Undo · Redo의 `priorConfirmed`:** `변경사항을 저장하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요.` / `확인`. 확인된 이전 상태와 History를 그대로 둔다. 이 확인 전용 문구는 Save가 오류를 던진 뒤의 `priorConfirmed`에만 쓰며 미확정이나 성공한 Save에는 쓰지 않는다. Add / Replace는 D8.5a P6 문구를 유지한다.
- **진행 중 표시:** 결과가 `completed`가 될 때까지 기존 Timeline / Project 상태를 보이며 시도한 Project를 미리 게시하지 않는다. Gate를 기다리기 전에 진행 중 표시를 세워 모든 변경과 Drag를 막는다. Editor 변경이 진행 중인 동안에만 Back / Editor 밖 Navigation을 막고 처리가 끝나면 되돌린다. 이것은 좁은 Navigation 규칙이며 일반 Late Result · 취소 정책의 승인이 아니다. 대기 시간이 항상 짧다고 말하지 않는다.
- **`completed`:** 확인된 의도 상태를 채택하고 그 History 전이를 정확히 한 번 적용한다(Delete / Reorder는 한 항목 추가와 Redo 비우기, Undo / Redo는 한 항목 이동). Save 오류 뒤 `completed`는 P4대로 정상 성공이다. Project와 History가 서로 맞지 않는 중간 상태를 드러내지 않는다.
- **`committedUnverified` / `indeterminate`:** 참조 가능 Media를 보존하고, 보이는 Timeline을 잠그되 확인된 저장 상태로 표시하지 않으며, 정확한 Editor U1 / U2 문구와 `프로젝트 화면으로` Action을 쓴다. Reconciliation이 필요한 동안 프로그래밍 호출을 포함한 모든 변경 진입점을 막는다. 자동 Reload는 없다; 프로젝트 화면으로 돌아가 그 Accepted Load로 갱신하고 기존 Gate 안 Load로 다시 열면 빈 History로 시작한다.

**구현(2026-10-05):**

- `ProjectEditorModel`은 공유 `ProjectLifecycleOperationGate`를 주입받는다(Acquisition 경계와 같은 Instance여야 한다; Release는 주입을 요구). 모든 변경은 Gate 안의 `commitInsideGate`(Expectation `update(from:to:)` → `update` → `observePersistedState(for:)` → D8.0 분류)를 쓰며, 그 앞의 `verifiedPriorInsideGate`가 `observePersistedProject(id:)`의 결과를 `ProjectStateSnapshot`으로 Editor 기준과 비교한다 — 다른 편집은 Save 전, Add / Replace는 Materialize 전.
- 진행 중 표시(`isCommittingMutation`)는 Gate를 기다리기 전에 세워지고(Drop은 동기 `commitReorder()`에서) 처리가 끝나면 내려간다; 그동안 `isNavigationLocked`로 Back을 숨긴다. `completed`일 때만 Project · 선택 · History가 한 번에 바뀐다.
- `EditorReconciliation`(U1, U2, 다시 확인, 찾을 수 없음)은 모든 변경 · Drag · 선택 · Acquisition 진입을 막고, 유일한 Action이 `AppRouter.leaveProjectEditor(_:)`로 Editor Route와 그 위를 제거한다(기존 Route 제거 경계와 Cleanup 예약이 그대로 동작한다). Editor를 떠난 뒤의 Cleanup은 저장소를 읽으며 메모리 상태를 권위로 쓰지 않는다.
- Replace 대상이 저장소에서 사라졌지만 Project는 있는 경우는 Editor 기준과 Prior가 다르므로 "Project 없음"이 아니라 `프로젝트를 다시 확인해주세요`로 정지한다. 대상 전용 안내가 필요한지는 남은 Presentation 질문이다.
- 미리 게시하지 않으므로 Drag를 놓으면 Timeline은 확인된 순서로 돌아간 뒤 `completed`에서 새 순서로 바뀐다; 진행 중에는 선택 변경도 받지 않는다. 이 확인된 순서 복귀 뒤 이동(Snap-back) 표시와 진행 중 Back 잠금은 iPhone 12 확인이 필요하며 기기 Gate는 해결되지 않았다(Simulator UI Test만 실행).
- 남은 것: 기기 검증, 일반 Late Result · 취소 정책, Rollback · Retry.

#### D8.6 `.replacingSaved`의 두 Save

**상태(2026-10-02):** 아래 두 Save 처리는 승인되지 않았고 OD-14 (a) 승인으로 대체되었다(역사 기록으로 보존). 현재 Production 코드는 아직 두 Save를 쓰며 단일 Save Repository API로의 연결은 Pending이다. (2026-10-05 갱신: 연결되었고 두 Save Production 분기는 제거되었다 — D8.5b.)

- **Save 1(`create(B)`):** Prior = "A 그대로 + B 없음", Intended = "A 그대로 + B 완전".
  - 확인된 이전 상태 → D4 Rollback, R4 §3, A와 그 Media 무변경.
  - 확인된 새 상태 → B Commit. Save 2로 진행한다.
  - Commit됨 · 확인 안 됨 또는 미확정 → Save 2를 실행하지 않는다; A와 그 Media를 보존한다; U1 또는 U2.
- **Save 2(`deleteProject(A)`):** B가 확인된 새 상태일 때만 실행한다.
  - Save 성공 → 독립 Read로 A Row 부재를 확인한 뒤에만 A의 Media Directory를 제거한다. 확인할 수 없으면 A Media를 보존한다(A Row가 정말 없으면 다음 시작의 Orphan Recovery가 회수한다).
  - Save 오류 → 독립 Read: A 없음 → 삭제된 것으로 보고 A Media 제거; A 완전히 그대로 → A와 Media 보존; 그 밖 → 미확정으로 보고 A Media 보존.
  - Save 2의 결과와 무관하게 B의 Commit은 성공이다; Save 2 실패를 B의 실패로 안내하지 않는다.
  - A가 남으면 그것은 ADR-033 / ADR-034 V1 Single Saved Project의 Safe Atomic Replacement에서 벗어난 결과다: 사용자는 "마지막 저장 Project를 대체"하기로 확인했는데 A가 Durable Row로 남는다. A는 Durable Row가 참조하므로 STEP 12B Orphan Recovery가 회수하지 않고, 최신 순서 정책상 B 뒤에 가려져 사용자에게 보이지 않으므로 영구적인 숨은 저장 공간이 된다. AGENTS.md의 "Multiple local drafts are supported" Guardrail은 이 결과를 정당화하지 않는다(그 Guardrail과 ADR-033 / ADR-034의 V1 단일 저장 Project 사이의 관계 자체도 소유자가 확인할 사항이다).
  - 처리 선택지(소유자 선택, ADR-034 계약에 대한 결정): (a) 안내 없음 + Log + 자동 재삭제 없음(숨은 A가 영구히 남음); (b) 다음 Select Clips 대체 또는 다음 시작에서 A 삭제를 다시 시도하는 규칙(Durable Project 삭제이므로 새 Cleanup 규칙이며 ADR-034 / ADR-039 개정이 필요); (c) A가 남았음을 알리는 새 안내. 이 ADR은 어느 것도 권장으로 확정하지 않는다.
- **검토 후속 2(2026-10-02; Source 감사 결과는 D8.6a, 결정은 OD-14):** B 생성과 A Metadata 삭제를 하나의 `ModelContext.save()`로 묶고 그 뒤 A의 오래된 Media를 안전하게 정리할 수 있는지 감사한다. 이 ADR은 위 두 Save 설계를 승인하지 않으며 숨은 이전 Project 처리 정책(OD-13)도 선택하지 않는다.
- **관찰된 기존 코드 위험:** 현재 코드는 `deleteProject(A)`가 실패해도 `removeProjectMedia(A)`를 호출하므로 A Row가 지워진 Media를 참조할 수 있다(필수 구현 의존성).
- Operation 전체는 Save 두 번이며 원자적이지 않다; Save 사이에서 멈추면 A와 B가 함께 남는다(Exploratory 관측).

#### D8.6a `.replacingSaved` 단일 Save 감사 결과(2026-10-02)

**상태:** OD-14 (a)와 ADR-033 Revision 1이 2026-10-02에 승인되었다. 이 절의 나머지(D8 판정 연결, 독립 Read 방법, 안내, 아래 Coordinator 순서의 연결)는 Proposed다. 구현: `ProjectRepository.replaceProject(previousID:with:)`(Dedicated `ModelContext`, `autosaveEnabled = false`, 모든 검증 뒤 Insert · Delete · 명시적 Save 한 번; Coordinator 연결 없음). (2026-10-02 갱신: 판정 연결 · 독립 Read · 안내 · Coordinator 연결 가운데 D8.5a P1 · P3 · P8에 적힌 부분은 Accepted — 미구현; 나머지는 Proposed.)

이 절은 검토 후속 2의 Source 감사 결과와, 소유자가 승인한 하나의 결합 Save 실험(2026-10-02, Exploratory)의 결과다. Production 코드는 바꾸지 않았으며 두 Save 설계도, 단일 Save 설계도, OD-13도 승인하지 않는다(감사 · 실험 시점 기준; 이후의 승인 상태와 구현은 위 상태 줄).

**기술적 가능성(Source 근거):**

- `PersistedVlogProject.clips`는 `@Relationship(deleteRule: .cascade, inverse: \PersistedVlogClip.project)`이고 Active와 Pending-deleted Clip Row가 모두 이 관계에 들어 있다(`PersistedVlogProject.init(project:)`가 `durableClips` 전체를 넣는다). 따라서 `modelContext.delete(A)`는 A의 모든 Durable Clip Row를 Cascade 대상으로 만든다(050-D Probe의 `deleteProject` 경계 관측과 일치).
- (감사 시점) `SwiftDataProjectRepository`의 유일한 쓰기 경로는 `saveOrRollback()` 안의 `modelContext.save()`이며, 실패 시 `rollback()` 뒤 새 `ModelContext`로 바꾼다. 같은 Context에 B 삽입과 A 삭제를 쌓고 `save()`를 한 번 호출하는 것은 이 구조로 표현할 수 있다. 구현된 `replaceProject`는 대신 Autosave를 끈 전용 `ModelContext`로 Save한다(위 상태 줄).
- 따라서 "한 번의 명시적 `ModelContext.save()`"는 기술적으로 가능하다. 그러나 Save 호출 하나가 SQLite Transaction 하나나 보편적 Atomicity를 증명하지 않는다. 050-B에서 `create` Save 하나가 SQLite Commit 2개를 쓰는 것이 관측되었고, 050-D Probe는 그중 첫 Commit이 `Z_PRIMARYKEY` Page만 바꾸고 Domain Row는 모두 두 번째 Commit에 있음을 관측했다; 따라서 Commit이 여럿이라는 사실만으로 "A 삭제"와 "B 삽입"이 별도 Domain Commit으로 나뉜다고 볼 수 없다. 결합 Save의 Commit 구조와 경계 상태는 측정됨(Exploratory, 재구성 경계, A ≤ 50 / B ≤ 10 Clip — 아래 결합 Save 실험 결과).

**조기 Save 위험:**

- Production Repository는 `modelContainer.mainContext`를 쓰며 Repository는 실패 뒤 교체 Context에만 `autosaveEnabled = false`를 설정한다. 즉 정상 경로의 Context는 Autosave가 켜져 있다: 결합 Save 실험의 Test Process에서 Production 형태 `mainContext`의 `autosaveEnabled`는 `true`로 읽혔다(그 한 Process에서 읽은 값).
- 따라서 새 API는 (1) 던질 수 있는 모든 Fetch · 검증을 어떤 삽입 · 삭제보다 먼저 끝내고, (2) 삽입 · 삭제 · `save()`를 중단 지점(`await`) 없이 한 동기 구간에서 실행하며, (3) 그 구간의 어떤 오류에도 `rollback()`해야 한다. 그렇지 않으면 Autosave가 B 삽입만 또는 A 삭제만 저장할 수 있다.
- `@Attribute(.unique) id`는 같은 ID 삽입을 오류가 아니라 Upsert로 처리할 수 있으므로 기존 `create`처럼 B ID 중복을 먼저 Fetch로 거부해야 한다.

**승인된 계약과의 관계:**

- ADR-033 "Safe Atomic Project Replacement"는 순서를 정한다: B를 완전히 Persist(6) → B Commit 검증(7) → 승격(8) → 그 뒤에만 A와 A의 Media 제거(9), 그리고 `A failed replacement must never destroy the last valid saved Project.` ROADMAP Phase 5(`A 보존 → … → 검증 → 승격 → 그 뒤 A 제거`)도 같다.
- 단일 Save는 B Persist와 A Metadata 삭제를 같은 Save에 넣으므로 6–9의 순서를 바꾼다. A의 Media는 B 확인 뒤까지 보존할 수 있지만, Save 성공 뒤 B를 확인할 수 없는 경우(Read-back 실패, Domain 변환 실패) A의 Row는 이미 없고, 다음 시작의 STEP 12B Orphan Recovery는 Row 없는 A Directory를 제거한다. 그 경우 B가 실제로 쓸 수 없는 Row라면 마지막 유효 저장 Project가 사라질 수 있다.
- 반대로 현재 두 Save 설계(D8.6)는 6–9의 순서를 지키지만 Save 2 실패 시 숨은 A가 남아 V1 Single Saved Project에서 벗어난다(OD-13).
- **측정되지 않은 가설 — 분할된 결합 Save의 최악 경우:** 만약 결합 Save의 Domain 변경이 SQLite Commit 여러 개로 나뉘고 "A 삭제 + Cascade"가 "B 삽입"보다 먼저 Durable해진 뒤 Process가 멈춘다면 Store에는 A도 B도 없을 수 있다. 그 경우 다음 시작에서 STEP 12B(`ProjectStartupRecoveryCoordinator.recoverProjectExclusively`)는 Row 없는 A와 B Directory를 모두 제거하여 두 Project를 모두 잃는다. 이것은 관측이 아니라 가설이다. 현재 두 Save 설계(D8.6)는 050-D Probe가 재구성한 경계(측정한 경우)에서 "A", "A + B" 또는 "B"만 보였고 "A도 B도 없음"은 보이지 않았다. 이는 실제 Process 강제 종료, 전원 손실, 모든 Save 오류에 대한 보장이 아니며 두 Save 설계가 모든 실패에 안전하다는 주장도 아니다.
- **결합 Save 실험 결과(2026-10-02, Exploratory — `docs/evidence/phase-06/adr-050d-combined-save-report.md`):** 격리된 Store에서 Autosave를 끈 하나의 `ModelContext`에 B 삽입과 A 삭제를 쌓고 `save()`를 한 번 호출했다(Small: A 5 Clip 중 Pending 1 → B 3; Large: A 50 Clip 중 Pending 10 → B 10; 각 3 Run). 매번 SQLite Commit은 2개였고 첫 Commit은 `Z_PRIMARYKEY` Page 하나만, 둘째 Commit은 B 삽입과 A · A의 모든 Clip Row(Pending 포함) 삭제를 함께 썼다. 재구성한 경계는 Save 직전 · 첫 Commit 직후 · 둘째 Transaction 중간이 모두 "A만", 둘째 Commit 직후가 "B만"이었고 "둘 다", "둘 다 없음", 부분, 읽기 불가는 나오지 않았다; 24개 경계 모두 `quick_check` = `ok`, 소유 없는 Clip Row 0. 이것은 측정한 경우의 재구성 경계이며 실제 Process 강제 종료, 전원 손실, 모든 Save 오류 동작의 보장이 아니다. 같은 실험에서 Production 형태 `mainContext`의 `autosaveEnabled`는 `true`로 읽혔다. 실험은 별도 Context에서 직접 삽입 · 삭제했으므로 제안된 `replaceProject` API나 Autosave가 켜진 `mainContext`와의 상호작용을 시험한 것이 아니다.
- 결론: 단일 Save는 결합 Save가 Crash 경계에서 이전 또는 새 상태만 남길 때에만 V1 단일 저장 Project 불변식을 강화한다; 위 실험은 측정한 경우에 그렇게 관측했지만 보장은 아니다. 단일 Save는 어떤 경우에도 ADR-033 Safe Atomic Replacement의 6–9 순서 문구 개정이 필요하다. 이 감사의 전제(Durable Journal · Durable Operation 기록을 도입하지 않음) 안에서는 두 계약을 동시에 완전히 만족하는 설계를 찾지 못했다. 전제 밖의 대안으로는 B 삽입과 같은 Save에서 A에 Superseded / Tombstone 표시를 남기는 Schema 추가가 있으나 이는 Durable 기록이므로 이 감사가 제안하지 않는다. 어느 쪽을 우선할지는 소유자 결정이다(OD-14).

**단일 Save를 택할 경우의 최소 설계(Proposed):**

- Repository API: `replaceProject(previousID: UUID, with project: VlogProject) throws`.
  1. B ID가 Store에 없음을 Fetch로 확인(있으면 `duplicateProject`).
  2. A Row를 Fetch(없으면 `projectNotFound`; 아래 Coordinator가 처리).
  3. Save 전 사전 검증: 삽입할 `PersistedVlogProject(project:)`를 `domainValue()`로 되돌려 Intended B와 같은지 확인(Mapping 오류를 Save 전에 거부; 저장 장치 오류는 막지 못함).
  4. 같은 동기 구간에서 `insert(B)`, `delete(A)`, `saveOrRollback()`.
  - (구현으로 대체됨, 2026-10-02) 구현된 `replaceProject`는 A를 먼저 Fetch하고, Autosave를 끈 전용 `ModelContext`에서 Insert · Delete · `save()`를 한 번 실행하며, 오류 시 그 전용 Context만 Rollback한다; 위 1–4는 감사 시점의 제안이다.
- (2026-10-02: 아래 Coordinator 순서 가운데 D8.5a P8에 적힌 단계만 Accepted — Gate 안 A 재확인, Save 전 B 파일 · Metadata 확인, `replaceProject`, 관측 · 분류, `completed`이고 A 부재 확인 시에만 A Media 제거; 미구현, 두 Save 분기는 구현 시 제거. 2026-10-05: 구현 — D8.5b. D4 Rollback 부분은 OD-4 미결이며 이번 Slice는 D8.5a P6의 임시 경계를 따른다.) Coordinator 순서(Lifecycle Gate 안): A가 여전히 같은 ID의 현재 저장 Project인지 재확인 → B Media Materialize(D4 Rollback 규칙) → 동기 구간 직전에 모든 B File의 존재 확인(현재 `compose`의 Commit 뒤 `fileExists` 검사를 Save 앞으로 옮김; 없으면 Save 없이 D4 Rollback) → `replaceProject` → D8.2 독립 Read로 "B 완전 + A 없음" 확인 → 확인된 경우에만 A의 Media Directory 제거 → Workspace Discard.
- Materialize에는 중단 지점이 있고 Home 삭제 · Editor `update`는 아직 Gate 밖이므로(D6 의존성), A의 존재 판정은 `replaceProject` 자신의 Fetch(2단계)가 최종 권위다. 그 Fetch가 `projectNotFound`를 던지면 아무것도 삽입 · 삭제되지 않았다. **대상 처리 제약(2026-10-02, 소유자 지시):** 이때 대체를 B만 만드는 생성으로 조용히 바꾸지 않는다; Target 무효화(D6)로 처리하여 B 후보를 D4 규칙으로 정리하고 Operation을 끝낸다. B만 생성하는 Fallback은 소유자가 따로 승인할 때만 쓴다.
- Save 성공 뒤 B File이 없다고 확인되면 "Commit됨 · 확인 안 됨"으로 처리하고 파괴적 정리를 하지 않는다(현재 `compose`의 B 삭제 경로를 쓰지 않는다).
- 현재 `ProjectsEntryModel`은 대체 대상 ID를 Gate 밖에서 미리 읽는다(`savedProjectID`); Lifecycle Gate 안에서 재확인한다. A가 그 사이 없어졌거나 다른 Project가 현재 저장 Project가 되었다면 Target 무효화(D6)로 처리하여 Operation을 끝내고 Retry를 제공하지 않는다(안내는 OD-8 / U4와 같은 범주의 소유자 선택). B만 생성하는 Fallback은 소유자의 별도 승인 없이는 쓰지 않는다.
- Save 결과 판정은 D8 그대로이며 Prior = "A 그대로 + B 없음(새 ID 부재 포함)", Intended = "B 완전 + A 없음"이다.

| Save 결과(단일 Save) | Metadata | Media | 사용자 결과 |
| --- | --- | --- | --- |
| Target 무효(Gate 재확인 실패 또는 `replaceProject`의 `projectNotFound`) | 무변경(아무것도 삽입 · 삭제하지 않음; B만 생성하는 Fallback 없음) | B 후보 D4 규칙으로 정리; A 상태 그대로 | D6 Target 무효화, `다시 시도` 없음, 안내는 OD-8 / U4 범주의 소유자 선택 |
| 사전 Fetch · 검증 실패(Save 전) | 무변경(아무것도 삽입 · 삭제하지 않음) | B 후보 D4 Rollback; A 무변경 | R4 §3(확인된 이전 상태) (2026-10-02: D4 Rollback은 OD-4 미결; 이 Save 전 실패 경로의 처리 · 안내는 D8.5a P6 범위 밖이며 미결) |
| Save 오류 → 확인된 이전 상태 | A 그대로, B 없음 | B 후보 D4 Rollback; A Media 보존 | R4 §3, `다시 시도` 가능 (2026-10-02: 이 행은 Proposed; 이번 Slice는 D8.5a P6 — Rollback · Retry 없음, 확인 전용 문구) |
| Save 오류 → 확인된 새 상태 | B 완전, A 없음 | B Media 보존; A Row 부재 확인 뒤 A Media 제거 | 정상 완료 |
| Save 성공 → 확인됨 | B 완전, A 없음 | B 보존; 확인 뒤 A Media 제거 | 정상 완료 |
| Save 성공 → 확인 불가 | B Durable(Save 성공), A Row 없음(가정) | B · A Media 모두 Process 안에서 보존; 다음 시작에서 Row 없는 A Directory는 STEP 12B가 제거 | U1(Commit됨 · 확인 안 됨) |
| 미확정(Save 오류 + 모순 · 읽기 실패, 예: "A 없음 + B 없음" 또는 "A + B") | 알 수 없음 | Process 안에서는 B · A Media 모두 보존, 파괴적 정리 없음; 다음 시작에서 STEP 12B는 그때 Row가 없는 Directory를 제거하므로 "A 없음 + B 없음"이었다면 A와 B를 모두 잃는다 | U2, `다시 시도` 없음 |
| Save 전 Crash | A 그대로 | Row 없는 B Directory는 다음 시작에서 제거 | 이전 상태 |
| Save 도중 Crash · 부분 Commit(측정한 경우의 재구성 경계에서는 관측되지 않음; 보장 아님) | "A 없음 + B 없음" 또는 "A + B" 가능 | 다음 시작에서 STEP 12B가 Row 없는 Directory를 제거: "A 없음 + B 없음"이면 A와 B 모두 손실; "A + B"면 둘 다 보존(숨은 A) | 마지막 유효 Project 손실 가능 |
| Save 뒤 · A Media 제거 전 Crash | B 완전(Durable), A 없음 | Row 없는 A Directory는 다음 시작에서 제거 | B가 저장 Project |

- Crash / Relaunch는 기존 STEP 12B와 ADR-047 Workspace Sweep만으로 위 표처럼 수렴하며 Durable Journal을 쓰지 않는다. "Save 도중 Crash · 부분 Commit" 행은 결합 Save 실험의 재구성 경계(측정한 경우)에서 관측되지 않았지만, 실제 강제 종료 · 전원 손실 · 더 큰 규모에서 생기지 않는다는 보장은 아니다.

**050-B Metadata Estimate와의 관계:**

- Accepted 050-B는 Save별 합이며 `.replacingSaved`를 Save 2회(`R = n`, `R = D_replaced`)로 계산한다. 단일 Save에 같은 Formula를 적용하면 `W_save` 한 번이 빠져 196,608 B 작아진다. 결합 Save는 측정됨(Exploratory): 관측 WAL 증가 65,920 B 대 두 Save Estimate 397,312 B(A 5 · B 3), 86,520 B 대 423,936 B(A 50 · B 10). 이 비교는 상수를 바꾸지 않으며 상한을 증명하지 않는다.
- 제안: 단일 Save를 택하더라도 Accepted 050-B의 두 Save 계산(`ImportMetadataOperation.replacingSaved`)을 그대로 쓴다(보수적). 상수나 Accepted 계산을 바꾸지 않는다; 바꾸려면 별도 소유자 결정이 필요하다.

**OD-14 제안 권장(Proposed — 소유자 결정 전, 승인 아님):** (a) 단일 Save. 근거: 측정한 경우에 결합 Save의 Domain 변경은 하나의 SQLite Transaction에 있었고 재구성 경계는 "A만" 또는 "B만"이었다; 두 Save 설계에는 Save 2 실패 시 숨은 A(OD-13)라는 구조적 이탈이 남는다. 남는 위험과 완화: 결합 Save가 성공했는데 B를 확인할 수 없거나 B가 실제로 쓸 수 없는 Row라면 A Row는 이미 없고 다음 시작에서 STEP 12B가 A Directory를 제거하므로 마지막 유효 저장 Project를 잃는다 — 이 잔여 경우를 소유자가 알고 받아들여야 하며, Save 전 B File 존재 확인과 B Metadata 변환 확인으로 줄이고, A Media는 확인 뒤에만 제거한다; 실제 강제 종료 · 전원 손실 · Process 안 Save 오류는 측정되지 않았다. (b)를 택하는 것도 정당한 소유자 결정이다.

**(a)를 택할 경우 필요한 ADR-033 "Safe Atomic Project Replacement" 개정 문구(제안):**

- 현재 5–9:
  - `5. Project B와 Clip Metadata를 만든다.`
  - `6. Project B를 완전히 Persist한다.`
  - `7. B의 Commit 성공을 검증한다.`
  - `8. B를 새 단일 저장 Project로 승격한다.`
  - `9. 그 뒤에만 Project A와 A의 App-managed Editing Media를 제거한다.`
- 제안 5–9:
  - `5. Project B와 Clip Metadata를 만들고, 저장 전에 B의 모든 Media 존재와 Metadata 변환을 확인한다.`
  - `6. Lifecycle Gate 안에서 A가 여전히 대체 대상인지 다시 확인한 뒤, B의 삽입과 A Metadata의 삭제를 하나의 Persist로 함께 Commit한다.`
  - `7. 독립 읽기로 B의 완전한 Commit과 A Metadata의 부재를 검증한다.`
  - `8. 검증되면 B가 새 단일 저장 Project다.`
  - `9. 그 뒤에만 A의 App-managed Editing Media를 제거한다; 검증할 수 없으면 A의 Media를 제거하지 않고 ADR-050 050-D D8의 결과 처리를 따른다.`
- 추가 문장(제안): `Commit 전에 실패한 대체는 A를 그대로 보존한다. 결합 Persist가 Commit된 뒤에는 A Metadata가 이미 제거되었으므로 그 뒤의 검증 실패는 대체 실패가 아니라 ADR-050 050-D D8의 확인 실패로 처리한다.`
- **불변식 범위 축소(개정):** `A failed replacement must never destroy the last valid saved Project.`의 "failed replacement"를 결합 Persist가 Commit되기 전의 실패로 한정한다. 이것은 명확화가 아니라 승인된 안전 불변식의 범위를 줄이는 개정이다: 결합 Persist가 Commit된 뒤 B를 확인할 수 없거나 B가 쓸 수 없는 Row인 경우 현재 문구로는 A를 파괴하면 안 되는 실패한 대체이지만, 개정 문구로는 대체 실패가 아니며 A는 다음 시작에서 사라진다. 소유자는 이 잔여 경우를 명시적으로 받아들여야 한다.
- ROADMAP Phase 5의 `A 보존 → B Workspace → Materialize → Persist → 검증 → 승격 → 그 뒤 A 제거` 요약도 같은 순서로 맞춘다.

**남은 불확실성과 가장 작은 확인 방법:**

- **OD-14 결정 전 입력:** 결합 Save의 SQLite Commit 구조, 경계 상태, WAL 증가를 WAL Prefix 방법으로 측정했다(위 실험 결과, 2026-10-02). 남은 불확실성은 실제 강제 종료 · 전원 손실 · Process 안 Save 오류와 측정 규모 밖의 동작이다.
- `mainContext.autosaveEnabled`: 결합 Save 실험의 한 Test Process에서 `true`로 읽힘(측정됨). 구현된 `replaceProject`는 Autosave를 끈 전용 Context를 쓰므로 이 값에 의존하지 않는다(별도 고정 Test 없음).
- Save 오류 경로: `ModelConfiguration(allowsSave: false)`로 연 Store에서 `save()`가 던지는지 확인하는 Unit Test(Save 도중 실패의 증거는 아니며 그렇게 표시).

**구현 · Test 계획(1–3과 5는 OD-14가 단일 Save를 택한 경우에만; 4는 결정 전 입력):**

1. `ProjectRepository.replaceProject(previousID:with:)`와 `SwiftDataProjectRepository` 구현, `InMemoryProjectRepository` 대응, DEBUG `UpdateFailingProjectRepository`(`AppEnvironment.swift`)와 Test Double의 전달 구현.
2. Unit Test(격리된 On-disk Store): 성공 시 B 완전 · A와 A의 Active / Pending Clip Row 모두 없음; B ID 중복 → 아무것도 바뀌지 않음; A 없음 → 정의된 오류이며 B 미삽입; 사전 검증 실패 → 무변경; `allowsSave: false` Store에서 오류 → Rollback 뒤 A 그대로.
3. Coordinator Test: Gate 안 대상 재확인, `projectNotFound` → Target 무효화이며 `create(B)` Fallback 없음, 확인 전 A Media 미제거, 확인 불가 · 미확정에서 A · B Media 보존, `.replacingSaved` 외 경로 무변경.
4. 위 WAL Prefix 측정은 OD-14 결정 전 입력이며 2026-10-02에 수행했다(`adr-050d-combined-save-report.md`, Exploratory).
5. 기존 Phase 5 `compose` 경로 교체 시점은 050-D의 Post-save Media 삭제 결함 수정과 함께 정한다.

#### D8.7 Startup Recovery 감사와 필요한 변경

- **현재 보장(코드 확인, `ProjectStartupRecoveryCoordinator`):** Project Directory 열거 실패 → 전체 중단; Project Row 읽기 오류 → 그 Project 건너뜀; Media 제거 직전 재검증 읽기 실패 → 보존; Live Editor Project 건너뜀; Durable Clip(Active + Pending)이 ID나 Path로 참조하는 Media 보존. 읽기 오류를 "Row 없음"으로 보지 않는다. (2026-10-06 갱신: Project Row 목록 읽기가 실패하면 그 Pass의 모든 Project Directory를 건너뛰고, Row 0개 + Canonical Directory ≥ 1이면 Directory와 참조 없는 Media 제거를 둘 다 건너뛴다 — ADR-039 STEP 12B Implementation Note 아래 "OD-12 최소 빈 Store 보호".)
- **구분:** Committed Project Media는 `Projects/<P>/Media/<C>.mov`이며 Durable Row 참조 여부로 판정한다. Abandoned Workspace Artifact는 `ProjectWorkspace/<op>/`이며 ADR-047에 따라 Live Registry에 없으면 Discardable이다. 미확정 Operation의 Workspace는 어떤 Durable Row도 참조하지 않으므로 다음 시작에서 회수되어도 Committed Media가 손실되지 않는다.
- **미확정 결과의 해결:** 다음 시작에서 Store를 읽을 수 있으면 Row가 있는 Project의 Media는 참조로 보존되고 Row가 없는 Canonical Directory는 Orphan으로 제거된다. 이는 그 시점의 Durable 상태와 일치하므로 Journal 없이 정확하다. ADR-047 No Resume는 바뀌지 않는다.
- **필요한 변경(ADR-039 STEP 12B 개정 제안):** Store는 열리지만 비어 있는 경우(예: Store File이 없어져 새로 만들어진 경우)는 현재 "Row 없음"과 구분되지 않아 모든 Canonical Project Directory가 Orphan으로 제거될 수 있다. 이는 "읽을 수 없거나 바뀐 Store를 비어 있는 것으로 보지 않는다"는 원칙과 충돌한다.
  - (i) 권장: Project Row가 0개인데 Canonical Project Directory가 1개 이상이면 그 실행의 Orphan Directory 제거를 모두 건너뛰고 Log한다. 새 Durable 상태가 없다. 단점은 Project가 하나도 없을 때의 진짜 Orphan이 남아 저장 공간을 쓰는 것이다(데이터 손실은 아님). 한계: 완전히 빈 Store만 막는다; 비어 있지 않지만 일부 Row가 빠진 교체 · 되돌려진 Store는 그 Project들의 Directory를 여전히 Orphan으로 제거하므로 위 원칙을 완전히 만족하지 않는다. (2026-10-06 갱신: 결정된 최소 보호는 Directory 제거만이 아니라 참조 없는 Media 제거도 함께 건너뛴다 — ADR-039 STEP 12B의 OD-12 항목 참조.)
  - (ii) 대안: Mellow Root에 Store 식별 Marker를 두어 Store 교체를 감지한다. 비어 있지 않은 교체 Store도 감지할 수 있지만(같은 Store 안에서 Row가 사라진 경우는 감지하지 못한다) 새 Durable 상태이므로 더 큰 개정이다.
- **범위 밖 관찰:** `MellowModelContainer.shared`는 Store를 열지 못하면 `fatalError`로 끝난다. 파괴적 정리는 일어나지 않지만 App을 쓸 수 없다. 이 ADR은 이를 다루지 않는다.

#### D8.8 Architecture 영향

- Durable Journal, Resumable Import, Background Continuation을 도입하지 않는다. 미확정 Operation의 기록은 Process 안 Memory에만 있고 Process가 끝나면 D8.7의 기존 Recovery가 Durable 상태로 정리한다. ADR-047 No Resume는 바뀌지 않는다.
- 필요한 개정: (1) Commit 경계(050-D D1–D3, 서두의 예외), (2) ADR-039 STEP 12B의 빈 Store 보호(D8.7), (3) 새 안내 U1–U4(R4 §3 / §4 문구는 바꾸지 않는 추가 Presentation).
- Storage Estimate와 Reserve(050-A / 050-B / 050-C)는 이 절과 독립이다.

---

## Decision Unit 050-E — `ProjectMediaTransfer` 잔여 File(연기, 승인 요청 없음)

**Unit Status:** 승인 요청 없음. 별도 후속 결정으로 기록한다.

- Transfer 복사 뒤 Adopt 전에 Process가 끝나면 `tmp/ProjectMediaTransfer/`에 Mellow 소유 복사본이 남을 수 있다. 현재 어떤 Startup 경로도 이를 회수하지 않는다.
- ADR-039 STEP 12B Implementation Note는 `tmp/ProjectMediaTransfer`를 열거조차 하지 않는다고 하고 ADR-047은 "tmp 미열거"를 이미 보장된 속성으로 적는다. 이 Directory의 Startup Cleanup은 승인된 Cleanup 규칙의 확장이며 이 ADR은 그것을 제안하지 않는다.
- UUID 형태의 이름만으로는 소유 증거가 되지 않는다. 후속 결정은 소유 증거(예: Operation Registry 또는 Manifest), Containment, Symlink, Active-use(Startup Maintenance는 Fire-and-forget이고 Picker Transfer는 Lifecycle Gate 밖이다), Registry 수명(Closure 반환부터 Adopt 완료 또는 제거까지)을 정해야 한다.
- 영향: 남은 복사본은 Occupancy로 Capacity에 반영되므로 Estimate 계산은 바뀌지 않는다. 그러나 ROADMAP Phase 6 Exit Criteria의 Recovery-safe Cleanup Integration 준비는 이 후속 결정(또는 System tmp 정리에 맡긴다는 명시적 결정)이 없으면 완전하지 않다.

---

## 구현 상태(Step 5B(2026-10-02))

- 구현됨(순수, 연결 없음): `MellowApp/Core/Projects/Import/ImportStorageEstimator.swift` — `ImportStoragePolicy`(Accepted 상수), `ImportStorageEstimator.normalizedOutput` / `remainingOutputBytes` / `metadata` / `requirement` / `check`, `ImportWriteFailureClassifier`(2026-10-05 명확화: 구현되었고 연결되지 않은 Typed 분류일 뿐이며 그 Logging · Presentation은 별도로 승인된 정책이 아니다 — 050-C 검사 경계와 함께 Proposed); Test `MellowTests/ImportStorageEstimatorTests.swift`.
- 구현됨(2026-10-05, 순수, 연결 없음): Accepted Set 조합 `ImportStorageWorkSet` / `ImportStorageOperation` — Preflight의 Accepted 항목과 실제 정규화 계획을 기존 Estimator 입력으로 바꾼다(Ready = 0, 정규화 = Accepted 영상 정책 + 계획 기준 Audio 대응, 쓰인 출력 = 0, 모든 정규화 항목에 자기 계획 필수); Metadata는 만들기 · `.replacingSaved`(보수적 두 Save) · Add · Replace를 Durable Row 수(Pending-deleted 포함)로 계산하며 출력 · Metadata · Reserve는 따로 유지된다. 이것은 계산일 뿐이며 C1 / C2 / C3의 연결 · 실행 시점 · Presentation을 승인하지 않는다.
- 정확한 축약 유리수 / Overflow 검사 정수 계산이며 Floating Point를 쓰지 않는다; Ready 항목과 이미 쓰인 출력은 0을 더하고, 출력 · Margin · Metadata · Reserve를 따로 볼 수 있다.
- 연결되지 않음: PhotosPicker / `ReceivedVideoFile`, Normalizer, Repository, Coordinator, UI, 기존 Phase 5 Admission. 검사 경계 연결과 Presentation은 Proposed다.

## 미해결 의존성(Import Storage Gate를 닫기 전 필요)

- 050-A: `S_audio` Inspector Fact와 Estimator 연결. (2026-10-05: Inspector Fact와 순수 Estimator 입력 대응 구현 — 실제 검사 경계 연결은 050-C 결정 뒤; 측정 범위 질문은 OA-4 명확화로 해결.)
- 050-D 검토 후속 2: `.replacingSaved` — OD-14 (a) Accepted와 ADR-033 Revision 1(2026-10-02), 결합 Save 측정(Exploratory), Repository API `replaceProject(previousID:with:)` 구현 · Test 완료; Coordinator 연결, D8 결과 판정, 확인 방법(OD-10), 안내는 Pending. (2026-10-02 갱신: OD-10 구현 정책 Accepted · `observePersistedState(for:)` 구현; 연결은 Pending.)
- 050-B(선택, Gate를 막지 않음): Operation 도중 Checkpoint, 210 Row를 넘는 큰 기존 Store / WAL(Store 크기 효과), 동시 Reader 조건의 추가 Metadata Evidence. 이 조건들은 Accepted Estimate 밖이며 아래 필수 Integration Gate와 구별된다.
- 050-C: C0a 구현, U의 신선도와 Purgeable 공간 동작 확인.
- 050-D: D8 Save Outcome 판정 구현(독립 Read, 비교, 결과별 처리); `.replacingSaved`에서 A 삭제 실패에도 A Media를 지우는 기존 코드 수정(2026-10-02 수리됨 — D8.0 "Save 뒤 Media 보존 수리"); ADR-039 STEP 12B 빈 Store 보호 개정; Process 안 Save 오류 뒤의 Durable 상태 확인(Crash 경계 Probe는 Save 단위 PRIOR / NEW만 관측했다; 오류를 던진 Save, Commit 뒤 오류, 전원 손실, `synchronous` 설정은 미확인 — `docs/evidence/phase-06/adr-050d-persistence-atomicity-report.md`; 가정이 확인되지 않으면 대안은 Save 오류 뒤 새 Context로 다시 읽은 Durable 상태로 Rollback / 보존을 정하는 Gate이며 이는 소유자 결정 후보다); D3 Post-commit 처리와 D4 Rollback 구현, D6의 Lifecycle Gate 적용(Project 삭제, Editor Add / Replace)과 Row 없는 Project Directory 재생성 방지, Disk Full 중 Save의 All-or-nothing 확인. (2026-10-02 갱신: D6의 Gate 적용과 Directory 재생성 방지는 구현되었다 — D6 구현 항목; 나머지 항목은 그대로 남는다.)
- 050-E: 후속 결정.
- 필수 Integration Gate(통과 주장 없음):
  - 실제 System PhotosPicker Transfer(iPhone 12): Provider File 위치 · Volume · 해제 시점 · Clone 여부, `.current` Encoding.
  - 실제 Source: 4K30 SDR, 4K60 HDR / Dolby Vision, 1080p60, Phase-5-ready Camera Clip, Portrait Aspect Mismatch, 고Detail / 고움직임, 저조도 Noise, AAC Passthrough(Stereo 및 2 Channel 초과), non-AAC `audioTranscode`.
    - 미검증 재생 관측(2026-10-05, 소유자 보고): Mellow 재생이 약간 작게 들렸다고 보고되었으나 비교는 결론이 나지 않았다. 원인은 정해지지 않았고 `S_audio`와 연결하지 않으며 Gain 변경은 없다; 실제 Source 검증에서 확인할 항목이다.
  - Low-storage: C0–C3 / CR 부족, Runtime Disk Full, 공간 확보 뒤 Retry, Replace 보존, U의 신선도.
  - Rollback-to-Workspace: 부분 Materialize, Save 실패, Restoration 실패, Mixed Set Retry 성공; Post-commit 확인 실패에서 Media 보존.
  - Device: Workspace Sweep End-to-end(Attempt 하위 Directory 포함).

## 소유자 선택

| ID | 제안 선택 | 기존 승인 규칙 / 새 정책 | 근거와 불확실성 | 의존하는 미해결 작업 | 지금 독립 승인 가능 |
| --- | --- | --- | --- | --- | --- |
| OA-1 | `R_video = 7,500,000 B/s` | 새 정책(ADR-024 Formula 공백) | 관측 Logical 최대 7,450,709 B/s; 합성 · 미측정 범주 다수; 상한 아님 | 없음(실제 Fixture로 재검토 권장) | **Accepted** |
| OA-2 | `m = 1/2` | 새 정책 | 측정에서 유도하지 않음; Run 간 8.5% 변동만 관측 | 없음 | **Accepted** |
| OA-3 | `C_out = 2 MiB` | 새 정책 | 관측 최대 1,006,513 B(≤ 38 MB 출력) | 없음 | **Accepted** |
| OA-4 | Passthrough `S_audio`; Transcode `R_tx = 32,000 B/s` + `3136/48000 s` | 새 정책 | `S_audio`는 정확한 Source 값; `R_tx`와 Priming 여유는 측정되지 않음 | `S_audio` Inspector Fact | **Accepted**(Inspector 연결은 Pending) — **2026-10-05: Inspector Fact 구현(`audioPayload`, 정규화와 같은 Track · 읽기 범위); 미결 질문(Proposed 아님 · 결정 필요): 합성 AAC(Priming 정보 없음)에서 Source 저장 21,320 B, Reader 전달(= 측정) 21,080 B, 정규화 출력 저장 21,320 B로 측정이 출력보다 240 B(Priming Packet 2개) 작았다; Encoder가 만든 AAC에서는 세 값이 같았다. 실제 iPhone / Photos AAC에서의 차이는 확인되지 않았다** — **명확화(2026-10-05, 사용자 승인 — Byte 범위만): `S_audio = max(선택된 Source Audio Track의 저장 Sample Data Byte, 정규화와 같은 Passthrough Reader가 전달하는 압축 Sample Data Byte)`; 두 값은 같은 선택 Track을 설명해야 하고 둘 다 성공 · 유효해야 하며, 어느 하나라도 없거나 무효이거나 Overflow면 미측정(0이나 다른 값으로 대체하지 않음, Passthrough 추정은 Fail-closed); 구현은 한쪽이 0이고 다른 쪽이 양수인 경우를 모순(무효)으로 보아 미측정으로 처리하고 양쪽 모두 0은 빈 Track의 유효한 0으로 본다; 보수적 정책 입력이며 증명된 출력 크기 상한이 아니다. 위 관측(21,320 / 21,080 / 21,320 B)은 그대로 보존되며 이 규칙의 `S_audio`는 21,320 B다. 구현됨(연결 없음)** |
| OB-1 | `W_op = Σ_saves (W_save + W_row × R_s)`, `W_save = 196,608 B`, `W_row = 512 B` | 새 정책(경험적 관측 + 정책 Margin) | 측정점(D ≤ 200, n ≤ 10, Store ≤ 210 Row) 안 관측 최대값 대비 약 1.33배 / 1.57배; Store 크기 효과는 별도 항 없음; 도중 Checkpoint · 큰 Store · 동시 Reader 미측정; 상한 아님 | 없음(위 미측정 조건은 Estimate 밖이며 Reserve가 덮는다고 보장하지 않음; 초과 시 Runtime 쓰기 실패 처리) | **Accepted** |
| OC-1 | Volume별 Occupancy / Additional 검사, 경계 C0 / C0a / C1 / C2 / C3 / CR, Fail-closed | ADR-024 적용 + 새 정책 | Capacity 값의 신선도 미증명 | C0a 구현; 경계 연결 | 계산 정책(Volume별 계산 · Fail-closed) **Accepted**; 경계 C0 / C0a / C1 / C2 / C3 / CR 연결은 Proposed |
| OC-2 | `Reserve_import = 256 MiB` | 새 정책(ADR-024: 0 아님) | 측정에서 유도하지 않음; 측정되지 않은 위험을 덮는다고 보장하지 않음 | 없음 | **Accepted** |
| OC-3 | 초기 부족 = R4 §4; Attempt 중 부족 = R4 §3; CR 부족 = R4 §3 재표시 + Source 보존 | §4 / §3은 기존 승인 규칙; 그 적용 경계는 해석 | Attempt 중 / CR 부족에서 원인이 저장 공간임을 안내하지 못함 | OD-4(Ready Source 보존은 Rename-back이 있어야 성립) | 예(OD-4와 함께; 대안 선택 시 R4 개정) |
| OC-4 | Phase 5 Admission 변경(256 MiB, 크기 미확인 거부, C0a)과 연결 단계 적용 | Phase 5 Gate 변경 | — | Phase 6 경로 통합(Task 23) | 예 |
| OC-5 | "Picker Transient 복사본" = Mellow 소유 Transfer 복사본 | 기존 문구의 해석 | Provider File 동작 미관측 | Picker Integration Gate | 예 |
| OC-6 | Accepted Set 이전 Transfer · Adopt 실패의 Phase 6 Presentation | UX 결정(승인 문서에 없음) | — | 없음 | 별도 결정 |
| OD-1 | Durable Commit = Save 성공; Read-back 실패는 Post-commit(050-D D1) | **ADR-037 STEP 11 Note · ADR-040 §9 · ADR-047 Ownership · ARCHITECTURE Commit 경계의 개정 제안** | Crash 경계에서는 Save 단위 PRIOR / NEW만 관측(첫 Commit은 `Z_PRIMARYKEY`만); 오류를 던진 Save · Commit 뒤 오류 · 전원 손실은 미확인 | 개정 문구; Process 안 Save 오류 뒤 Durable 상태 확인; Integration Test | 예(개정으로서) — **2026-10-02: D8.0 분류 규칙에 담긴 Save / 확인 결과 의미만 Accepted; 나머지(Editor Reload 등)는 Proposed** — **2026-10-02: Editor 처리는 D8.5a P2로 Accepted(미구현)** |
| OD-2 | Post-commit 확인 실패 = "Commit됨 · 확인 안 됨": Media / Row 보존, Editor Reload, A 보존(050-D D3) | **같은 승인 문구의 개정 제안**(현재 코드와도 다름) | D2 Trace | OD-1; 구현 | 예(개정으로서) — **2026-10-02: D8.0 분류 규칙에 담긴 Save / 확인 결과 의미만 Accepted; 나머지(Editor Reload 등)는 Proposed** — **2026-10-02: Editor 처리는 D8.5a P2로 Accepted(자동 Reload 없음, 모든 변경 차단, 프로젝트 화면으로 돌아가 다시 열기); 미구현** |
| OD-3 | U1(Commit됨 · 확인 안 됨) · U2(미확정) 안내와 Action(050-D D8.5); 읽을 수 없는 B Row = 미확정 | 새 UX | 기존 `저장되지 않았어요` / `만들지 못했어요` / `그대로 있어요` 사용 불가 | OD-2, OD-9 | OD-2 · OD-9 뒤 — **2026-10-02: U1 / U2의 Editor · Select Clips 정확한 문구와 Action이 D8.5a P3로 Accepted(미구현); "읽을 수 없는 B Row = 미확정" 일괄 규칙은 승인되지 않음(D8.0 유지)** |
| OD-4 | Pre-commit Rollback-to-Workspace(Ready Rename-back, 정규화 출력 제거)(050-D D4) | Task 13 / 14와 ADR-047 Boundary F의 해석 | Filesystem 실패 시 Retry 불가 | 구현 | 예(Task 14 해석 확인 필요) — **2026-10-02: 미결 유지; 이번 Slice는 D8.5a P6의 임시 경계(Rollback 없음)** — **2026-10-05: D7a 1항으로 Accepted(미구현) — Save 시도 전 실패 · 취소와 `priorConfirmed`에서만 Rollback, Ready 복원 · 정규화 출력 제거 · 확인; D4 4항은 Proposed** |
| OD-5 | U3: Restoration · 정리 실패(확인된 이전 상태, `다시 시도` 없음) 안내(050-D D8.5) | 새 UX(R4 §3 외부 Source 무효와 구별) | "저장되지 않았어요"는 확인된 이전 상태에서만 | OD-4, OD-9 | OD-4 뒤 — **2026-10-05: 복원 · 정리 실패 안내는 D7a 5항으로 결정(Commit되지 않았음이 확정된 경우에만, Retry 없음); Retry 시점 Source 무효 안내는 미결** |
| OD-6 | 취소 경계: Save 직전까지 받고 Save 성공 뒤 취소는 성공(050-D D5) | R4 §2 적용 | — | 없음 | 예 — **2026-10-05: D7a 3항으로 Accepted(미구현)** |
| OD-7 | Target 무효화: Retry 없음, Project Directory 재생성 금지, Late Result 폐기(050-D D6) | Task 15 적용 + 새 규칙 | — | Lifecycle Gate 적용 구현 | 예 — **2026-10-02: Gate 적용 · Materialize 전 Target 재확인(Directory 재생성 금지)만 직렬화 전제조건으로 구현; Retry · Late Result · 안내 결정은 미승인** — **2026-10-05: 감지 · 거부 · 후보 정리는 D7a 4항으로 Accepted(미구현); Late Result 폐기는 일반 정책과 함께 미결** |
| OD-8 | U4: Target 무효 안내(살아 있는 Editor의 Add / Replace); 삭제된 Project는 안내 없음(050-D D8.5) | 새 UX | — | OD-7 | OD-7 뒤 — **2026-10-02: Gate 적용 구현은 Target 무효 시 기존 `addFailed` / `replaceFailed` 안내(재시도 · "그대로" 문구)를 임시 재사용한다 — 이 제안과 어긋나는 알려진 차이이며 결정은 Pending** — **2026-10-05: Select Clips 대체 Target 무효 안내만 D8.5b로 결정; Editor U4는 미결** — **2026-10-05: Editor의 Project 없음 · 다시 확인 정지 안내는 D8.5c로 결정(살아 있는 Editor에서의 별도 U4 문구는 쓰지 않음)** |
| OD-9 | Save Outcome 판정: Save 오류 · 확인 실패 뒤 독립 Read로 확인된 이전 / 확인된 새 / 미확정을 정하고 결과별 처리(050-D D8.1–D8.5); 확인된 이전 상태는 새 ID 부재 확인 필수 | **ADR-040 §9 · ADR-037 STEP 11 Note · ROADMAP Task 14의 Persist 실패 분기 개정 제안**(확인된 이전 상태의 Save 오류는 기존 문구와 R4 §3 그대로) | 재구성 경계 관측은 측정한 경우에 한함; 독립 Read의 Coordinator Cache 독립성 미확인 | OD-10; Lifecycle Gate 적용(D8.4); 구현 | 예(개정으로서) — **분류 규칙 Accepted(2026-10-02, D8.0); 순수 분류기 구현, 독립 Read · Gate · Rollback 연결은 Pending** — **2026-10-02: 결과별 처리 가운데 D8.5a P1 · P2 · P4 · P5 · P6(임시) · P8이 Accepted(미구현); P7 보류, Rollback · Retry는 Proposed** |
| OD-10 | 독립 Read 방법: 같은 Container의 새 `ModelContext`(권장) 또는 별도 `ModelContainer` | 구현 정책 | 권장안의 Coordinator Cache 독립성 미검증; 대안의 동시 열기 동작 미검증; 파괴적 Rollback은 새 ID 부재 확인으로 보강(OD-9) | 없음 | 예 — **Accepted(2026-10-02): 새 전용 `ModelContext`(Autosave 꺼짐, `includePendingChanges = false`) — 구현 정책일 뿐 Cache 우회 · 원자적 Snapshot 보장 아님; `observePersistedState(for:)` 구현(연결 없음)** — **2026-10-05: Select Clips에 연결(D8.5b); Editor 연결(D8.5c)** |
| OD-11 | `.replacingSaved` 두 Save 처리: B 확인 전 Save 2 없음; A Row 부재 확인 뒤에만 A Media 제거; Save 2 실패는 B 성공을 바꾸지 않음(050-D D8.6) | 새 정책(현재 코드와 다름) | Save 사이 정지 시 A + B 공존 관측 | 기존 A Media 삭제 코드 수정; 단일 Save 가능성 감사(검토 후속 2) | 두 Save 설계는 승인 대상 아님(감사 결과 뒤 재제출) — **2026-10-02: OD-14 (a) 승인으로 대체됨(두 Save 설계는 승인되지 않음)** — **2026-10-02: "A Row 부재 확인 뒤에만 A Media 제거"와 Save 오류 · 확인 실패 시 B 보존을 현재 두 Save 경로에 적용(D8.0 보존 수리); 그 밖의 OD-11 · D8.6 처리와 단일 Save `replaceProject` 연결은 미변경 · Proposed; B가 확인되지 않은 채 보존되면 A와 B가 함께 남을 수 있으며 그 처리는 OD-13 / D8.5와 함께 Pending** |
| OD-12 | Startup Recovery 빈 Store 보호: Row 0개 + Directory ≥ 1이면 Orphan Directory 제거 생략(권장) 또는 Store 식별 Marker(050-D D8.7) | **ADR-039 STEP 12B 개정 제안** | 빈 Store 재생성 시 전체 Directory 제거 위험(코드 분석, 미재현) | 없음 | 예(개정으로서) — **2026-10-06: 최소 보호 결정 · 구현(Directory와 참조 없는 Media 제거 둘 다 생략, 읽기 실패 = 모름); Store 식별 Marker와 부분 손실 보호는 미결** |
| OD-13 | 남은 A의 처리: (a) 안내 없음 · 자동 재삭제 없음(숨은 A 영구 잔존), (b) 나중 A 삭제 재시도 규칙, (c) 새 안내(050-D D8.6) | **ADR-033 / ADR-034 Safe Atomic Replacement에서의 이탈에 대한 결정**((b)는 ADR-034 / ADR-039 개정 필요) | 남은 A는 STEP 12B가 회수하지 않고 최신 순서로 가려짐 | OD-11 | 별도 결정 — **2026-10-02: 두 Save 경로가 승인되지 않아 결정 보류(단일 Save에서 "A + B"는 측정한 경우 관측되지 않음)** |
| OD-14 | `.replacingSaved` Save 구조: (a) 단일 `ModelContext.save()`(B 삽입 + A 삭제) — 원자적으로 Commit되면 숨은 A 없음, ADR-033 6–9 순서 개정 필요, Save 성공 뒤 B 확인 불가 또는 B가 쓸 수 없는 Row면 다음 시작에서 A 소실(잔여 위험; ADR-033 "failed replacement" 불변식 범위 축소), 결합 Save의 Domain 변경이 분할 Commit된다면 Crash 시 A와 B 모두 손실 위험(가설; 측정한 경우의 재구성 경계에서는 Domain 변경이 한 Commit이었고 "둘 다 없음"은 관측되지 않음, 보장 아님); (b) 현재 두 Save — ADR-033 순서 유지, Save 2 실패 시 숨은 A(OD-13), 재구성 경계(측정한 경우)에서 "A도 B도 없음"은 관측되지 않음(보장 아님)(050-D D8.6a) | **ADR-033 Safe Atomic Replacement 문구 개정 및 안전 불변식 범위 축소((a)의 경우) 또는 ADR-033 / ADR-034 Single Saved Project 이탈 위험 수용((b)의 경우)** | Source 감사 + 결합 Save 실험(Exploratory, A ≤ 50 / B ≤ 10, 재구성 경계) | (a)를 택하면 ADR-033 개정 · 구현 · Test | 별도 결정; Proposed 권장 (a)(D8.6a), 승인 아님 — **Accepted (a)(2026-10-02, 사용자 승인); ADR-033 Revision 1** |
| OE-1 | `ProjectMediaTransfer` 잔여 File 정리(050-E) | ADR-039 / ADR-047 확장(후속) | — | 별도 결정 | 이 ADR 범위 밖 |

## Consequences

- Unit별 승인이 가능하다. 050-A / 050-C / 050-D의 독립 승인 항목만으로도 Pure Estimator / Check와 Transaction 규칙을 구현 계획에 넣을 수 있지만 050-B가 해결되기 전에는 Import Storage Gate가 닫히지 않는다. — **갱신(2026-10-02):** 050-A · 050-B와 050-C 계산 정책은 Accepted되었고 순수 Estimator / Check로 구현되었다(연결 없음). Import Storage Gate는 검사 경계 연결, 050-D, 필수 Integration Gate 때문에 여전히 열려 있다.
- Estimate는 관측 출력보다 크게 잡히므로 거의 가득 찬 기기에서 일부 Import가 실제로는 성공했을 상황에서도 차단될 수 있다.
- Runtime Disk Full은 여전히 가능하며 050-C / 050-D가 처리한다.

## Non-goals

- Production 구현, UI 연결, Encoder Bitrate 설정, Quality Downgrade, Clip-count / Duration Cap, 새 사용자 Copy, `ProjectMediaTransfer` Startup Cleanup 승인, Export Storage, Performance Acceptance Threshold, Pending Gate의 해결 표시.
