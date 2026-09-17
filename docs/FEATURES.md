# Mellow — Feature Definition

## 1. Document Purpose

이 문서는 Mellow의 실제 기능 범위와 우선순위를 정의한다.

`PRODUCT.md`가 Mellow가 어떤 제품인지 정의한다면, 이 문서는 실제로 어떤 기능을 구현하고 어떤 기능을 초기 범위에서 제외할지를 구체적으로 정의한다.

이 문서는 `DESIGN.md`, `ARCHITECTURE.md`, `ROADMAP.md`와 실제 구현의 기준으로 사용한다.

확정되지 않은 기능은 임의로 MVP에 포함하지 않는다.

### Confirmed Platform Baseline

- iPhone-first Native Application
- Swift / SwiftUI
- Minimum iOS: iOS 18.0
- Official Device Quality Baseline: iPhone 12 and later
- Primary Physical Test Device: iPhone 12

`iPhone 12 and later`는 공식 개발 및 QA 기준이며 App Store에서 이전 기기의 설치를 인위적으로 제한하는 조건이 아니다.

---

## 2. Core Product Loop

Mellow의 핵심 사용자 흐름은 다음과 같다.

**Mellow 실행 / Splash**

↓

**Permission Onboarding (첫 실행 시에만 표시)**

↓

**Portrait Camera**

↓

**영상 Clip 촬영 또는 Photos에서 영상 가져오기**

↓

**추가 Clip 촬영 및 가져오기**

↓

**Clip 확인 및 정리**

↓

**Clip 순서 변경**

↓

**각 Clip의 사용 구간 Trim(Project-owned Clip Media 범위 안)**

↓

**전체 Vlog Preview**

↓

**하나의 Video로 Export**

↓

**Photos에 저장 또는 공유**

이 전체 흐름이 실제 iPhone에서 안정적으로 동작하는 것이 Mellow MVP의 핵심 목표다.

---

## 3. Feature Priority Levels

### MVP Required

Mellow의 첫 번째 사용 가능한 제품을 구성하는 데 반드시 필요한 기능이다.

MVP Required 기능이 완성되지 않은 상태에서는 MVP가 완료된 것으로 간주하지 않는다.

### Post-MVP

Mellow의 제품 방향에는 적합하지만 첫 번째 MVP에는 포함하지 않고 이후 검토하는 기능이다.

### Future Candidate

장기적으로 검토할 수 있지만 현재 구현을 전제로 하지 않는 기능이다.

### Out of Scope

현재 Mellow의 제품 방향에서 의도적으로 제외하는 기능이다.

---

# 4. MVP — Vlog Project

## F-MVP-001 — Create New Vlog

사용자는 새로운 Mini Vlog 프로젝트를 생성할 수 있어야 한다.

새 프로젝트를 만들 때 프로젝트 이름 입력 Prompt를 제공하지 않는다.

ADR-032에 따라 V1은 형식 선택 단계를 제공하지 않고 새 프로젝트는 항상 `9:16 Portrait`이며, App Launch만으로 비어 있는 프로젝트를 저장하지 않는다.

### Required

- 새로운 Portrait 9:16 Vlog 프로젝트 생성
- 형식 선택 단계 없이 Camera에서 촬영 또는 Clip 추가 흐름으로 진입
- 프로젝트 생성 날짜 및 시간 기록
- 프로젝트 마지막 수정 시각 기록
- App Launch / Camera 표시 / Onboarding 완료만으로 빈 프로젝트를 저장하지 않음

### Not Required in V1

- Orientation 선택 UI
- 새 Landscape 16:9 프로젝트 생성

### Not Required

- 프로젝트 설명
- 프로젝트 태그
- 프로젝트 카테고리

---

## F-MVP-002 — Project Orientation

Domain이 표현하는 화면 비율은 다음 두 가지다.

- Portrait — 9:16
- Landscape — 16:9

ADR-032에 따라 V1이 새로 생성하는 프로젝트는 `9:16 Portrait`뿐이며 Landscape는 Domain / Schema 표현으로만 유지한다.

프로젝트의 화면 비율은 해당 프로젝트가 유지되는 동안 변경되지 않는다.

기기의 물리적인 회전만으로 프로젝트의 화면 비율이 자동 변경되지 않는다.

### Required Behavior

9:16 프로젝트는 세로 촬영, 세로 Preview, 세로 Export를 기준으로 동작한다.

16:9 프로젝트의 가로 촬영, Preview와 Export 동작은 Landscape 복원 Phase가 소유하며 V1 Camera UI 요구사항이 아니다.

기존에 저장된 Landscape 프로젝트는 삭제하거나 Migration하지 않으며 필요한 Compatibility 동작은 Transitional Decision으로 남긴다.

---

# 5. MVP — Project Drafts

## F-MVP-003 — Multiple Draft Projects

Domain은 여러 개의 미완성 Vlog 프로젝트를 표현할 수 있지만 ADR-033에 따라 **V1 Product는 편집 가능한 저장 Project를 최대 하나만 유지한다.**

- 저장 Project가 없으면 Camera `Projects → Select Clips`로 첫 Project를 만든다.
- 저장 Project가 있으면 `Load Last Saved`로 열거나 `Select Clips`로 대체 Project를 만들며 대체는 명시적 확인과 Safe Atomic Replacement를 거친다.
- Recording은 Project를 만들지 않으므로 V1 정상 흐름에서 0 Clip Project는 생성되지 않는다.
- Multi-project 보관 / Recent Browser는 Post-V1 복원 결정으로 남기며 Domain 능력은 제거하지 않는다.

Project 삭제 / 대체는 Mellow Editing Copy만 제거하며 Photos 원본은 절대 삭제하지 않는다.

---

## F-MVP-004 — Automatic Draft Saving

사용자가 별도의 저장 버튼을 누르지 않아도 현재 프로젝트 상태를 자동으로 보존한다.

앱 재실행 또는 기기 재부팅 후에도 자동 저장된 로컬 Draft를 다시 열 수 있어야 한다.

0 Clip Project도 Project Orientation과 Draft Metadata를 보존한 채 다시 열 수 있어야 한다.

### Required State

- Project orientation
- Project creation date
- Last edited date
- Clip 목록
- Clip 순서
- Clip source
- Trim 범위
- Framing 정보
- Thumbnail 정보
- 기타 프로젝트 복구에 필요한 최소 상태

---

## F-MVP-005 — Draft Retention

Draft에는 자동 만료 기간을 두지 않는다.

Draft는 사용자가 직접 삭제하기 전까지 로컬 기기에 유지한다.

앱 삭제 또는 기기 교체 이후의 Draft 복구는 초기 버전에서 보장하지 않는다.

iCloud 기반 Draft 동기화 또는 복구 기능은 향후 기능으로 검토한다.

---

## F-MVP-006 — Automatic Project Name

MVP에서는 사용자가 Vlog 프로젝트 이름을 직접 지정하지 않는다.

프로젝트의 표시 이름은 생성 날짜와 시간을 기반으로 자동 생성한다.

예시는 다음과 같다.

`Sep 10, 4:12 PM`

정확한 날짜 및 시간 표기 방식은 사용자의 Locale을 따르는 방향을 우선한다.

위 표기는 예시이며 구체적인 Format은 아직 확정하지 않는다.

프로젝트 Rename은 MVP에서 제공하지 않는다.

---

## F-MVP-007 — Draft Thumbnail

Draft의 대표 이미지는 현재 Project의 logical Clip Order에서 첫 번째 Healthy / Usable Clip의 Thumbnail을 기본값으로 사용한다.

Representative Source의 `첫 번째`는 Clip 생성 시각이나 Filename이 아니라 current logical Clip Order를 기준으로 판단하며 Unavailable Clip은 Representative Source가 될 수 없다.

0 Clip Project 또는 모든 Clip이 Unavailable인 Project에는 usable Representative Source가 없으므로 다른 Project Thumbnail이나 임의 Media를 재사용하지 않고 정상 Media를 암시하지 않는 Placeholder를 표시한다.

Representative Thumbnail은 Project / Clip State와 Media의 Source of Truth가 아닌 재생성 가능한 Derived / Cache Data다.

Thumbnail Missing, Corruption, Generation Failure 또는 Cache Cleanup은 Project / Clip Corruption, Delete, Recording / Import / Editing 차단이나 Recent 전체 Load Failure를 의미하지 않는다.

Representative Source는 Clip Add, Delete, Undo Restore, Replace 성공, Reorder, Availability Change와 Project Reload 또는 Reconciliation 뒤에 current logical Clip Order를 기준으로 다시 평가한다.

Representative Thumbnail은 가능한 범위에서 current effective edited appearance를 반영하며 Project Orientation, Framing, Transform, Direct-recorded Front Mirror Semantics 또는 SDR Interpretation이 바뀌면 stale Derived Representation을 영구 current Representative로 사용하지 않는다.

Thumbnail Generation은 비동기일 수 있으며 Result 적용 직전에 Project / Clip Liveness, Clip Availability, Media Identity, current Representative Source Identity와 applicable Edit State가 유효한지 확인한다.

위 조건이 바뀐 Stale Thumbnail Result는 폐기하며 deleted Project / Clip을 되살리거나 이전 Representative를 current Representative 위에 다시 적용하지 않는다.

정확한 Thumbnail Frame Selection, Image Format / Dimensions, Placeholder Visual과 Cache / Retry Policy는 아직 확정하지 않는다.

### Acceptance Criteria

| 시나리오 | 기대 결과 |
| --- | --- |
| 여러 Healthy Clip이 있는 Project | current logical Clip Order에서 첫 번째 Healthy / Usable Clip을 Representative Source로 사용한다. |
| 현재 첫 번째 Clip이 Unavailable인 Project | Unavailable Clip을 Representative Source로 사용하지 않고 다음 Healthy / Usable Clip을 사용한다. |
| 0 Clip 또는 All-unavailable Project | unrelated Thumbnail이나 임의 Media를 재사용하지 않고 Placeholder를 표시한다. |
| Reorder | 새 current logical Clip Order를 기준으로 Representative Source를 다시 평가한다. |
| Representative Source의 Delete 또는 Unavailable Transition | 다음 Healthy / Usable Clip을 다시 찾고 없으면 Placeholder를 사용한다. |
| Undo Restore 또는 successful Replace | current order와 restored / replaced Clip의 Usability를 기준으로 Representative Source를 다시 평가한다. |
| Replace Failure | 기존 Unavailable Placeholder와 current Representative Source 상태를 유지한다. |
| Thumbnail Missing, Corruption 또는 Generation Failure | Project / Clip Media와 Recent를 유지하고 Placeholder 또는 Retry를 허용한다. |
| Edit 또는 Representative Source 변경 후 Late Thumbnail Result | current Representative Source나 valid edit state와 일치하지 않는 Result를 폐기하고 deleted Project / Clip을 되살리지 않는다. |

---

## F-MVP-008 — Draft Metadata

Draft 목록에서 사용자가 프로젝트를 구분할 수 있는 최소 정보를 제공한다.

### Candidate Information

- Thumbnail
- 생성 날짜 및 시간
- 마지막 수정 시각
- Clip 개수
- 현재 Vlog 총 재생 시간
- Project orientation

정확한 정보 구성은 `DESIGN.md`에서 결정한다.

---

## F-MVP-009 — Keep Draft After Export

Vlog를 Export했다고 해서 해당 Draft를 자동 삭제하지 않는다.

사용자는 Export 이후에도 프로젝트를 다시 열어 수정하고 다시 Export할 수 있어야 한다.

Draft 삭제는 사용자의 명시적인 행동으로만 수행한다.

---

## F-MVP-010 — Delete Draft

사용자는 더 이상 필요하지 않은 Draft를 삭제할 수 있어야 한다.

Draft 삭제 시 Mellow 내부에 보관 중인 해당 프로젝트의 미디어와 프로젝트 데이터만 삭제한다.

Photos Library에 존재하는 원본 미디어에는 영향을 주지 않는다.

프로젝트 전체 삭제는 사용자의 명시적인 Confirmation 이후 실행한다.

Confirmation의 세부 UI는 `DESIGN.md`에서 결정한다.

---

# 6. MVP — Camera

## F-MVP-011 — Vlog Camera

사용자는 Mellow 내부에서 짧은 영상 Clip을 촬영할 수 있어야 한다.

한 프로젝트에서 여러 개의 Clip을 연속해서 촬영할 수 있어야 한다.

### Required

- Camera Preview
- 영상 녹화 시작
- 영상 녹화 종료
- 현재 녹화 상태 표시
- 현재 녹화 시간 표시
- 촬영 완료 후 Clip 저장
- 동일 프로젝트에 추가 Clip 촬영

---

## F-MVP-012 — Rear Camera

Mellow는 iPhone의 Rear Camera를 이용한 영상 촬영을 지원한다.

Rear Camera를 선택하면 기본 1× Wide Camera로 Capture한다.

MVP에서는 0.5× Ultra Wide, Telephoto 또는 물리 Lens를 직접 선택하는 Lens Selector UI를 제공하지 않는다.

Rear Preview와 Active Recording에서 1× 이상 Continuous Zoom을 지원한다.

Recording 중 Zoom 변경은 같은 Clip 안에서 이어지며 Recording을 Stop / Restart하거나 새로운 Clip을 만들거나 선택한 최대 Duration Timer를 Reset하지 않고 Project Orientation 또는 Aspect Ratio를 변경하지 않는다.

Zoom Factor는 승인된 1.0×–2.0×로 Clamp하며 동일한 Rear Wide Camera를 유지한다.

Device가 지원하는 이론적 최대 Zoom Factor는 Product Maximum으로 자동 채택하지 않는다.

Rear Zoom은 Capture-time Camera Behavior이며 Phase 7의 Metadata 기반 Editing Framing으로 Zoom 이전의 전체 1× Field of View를 복원할 수 있다고 보장하지 않는다.

승인된 Interaction은 Pinch-to-zoom이며 Gesture 중 작은 Numeric Indicator만 허용하고 Persistent Zoom Button / Slider는 제공하지 않는다.

---

## F-MVP-013 — Front Camera

Mellow는 iPhone의 Front Camera를 이용한 영상 촬영을 지원한다.

사용자는 녹화하지 않는 idle 상태에서 Rear Camera와 Front Camera를 전환할 수 있어야 한다.

Front Camera와 Rear Camera의 동시 촬영은 MVP 범위에 포함하지 않는다.

Front Camera Zoom과 Zoom UI / Gesture는 MVP에서 제공하지 않는다.

Front Camera Preview는 Mirrored Appearance를 사용하며 Mellow에서 직접 촬영하여 저장한 Front Clip은 이후 Preview, Editing과 Export에서도 촬영 중 본 Mirrored Framing과 동일한 사용자-visible Appearance를 유지한다.

Mirror Toggle은 MVP에서 제공하지 않으며 Photos에서 Import한 Source에는 이 Front Camera Mirroring 정책을 적용하지 않는다.

---

## F-MVP-014 — Camera Switching

사용자는 녹화하지 않는 idle 상태에서 Rear Camera와 Front Camera를 전환할 수 있어야 한다.

Recording 중 Camera Switching은 허용하지 않는다.

---

# 7. MVP — Recording Duration

## F-MVP-015 — Maximum Clip Recording Duration

Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration을 제공하고 기본 선택은 `3s`다.

선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있으며 Project-level 불변 속성이 아니다.

Preset은 정확한 Output Duration이 아니라 다음 Clip의 Maximum이며 3s 선택 후 1.4초 수동 종료도 허용한다.

사용자는 선택한 최대 Duration 이전에는 원하는 시점에 자유롭게 녹화를 종료할 수 있다.

녹화 시간이 선택한 최대 Duration에 도달하면 Mellow가 자동으로 녹화를 종료한다.

ADR-033에 따라 Direct Capture의 최소 길이는 1.0초이며 `1.0s <= actual duration <= selected maximum`만 유효하다. 3s Preset에서 1.4초 종료는 저장, 0.7초 종료는 폐기하며 1초 미만을 반올림하지 않는다.

### Required

- 녹화 시작 후 자유로운 수동 종료(Shutter Tap → Early Stop)
- `1s / 2s / 3s / 4s / 5s` 최대 녹화 시간 선택과 기본 `3s`
- 선택한 최대 Duration 도달 시 자동 종료
- 1.0초 미만 Capture 폐기
- Recording 중 Duration Picker / Flip / Projects Lock과 Shutter만 Manual Stop
- Shutter 주변 Circular Progress Ring(`elapsed / selected maximum`)으로 진행 표시, 큰 숫자 Timer 없음
- 자동 종료된 Clip의 Photos 저장
- 자동 종료 이후 정상적인 다음 촬영 가능
- 승인된 Recording Estimate와 Safety Reserve를 충족하지 못하면 Recording, Progress와 선택한 최대 Duration Timer를 시작하지 않음
- Storage 부족을 이유로 Capture Quality, Frame Rate, Audio 또는 최대 Recording Duration을 자동으로 낮추지 않음

### Excluded from MVP

- 선택한 Preset과 정확히 같은 Output Duration 강제
- 5초를 초과하는 단일 Clip 촬영
- Recording pause
- Recording resume

---

## F-MVP-016 — Recording Progress Feedback

사용자는 현재 Clip의 녹화 진행 상태와 5초 제한을 자연스럽게 인지할 수 있어야 한다.

Recording Progress는 Record Button 주변의 Progress Ring을 중심으로 표현하며 큰 Countdown 숫자는 사용하지 않는다.

구체적인 Progress 표현과 선택한 최대 Duration 도달 전 Visual Feedback의 세부 동작은 `DESIGN.md`에서 결정한다.

### Confirmed Recording Haptic Policy

- Recording Start에는 Haptic을 사용하지 않으며 Record Button Tap 또는 Recording Start 성공을 Haptic 발생 조건으로 사용하지 않는다.
- Successful Manual Stop 완료 시 subtle completion haptic을 제공한다.
- Successful selected-maximum Auto-stop 완료 시 subtle completion haptic을 제공한다.

Manual Stop과 Auto-stop의 Haptic은 모두 "이 Clip의 Recording이 종료되었다."라는 동일한 의미를 가지며 종료 직전의 예고 신호가 아니다.

Haptic은 보조 Feedback이며 기존 Visual Recording State, Circular Progress와 Completion State를 대체하지 않는다.

Haptic을 사용할 수 없거나 사용자가 인지하지 못해도 Visual Feedback으로 Recording 상태를 이해할 수 있어야 한다.

Recording Error / Interruption의 Haptic 정책은 별도 Pending으로 유지한다.

정확한 Haptic API, Style, Intensity, Pattern, Duration과 Generator 구현은 Native iOS 구현 및 실제 iPhone 12 Tuning 대상으로 남기며 정상 Start / Manual Stop / Auto-stop의 Haptic 여부는 다시 Open으로 취급하지 않는다.

---

# 8. MVP — Audio Recording

## F-MVP-017 — Record Audio

영상 촬영 시 Microphone이 허용되어 있으면 Audio를 함께 녹음한다.

ADR-033에 따라 Microphone은 선택 권한이다. Denied / Restricted여도 Video Recording은 계속 가능하며 Clip은 무음으로 기록되고 Camera는 `mic.slash` 상태를 조용히 표시한다. Microphone Control Tap은 `.notDetermined` → 권한 요청, `.denied` → Settings Recovery, `.restricted` → 사용 불가 설명, `.authorized` → 일반 상태다.

Direct Recording 시작에는 Camera 권한과 Photos Add 권한이 필요하며 Microphone 거부는 Recording을 차단하지 않는다.

Camera 또는 Microphone Permission 상태와 관계없이 Photos Video Import는 자체 Picker / Permission Flow를 통해 사용할 수 있어야 하며 Audio Track이 없는 Source Video도 허용한다.

### Required

- Microphone permission 처리
- Video와 Audio 동기화
- Microphone permission 거부 상태 처리
- 녹화된 Audio를 Preview 및 Export에 유지

---

# 9. MVP — Import from Photos

## F-MVP-018 — Import Existing Video

사용자는 iPhone Photos Library의 기존 영상을 현재 Vlog 프로젝트에 추가할 수 있어야 한다.

ADR-042에 따라 Photos에서 가져오는 원본 영상은 **전체 길이가 `1.0s <= sourceDuration <= 5.0s`(양 끝 포함)일 때만** 받아들인다. 1.0초 미만이거나 5.0초를 초과하는 영상은 프로젝트에 가져오지 않으며 긴 영상에서 최대 5초 구간을 선택하는 기능은 제공하지 않는다.

4K를 포함한 고해상도 Source Video를 Import할 수 있다.

SDR 및 HDR / Dolby Vision Source Import를 허용하며 30 fps보다 높은 Source도 가져올 수 있다.

HDR / Dolby Vision Source도 5초 이하 전체 Source를 SDR Working Media로 정규화하며 Photos 원본은 변경하지 않는다.

---

## F-MVP-019 — Imported Video Duration Policy

ADR-042에 따라 Photos Source Video는 **전체 길이**가 `1.0s <= sourceDuration <= 5.0s`(양 끝 포함)일 때만 가져올 수 있다.

1.0초 미만이거나 5.0초를 초과하는 원본 영상은 Import를 거부하며 원본 영상 안에서 최대 5초 구간을 선택하는 Segment Selection은 제공하지 않는다.

### Required

- 전체 길이가 1.0초 이상 5.0초 이하(양 끝 포함)인 원본 영상만 Import 가능; 정확히 1.0초와 정확히 5.0초는 허용
- 범위 안의 원본 영상은 전체 길이가 그대로 Clip이 된다
- 1.3초, 2.7초, 4.5초, 5.0초 같은 비정수 길이 허용(정수 불필요), Camera Preset과 무관
- 0.4초 / 0.8초 등 1.0초 미만 거부, 5.0초 초과 거부, 0 이하 / 읽을 수 없음 Invalid
- 범위 밖 영상 거부 시 Materialize / Normalize / Persist / Append / Replace 미수행, Project-owned Media 미생성, Clip Metadata 미Commit, 부분 Project 변경 없음, Photos 원본 불변
- 단일 항목 / Replace 후보의 5.0초 초과 거부 안내는 기존 `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`, 1.0초 미만 거부 안내는 `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`(ADR-042 Revision 2); Replace 후보 거부 시 기존 Clip 보존
- 다중 선택(Select Clips / Editor Add)은 ADR-042 Revision 3에 따라 Duration-ineligible 항목만 제외하고 유효 항목으로 계속 진행하며 통합 안내를 한 번 표시: 짧은 항목만 제외 `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.`, 긴 항목만 제외 `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.`, 둘 다 제외 `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`; 전부 Ineligible이면 아무것도 추가하지 않음; Normalization-required 항목은 제외되지 않음; Accepted Set의 Commit은 Atomic
- Validation 결과는 최소한 Below-minimum / Above-maximum / Normalization 필요 / Invalid Media를 구분
- 구현 상태: 5.0초 초과 거부는 Phase 5 구현 완료, 1.0초 미만 거부는 Phase 6 구현 요구(현재 Phase 5 Validator는 1.0초 미만을 Ready로 통과시킨다)
- 원본 영상의 비파괴적 처리

### PhotosPicker 제약

System PhotosPicker는 길이로 항목을 미리 숨기거나 비활성화하지 못하므로 사용자가 1.0초 미만 또는 5.0초 초과 영상을 탭할 수 있다. Mellow는 Metadata Validation 후 해당 항목을 거부하고 Materialize / Normalize / Persist / Append / Replace / Commit 어느 것도 하지 않는다. Broad Photos Read 권한을 요구하지 않는다.

### Example

원본 영상 길이가 4.5초라면 전체 4.5초가 그대로 Clip으로 추가되고, 정확히 1.0초 또는 5.0초여도 추가된다. 원본 영상 길이가 0.8초라면 `영상이 너무 짧아요` 안내와 함께 거부되고, 2분 14초라면 `영상이 너무 길어요` 안내와 함께 거부되며 두 경우 모두 프로젝트는 변경되지 않는다.

---

## F-MVP-020 — Normalize Clip Duration Rule

Mellow 프로젝트에서 사용하는 하나의 최종 Clip은 촬영 방식과 관계없이 `0 < effectiveClipDuration <= 5 seconds`를 만족한다.

Imported Clip은 전체 Source Duration이 `1.0s <= duration <= 5.0s`인 Photos Video 전체이며 1.3초, 2.7초, 4.5초, 5.0초처럼 정수가 아니어도 되고 Camera Preset에 맞출 필요가 없다(ADR-042).

직접 촬영한 Clip과 Photos에서 가져온 Clip은 이후 Clip 관리, Preview, Trim, Export 단계에서 가능한 한 동일한 구조로 취급한다.

---

## F-MVP-021 — Imported Media Safety

사용자가 Imported Clip 추가를 확정하면 프로젝트에서 사용할 Project-owned Local Media를 생성한다.

SDR, HDR / Dolby Vision 및 4K를 포함한 고해상도 Source의 5초 이하 전체 Source를 기준으로 1080p-class / 30 fps / SDR Working Media를 생성한다. Normalization은 전체 Source Duration Eligibility(F-MVP-019) 검사 이후에만 시작한다.

1080p-class는 고해상도 Source의 Working Target이며 저해상도 Source의 Upscaling 여부와 정확한 Raster Dimension Rule은 아직 확정하지 않는다.

### Normalization Acceptance Criteria

- HDR / Dolby Vision Source도 Project-owned SDR Working Media로 정규화하며 HDR Metadata 보존을 MVP 완료 조건으로 요구하지 않는다.
- 30 fps 초과 Source도 Working Media에서는 30 fps 기준을 충족한다.
- 고해상도 Source는 승인된 1080p-class Working Target을 따르며 Photos 원본의 Resolution / Frame Rate / Color는 변경하지 않는다.
- Project Fill + Crop을 Working File에 bake-in하지 않으며 Source의 Presentation Aspect Ratio와 이후 Framing에 필요한 유효 화면 영역을 보존한다.
- Source Rotation / Presentation Transform을 올바르게 반영하여 Framing 가능한 화면 영역이 손상되지 않는다.
- Normalization Output은 Final Working Media 등록 전에 Validation하며 심각한 Highlight Clipping, 잘못된 색 변환 또는 Orientation 손상 등 명백한 변환 실패를 정상 Media로 등록하지 않는다.
- 실패와 취소 시 Valid Source / Staging 및 Recovery Candidate는 확정된 Media Safety 계약에 따라 보호한다.
- Import / Normalization의 Estimated Peak Additional Storage와 Safety Reserve를 충족하지 못하면 Materialization과 Normalization을 시작하지 않는다.
- Storage 부족이나 Runtime Disk Full로 생성된 Partial / Incomplete Output을 정상 Clip으로 Commit하지 않고 Photos 원본과 기존 Project Media를 보호한다.
- Storage 부족을 이유로 승인된 1080p-class / 30 fps / SDR Working Media 정책을 자동 하향하지 않는다.

정상적으로 Project-owned Media가 생성되어 추가된 Clip은 이후 Photos 원본이 삭제되어도 Draft에 유지되어야 한다.

Draft를 삭제할 때는 Mellow 내부 복사본만 삭제하며 Photos의 원본 영상에는 영향을 주지 않는다.

Photos 원본은 Import, 정규화 또는 편집 과정에서도 수정하거나 삭제하지 않는다.

미디어 저장은 `ARCHITECTURE.md`와 ADR-020 / ADR-021의 확정된 기준을 따르며 SDR 정규화 방향은 ADR-022를 따른다.

Working Media Codec / Container, 정확한 SDR Color Profile / Tagging, Tone-mapping 구현 방법, Upscaling과 Raster Dimension Rule의 미결 세부값은 임의로 확정하지 않는다.

---

# 10. MVP — Orientation Handling for Imported Video

## F-MVP-022 — Imported Orientation Handling

Photos에서 가져오는 영상의 원본 화면 비율이 현재 프로젝트의 화면 비율과 다를 수 있다.

예를 들어 9:16 프로젝트에 16:9 영상을 가져올 수 있다.

이 경우 Mellow는 프로젝트 화면 비율에 맞게 해당 영상을 처리해야 한다.

### Required Behavior

- 기본 Layout은 Fill + Crop이다.
- 프로젝트 Canvas를 채우고 초과 영역을 Preview / Export Composition에서 Crop한다.
- 사용자가 Framing 위치를 조정할 수 있어야 한다.
- Working Media에는 Project Crop을 미리 bake-in하지 않으며 이후 Framing할 Source 영역을 보존한다.
- Crop Region, Position 및 Scale은 가능한 한 Editing Metadata로 유지하며 일반 Trim / Framing 변경마다 Media를 다시 인코딩하지 않는다.

Fit과 Background Blur는 MVP에서 제공하지 않는다.

세부 Crop UI와 Pinch to Zoom 지원 여부는 아직 확정하지 않는다.

---

# 11. MVP — Clip Management

## F-MVP-023 — Clip List

현재 Vlog 프로젝트에 포함된 모든 Clip을 사용자가 확인할 수 있어야 한다.

각 Clip을 Ordered Thumbnail Strip에서 시각적으로 구분하고 Single Tap으로 선택하여 관련 Clip Tools를 노출 / 활성화하며 일반 Tap으로 Text Entry를 열지 않는다.

ADR-034에 따라 Phase 5 표현은 Horizontal Ordered Strip(Clip당 한 항목, Thumbnail Primary + Compact Duration Label, Color-only가 아닌 Selected State, Long Press + Drag / Move Earlier·Later Reorder)이며 Large Preview는 Shell만 제공하고 실제 Effective-result Playback은 Phase 8 소유다. Waveform / Track / Playhead Timeline / Keyframe / Layer / Multi-track은 두지 않는다.

### Candidate Information

- Thumbnail
- Duration
- Clip source
- 현재 순서

정확한 UI는 `DESIGN.md`에서 정의한다.

참조 Media가 Missing, Unreadable, Corrupt, Validation 실패 또는 Expected Media Reference와 불일치하는 Clip은 기존 Timeline / Organizer Position을 유지하는 Unavailable 상태로 사용자에게 표시한다.

Unavailable Clip은 자동으로 삭제하거나 숨기거나 Healthy Clip으로 표시하지 않는다.

일부 Clip이 Unavailable이어도 Project는 열리고 Healthy Clip은 개별 Preview, Trim, Reorder와 새 Clip 추가를 계속 사용할 수 있다.

---

## F-MVP-024 — Add Additional Clips

사용자는 프로젝트를 생성한 이후에도 새로운 Clip을 계속 추가할 수 있어야 한다.

새로운 Clip은 Mellow Camera로 촬영하거나 Photos Library에서 Import할 수 있다.

ADR-037에 따라 Editor의 Add Clip은 System PhotosPicker로 Phase-5-ready Media를 현재 Project 끝에 Atomic하게 Append하며 Camera를 열지 않는다. ADR-042 Revision 3에 따라 다중 선택의 Duration-ineligible 항목(1.0초 미만 / 5.0초 초과)은 Transaction 전에 제외되고 통합 안내로 알리며 나머지 Accepted Set이 Atomic하게 Append된다(Phase 6 구현 요구). Mellow Camera로 촬영한 Clip은 Photos에 저장된 뒤 같은 경로로 추가한다.

Unavailable Clip은 사용자가 기존 Media Acquisition Capability를 통해 Replace할 수 있으며 성공한 Replace는 Unrelated Clip Reorder 없이 기존 Logical Slot을 복구한다.

Replace가 취소, Validation 실패, Storage 부족, Import 또는 Recording 실패, App Interruption으로 완료되지 않으면 기존 Unavailable Placeholder, Project와 다른 Clip을 유지한다.

Photos Video Import를 Replacement Source로 선택하는 경우에도 F-MVP-021의 Photos 원본 보존 계약을 따른다.

Replacement의 Clip Identity와 기존 Trim, Framing, Transform, Thumbnail Metadata Preserve / Reset 정책은 구현 전에 별도 Gate에서 결정한다. — Resolved by ADR-040 (2026-09-16, Phase 5 STEP 13): Replacement는 새 Clip Identity(Model B)로 기존 Logical Slot을 차지하고 `.imported`, Trim Reset(전체 Source), Framing nil, 새 Thumbnail을 가지며 기존 Unavailable Clip은 Durable Pending으로 남아 Session History의 Undo / Redo와 STEP 12A Cleanup 계약을 따른다. Phase 5의 Unavailable 범위는 Committed 파일 없음 / 해석 불가이며 Replace Source는 System PhotosPicker 1개 Video다.

---

## F-MVP-025 — Delete Clip

사용자는 필요하지 않은 Clip을 현재 Vlog 프로젝트에서 제거할 수 있어야 한다.

**ADR-038 (2026-09-16):** Undo는 Delete 전용 Snackbar가 아니라 Editor Navigation Bar 우상단의 상시 Undo / Redo Session History(시간순 LIFO, Reorder + Delete + 이후 편집, Session-local, Undo / Redo마다 Autosave, 새 편집은 Redo 폐기)로 제공한다. 아래 "가장 최근 Delete 한 건" / Snackbar / Undo Window 문구는 당시 기록이며 Superseded다.

Clip Delete Action 직후 해당 Clip을 UI에서 제거하고 Undo를 제공한다. ADR-034에 따라 Delete는 선택 Clip의 명시적 Action이며 일반 Clip Delete 앞에 별도 확인을 두지 않는다.

(Superseded by ADR-038) MVP에서 사용자에게 노출되는 Undo는 가장 최근 Clip Delete Action 한 건이다.

(Superseded by ADR-038) 새로운 Clip Delete가 발생하면 이전 Delete의 사용자-visible Undo Opportunity는 종료된다.

Undo는 삭제했던 동일 Clip Identity와 기존 Media 및 해당 Clip의 Metadata를 복원하며 새로운 Duplicate Clip을 생성하지 않는다.

Undo Window 중 App Process가 종료되면 Undo Opportunity를 다음 실행까지 유지하지 않는다.

재실행 시 해당 Delete는 확정된 Logical Deletion으로 취급하며 삭제된 Clip을 임의로 다시 표시하지 않는다.

Undo 전에 다른 Clip이 Reorder되어도 현재 다른 Clip의 상대 순서와 Unrelated Reorder를 되돌리지 않는다.

복원 위치는 현재 Project 상태를 존중하면서 삭제 당시 위치에 최대한 가깝게 결정적으로 정한다.

ADR-021의 Accepted 복원 기준에 따라 삭제 당시 이전 인접 Clip이 현재 유효하게 남아 있으면 그 바로 뒤, 이전 인접 Clip을 사용할 수 없고 다음 인접 Clip이 유효하게 남아 있으면 그 바로 앞에 복원한다.

두 인접 Clip 모두 사용할 수 없으면 삭제 당시 Original Index를 현재 Clip 배열의 유효한 삽입 범위로 Clamp하며 두 Clip이 모두 남아 있어도 이전 인접 Clip을 우선한다.

Clip 삭제는 Photos Library의 원본 영상에 영향을 주지 않는다.

Unavailable Clip의 Delete도 이 Feature의 Logical Delete, Undo와 Active Media Usage 계약을 그대로 따른다.

### Acceptance Criteria

| 시나리오 | 기대 결과 |
| --- | --- |
| Clip 삭제 | 해당 Clip이 즉시 UI에서 사라지고 짧은 Undo Opportunity가 제공된다. |
| 이전 Undo Opportunity 중 다른 Clip 삭제 | 새로 삭제한 Clip 한 건에만 사용자-visible Undo가 제공되며 이전 Delete의 Undo Opportunity는 종료된다. |
| 유효한 Undo 수행 | 삭제했던 동일 Clip Identity와 기존 Media 및 해당 Clip의 Metadata를 복원하고 Duplicate Clip을 만들지 않는다. |
| Undo Window 중 Process 종료 후 재실행 | Undo Opportunity가 복원되지 않으며 해당 Delete는 확정된 Logical Deletion으로 유지되고 Clip이 다시 표시되지 않는다. |
| Clip 삭제 후 다른 Clip Reorder 및 Undo | 확정된 인접 Clip / Original Index 기준으로 복원하며 현재 다른 Clip의 상대 순서와 Unrelated Reorder를 보존한다. |
| 양쪽 인접 Clip이 모두 남아 있거나 사용할 수 없는 상태에서 Undo | 둘 다 남아 있으면 이전 인접 Clip을 우선하고 둘 다 사용할 수 없으면 현재 삽입 범위로 Clamp한 Original Index를 사용한다. |
| Unavailable Clip 삭제 | Unavailable이라는 이유로 Delete Confirmation 또는 Undo Semantics를 변경하지 않고 이 Feature의 Logical Delete와 Undo 계약을 적용한다. |

Undo 표현은 ADR-038(Navigation Bar 상시 Undo / Redo, Undo Window 없음)로 확정되었으며 Animation, Haptic과 Delete UI의 세부 시각 처리만 Tuning으로 남는다.

Physical Deletion과 Active Usage Tracking의 구체적인 구현 방식 및 Coordinator / Lease / Reference Counter 구조는 이 기능 정의에서 확정하지 않는다.

---

## F-MVP-026 — Reorder Clips

사용자는 Clip Thumbnail의 Long Press + Drag로 순서를 변경하고 Move Earlier / Move Later 같은 Non-drag Accessibility 대안으로도 같은 결과를 만들 수 있어야 한다.

변경된 순서는 Preview와 Export 결과에 동일하게 반영되어야 한다.

---

# 12. MVP — Clip Trim

## F-MVP-027 — Trim Recorded Clip

사용자는 직접 촬영한 Clip의 시작점과 종료점을 조정할 수 있어야 한다.

Trim 작업은 원본 Clip을 직접 수정하지 않는 비파괴 방식으로 처리한다.

---

## F-MVP-028 — Trim Imported Clip

사용자는 Photos에서 가져온 Clip(전체 길이 5초 이하, F-MVP-019)의 시작점과 종료점을 Recorded Clip과 같은 방식으로 조정할 수 있어야 한다.

ADR-042에 따라 Imported Clip의 Re-trim은 받아들여진 Project-owned Clip Media 범위 안에서만 가능하며(`0 < trimDuration <= 5 seconds`, `trimStart + trimDuration <= sourceDuration`) 원본 Source 전체 범위로 확장할 수 없고 Source Reference를 유지하지 않는다.

---

## F-MVP-029 — Simple Trim Experience

Mellow의 Trim은 전문 영상 편집 수준의 정밀한 Timeline을 목표로 하지 않는다.

Trim UX는 빠르고 이해하기 쉬운 조작을 가장 우선한다.

### Required

- 시작점 조절
- 종료점 조절
- 선택된 구간 Preview
- 현재 Clip 길이 확인
- 최대 5초 규칙 유지
- 원본 미디어 보존

### Not Required

- Multi-cut
- Ripple editing
- Multi-track timeline
- Professional frame editor

---

# 13. MVP — Vlog Duration

## F-MVP-030 — No Fixed Total Vlog Duration Limit

Mellow는 전체 Vlog의 총 재생 시간에 제품 차원의 고정 최대 제한을 두지 않는다.

사용자는 필요한 만큼 Clip을 프로젝트에 추가할 수 있다.

---

## F-MVP-031 — No Fixed Clip Count Limit

하나의 Vlog에 포함할 수 있는 Clip 개수에 제품 차원의 고정 최대 제한을 두지 않는다.

실제 처리 가능 범위는 기기의 저장 공간과 시스템 자원의 영향을 받을 수 있다.

---

## F-MVP-032 — Large Project Handling

프로젝트가 매우 커졌을 경우 앱이 임의로 실패하거나 종료되는 것보다 사용자에게 현재 상태를 명확하게 안내해야 한다.

### Required Direction

- 사용 가능한 저장 공간 고려
- Large Project의 실제 처리 성능과 시스템 자원 고려
- Export 가능 여부 고려
- 큰 프로젝트의 Export 진행 상태 표시
- 실패 발생 시 이해 가능한 오류 제공
- 불필요하게 전체 영상을 Memory에 동시에 로드하지 않는 구조
- Export Snapshot과 Project Duration에 따른 Operation-specific Storage Requirement 판단
- Storage 부족 시 해당 Operation만 차단하고 다른 사용 가능한 기능을 전역 차단하지 않음
- Storage 문제를 새로운 Total Duration 또는 Clip Count 제한으로 해결하지 않음

구체적인 구현 방식은 `ARCHITECTURE.md`에서 정의한다.

---

# 14. MVP — Preview

## F-MVP-033 — Clip Preview

사용자는 개별 Clip을 재생하여 현재 해당 Clip이 실제 Vlog에서 어떻게 보일지 확인할 수 있어야 한다.

Individual Clip Preview는 Raw Source 또는 Raw Working Media를 Editing State 없이 직접 재생하는 기능이 아니라 해당 Clip의 effective edited result를 재생한다.

Individual Clip Preview는 현재 effective Trim, Project Orientation, Fill + Crop을 포함한 current Framing / Scale / Position, applicable Transform, Direct-recorded Front Camera의 Mirrored Appearance, SDR interpretation과 존재하는 Clip Audio를 반영한다.

MVP Clip Preview는 SDR이며 HDR / Dolby Vision Source에서 시작한 Clip도 SDR로 재생한다.

Audio Track이 없는 Imported Clip은 유효한 Silent Clip이며 Individual Clip Preview는 존재하는 Audio만 포함한다.

다른 Clip이 Unavailable이어도 Healthy / Usable Clip의 Individual Clip Preview는 사용할 수 있다.

Unavailable Clip 자체의 Video Preview는 제공하지 않고 Replace 또는 Delete Flow를 사용한다.

0 Clip Project에는 Individual Clip Preview 대상이 없다.

Individual Clip의 Trim, Framing, Transform 또는 Media Availability가 바뀌면 이전 Preview Composition을 Stale로 간주하고 다음 유효 Preview는 최신 effective edited state를 사용한다.

### Acceptance Criteria

| 시나리오 | 기대 결과 |
| --- | --- |
| Trim, Framing 또는 Transform이 있는 Healthy Clip의 Individual Preview | 현재 effective Trim, Framing / Scale / Position과 applicable Transform을 반영한 결과를 재생한다. |
| Direct-recorded Front Clip의 Individual Preview | 촬영 중 사용자가 본 Mirrored Appearance와 동일한 결과를 재생한다. |
| HDR / Dolby Vision Source 또는 Audio가 없는 Imported Clip | SDR로 재생하며 Audio가 없으면 Silent Clip으로 정상 재생한다. |
| 0 Clip Project | Individual Clip Preview 대상이 없다. |
| 다른 Clip이 Unavailable인 Healthy Clip | 다른 Clip의 Unavailable 상태 때문에 Individual Clip Preview가 차단되지 않는다. |
| 대상 Clip이 Unavailable | Raw Media를 대신 재생하거나 Silent Substitute를 사용하지 않고 Replace 또는 Delete Flow를 제공한다. |
| Preview 준비 후 대상 Clip의 Edit State 또는 Availability 변경 | 기존 Composition을 Stale로 처리하고 다음 유효 Preview가 최신 State를 반영한다. |

---

## F-MVP-034 — Full Vlog Preview

사용자는 현재 프로젝트 전체를 하나의 Vlog처럼 연속 재생하여 확인할 수 있어야 한다.

Full Vlog Preview는 Raw Clip을 단순 연결하는 기능이 아니라 현재 Project의 effective edited result를 현재 Clip Order대로 재생하는 기능이다.

### Preview Must Reflect

- Clip order
- 각 Clip의 Trim
- Fill + Crop 및 사용자 Framing
- Project orientation
- applicable Transform
- Direct-recorded Front Camera mirrored appearance
- Video
- valid Clip Audio와 Audio가 없는 Imported Clip의 Silent 상태
- SDR interpretation

전체 Preview는 SDR을 기준으로 하며 Export와 동일한 canonical Composition Semantics를 사용한다.

HDR Source라는 이유로 Preview만 HDR로 재생하는 별도 기본 Pipeline을 두지 않는다.

초기 MVP에서는 Clip Boundary에 Fade, Dissolve, Crossfade, Audio Fade 또는 Audio Crossfade를 자동 삽입하지 않고 현재 Clip Order를 직접 이어서 재생한다.

Full Vlog Preview는 하나 이상의 Usable Committed Clip, Unresolved Unavailable Clip 부재와 Valid Composition Source가 있을 때만 제공한다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Full Vlog Preview를 비활성화하고 손상된 Clip을 조용히 생략한 결과를 재생하지 않는다.

Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경은 이전 Full Vlog Preview Composition을 Stale로 만들며 다음 유효 Preview는 최신 Project State를 사용한다.

Full Vlog Preview는 매번 완성 Video File을 사전 Render하는 것을 기본 구현으로 요구하지 않는다.

### Acceptance Criteria

| 시나리오 | 기대 결과 |
| --- | --- |
| 하나 이상의 Healthy Clip이 있는 Project | 현재 Clip Order와 모든 current effective edit state를 반영한 Full Vlog Preview를 제공한다. |
| Reorder, Trim, Framing 또는 Transform 변경 후 다음 Preview | 기존 Composition을 재사용하지 않고 최신 Project State를 반영한다. |
| Direct-recorded Front Clip과 Imported Clip이 섞인 Project | Front Clip의 Mirrored Appearance, Project Orientation, SDR interpretation과 존재하는 Audio를 Export와 같은 의미로 적용한다. |
| Audio가 없는 Imported Clip | 해당 Clip을 valid silent Clip으로 포함하고 자동 Audio Crossfade를 삽입하지 않는다. |
| 0 Clip Project | Full Vlog Preview를 비활성화한다. |
| Healthy Clip과 Unresolved Unavailable Clip이 함께 있는 Project | Full Vlog Preview를 차단하고 Unavailable Clip을 자동 생략한 결과를 재생하지 않는다. |
| Clip Boundary | 자동 Video Transition 또는 자동 Audio Fade / Crossfade 없이 현재 Clip Order를 직접 연결한다. |

---

# 15. MVP — Export

## F-MVP-035 — Export Vlog

사용자는 현재 프로젝트를 하나의 완성된 영상 파일로 Export할 수 있어야 한다.

### Required

- 모든 Clip 결합
- Clip 순서 반영
- 각 Clip의 Trim 반영
- Fill + Crop 및 사용자 Framing 반영
- applicable Transform과 Direct-recorded Front Camera mirrored appearance 반영
- Project orientation 유지
- 존재하는 Clip Audio 유지 및 Audio가 없는 Imported Clip의 Silent 상태 유지
- Preview와 동일한 canonical Composition Semantics 사용
- 안정적인 영상 파일 생성

Export는 하나 이상의 Usable Committed Clip, Unresolved Unavailable Clip 부재와 Valid Composition Source가 있을 때만 시작한다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Export를 비활성화하고 손상된 Clip을 조용히 생략한 결과를 생성하지 않는다.

### Confirmed Video Standard

MVP 표준 Output Profile은 1080p / 30 fps / SDR이다.

Imported Working Media의 1080p-class / 30 fps / SDR 기준은 아래 Project Output Canvas로 미리 Crop한다는 의미가 아니며 F-MVP-021 / F-MVP-022의 Framing 보존 계약을 따른다.

- Portrait 9:16 Output: 1080 × 1920
- Landscape 16:9 Output: 1920 × 1080

Mellow Camera의 기본 Capture Profile도 1080p / 30 fps다.

720p Export, 4K Export와 60 fps Export는 MVP에서 제공하지 않으며 사용자에게 Export Resolution이나 Frame Rate 선택을 제공하지 않는다.

HDR Export는 MVP에서 제공하지 않으며 SDR Export의 Clip Order, Trim, Framing / Scale / Position, Transform, Project Orientation, Front Mirroring, Audio Inclusion 및 색 해석은 동일한 Project State의 Preview와 가능한 한 일치해야 한다.

Export Codec, Container, Bitrate, Audio Codec / Bitrate, 정확한 SDR Color Profile / Tagging, Background Export와 재Export가 필요한 경우의 Retry 세부 정책은 아직 확정하지 않는다.

Working Media Codec / Container와 Export Codec / Container는 별도 Decision이며 자동으로 동일하게 정하지 않는다.

Export는 현재 Immutable Export Snapshot의 Duration과 승인된 Output Profile을 기준으로 Estimated Peak Additional Storage와 Safety Reserve를 판단하고 부족하면 Export를 시작하지 않는다.

Storage 부족을 이유로 Export Quality를 자동 하향하지 않으며 Runtime Disk Full로 생성된 Partial Output을 성공한 Export로 노출하지 않는다.

Local Storage Preflight는 Photos Library의 최종 Save 성공을 보장하지 않으며 Photos Save 실패는 별도 Lifecycle로 처리한다.

Export Rendering은 Export Process 성공, Output File 존재, Output Validation 성공과 현재 Export Operation Identity 연결을 모두 충족하여 Successful Local Export Artifact를 만든 시점에 성공한다.

Photos Save Success는 Export Rendering Success와 별개이며 Photos Save Failure가 Successful Local Export Artifact 또는 Export Rendering Success를 무효화하지 않는다.

성공한 Local Export Artifact는 Photos Save, Photos Save Retry와 iOS Share Sheet에 재사용하며 단순 Photos Save Failure 또는 Share 재시도 때문에 동일 Project를 다시 Render하지 않는다.

Export 후에도 Draft를 유지하며 iOS Share Sheet로 완성된 Video를 공유할 수 있어야 한다.

---

## F-MVP-036 — Save to Photos

완성된 Vlog는 사용자의 iPhone Photos Library에 저장할 수 있어야 한다.

### Required

- 필요한 Photos permission 처리
- Export 진행 상태 표시
- Export Rendering Success와 Photos Save Success를 구분하는 피드백
- Export Rendering Failure와 Photos Save Failure를 구분하는 피드백
- 정상적인 영상 파일을 Photos에 저장
- Photos Save Failure 후 동일 Valid Local Export Artifact를 사용한 Save Retry와 Share
- Share Cancel 후 Artifact, Draft와 Save / Share 재시도 가능 상태 유지
- Photos Save에 성공하지 않은 Result Flow 종료 시 명시적 Discard Confirmation

### Acceptance Criteria

- Successful Render는 Validation을 통과하고 현재 Export Operation과 연결된 Local Export Artifact를 만든다.
- Photos Save Failure는 Successful Render를 실패로 바꾸지 않고 Valid Local Export Artifact를 유지한다.
- Photos Save Retry와 Share는 같은 Valid Local Export Artifact를 재사용한다.
- Share Cancel은 Local Export Artifact를 삭제하거나 Export Failure로 표시하지 않는다.
- Export 이후에도 Project와 Draft는 수정 및 재Export에 사용할 수 있다.
- Photos에 저장 완료된 결과는 Project Lifecycle 밖의 외부 결과로 유지한다.
- Photos Save에 성공하지 않은 Local Export Artifact는 사용자의 명시적 Discard 없이 정리하지 않는다.
- Photos Save, Save Retry, Share Sheet 또는 Share Handoff처럼 Artifact를 사용하는 Active Consumer가 존재하는 동안 Local Export Artifact를 Physical Cleanup하지 않는다.

---

## F-MVP-037 — Preserve Original Media

Preview와 Export 과정은 사용자의 원본 영상 및 원본 Photos Asset을 파괴적으로 변경하지 않는다.

---

# 16. MVP — Permissions

## F-MVP-038 — Camera Permission

첫 실행 Onboarding에서 Camera 사용 의도를 설명하고 필요한 시점에 Camera permission을 요청한다.

권한이 거부된 경우 사용자가 문제와 해결 방법을 이해할 수 있는 상태를 제공하고 앱 전체를 막지 않는다.

Camera Permission이 Denied 또는 Restricted이면 Direct Recording을 시작할 수 없고 Camera Capture UI는 Recording 불가 상태를 명확히 표현한다.

필요한 경우 Settings로 이동할 적절한 경로를 제공할 수 있으며, Camera 권한은 이미 결정된 기존 설치에서는 Onboarding을 건너뜀 상태로 유지할 수 있다.

Camera Permission 문제로 앱 전체나 Photos Video Import를 차단하지 않는다.

Microphone / Photos / Location 권한은 각 기능 소유 Phase에서 별도 요청한다.

---

## F-MVP-039 — Microphone Permission

Audio가 포함된 영상 촬영을 위해 필요한 시점에 Microphone permission을 요청한다.

Microphone Permission이 Denied 또는 Restricted이면 Direct Recording을 시작하지 않고 무음 Direct-recorded Video로 자동 대체하지 않는다.

사용자에게 Microphone Permission이 필요한 이유를 안내하며 Photos Video Import는 계속 사용할 수 있고 Audio Track이 없는 Source Video도 허용한다.

---

## F-MVP-040 — Photos Permission

기존 영상을 Import하거나 완성된 Vlog를 저장하는 데 필요한 최소한의 Photos 접근 권한을 사용한다.

필요 이상의 Photos Library 권한을 요청하지 않는 방향을 우선한다.

---

# 17. MVP — Recording Reliability

## F-MVP-041 — Recording Interruption Handling

촬영 중 앱 또는 시스템 상태 변화로 Recording Session이 중단될 수 있다.

### Possible Cases

- 앱이 Background로 이동
- 전화 또는 시스템 interruption
- Camera session interruption
- 저장 공간 부족
- Recording failure

가능한 경우 이미 정상적으로 기록된 영상 데이터를 보호해야 한다.

촬영이 실패한 경우 사용자가 현재 상태를 이해할 수 있어야 한다.

Interruption은 Successful Manual Stop 또는 Successful selected-maximum Auto-stop으로 표시하지 않고 정상 Completion Haptic을 자동 적용하지 않는다.

생성된 Media는 ADR-020의 Transactional Commit / Validation / Recovery와 ADR-021의 Project Validity / Late Result 계약을 따르며 Invalid 또는 Incomplete Media를 정상 Clip으로 Commit하지 않는다.

ADR-033에 따라 Interruption / Background Partial Media는 1.0초 이상이고 Finalization이 성공하면 Photos에 저장하고 1.0초 미만이면 폐기하며, Hard Crash 이후에는 Best-effort Staging Recovery만 수행한다.

Recording 시작 전에는 Camera / Microphone Permission, Required Capture Device, Session Configuration, Project Validity와 Orientation Eligibility를 확인한다.

Portrait Project는 Portrait Posture, Landscape Project는 Landscape Left 또는 Landscape Right에서 새 Recording을 시작할 수 있다.

ADR-032에 따라 V1이 지원하는 Capture 자세는 upright Portrait이며 Landscape 자세에서는 조용한 `Rotate your iPhone` 안내와 함께 Capture를 사용할 수 없는 상태로 유지한다.

Project Orientation mismatch, Face Up, Face Down, Unknown 또는 안정적으로 판단할 수 없는 Orientation에서는 Recording, Progress와 선택한 최대 Duration Timer를 시작하지 않는다.

Recording 중 Device Rotation만으로 현재 Recording을 Stop / Restart하거나 새 Clip을 만들거나 Project Orientation / Clip Aspect Ratio를 변경하지 않고 Active Rear Zoom을 Reset하지 않는다.

Recording이 끝난 뒤 다음 Record 요청 전에 Orientation Eligibility를 다시 확인한다.

---

## F-MVP-042 — Safe Clip Storage

촬영이 정상적으로 완료된 Clip은 즉시 안전한 로컬 저장소에 보존한다.

사용자가 아직 Vlog를 Export하지 않았다는 이유로 촬영한 Clip이 쉽게 유실되어서는 안 된다.

Storage Pressure 또는 Runtime Disk Full은 Committed Clip, Draft, Project-owned Valid Media, Recovery Candidate, Undo Candidate, Active Usage Media나 다른 Project Media를 자동 삭제할 근거가 아니다.

자동 Cleanup은 ADR-020 / ADR-021에 따라 Recovery가 필요하지 않고 Undo / Active Usage / 다른 Reference가 없다고 안전하게 분류된 Disposable Temporary Artifact 또는 Confirmed Orphan에만 적용한다.

Preflight 이후 Write 또는 Metadata Persistence가 Storage 부족으로 실패하면 Partial / Incomplete Output을 정상 결과로 Commit하지 않고 Final Media가 존재하는 Recoverable Operation은 Recovery Candidate로 보존한다.

Successful Local Export Artifact도 Active Consumer, Retry 또는 Recovery Requirement가 남아 있으면 자동 Cleanup하지 않으며 ADR-025의 Result Lifecycle과 Recovery Classification을 따른다.

---

# 18. MVP — Basic App Areas

Mellow MVP는 최소한 다음 제품 영역을 가진다.

### Launch

ADR-032에 따라 Launch는 `MellowSplashLogo` Splash이며 첫 실행은 Permission Onboarding을 거쳐, 이후 실행은 곧바로 Portrait Camera로 진입한다.

Launch는 Orientation Chooser가 아니며 App Launch만으로 Project를 저장하지 않는다.

ADR-028의 `Format 선택 즉시 Project 저장` Creation Trigger는 Format Chooser와 함께 V1에서 사라지며 Launch 시점 생성으로 대체하지 않는다.

Camera Chrome의 Upper Trailing 영역에 작은 Projects Button을 조용한 Secondary Access로 두고 Accessibility Label은 `Projects`로 제공한다.

ADR-033에 따라 Projects는 저장 Project가 없으면 `Select Clips`, 있으면 `Load Last Saved` / `Select Clips`를 제공하며 Multi-project Recent Browser는 V1 Primary Flow가 아니다. Phase 3 구현의 Recent Projects 화면은 Phase 5에서 이 Entry로 정렬한다.

큰 Existing-project Text CTA와 Camera의 Project Thumbnail / Metadata / Recent Grid는 제공하지 않으며 정확한 Iconography는 Phase 3 Visual 구현에서 정한다.

기존 프로젝트 화면의 사용자-facing 명칭은 `Recent Projects`를 사용한다.

내부 Domain에서는 `Draft`라는 기술 용어를 사용할 수 있다.

0 Clip Project는 유효한 Draft로 Recent에서 다시 열 수 있으며 Error로 표시하거나 자동 삭제하지 않는다.

### Orientation Selection

새 프로젝트의 9:16 또는 16:9 비율을 선택한다.

### Camera

새로운 Clip을 촬영한다.

ADR-032 이후 V1 구조는 Portrait Camera → Short Clip Capture → Clip Review / Management → Editor → Export를 하나의 Persisted Vlog Project 안에서 연결한다.

Camera Chrome은 두 Affordance를 분리한다(ADR-041): Upper-trailing `Projects`가 저장 Project 접근(Projects 화면 → Editor)이고, 좌하단 Compact Slot은 방금 촬영한 Direct Capture의 피드백(이후 별도 승인 시 Latest Capture Review)이다. 좌하단 Slot은 저장 Project Representative나 Editor 바로가기가 아니며 별도 Dashboard나 복잡한 Camera Timeline을 추가하지 않는다. Project Representative Thumbnail은 Projects 화면 같은 Project-oriented Surface에만 표시한다.

### Video Import

Photos Library의 기존 영상을 프로젝트에 추가한다.

### Project / Clips

촬영하거나 가져온 Clip을 확인하고 정리한다.

Unavailable Clip은 기존 위치를 유지하고 Replace 또는 Delete Action에 접근할 수 있어야 한다.

### Trim

각 Clip에서 실제 Vlog에 사용할 구간을 결정한다.

### Preview

현재 프로젝트의 전체 결과를 확인한다.

### Export

완성된 Vlog를 하나의 영상으로 생성하고 저장한다.

정확한 Screen Architecture와 Navigation은 `DESIGN.md`에서 정의한다.

---

# 19. Post-MVP — Advanced Camera Controls

Tap to Focus, Exposure Control, Front Camera Zoom, 0.5× Ultra Wide / Telephoto 선택, Lens Selector와 Torch는 MVP에 포함하지 않으며 도입 시점과 세부 정책은 Post-MVP에서 검토한다.

Rear Camera의 1× 이상 Continuous Zoom은 F-MVP-012의 MVP 기능이며 이 Post-MVP 범위에 포함하지 않는다.

## F-POST-001 — Tap to Focus

사용자가 Camera Preview의 특정 영역을 선택하여 Focus를 지정할 수 있는 기능을 검토한다.

---

## F-POST-002 — Exposure Control

사용자가 촬영 중 간단하게 Exposure를 조절할 수 있는 기능을 검토한다.

---

## F-POST-003 — Advanced Zoom and Lens Controls

Front Camera Zoom, 0.5× Ultra Wide / Telephoto 직접 선택과 Lens Selector 등 MVP보다 확장된 Zoom / Lens Control을 검토한다.

지원 범위와 Lens 전환 정책은 추후 결정하며 MVP Rear 1× 이상 Continuous Zoom을 다시 Post-MVP로 분류하지 않는다.

---

## F-POST-004 — Torch

Rear Camera 촬영 중 Torch를 사용할 수 있는 기능을 검토한다.

---

# 20. MVP — Lightweight Clip Text

## F-MVP-043 — Explicit Clip Text Tool

ADR-030은 기존 F-POST-005 Text Overlay 분류를 가벼운 Clip Text 범위에 한해 대체한다.

선택한 Clip → 명시적인 `T` Tool → 해당 Clip의 Text 추가 / 수정 흐름을 제공하며 `T`는 Editor Tool Layout에서 발견하기 쉬워야 한다.

일반 Clip Tap은 선택만 하고 Text Entry를 열지 않는다.

Font 선택, Position, Size, Text Duration과 Animation 세부 정책은 Phase 7 구현 전 Gate에서 결정하며 복잡한 Typography / Effect Editor, Text Animation System, Keyframe, Multi-track Text Timeline과 Sticker는 추가하지 않는다.

Phase 7은 Text 입력 / 수정 UI를 소유하고 Phase 8 Preview와 Phase 9 Export는 승인된 동일 Text 결과를 반영한다.

---

# 21. Post-MVP — Music

## F-POST-006 — Background Music

사용자는 Vlog에 Background Music을 추가할 수 있는 기능을 향후 사용할 수 있다.

### Open Considerations

- Music source
- Music licensing
- Original audio volume
- Music volume
- Fade in
- Fade out
- Video와 Music 길이 처리

---

# 22. Post-MVP — Transitions

## F-POST-007 — Simple Transitions

Clip 사이에 간단한 Transition을 적용할 수 있는 기능을 검토한다.

많은 Transition Effect를 제공하기보다 Mellow에 어울리는 제한된 종류의 Transition을 제공하는 방향을 우선 검토한다.

---

# 23. Future Candidate — Video Look

## F-FUTURE-001 — Mellow Video Looks

향후 Mellow 특유의 영상 분위기를 표현하기 위한 Video Look 기능을 검토한다.

전문적인 Color Grading 도구보다 선택된 Look을 간단하게 적용하는 방식을 우선한다.

현재 MVP의 구현 대상이 아니다.

---

# 24. Future Candidate — Mini Vlog Templates

## F-FUTURE-002 — Templates

사용자가 많은 편집 결정을 하지 않아도 일정한 흐름의 Mini Vlog를 만들 수 있는 Template 기능을 검토한다.

### Example Candidates

- Daily Vlog
- Travel
- Cafe
- Weekend
- Memories

현재 MVP의 구현 대상이 아니다.

---

# 25. Future Candidate — Assisted Editing

## F-FUTURE-003 — Smart Editing

향후 사용자의 Vlog 편집 부담을 줄이기 위한 자동 또는 반자동 편집 기능을 검토할 수 있다.

### Candidate Features

- Clip recommendation
- Automatic trim assistance
- Automatic arrangement
- Highlight selection
- Beat-aware editing

이 기능은 기본 촬영 및 편집 경험이 충분히 검증된 이후 검토한다.

---

# 26. Future Candidate — Cloud and Sync

## F-FUTURE-004 — iCloud Draft Sync

향후 여러 Apple 기기 또는 기기 교체 상황에서 Draft를 복구하거나 동기화할 수 있는 기능을 검토한다.

초기 MVP에서는 Draft를 로컬 저장한다.

---

# 27. Explicitly Out of Scope

## Additional MVP Exclusions

- Project Rename
- Clip Split
- Clip Duplicate
- Fit Layout
- Background Blur
- 5초 초과 Photos 영상 Import와 긴 원본에서의 최대 5초 Segment Selection, 원본 Source Reference 유지 / 원본 범위 Re-trim(ADR-042)

위 기능의 향후 도입 여부와 세부 범위는 별도 결정 대상이다.

---

## Photo Capture and Editing

Mellow 초기 제품은 다음 기능을 제공하지 않는다.

- Photo Camera
- Photo Import Workflow
- Photo Filters
- Photo Editing
- Photo Export

Mellow는 사진 편집 앱으로 확장하지 않는다.

---

## Professional Video Editor

Mellow는 다음과 같은 전문 영상 편집 기능을 목표로 하지 않는다.

- Multi-track Timeline
- Layer System
- Keyframe Editor
- Advanced Masking
- Chroma Key
- Motion Graphics Editor
- Professional Color Grading
- Complex Speed Curves
- Desktop-class Video Editing

---

## Dual Camera Recording

Front Camera와 Rear Camera를 동시에 촬영하는 기능은 MVP에 포함하지 않는다.

향후 제품 가치가 확인되면 별도로 검토한다.

---

## Social Network

Mellow 자체에 다음과 같은 Social Network 기능을 만들지 않는다.

- Feed
- Follow
- Likes
- Comments
- Creator Social Graph

---

## Desktop Editing

Mellow 초기 제품은 Mac 또는 Desktop용 영상 편집 시스템을 제공하지 않는다.

---

# 28. MVP Completion Definition

Mellow MVP는 다음 사용자 시나리오가 실제 iPhone에서 처음부터 끝까지 안정적으로 동작할 때 완료된 것으로 판단한다.

1. 사용자가 Mellow를 실행한다.
2. 새로운 Vlog 프로젝트를 생성한다.
3. 9:16 또는 16:9를 선택한다.
4. Rear Camera 또는 Front Camera로 새로운 Clip을 촬영한다.
5. 사용자가 원하는 시점에 녹화를 종료하거나 선택한 최대 Duration에 도달하여 자동 종료된다.
6. 추가 Clip을 촬영할 수 있다.
7. Photos Library에서 기존 영상을 가져올 수 있다.
8. 5초 이하 Imported Video는 전체가 Clip이 되며 5초 초과 영상은 거부 안내를 받는다(ADR-042).
9. 촬영 또는 Import한 Clip을 확인할 수 있다.
10. 불필요한 Clip 삭제가 즉시 UI에 반영되고 ADR-038의 Editor Session Undo / Redo History(시간순 LIFO, Process 종료 후 미유지)로 되돌릴 수 있다.
11. Clip의 순서를 변경할 수 있다.
12. 각 Clip의 시작점과 종료점을 Trim할 수 있다.
13. 전체 Vlog를 Preview할 수 있다.
14. 프로젝트 비율에 맞는 1080p / 30 fps / SDR 영상으로 Export할 수 있고 동일한 Project State의 SDR Preview와 색 및 Framing이 가능한 한 일치한다.
15. Export한 영상을 Photos Library에 저장하고 iOS Share Sheet로 공유할 수 있다.
16. 앱 재실행과 기기 재부팅 후에도 자동 저장된 로컬 프로젝트를 계속 작업할 수 있다.
17. 여러 개의 Draft 프로젝트를 동시에 유지할 수 있다.
18. Export 이후에도 Draft를 다시 열어 수정하고 재Export할 수 있다.
19. 프로젝트 전체 삭제는 Confirmation 이후 실행되며 Photos 원본에 영향을 주지 않는다.

이 핵심 흐름 중 하나라도 정상적으로 완료할 수 없다면 MVP가 완료된 것으로 판단하지 않는다.

---

# 29. Confirmed Feature Decisions

현재까지 확정된 기능 결정은 다음과 같다.

- Mellow는 Mini Vlog 전용 앱이다.
- iPhone-first Native Application으로 Swift / SwiftUI를 사용한다.
- Minimum iOS는 iOS 18.0이다.
- 공식 Device Quality Baseline은 iPhone 12 and later이고 Primary Physical Test Device는 iPhone 12다.
- iPhone 12 기준은 개발 및 QA 기준이며 App Store 설치 제한 조건이 아니다.
- 사진 촬영 및 사진 편집 기능은 제품 범위에서 제외한다.
- Mellow 내부에서 직접 영상을 촬영할 수 있다.
- Rear Camera와 Front Camera를 모두 지원한다.
- Camera Switching은 idle 상태에서만 가능하며 Recording 중에는 허용하지 않는다.
- Front와 Rear Camera 동시 촬영은 MVP에 포함하지 않는다.
- Rear Camera는 기본 1× Wide를 사용하며 Preview와 Recording 중 1× 이상 Continuous Zoom을 지원한다.
- Rear Zoom은 승인된 1.0×–2.0× Pinch와 Gesture 중 Transient Indicator를 사용하고 0.5× Ultra Wide, Telephoto와 Lens Selector는 MVP에서 제공하지 않는다.
- Front Camera Zoom은 MVP에서 제공하지 않고 Front Preview와 Direct-recorded Front Clip의 Preview / Editing / Export는 동일한 Mirrored Appearance를 유지한다.
- Camera 또는 Microphone Permission이 없으면 Direct Recording을 시작하거나 무음 Video로 대체하지 않으며 Photos Import는 독립적으로 사용할 수 있다.
- Orientation mismatch / Face Up / Face Down / Unknown / Unstable 상태에서는 새 Recording을 시작하지 않고 Mid-record Rotation은 현재 Recording이나 Project Orientation / Active Rear Zoom을 변경하지 않는다.
- Recording Interruption은 Successful Completion으로 표시하지 않으며 ADR-033에 따라 1.0초 이상이고 Finalization이 성공하면 Photos에 저장하고 미만이면 폐기한다.
- 하나의 촬영 Clip은 최대 5초다.
- 사용자는 선택한 최대 Duration 이전에는 자유롭게 녹화를 종료할 수 있다.
- 촬영 시간이 선택한 최대 Duration에 도달하면 자동으로 녹화를 종료한다.
- Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration을 제공하고 기본 선택은 `3s`다.
- 선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있으며 Project-level 불변 속성이 아니다.
- Recording Pause / Resume는 MVP에서 제공하지 않는다.
- Recording Start에는 Haptic을 사용하지 않는다.
- Successful Manual Stop과 Successful selected-maximum Auto-stop에는 동일한 Recording 종료 의미의 subtle completion haptic을 제공한다.
- Recording Haptic은 보조 Feedback이며 기존 Visual Recording State / Circular Progress / Completion State를 대체하지 않는다.
- Photos Library의 기존 영상을 프로젝트에 Import할 수 있다.
- Imported Video는 원본 전체 길이가 `1.0s <= duration <= 5.0s`(양 끝 포함)일 때만 가져오며 1.0초 미만 / 5.0초 초과 원본은 거부하고 Segment Selection은 제공하지 않는다(ADR-042).
- SDR, HDR / Dolby Vision, 4K / High-resolution 및 30 fps 초과 Source Import를 허용한다.
- 5초 이하 전체 Source의 Project-owned Working Media는 1080p-class / 30 fps / SDR을 기준으로 하며 Photos 원본은 변경하지 않는다.
- Project Fill + Crop을 Working File에 bake-in하지 않고 이후 Framing에 필요한 Source의 유효 화면 영역을 보존한다.
- Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 편집으로 유지한다.
- 정상적으로 추가된 Project-owned Clip은 이후 Photos 원본이 삭제되어도 Draft에 유지한다.
- 프로젝트에서 사용하는 하나의 최종 Clip 길이는 최대 5초다.
- Project orientation은 9:16 Portrait와 16:9 Landscape를 지원하며 ADR-032에 따라 V1의 새 Capture는 9:16 Portrait만 사용한다.
- Recording은 Project를 만들지 않으며 Camera Clip은 Photos Add 권한으로 Photos에 직접 저장된다(ADR-033).
- Direct Capture 최소 길이는 1.0초이며 Microphone은 선택 권한이다(ADR-033).
- V1은 편집 가능한 저장 Project를 하나만 유지하고 대체는 Safe Atomic Replacement를 따르며 Photos 원본을 삭제하지 않는다(ADR-033).
- 하나의 프로젝트에서는 하나의 Orientation을 유지한다.
- Imported Video의 Aspect mismatch 기본 정책은 Fill + Crop이며 사용자가 Framing 위치를 조정할 수 있다.
- Fit과 Background Blur는 MVP에서 제공하지 않는다.
- 개별 Clip 삭제는 즉시 UI에 반영하고 짧은 Undo Opportunity를 제공한다.
- 사용자-visible Undo / Redo는 ADR-038의 Editor Session History(시간순 LIFO)를 따른다.
- Undo는 동일 Clip Identity와 기존 Media 및 해당 Clip의 Metadata를 복원하며 Duplicate Clip을 생성하지 않는다.
- Undo Window 중 Process가 종료되면 다음 실행에 Undo Opportunity를 유지하지 않고 해당 Delete를 확정된 Logical Deletion으로 취급한다.
- 재정렬 후 Undo는 현재 다른 Clip의 상대 순서와 Unrelated Reorder를 보존하며 F-MVP-025의 확정된 복원 위치 기준을 따른다.
- 프로젝트 전체 삭제는 Confirmation 이후 실행한다.
- 전체 Vlog의 총 재생 시간에는 고정 최대 제한을 두지 않는다.
- 하나의 Vlog에 포함할 수 있는 Clip 개수에도 고정 최대 제한을 두지 않는다.
- Recording, Photos Import / Normalization과 Export는 각각 Estimated Peak Additional Storage와 Safety Reserve를 사용하는 Operation-aware Storage Preflight를 적용한다.
- Storage 부족은 기본적으로 해당 Operation만 차단하며 승인된 Media 품질을 자동 하향하거나 Draft / Committed / Recoverable Media를 자동 삭제하지 않는다.
- Runtime Disk Full 또는 Write Failure의 Partial / Incomplete Output을 정상 결과로 Commit하지 않고 기존 Committed Media와 Photos 원본을 보호한다.
- 여러 개의 미완성 Vlog 프로젝트를 동시에 저장할 수 있다.
- Draft에는 자동 만료 기간을 두지 않는다.
- Draft는 사용자가 직접 삭제하기 전까지 유지한다.
- 프로젝트 상태는 자동 저장하며 앱 재실행과 기기 재부팅 후에도 로컬 Draft를 유지한다.
- 0 Clip Project는 유효한 Draft로 보존하고 Recent에서 다시 열며 Recording과 Photos Import를 허용하고 Full Preview와 Export는 비활성화한다.
- Unavailable Clip은 기존 Timeline Position에 남기고 자동 삭제, 자동 대체 또는 조용한 Preview / Export 생략을 하지 않으며 사용자가 Replace 또는 Delete할 수 있게 한다.
- 일부 또는 모든 Clip이 Unavailable이어도 Project와 Healthy Clip을 보존하고 새 Direct Recording, Photos Video Import, Replace와 Delete를 허용하며 Full Preview와 Export는 Unresolved Unavailable Clip이 없을 때만 제공한다.
- Replace 실패는 기존 Unavailable Placeholder, Project와 다른 Clip을 유지하고 성공한 Replace는 Unrelated Reorder 없이 기존 Logical Slot을 복구한다.
- 앱 삭제 및 기기 교체 이후 복구와 iCloud 동기화·복구는 MVP 보장에 포함하지 않는다.
- 프로젝트 이름 입력 Prompt는 MVP에서 제공하지 않는다.
- 프로젝트 이름은 생성 날짜 및 시간을 기준으로 자동 생성한다.
- Project Rename은 MVP에서 제공하지 않는다.
- 전용 기존 프로젝트 Browser는 `Recent Projects`로 표시하며 내부 Domain에서는 `Draft` 용어를 사용할 수 있다.
- Draft의 Representative Thumbnail은 current logical Clip Order의 첫 번째 Healthy / Usable Clip을 기준으로 하며 Unavailable Clip은 건너뛰고 0 Clip 또는 All-unavailable Project에는 Placeholder를 사용한다.
- Representative Thumbnail은 Derived / Cache Data이므로 Failure가 Project / Clip Corruption이나 Recent Load Failure를 의미하지 않으며 mutation과 stale async result에서 current Representative를 다시 검증한다.
- Export 이후에도 Draft를 자동 삭제하지 않는다.
- Draft를 다시 열어 수정하고 다시 Export할 수 있다.
- MVP Preview는 SDR이며 Export는 1080p / 30 fps / SDR을 기준으로 하고 Portrait Output은 1080 × 1920, Landscape Output은 1920 × 1080이다.
- Individual Clip Preview는 Raw Source가 아닌 current effective edited result를 제공하고 Full Vlog Preview와 Export는 같은 canonical Composition Semantics로 Clip Order, Trim, Framing / Scale / Position, Transform, Project Orientation, Front Mirroring, SDR 해석 및 Audio Inclusion을 적용한다.
- MVP Full Vlog Preview와 Export는 현재 Clip Order를 직접 이어서 사용하며 자동 Video / Audio Transition을 삽입하지 않는다.
- Healthy Clip의 Individual Preview는 다른 Clip의 Unavailable 상태와 무관하게 가능하고 Unavailable Clip 자체의 Video Preview는 제공하지 않는다.
- Composition에 영향을 주는 Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경 뒤에는 다음 유효 Preview가 최신 Project State를 사용한다.
- HDR Export는 MVP에서 제공하지 않는다.
- 720p Export, 4K Export와 60 fps Export는 MVP에서 제공하지 않는다.
- Export Rendering Success와 Photos Save Success를 분리하고 Successful Local Export Artifact를 Save, Save Retry와 Share에 재사용한다.
- Photos Save Failure는 Rendered Result와 Draft를 유지하고 Save Retry와 Share를 제공하며 Share Cancel은 Artifact를 유지한다.
- Photos Save에 성공하지 않은 Result Flow 종료는 명시적 Discard Confirmation을 요구하고 Photos에 저장된 결과는 Project Lifecycle 밖의 외부 결과로 유지한다.
- 핵심 미디어 작업은 Local-first로 동작한다.
- Clip Split과 Duplicate는 MVP에서 제공하지 않는다.
- Focus, Exposure, Zoom, Torch 등 Advanced Camera Controls는 Post-MVP 검토 대상이다.
- Photos에서 가져온 원본 영상은 변경하거나 삭제하지 않는다.
- Original Media는 비파괴 방식으로 처리한다.

---

# 30. Open Decisions

다음 항목은 확정된 MVP 결정의 세부사항 또는 향후 검토 사항이며 이미 확정된 MVP 포함·제외 여부를 다시 Open으로 취급하지 않는다.

## Camera

- Post-MVP Tap to Focus 도입 시점 및 세부 동작
- Post-MVP Exposure Control 도입 시점 및 세부 동작
- Rear Zoom Maximum Product Quality Limit — Resolved: 2.0×, Minimum 1.0×
- Rear Zoom Interaction / Indicator — Resolved: Pinch, Gesture 중 Transient Numeric Indicator 허용, Persistent Button / Slider 없음
- Post-MVP Front Camera Zoom과 Advanced Lens Control 도입 시점 및 지원 범위
- Post-MVP Torch 도입 시점 및 세부 동작
- Rear 1× Wide, Ultra Wide / Telephoto / Lens Selector 제외와 Front Mirroring 정책 — Resolved by ADR-023

## Recording

- 최소 Clip 길이 제한 여부 — Direct Capture는 Resolved by ADR-033(1.0초); Imported Photos Source는 Resolved by ADR-042(1.0초)
- Recording Error / Interruption의 Haptic 정책
- 승인된 Completion 의미 안의 정확한 Haptic API / Style / Intensity / Pattern / Duration / Generator 구현 및 Tuning
- 선택한 최대 Duration 자동 종료 직전 Visual Feedback 방식
- 앱이 Background로 이동할 때 촬영 중 Clip 처리 정책 — Resolved by ADR-033(즉시 정지 / Finalize, 1.0초 이상이면 저장)
- Recording Interruption에서 Valid Partial Clip의 최종 처리 — Resolved by ADR-033

## Orientation

- Phase 2 Orientation Selection 구조 — Resolved by ADR-028: Launch Chooser에서 선택 즉시 저장 후 Camera Placeholder 진입.
- 9:16 프로젝트 촬영 중 기기를 가로로 들었을 때 제공하는 회전 안내의 구체적인 형태와 위치
- 16:9 프로젝트 촬영 중 기기를 세로로 들었을 때 제공하는 회전 안내의 구체적인 형태와 위치
- 정확한 Orientation Detection API / Threshold / Debounce

## Imported Video

- Trim과 Crop의 세부 화면 구성
- Crop 시 Pinch to Zoom 지원 여부
- Imported Clip의 Re-trim 범위 및 Source Reference 유지 여부 — Resolved by ADR-042: Project-owned Clip Media 범위 안에서만 Re-trim, Source Reference 없음
- Working Media Codec / Container
- 정확한 SDR Color Profile / Tagging 및 Tone-mapping 구현 방법
- 저해상도 Source의 Upscaling 정책
- 1080p-class Working Media의 정확한 Raster Dimension Rule
- Post-MVP Fit 또는 Background Blur 도입 여부

## Project

- Recent Layout과 Phase 2 표시 정보 — Resolved by ADR-028: Adaptive Thumbnail Grid, Neutral Placeholder, 자동 이름, Orientation과 Clip Count.
- 프로젝트 자동 표시 이름의 구체적인 날짜 및 시간 Format
- Phase 2 Project 삭제 Confirmation — Resolved by ADR-028: Item Menu → Delete → System Alert.
- Draft 저장 실패 처리 및 자동 복구의 세부 정책
- Phase 2의 0 Clip Project 표현 — Resolved by ADR-028: 동일 Recent Item에 Neutral Placeholder와 `0 clips`; Project-level Corruption의 Exact Failure-state UI / Copy는 Pending.
- Project Metadata Recovery Algorithm
- Representative Thumbnail의 정확한 Frame Selection, Placeholder Visual, Image Format / Dimensions, Cache Directory, Eviction과 Retry Policy
- Operation-aware Storage Preflight와 Fixed Global Threshold 미사용 — Resolved by ADR-024
- 정확한 Safety Reserve 크기 — Pending, 관련 Media Operation Phase Gate
- Recording / Import / Export의 정확한 Storage Estimate Formula와 계산 상수 — Pending, 각 Owning Phase Gate
- Storage Warning 기준과 Low-storage UI의 정확한 Presentation — Pending, Owning UX Gate
- Draft Storage 사용량 표시 여부
- 프로젝트 Rename 기능의 Post-MVP 추가 여부
- Export 완료 프로젝트와 미완성 프로젝트의 UI 구분 여부

## Clip Management

- (Resolved by ADR-038: Undo Window 불필요, Undo / Redo는 Navigation Bar 상시 Control) Delete / Undo의 세부 Visual Tuning
- Delete / Undo Animation
- Delete / Undo Haptic
- Delete UI의 시각적 처리
- Physical Deletion의 구체적인 구현 방식
- Active Usage Tracking의 구체적인 구현 방식
- Coordinator / Lease / Reference Counter 구조
- Unavailable Clip의 Exact Visual Design과 Replace UI Flow — Resolved by ADR-040 / DESIGN 19절 STEP 13
- Replacement Clip Identity와 Trim, Framing, Transform, Thumbnail Metadata Preserve / Reset 및 사용자 Reset 안내 정책 — Resolved by ADR-040 (새 Identity, Trim / Framing Reset, 새 Thumbnail, Phase 5에는 안내할 Reset 없음)
- Post-MVP Clip Duplicate 도입 여부
- Post-MVP Clip Split 도입 여부
- 개별 Clip Mute 기능 필요 여부

## Export

- Video Codec
- File Container
- Video Bitrate, Audio Format 및 Audio Bitrate
- 확정된 SDR Export 방향 내 정확한 SDR Color Profile / Tagging 세부값
- 고정된 1080p / 30 fps 범위 내 Export Quality 선택 기능 제공 여부
- ADR-025로 확정된 Render / Photos Save / Share Lifecycle을 전제로 한 Export 및 Share 화면의 세부 UX, Exact Completion UI와 Retry Button Placement
- Export 중 앱 Background 이동 처리 방식
- 재Export가 필요한 경우의 Export Failure Retry 방식

## Audio

- 전체 프로젝트 Audio On / Off 기능
- 개별 Clip Mute 기능
- 개별 Clip Volume 조절 기능

## Future Editing

- 가벼운 MVP Clip Text의 세부 정책 — Before Phase 7
- Music 기능의 구체적인 범위
- Transition 기능의 구체적인 범위
- Video Look 기능 도입 여부
- Template 시스템 도입 여부
- Smart Editing 기능 도입 여부

## Cloud

- iCloud Draft Backup
- iCloud Sync
- 기기 변경 시 Draft 복원

각 Open Decision은 제품 가치, UX 단순성, 기술 비용을 함께 검토한 후 이후 문서에서 순차적으로 결정한다.
