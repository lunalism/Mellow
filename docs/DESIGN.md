# Mellow — Design Definition

## 1. Document Purpose

이 문서는 Mellow의 사용자 경험, 화면 구조, 인터랙션 원칙, 시각적 방향을 정의한다.

`PRODUCT.md`가 제품의 목적을 정의하고 `FEATURES.md`가 기능 범위를 정의한다면, 이 문서는 사용자가 그 기능을 실제로 어떻게 경험하는지를 정의한다.

이 문서는 실제 SwiftUI 화면 구현의 디자인 기준으로 사용한다.

기술 구현 방식은 `ARCHITECTURE.md`에서 별도로 정의한다.

확정되지 않은 디자인 세부사항은 임의로 구현하지 않는다.

---

## 2. Design Philosophy

Mellow의 디자인은 영상 자체가 중심이 되어야 한다.

사용자는 앱의 UI를 보기 위해 Mellow를 사용하는 것이 아니라 자신의 순간을 기록하기 위해 Mellow를 사용한다.

모든 화면과 인터랙션은 다음 원칙을 따른다.

### 2.1 Content First

영상이 항상 화면에서 가장 중요한 시각적 요소가 되어야 한다.

UI가 영상보다 강하게 보이지 않아야 한다.

촬영 화면에서는 특히 장식적인 요소를 최소화한다.

### 2.2 Calm

Mellow는 빠르게 반응하지만 시각적으로 조급하게 느껴지지 않아야 한다.

과도한 Animation, Flash, Pop-up, 강한 경고 표현을 피한다.

### 2.3 Simple

한 화면에서 사용자가 내려야 하는 결정의 수를 최소화한다.

한 번에 많은 기능을 보여주지 않는다.

필요한 기능만 현재 Context에 맞게 표시한다.

### 2.4 Natural

버튼을 누른 뒤의 반응과 화면 전환은 사용자가 예상할 수 있어야 한다.

앱의 동작이 놀랍거나 복잡하기보다 자연스럽고 익숙하게 느껴져야 한다.

### 2.5 Fast to Capture

Mellow에서 가장 중요한 행동은 촬영이다.

사용자가 새로운 Vlog를 시작한 뒤 가능한 짧은 단계 안에 촬영 화면으로 진입할 수 있어야 한다.

### 2.6 Minimal Editing

편집 화면은 전문 Video Editor처럼 보여서는 안 된다.

Timeline, Layers, Track과 같은 전문 편집 개념을 가능한 한 사용자에게 노출하지 않는다.

---

## 3. Brand Direction

Mellow의 브랜드는 따뜻하고 차분한 필름 감성을 기반으로 한다.

전체적인 시각 키워드는 다음과 같다.

- Warm
- Calm
- Soft
- Minimal
- Cozy
- Film-inspired
- Gentle
- Personal

Mellow의 브랜드 화면은 ADR-028의 Native Adaptive System Appearance를 따른다.

Camera와 Video Preview 화면에서는 브랜드 컬러보다 영상 콘텐츠의 가독성을 우선한다.

촬영 UI에 브랜드 컬러를 과도하게 적용하지 않는다.

---

## 4. Visual Separation Principle

Mellow의 일반 App UI와 Camera UI는 같은 브랜드에 속하지만 시각적으로 동일하게 만들 필요는 없다.

### Brand-oriented Screens

다음 화면에서는 Mellow의 따뜻한 브랜드 스타일을 적극적으로 사용할 수 있다.

- Home
- Recent
- New Vlog
- Orientation Selection
- Empty State
- Settings
- Export Completion

### Content-oriented Screens

다음 화면에서는 영상 콘텐츠가 UI보다 우선한다.

- Camera
- Clip Preview
- Trim
- Crop
- Full Vlog Preview

Content-oriented Screen에서는 Black, Dark Neutral, White Overlay 등 영상 위에서 높은 가독성을 제공하는 색상을 우선한다.

---

## 5. Information Architecture

Mellow MVP의 기본 화면 구조는 다음과 같다.

- Launch / Splash
  - 첫 실행: Permission Onboarding → Portrait Camera
  - 이후 실행: Portrait Camera
- Portrait Camera (V1의 기본 Application Surface)
  - Quiet Projects Access → 전용 Pushed Projects 화면 `프로젝트`(ADR-035 Destination, ADR-036 Content): 항상 두 개의 중앙 Action `새 프로젝트 시작`(Primary) / `기존 프로젝트 불러오기`(저장 Project 있을 때만 Enabled, ProjectEditor 직접 열기); 표준 Back으로 Camera 복귀. Recent Grid / Card / Metadata 없음; Multi-project Recent Grid는 V1 Primary Flow가 아니며 구조만 보존한다.

Project 내부의 주요 흐름은 다음과 같다.

- Camera
- Import Video
- Clip Organizer
- Trim / Crop
- Preview
- Export

사용자가 기능 구조를 이해하기 위해 복잡한 Navigation Hierarchy를 학습할 필요가 없어야 한다.

---

## 6. Launch

ADR-032에 따라 V1의 시작 경험은 Splash이며 Format Chooser, Home Dashboard와 중간 New Vlog Button을 두지 않는다.

첫 실행은 `Splash → Permission Onboarding → Portrait Camera`, 이후 실행은 `Splash → Portrait Camera`다.

제품 원칙은 `Mellow를 열면 바로 촬영을 시작한다`이며 Camera가 기본 Application Surface가 된다.

ADR-028의 `Choose your vlog format` Orientation Chooser와 Format-first Creation은 V1 Target UX에서 제거되며 Phase 2 Visual Baseline은 `DECISIONS.md`의 승인 기록으로 보존한다.

### Splash

승인된 Splash Asset은 `MellowSplashLogo`이며 Catalog 위치는 `MellowApp/Resources/Assets.xcassets/MellowSplashLogo.imageset`이다.

Launch 표현은 승인된 Camera-symbol Logo Artwork만 사용한다.

Marketing Copy, Tagline, Loading 비율 표시, Onboarding 문구와 장식 Illustration은 두지 않는다.

Native iOS Launch Screen / Launch Presentation에 Logo를 중앙 배치하고 인위적인 Timer, 강제 지연과 긴 Animation 없이 Application 상태가 준비되는 즉시 전환한다.

Splash는 Brand Identity, Launch Continuity와 Onboarding / Camera로의 매끄러운 전환을 위한 것이며 시작을 의도적으로 지연시키기 위한 화면이 아니다.

정확한 Logo 표시 크기와 Light / Dark Background 표현은 구현 Visual Review 세부로 남긴다.

시작 경험에는 Recent Item을 직접 표시하지 않으며 사용자에게 Draft 용어를 노출하지 않는다.

## 6.1 Permission Onboarding

Camera 진입 전 Onboarding은 기능 동작을 설명하고 필수 권한을 준비하는 목적의 간단한 단계다.

이 단계의 목적은 `Splash → Portrait Camera` 전환의 갑작스러운 권한 실패를 줄이고, 사용자 기대를 맞추는 것이다.

Camera 권한은 설명 상태에서 요청되며, 안내 자체와 시스템 권한 요청은 분리한다.

ADR-033에 따라 첫 실행 Onboarding은 `Camera → Microphone → Photos Add`를 각각 설명한 뒤 한 번에 하나씩 시스템 요청하며 iOS 권한 Sheet를 동시에 띄우지 않는다. Microphone은 선택(거부 시 무음 Recording), Photos는 가장 좁은 Add-to-library 권한이며 Location은 요청하지 않는다. Phase 3 구현의 Camera-only 요청은 Phase 4에서 이 순서로 확장한다.

카메라가 허용된 기존 설치는 Onboarding을 건너뛸 수 있으며, 완료 상태는 앱 재실행 간에 유지되는 app-level flag로 추적한다.

Onboarding은 첫 실행에서만 강하게 제시되며, 앱 전체에서 반복되지 않는다.

---

## 7. Recent

> **현재 상태(2026-09-15, Phase 5 STEP 7):** 이 화면은 Canonical Camera 경로에서 더 이상 진입하지 않는다(Camera `Projects` → `프로젝트`, §11 Projects Access 참조). 아래 내용은 Phase 2 당시 승인 기록이며 Multi-project Recent Browser 구조는 Post-V1 복원 결정 전까지 DEBUG 회귀 경로로만 보존한다.

ADR-033에 따라 V1은 편집 가능한 저장 Project를 하나만 유지하며 Camera `Projects` Entry가 저장 Project가 없으면 `Select Clips`, 있으면 `Load Last Saved` / `Select Clips`를 제공한다. 아래 Multi-project Recent Grid는 ADR-028 당시의 승인 기록이며 V1 Primary Projects Flow가 아니고 Post-V1 복원 결정 전까지 구조만 보존한다.

Recent Projects는 ADR-028에 따라 전용 화면의 두 열 Adaptive Thumbnail Grid로 표시하고 Accessibility Size에서는 한 열로 전환한다.

Phase 2는 실제 Thumbnail을 생성하지 않으며 Orientation과 무관하게 동일한 외부 Placeholder Geometry를 유지한다.

프로젝트는 마지막 수정 시각을 기준으로 최근 항목부터 표시하는 방향을 우선한다.

### Phase 2 Project Information

ADR-028에 따라 Neutral Placeholder, 기존 Domain의 자동 Project Name, Project Orientation / Aspect Ratio와 Clip Count만 표시한다.

Recent의 날짜 기반 표시 이름만 `Sep 13 · 9:10 AM`과 같은 Locale-aware Compact Month / Day 및 Short Time으로 표현하며 Canonical Domain displayName은 변경하지 않고 일반 Text Size에서 한 줄, Accessibility Size에서 필요한 줄바꿈을 허용한다.

추가 Creation / Modified Timestamp와 Duration은 표시하지 않는다.

0 Clip Project도 동일한 Item에 `0 clips`로 표시하며 별도 Card나 Draft Category를 만들지 않는다.

Thumbnail은 현재 Project의 logical Clip Order에서 첫 번째 Healthy / Usable Clip을 기본 대표 이미지로 사용한다.

Unavailable Clip은 Recent의 Representative Thumbnail Source가 될 수 없으며 Representative Source의 `첫 번째`는 Clip 생성 시각이나 Filename이 아니라 current logical Clip Order를 기준으로 판단한다.

Clip이 없거나 모든 Clip이 Unavailable인 Project는 unrelated Media를 재사용하지 않는 neutral Placeholder를 표시할 수 있다.

Representative Thumbnail은 현재 Project를 대표하는 Derived Representation이므로 Thumbnail Failure를 destructive Project Error처럼 표현하지 않으며 Project / Clip Media, Recent 진입과 다른 Project를 유지한다.

Representative Source는 Reorder, Delete, Undo Restore, Replace 성공, Availability Change와 Project Reload 또는 Reconciliation 뒤에 다시 평가하며 Replace Failure는 기존 Unavailable Placeholder와 current Representative 상태를 유지한다.

Representative Thumbnail은 가능한 범위에서 Project Orientation, Framing, Transform, Direct-recorded Front Mirror Semantics와 SDR Interpretation을 반영한 current effective edited appearance와 일치해야 한다.

정확한 Placeholder Illustration, Thumbnail Crop, Corner Radius, Overlay, Badge, Unavailable Visual과 Thumbnail Frame Selection은 Phase 2 또는 해당 Owning UX Gate에서 결정하되 0 Clip 또는 All-unavailable 상태를 Corruption처럼 표현하지 않는다.

---

## 8. New Vlog

ADR-032에 따라 V1에는 별도의 New Vlog Action과 형식 선택 단계가 없다.

사용자는 Splash 이후 Portrait Camera에 도달하며 프로젝트 이름을 입력하도록 요구하지 않는다.

기본 흐름은 다음과 같다.

1. Splash
2. 첫 실행에서는 Permission Onboarding
3. Portrait Camera 진입

App Launch만으로 비어 있는 Project를 저장하지 않으며 새 Portrait Project의 정확한 생성 시점은 Recording / Capture 구현 Phase가 소유한다.

사용자가 촬영 전에 입력해야 하는 필수 Text Field는 두지 않는다.

---

## 9. Orientation Selection

ADR-032에 따라 V1은 Orientation Selection 화면을 제공하지 않으며 새 프로젝트는 항상 `9:16 Portrait`이다.

아래 두 형식은 Domain / Schema가 계속 표현하는 값이며 Landscape 선택 UI의 복원은 Post-V1 Product Decision이다.

### Portrait

**9:16**

세로 기반의 Mini Vlog를 위한 모드다.

### Landscape

**16:9**

가로 기반의 Mini Vlog를 위한 모드다.

두 옵션은 기술적인 설정 항목처럼 보이지 않고 시각적으로 이해하기 쉬운 선택지로 표현한다.

화면 비율 Preview 또는 간단한 Visual Representation을 사용할 수 있다.

Phase 2의 `선택 즉시 저장 후 Camera 진입` 흐름은 ADR-032의 Format Chooser 제거와 함께 V1에서 사용하지 않으며 Launch 시점 생성으로 대체하지 않는다.

Project 삭제는 Item Menu의 Delete에서 System Confirmation Alert를 거치며 Phase 2에서 Swipe-to-delete는 사용하지 않는다.

---

## 10. Orientation Behavior

프로젝트 Orientation은 프로젝트 생성 시 결정되고 프로젝트가 유지되는 동안 변경하지 않는다.

기기의 물리적 회전으로 프로젝트 비율을 자동 변경하지 않는다.

ADR-032에 따라 V1이 지원하는 Capture 자세는 upright Portrait이며 아래 16:9 Project 동작은 Landscape 복원 Phase가 소유한다.

### 9:16 Project

사용자가 iPhone을 Portrait 방향으로 들고 촬영하도록 유도한다.

기기가 Landscape 방향으로 회전된 경우 촬영 화면 위에 조용한 Orientation 안내를 표시한다.

### 16:9 Project

사용자가 iPhone을 Landscape 방향으로 들고 촬영하도록 유도한다.

기기가 Portrait 방향인 경우 가로 방향으로 돌리라는 안내를 표시한다.

Orientation mismatch 상태를 오류처럼 강하게 표현하지 않는다.

안내는 영상 Preview를 크게 가리지 않아야 한다.

새 Recording은 Device Orientation이 Project Orientation과 일치할 때만 시작한다.

9:16 Project는 Portrait Posture, 16:9 Project는 Landscape Left 또는 Landscape Right에서 Recording을 시작할 수 있다.

Face Up, Face Down, Unknown 또는 아직 안정적으로 판단할 수 없는 Orientation에서는 새 Recording을 시작하지 않는다.

Recording을 시작할 수 없는 상태임은 이해 가능해야 하지만 Project Aspect Ratio를 바꾸거나 Camera를 자동 회전시키지 않고 quiet / subtle / content-first Rotate Device Guidance를 제공한다.

정확한 Icon, Wording, Banner / Toast / Overlay 형태, Animation과 위치는 Phase 3 Structural UX Gate에서 결정한다.

Recording이 시작된 뒤 Device를 회전해도 현재 Recording을 자동 Stop / Restart하지 않고 Project Orientation과 Clip Aspect Ratio를 변경하지 않으며 다음 Record 요청 전에 Orientation을 다시 확인한다.

ADR-033에 따라 Active Recording 중에는 `Rotate your iPhone`을 차단 상태로 표시하지 않으며 Progress와 Shutter Stop이 Primary로 유지된다. Recording이 끝나면 즉시 자세를 재평가하여 upright Portrait이 아니면 `Rotate your iPhone` 안내를 복원하고 다음 Recording을 막는다.

---

## 11. Camera Screen

Camera는 Mellow에서 가장 중요한 화면이다.

사용자는 Camera를 열었을 때 별도의 설명 없이 바로 촬영 방법을 이해할 수 있어야 한다.

Camera Preview는 화면을 거의 전부 차지하는 Full-bleed 구조로 유지한다.

ADR-032에 따라 V1 Camera는 Portrait 9:16 전용이며 Camera가 기본 Application Surface다.

Splash / Onboarding 단계에서 Camera Foundation 준비가 완료되어도 Camera Preview는 실제 Camera 진입 전에 시작하지 않는다.

출력 비율은 Project Orientation을 기준으로 소프트 가이드나 외곽 틴트로 표시하여 프레이밍 의도를 유지한다.

### Projects Access

Format Selection 화면이 사라지므로 Projects 진입은 Camera Chrome으로 이동한다. ADR-033에 따라 구조는 `Portrait Camera → Projects → Select Clips`(저장 Project 없음) 또는 `Portrait Camera → Projects → Load Last Saved / Select Clips`(저장 Project 있음)이며 `Select Clips`로 대체할 때는 `Creating a new project will replace your last saved project.`에 해당하는 확인을 거친다.

Projects는 조용한 Secondary Action으로 유지하고 Camera가 시각적으로 우선한다.

Camera에 Recent Grid를 직접 표시하지 않고 `Continue an existing project?` CTA도 사용하지 않으며 Multi-project Recent Browser는 V1 Primary Flow가 아니다.

선호 배치는 Camera Chrome의 Upper Trailing이고 Accessibility Label은 `Projects`이며 정확한 SF Symbol, 크기, 간격과 Press 표현은 구현 Polish로 남긴다.

#### Projects 화면 — Final Visual Baseline (ADR-036 Interaction, 승인 Mockup)

Projects는 Native NavigationBar(중앙 Inline Title `프로젝트`, 시스템 Back)를 가진 전용 Pushed 화면이며 Project 관리 화면이 아니라 **단순한 결정 화면**이다. Navigation Bar 아래 남은 영역을 Content Canvas로 보고 하나의 Content Group을 **수평 + 수직 중앙**에 놓는다(Geometry-aware Layout, 고정 Top Offset / 절대 좌표 없음; Dynamic Type 초과 시 Clipping / Font 축소 대신 Scroll).

**공통 구조(순서 고정):** ① 작은 상단 Visual(~80pt Rounded Square, Radius 20, 장식용 / Tap 불가 / VoiceOver 제외) ② 상태별 Headline(title2 Semibold) ③ 상태별 Supporting Copy(subheadline, `.label`) ④ Compact Primary `+ 새 프로젝트 시작` ⑤ Quiet Secondary `기존 프로젝트 불러오기`. Supporting Copy → Primary 간격이 Primary → Secondary 간격보다 크며 두 Action은 하나의 선택 단위로 읽힌다.

- **저장 Project 없음:** Visual = 중립 Placeholder(`tertiarySystemFill` + `film` Symbol). Headline `아직 프로젝트가 없어요`. Supporting `촬영한 순간들을 골라 / 첫 번째 Vlog를 만들어보세요.`. Primary Enabled, Secondary **Disabled**(같은 위치, 감소된 강조, 사용할 수 없음 Accessibility State).
- **저장 Project 있음:** Visual = Project Representative Visual Contract — 이후 Thumbnail Slice가 ① Canonical Representative Project Thumbnail ② 첫 Usable Clip Thumbnail ③ Placeholder 우선순위로 공급하며(Aspect Fill, Rounded Square Clip), 공급되기 전에는 결정적으로 Placeholder를 사용하고 Thumbnail이 존재한다고 주장하지 않는다. Headline `이어서 만들래요?`. Supporting `마지막으로 저장한 프로젝트가 있어요.`. Primary / Secondary 모두 Enabled; Secondary는 List / Card / 추가 확인 없이 ProjectEditor를 직접 연다.
- **Primary Style:** Compact Rounded Rectangle(Radius 16, ~260pt 폭, ≥52pt, Capsule / Edge-to-edge 아님), Decorative `plus` Symbol + Label(Accessibility Label은 `새 프로젝트 시작`). Background는 Light / Dark 동일한 Mellow Signature Gradient(§30 Mellow Signature Colors, `#FF8A65 → #FF7A45 → #FF5E3A` Horizontal), Foreground는 `plus`와 Label 모두 Near-black Signature Foreground. Glow / Shadow / Border / Gradient Animation 없음 — 이 CTA가 Appearance를 가로지르는 Brand Anchor다.
- **Secondary Style:** Border / Background 없는 중앙 Text Button(subheadline Semibold, `.primary`, ≥44pt Target). Disabled는 같은 자리에서 감소된 강조(Contrast Audit 통과 수준)로 남고 VoiceOver가 사용할 수 없음을 알린다. Destructive Styling은 대체 확인 Alert에만 있다.
- **표시하지 않음:** `최근 프로젝트` / `마지막 프로젝트` Section, Project Card, Project 날짜 / 이름, Clip 수, 길이, `이어서 편집`, Recent List / Grid, Caption / Badge / Overlay, Illustration, Dashboard.
- VoiceOver 순서: Navigation → Headline → Supporting → `새 프로젝트 시작` → `기존 프로젝트 불러오기`. 화면 Copy는 임시 Korean V1 Copy이며 Localization은 이후 Polish다.

### Primary Controls

Control은 미리보기 위에 오버레이로 배치한다.

- Record
- Front / Rear Camera Switch
- Recorded Clips 진입
- Import Video
- Back 또는 Project Exit

Primary Record Button은 촬영 화면에서 가장 명확한 Action이어야 한다.

기타 Control은 Record Button보다 시각적 우선순위가 낮아야 한다.

Rear Camera는 기본 1× Wide Capture와 1× 이상 Continuous Zoom을 Preview 및 Recording 중 지원한다.

Rear Zoom은 Content-first Interaction을 유지하며 0.5× / 1× / Telephoto Lens Selector 또는 물리 Lens 선택 UI를 제공하지 않는다.

Phase 3 승인 구조는 동일한 Rear 1× Wide Camera에서 1.0×–2.0× Pinch-to-zoom이며 양 끝에서 Clamp한다.

Persistent Zoom Button / Slider는 없으며 Gesture 중 작은 Numeric Indicator만 허용하고 Gesture Feel은 iPhone 12에서 조정할 수 있다.

Front Camera에는 Zoom UI / Gesture를 제공하지 않는다.

Front Preview는 Mirrored Appearance를 사용하고 Mellow에서 직접 촬영한 Front Clip의 Preview / Editing / Export도 사용자가 촬영 중 본 Mirrored Framing과 일치해야 한다.

Mirror Toggle은 MVP에서 제공하지 않는다.

---

## 12. Recording Interaction

사용자가 Record Button을 누르면 즉시 녹화를 시작한다.

사용자는 선택한 최대 Duration 이전 언제든 Record Button을 다시 눌러 녹화를 종료할 수 있다.

선택한 최대 Duration에 도달하면 Mellow가 자동으로 Recording을 종료한다.

Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration을 제공하고 기본 선택은 `3s`다.

선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있으며 Project-level 불변 속성이 아니다.

Preset은 정확한 Output 길이를 강제하지 않으며 3s 선택 후 1.4초에 수동 종료할 수 있다.

ADR-033에 따라 Shutter는 Idle에서 Tap → 시작, Recording 중 Tap → Manual Early Stop이며 Hold-to-record는 없다. 실제 길이가 1.0초 이상이면 Finalize / Photos 저장, 1.0초 미만이면 폐기한다. Recording 중에는 Duration Picker, Flip, Projects와 Navigation을 잠그고 Shutter만 Stop Control로 유지하며 저장 성공 / 폐기 / 실패 후 복원한다.

Recording은 Project를 만들지 않는다. 성공한 Clip은 Photos에 저장되며 Project는 `Projects → Select Clips`에서만 만들어진다.

Microphone이 Denied / Restricted이면 `mic.slash` 형태의 조용한 Muted 상태를 표시하고 무음으로 계속 촬영할 수 있으며 이 Control은 Camera를 시각적으로 지배하지 않는다.

녹화 중 Pause / Resume 기능은 제공하지 않는다.

---

## 13. Recording Feedback

Record Button 주변에 선택한 최대 Duration Recording Progress를 표현하는 Circular Progress 형태를 우선 검토한다.

Progress 표현은 Timer를 읽지 않아도 촬영 종료가 가까워지고 있음을 직관적으로 알 수 있게 해야 한다.

화면 중앙에 큰 Countdown 숫자를 표시하지 않는다. ADR-033에 따라 Shutter 주변 Circular Progress Ring이 `elapsed / selected maximum`을 표현하는 Primary Progress Surface이며 `00:02 / 00:03` Text, 큰 Duration Text나 별도 Timeline / Progress Bar를 두지 않는다. Ring 색상은 Visual 구현 결정이다.

마지막 구간에서는 기존 Visual Progress 변화로 자동 종료가 가까워졌음을 자연스럽게 알릴 수 있다.

Recording Start에는 Haptic을 사용하지 않고 Successful Manual Stop과 Successful selected-maximum Auto-stop 완료 시에만 동일한 종료 의미의 subtle completion haptic을 제공하며 종료 직전 예고 Haptic으로 사용하지 않는다.

Haptic은 기존 Visual Recording State / Circular Progress / Completion State를 보조하며 Haptic을 사용할 수 없거나 사용자가 인지하지 못해도 Recording 상태를 이해할 수 있어야 한다.

Error / Interruption Haptic은 Pending이며 정확한 구현과 Tuning의 범위는 29절을 따른다.

---

## 14. Camera Switching

Front Camera와 Rear Camera 전환은 녹화하지 않는 상태에서만 가능하다.

Recording 중에는 Camera Switch 기능을 비활성화한다.

사용자가 촬영 중 Camera Switch Control을 실수로 누르더라도 현재 Recording이 손상되지 않아야 한다.

Front와 Rear Camera 동시 촬영은 MVP에 포함하지 않는다.

Rear Zoom은 Front / Rear Camera Switching과 다른 Interaction이며 Recording 중에도 같은 Rear Camera와 Clip을 유지한 채 사용할 수 있다.

---

## 15. Import Video

사용자는 Camera 또는 Project 화면에서 기존 Photos Library 영상을 추가할 수 있어야 한다.

Import 기능은 Camera 촬영보다 숨겨져서는 안 되지만 Record Button보다 높은 시각적 우선순위를 갖지 않는다.

Photos에서 영상을 선택하면 원본 영상의 길이에 관계없이 사용할 수 있어야 한다.

5초보다 긴 영상은 Import 이후 사용할 최대 5초 구간을 선택한다.

5초보다 짧은 영상은 전체 영상을 기본 선택 상태로 보여줄 수 있다.

---

## 16. Imported Video Trim

Imported Video의 Trim 화면은 원본 전체 영상에서 사용할 구간을 선택하는 역할을 한다.

사용자는 시작점과 종료점을 조절할 수 있어야 한다.

Imported Segment는 `0 < duration <= 5 seconds` 범위에서 자유롭게 선택하며 1.3초, 2.7초, 4.5초, 5.0초처럼 정수가 아니어도 되고 Camera Preset에 맞출 필요가 없다.

Trim UI는 전문 Timeline Editor처럼 복잡하게 보이지 않아야 한다.

현재 선택된 구간 길이를 사용자가 쉽게 확인할 수 있어야 한다.

---

## 17. Imported Video Aspect Ratio

Imported Video의 원본 화면 비율과 현재 Project Orientation이 다를 수 있다.

MVP의 기본 동작은 **Fill + Crop**을 사용한다.

예를 들어 16:9 영상을 9:16 프로젝트에 가져오면 9:16 Canvas를 채우도록 확대하고 필요한 영역을 Crop한다.

사용자는 영상의 위치를 Drag하여 Framing을 조정할 수 있어야 한다.

필요한 경우 Pinch to Zoom 지원을 검토할 수 있다.

`Fit` 또는 Background Blur와 같은 추가 Layout 방식은 MVP 필수 기능으로 두지 않는다.

---

## 18. Project Screen

Project Screen / Lightweight Editor는 현재 Vlog를 구성하는 Clip을 관리하는 공간이다.

ADR-032 이후 V1 구조는 Portrait Camera → Short Clip Capture → Clip Review / Management → Editor → Export를 하나의 Persisted Vlog Project 안에서 연결한다.

Camera에는 최근 / 마지막 Clip의 작은 Thumbnail 또는 동등한 Compact Project-content Affordance를 두고 탭하면 해당 Project의 Clip Review / Editor로 이동하며 별도 Dashboard나 복잡한 Camera Timeline을 추가하지 않는다.

Editor는 큰 Preview를 Primary Visual Focus로 두고 단순한 Ordered Clip Thumbnail Strip, 명시적인 Clip Selection, 가벼운 Clip Tools와 Add Clip / Final Output Action으로 구성한다.

Clip Thumbnail의 Single Tap은 선택이며 Text Entry를 바로 열지 않는다.

Long Press + Drag로 순서를 바꾸고 Move Earlier / Move Later와 같은 Non-drag Accessibility 대안을 제공한다.

Trim / Text / Delete는 명시적인 Clip Action이다. Add Clip은 ADR-037에 따라 System PhotosPicker를 열어 Phase-5-ready Media를 현재 Project 끝에 추가하며 Camera를 열지 않는다(Camera로 촬영한 Clip은 Photos 저장 후 같은 경로로 추가한다). 각 기능은 기존 Owning Phase에서 구현한다.

Final Output의 정확한 Label과 동작은 Export Phase에서 결정하며 Toolbar Geometry를 이 결정에서 고정하지 않는다.

사용자는 이 화면에서 현재 Vlog의 전체 구조를 빠르게 이해할 수 있어야 한다.

주요 기능은 다음과 같다.

- Clip 확인
- Clip 순서 변경
- Clip 삭제
- Clip Trim
- Clip 추가(PhotosPicker, ADR-037)
- Video Import
- 전체 Preview
- Export

전문적인 Video Timeline Interface를 그대로 복제하지 않는다.

0 Clip Project는 Recording과 Video Import를 시작할 수 있지만 Full Preview와 Export는 사용할 수 없음을 Error Screen이 아닌 정상적인 Project 상태로 전달한다.

0 Clip Project에는 Individual Clip Preview 대상도 없음을 정상적인 Project 상태로 전달한다.

일부 또는 모든 Clip이 Unavailable이어도 Project를 열고 Healthy Clip을 계속 관리할 수 있어야 하며 Project 전체를 자동으로 제거하지 않는다.

---

### Explicit Text Tool

선택한 Clip → 명시적인 `T` Tool → 해당 Clip의 Text 추가 / 수정 흐름을 제공하며 `T`는 Editor Tool Layout에서 발견하기 쉬워야 한다.

일반 Clip Tap은 선택만 하고 Text Entry를 열지 않는다.

Font 선택, Position, Size, Text Duration과 Animation 세부 정책은 Phase 7 구현 전 Gate에서 결정하며 복잡한 Typography / Effect Editor, Text Animation System, Keyframe, Multi-track Text Timeline과 Sticker는 추가하지 않는다.

---

## 19. Clip Representation

각 Clip은 Thumbnail을 중심으로 표현한다.

필요한 경우 Clip Duration을 함께 표시한다.

직접 촬영한 Clip과 Imported Clip을 시각적으로 지나치게 다르게 표현할 필요는 없다.

사용자에게 중요한 것은 Clip의 출처보다 Vlog에서 어떻게 사용되는지다.

Unavailable Clip은 숨기지 않고 기존 Timeline Position을 차지하며 Healthy Clip과 구분할 수 있고 Replace와 Delete Action에 접근할 수 있어야 한다.

Unavailable 상태의 정확한 Icon, Thumbnail Placeholder, Label, Color, Button Layout, Modal 또는 Sheet와 Copy는 Phase 5 Structural UX Gate에서 결정한다.

Phase 5 STEP 8 Editor Baseline(V4.1 Full-canvas Timeline, 승인 2026-09-15 — Simulator Visual Review + LunaTestphone Physical Review): ProjectEditor는 앱의 Light / Dark Appearance와 무관하게 Editor 전용 Dark Media Workspace(Black Canvas, Dark Elevated Dock, Light Foreground)를 사용한다 — Projects는 일반 App Surface, Editor는 집중형 작업 공간이며 Global Appearance는 바꾸지 않는다. 구성은 Native Navigation(`Back` / `Project`) → Navigation과 Dock 사이의 모든 Flexible 공간을 차지하는 Full Preview Canvas(Workspace와 같은 Black, Card / 가시 경계 없음, 좌우 Inset ≈ 4pt, 상하 Gap 8pt) → Compact Bottom Timeline Dock(≈100pt, 좌우 여백 10pt, Radius 20, Bottom Safe-area 위 6pt)이다. Canvas는 Overlay 가능한 ZStack이며 이후 Project Media는 Canvas 안에 9:16 `aspectRatio(.fit)`으로 놓이고, 이후 Text / Sticker 등 Editor Control은 Canvas 위에 Overlay로 얹혀 Preview 크기를 줄이지 않는다(이번 STEP에서는 어떤 Control도 렌더링하지 않으며 Text / Sticker 기능은 존재하지 않는다). STEP 8의 Canvas는 Placeholder Shell로 희미한 `film` Glyph만 보이고 Engineering Copy가 없으며 Accessibility는 `Preview, selected clip N`이다. Dock 안의 Clip Navigation은 Leading 정렬 Ordered Timeline / Filmstrip으로 좌 → 우 논리 순서를 유지하고 짧은 Project를 중앙 정렬하지 않으며 넘치면 Horizontal Scroll한다. Dock에는 Heading이 없고 `Total 7.0s`는 Dock 우상단의 Caption2 Secondary Metadata다. Cell은 44 × 78pt 9:16(Radius 7, 간격 4pt) Aspect Fill Thumbnail이고 Duration은 Cell 우하단의 작은 불투명 Near-black Tag(`3.0s`, Caption2 Monospaced, Decorative — Accessibility Label이 Duration을 말함)로 표시한다. 선택 Clip은 Mellow Signature Orange 500 Outline 2pt + Accessibility Selected State(Checkmark / Scale / Lift / Glow 없음, Geometry 고정), 비선택은 Quiet Hairline이다. Production Timeline은 Dock의 Leading Inset(10pt)에서 바로 시작하며 Dead Add Control이나 빈 Slot을 두지 않는다. 이후 Leading `+`(Add Clip, 40pt Circle)은 ADR-037에 따라 System PhotosPicker로 Media 선택을 열어 Phase-5-ready Clip을 현재 Project 끝에 추가하며, 기능이 구현된 뒤에만 Production에 나타나고 같은 Timeline HStack 앞에 Prepend된다(DEBUG Build만 `+` Reference Visual을 Staging하며 `-uiTestProductionTimeline`이 Release 표현을 재현한다). 이후 Reorder는 같은 Timeline에서 Long Press + Horizontal Drag로 구현하며 Clip Identity는 Stable Clip ID, Cell Geometry는 고정이다. Thumbnail 생성 실패 Cell은 같은 크기 / Radius / 위치에 Neutral Dark Surface + `film` Symbol + Duration Tag를 유지한다(ADR-026 Unavailable Replace / Delete UX는 별도 Slice).

Healthy Clip의 Individual Clip Preview는 사용자가 현재 이 Clip이 실제 Vlog에서 어떻게 보일지 확인하는 경험이어야 하며 Raw Source를 단순 재생하는 별도 원본 확인 경험으로 표현하지 않는다.

Individual Clip Preview는 현재 Trim, Framing / Scale / Position, applicable Transform, Project Orientation, Direct-recorded Front Clip의 Mirrored Appearance, SDR 해석과 존재하는 Audio를 반영하며 정확한 진입 방식과 Playback Control은 Phase 8 Structural UX Gate에서 결정한다.

Unavailable Clip 자체에는 Video Preview를 제공하지 않고 사용자가 Replace 또는 Delete Flow를 통해 해결할 수 있게 한다.

---

## 20. Reorder Clips

사용자는 Long Press + Drag로 Clip 순서를 변경하며 Move Earlier / Move Later와 같은 Non-drag Accessibility 대안을 사용할 수 있어야 한다.

Drag 중 현재 Clip의 위치와 삽입될 위치를 명확하게 표시한다.

순서 변경은 즉시 Project State에 반영한다.

별도의 Save Button을 요구하지 않는다.

---

## 21. Delete Clip

개별 Clip 삭제 시 매번 Confirmation Dialog를 표시하지 않는다.

삭제는 즉시 수행하고 짧은 시간 동안 Undo Action을 제공하는 방향을 사용한다.

예시는 다음과 같다.

`Clip removed · Undo`

Clip 삭제가 Photos Library의 원본 영상 삭제로 오해되지 않도록 한다.

Unavailable Clip의 Delete도 기존 Clip Delete / Undo 의미를 변경하지 않는다.

---

## 22. Delete Project

전체 Project 삭제는 Clip 삭제보다 훨씬 큰 결과를 가져오기 때문에 Confirmation을 요구한다.

Confirmation은 Project와 Mellow 내부 미디어가 삭제된다는 사실을 명확하게 설명해야 한다.

Photos Library의 원본 영상에는 영향을 주지 않는다는 점을 필요에 따라 안내한다.

Destructive Action은 시각적으로 명확하게 구분한다.

---

## 23. Full Vlog Preview

사용자는 현재 Project 전체를 실제 Export 결과와 유사한 형태로 연속 재생할 수 있어야 한다.

Full Vlog Preview는 Raw Clip을 단순 연결하는 기능이 아니라 현재 Vlog 전체가 Export될 때의 effective edited result를 확인하는 경험이어야 한다.

Preview에서는 다음 요소를 반영한다.

- Clip order
- Trim
- Fill + Crop과 current Framing / Scale / Position
- applicable Transform
- Project orientation
- Direct-recorded Front Clip의 Mirrored Appearance
- SDR interpretation
- 존재하는 Clip Audio와 Audio가 없는 Imported Clip의 Silent 상태

Full Vlog Preview와 Export는 동일한 Composition Semantics를 사용하며 Clip order, Trim, Framing, Transform, Orientation, Mirroring, SDR 및 Audio의 의미가 달라지지 않아야 한다.

Clip 사이에는 MVP에서 자동 Video Transition, Audio Fade 또는 Audio Crossfade를 적용하지 않고 현재 Clip Order를 직접 이어서 사용한다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Full Vlog Preview를 제공하지 않으며 문제 Clip을 조용히 생략한 완성본처럼 재생하지 않는다.

다른 Clip이 Unavailable이어도 Healthy Clip의 개별 Preview는 계속 가능하다.

Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경 후에는 기존 Preview가 최신 Vlog 결과처럼 남지 않으며 다음 유효 Preview는 최신 Project State를 반영한다.

정확한 Playback Controls, Scrubber, Navigation, Entry / Exit Transition, Control Placement와 Fullscreen Behavior는 Phase 8 Structural UX Gate에서 결정한다.

---

## 24. Export

Export는 Project 작업의 명확한 Completion Action으로 제공한다.

사용자가 Export 버튼을 눌렀다고 Project가 삭제되거나 완료 상태로 강제 전환되지는 않는다.

Export는 현재 Project State를 기준으로 하나의 결과 Video를 생성하는 동작이다.

Export에는 시간이 걸릴 수 있으므로 진행 상태를 사용자에게 표시해야 한다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Export를 시작하지 않으며 사용자가 Replace 또는 Delete로 문제를 해결해야 한다.

Export Result Flow는 최소한 Exporting, Export rendered / local result ready, Saved to Photos, Photos save failed, Sharing, Share cancelled / returned와 unsaved Result의 Discard Confirmation을 의미상 구분할 수 있어야 한다.

Export Rendering이 성공한 상태는 Validation을 통과한 Local Export Artifact가 준비된 상태이며 `Saved to Photos` 상태와 동일하지 않다.

`Saved to Photos`는 실제 Photos Save가 성공한 뒤에만 표시하며 이 상태에서 Share와 Done을 제공할 수 있다.

Photos Save Failure는 Export Rendering Failure와 구분해 표시하고 Local Result, Save Retry와 Share 가능 상태를 유지해야 한다.

Share Cancel 또는 Share Sheet에서 돌아온 상태는 Export Failure가 아니며 Local Result와 Save / Share 재시도 가능 상태를 유지해야 한다.

Photos Save에 성공하지 않은 Result Flow를 Done 또는 close하려는 경우에는 silent cleanup 대신 unsaved Result임을 알리고 명시적 Discard Confirmation을 제공해야 한다.

정확한 Screen Layout, Button Hierarchy, Copy, Retry Placement와 Discard Confirmation Presentation은 Phase 9 Structural UX Gate에서 결정한다.

`Share`는 iOS Share Sheet를 사용한다.

---

## 25. Autosave

Mellow는 Project 편집 과정에서 별도의 Save Button을 요구하지 않는다.

사용자의 변경사항은 가능한 한 자동 저장한다.

다음과 같은 변화가 발생하면 Project State를 자동으로 보존한다.

- Clip 추가
- Clip 삭제
- Clip Reorder
- Trim 변경
- Imported Video 추가
- Project Metadata 변경

Autosave 과정 자체를 사용자에게 반복적으로 알리지 않는다.

---

## 26. Permissions UX

Permission은 앱 최초 실행 시 한꺼번에 모두 요청하지 않는다.

ADR-033에 따라 첫 실행 Onboarding은 Camera, Microphone, Photos Add를 각각 설명한 뒤 한 번에 하나씩 요청하며 Location은 요청하지 않는다. 이후 Photos Import 등은 실제 기능을 처음 사용하는 시점에 Contextual하게 요청한다.

사용자가 권한을 거부한 경우 Mellow가 해당 권한을 왜 필요로 하는지 짧고 명확하게 설명한다.

Settings 이동이 필요한 경우 적절한 Action을 제공한다.

Camera 또는 Photos Add Permission이 없으면 Direct Recording을 성공 Capture로 완료할 수 없으며 Settings Recovery를 제공한다. Microphone은 선택 권한이며 Denied / Restricted이면 무음으로 촬영을 계속할 수 있고 `mic.slash` 상태 Control이 `.notDetermined` → 요청, `.denied` → Settings, `.restricted` → 설명으로 동작한다.

Permission 안내는 Recording만 제한된다는 사실과 Photos Video Import는 계속 사용할 수 있다는 사실을 구분하여 전달해야 한다.

Camera / Microphone Permission Denied가 앱 전체를 차단하거나 Import Action을 숨기는 상태가 되어서는 안 된다.

정확한 Permission Screen Layout과 Copy는 Phase 3 Structural UX Gate에서 결정한다.

---

## 27. Error UX

Error Message는 기술적인 원인보다 사용자가 무엇을 해야 하는지 중심으로 작성한다.

다음과 같은 기술적인 표현은 사용자에게 노출하지 않는다.

- AVFoundation Error
- Asset Export Failed
- Session Invalid
- Permission Status Error

사용자가 이해할 수 있는 표현을 사용한다.

예시는 다음과 같다.

- `Camera access is needed to record a clip.`
- `There isn’t enough storage to save this video.`
- `This vlog couldn’t be exported. Try again.`
- `Recording was interrupted.`

정확한 최종 Copy는 Localization 단계에서 결정한다.

---

## 28. Motion

Motion은 Mellow의 차분한 분위기를 강화하는 방향으로 사용한다.

Animation 자체가 사용자의 관심을 빼앗아서는 안 된다.

Motion은 다음 역할을 위해 사용할 수 있다.

- State transition
- Clip insertion
- Clip reorder
- Delete Undo
- Export completion
- Recording feedback

과도한 Bounce, Spring, Zoom Effect 사용을 피한다.

---

## 29. Haptics

MVP Recording Haptic의 사용 여부와 의미는 다음과 같이 확정한다.

| Recording Event | Haptic Policy |
| --- | --- |
| Recording Start | Haptic 없음 |
| Successful Manual Stop | 완료 시 subtle completion haptic |
| Successful selected-maximum Auto-stop | 완료 시 subtle completion haptic |
| Recording Error / Interruption | 별도 Pending |

Manual Stop과 Auto-stop의 Haptic은 모두 "이 Clip의 Recording이 종료되었다."라는 동일한 의미를 갖는다.

Record Button Tap이나 Recording Start 성공에는 Haptic을 제공하지 않으며 종료 직전 예고를 위해 Completion Haptic을 앞당기지 않는다.

Haptic은 보조 Feedback이며 유일한 Recording State Indicator가 아니다.

기존 Visual Recording State, Circular Progress와 Completion State는 그대로 유지하며 Haptic을 사용할 수 없거나 사용자가 인지하지 못해도 Recording 상태를 이해할 수 있어야 한다.

Recording Error / Interruption에는 Camera / App Interruption, Permission Issue, Recording Failure와 Media Write Failure가 포함되며 이 경우의 Haptic은 이번 정책에서 확정하지 않는다.

정확한 Haptic API, Style, Intensity, Sharpness, Pattern, Duration과 Generator 구현은 특정 기술로 확정하지 않고 Phase 4의 Native iOS 구현 및 실제 iPhone 12 Tuning 대상으로 남긴다.

Phase 12에서는 승인된 의미를 유지하는 Subtlety, Consistency, Perceived Quality와 Accessibility Regression만 다듬으며 Start Haptic 추가 등 정책 변경은 Exception and Replanning Protocol에 따른 사용자 승인이 필요하다.

다음 Recording 외 사용 지점은 기존 검토 후보로 유지하며 이번 정책으로 사용 여부를 확정하지 않는다.

- Clip reorder placement
- Export completion

모든 Button Tap에 Haptic을 사용하지 않는다.

Haptic은 실제 iPhone 테스트를 통해 승인된 의미 안에서 강도와 체감 품질을 조정한다.

---

## 30. Color Direction

ADR-028에 따라 Cream 기반 Background를 제거하고 Native iOS Light / Dark Appearance를 자동으로 따른다.

systemBackground, label, secondaryLabel, secondarySystemBackground와 separator 등 Semantic Color를 우선한다.

Launch, Recent Projects와 Camera Placeholder의 전체 Page / Safe-area Background는 Light에서 Pure White, Dark에서 Pure Black으로 보여야 하며 Cream, Grouped Background나 Material로 Page를 착색하지 않는다.

Card만 Neutral Adaptive Secondary Surface를 사용할 수 있으며 Primary Label의 Contrast를 검증한다.

### Mellow Signature Colors

Recording Progress Ring Visual 탐색에서 승인된 Warm Peach / Orange 계열을 Feature 전용 색상 아이디어에서 공유 **Mellow Signature Palette**로 승격한다. Swift Token은 `MellowDesignSystem.signature*`이며 Raw Hex를 View에 흩뿌리지 않는다.

#### Foundation Palette

| Token | Hex | Intended role |
| --- | --- | --- |
| Peach 50 | #FFD7C7 | soft tint / subtle supporting accent |
| Peach 100 | #FFB89C | light warm accent |
| Peach 300 | #FF8A65 | signature Peach / gradient start |
| Orange 400 | #FF7A45 | primary warm accent / gradient midpoint |
| Orange 500 | #FF5E3A | strong Orange / gradient end |

이 단계에서 추가 Shade를 발명하지 않는다.

#### Signature Gradient

`Peach 300 → Orange 400 → Orange 500` = `#FF8A65 → #FF7A45 → #FF5E3A` (`MellowDesignSystem.signatureGradient`). 사각형 Primary Action에는 단순 Horizontal 진행을 사용하고, 특정 Component가 다른 Geometry를 요구할 때만 예외로 한다(Recording Ring은 Angular).

의미: 따뜻하고 친근하며 현대적이고, 순간을 만들고 담는 행위와 연결되며, 순수 Red보다 경고감이 적다. **Positive Creation / Capture / Primary-action Energy**를 뜻하며 Mellow Brand Accent로 **선택적으로** 사용한다.

#### Usage

- Recording: Recording Progress Ring은 이 Signature 계열에 속한다(Ring은 Peach 50 → Orange 500 다섯 Stop Angular).
- Projects: `새 프로젝트 시작` Primary CTA는 Signature Gradient를 사용한다.
- 이후 명시적으로 승인된 Creation / Start Action에만 확장한다.
- Secondary Action(`기존 프로젝트 불러오기` 등)은 Neutral을 유지한다.
- Destructive(예: 대체 확인의 `새 프로젝트 만들기`)는 System Destructive / Red Semantics를 유지하며 Mellow Orange를 쓰지 않는다: Mellow Orange = 생성 / 긍정 Primary, System Red = 파괴적 결과.
- Error / Warning / Disabled / 모든 Selectable Element에 Signature Color를 쓰지 않는다. Brand Color 과용을 피한다.

#### Accessibility

- Foreground는 Contrast에 따라 고른다. 승인된 Palette는 여러 Stop에서 White Text의 일반 Text Contrast가 부족하므로 Signature Gradient 위에는 기본적으로 White / Light Text를 두지 않고 Near-black Semantic Dark Foreground(`MellowDesignSystem.signatureForeground`, #1C1C1E)를 사용한다.
- Brand Color가 가독성을 덮어쓰지 않는다. Audit을 통과시키기 위해 Palette 값을 바꾸지 않는다 — Palette는 Canonical이고 Foreground가 적응한다.
- Light / Dark에서 같은 Gradient를 사용한다(Dark에서 반전 / White 대체 없음). 주변 System Surface만 Appearance에 적응한다.
- Color만으로 상태를 전달하지 않는다.

---

## 31. Typography

Typography는 영상보다 시각적으로 강하지 않아야 한다.

기본적으로 iOS에서 자연스럽게 느껴지는 Typography System을 우선한다.

많은 Font Weight와 Font Size를 사용하지 않는다.

Primary, Secondary, Metadata 정도의 명확한 Hierarchy를 유지한다.

정확한 Typeface와 Size는 디자인 테스트 후 결정한다.

---

## 32. Shape Language

Mellow의 UI는 부드러운 Rounded Geometry를 기본 방향으로 사용한다.

Button, Card, Thumbnail Container 등에 과도하게 다른 Corner Radius를 사용하지 않는다.

Camera Recording Control은 기능적 가독성을 우선한다.

---

## 33. Accessibility

Mellow는 초기 구현부터 Accessibility를 고려한다.

### Required Direction

- 충분한 Touch Target
- VoiceOver Label
- Dynamic Type 고려
- Color만으로 상태를 전달하지 않음
- 충분한 Contrast
- Reduce Motion 대응 검토

Camera와 Video Preview 위의 Control도 접근 가능한 Label을 가져야 한다.

이 기준은 Phase 12에서 처음 적용하지 않으며 각 관련 UI Phase의 Implementation, Acceptance Criteria와 Exit Criteria에 처음부터 연결한다.

최소한 Phase 2의 Home / Recent, Phase 3 / 4의 Camera / Recording, Phase 5의 Clip Management, Phase 6의 Import Selection, Phase 7의 Trim / Framing, Phase 8의 Preview와 Phase 9의 Export에서 해당 화면에 적용 가능한 위 기준을 구현하고 검증한다.

각 Phase는 Touch Target, VoiceOver Label과 Control 식별, Dynamic Type에서의 핵심 Flow, Color만으로 상태를 전달하지 않는지와 Contrast를 확인하고 해당 Motion이 있다면 Reduce Motion 대응을 검토·검증한다.

화면별 검증 결과와 적용 범위 또는 미해결 사항을 남기며 필요한 접근성 검증을 Phase 12로 미룬 채 해당 Phase를 완료 처리하지 않는다.

Phase 12에서는 이미 적용된 Accessibility의 화면 간 일관성, Regression과 Edge Case를 종합 검증하고 Hardening한다.

이 적용 시점 원칙은 새로운 수치 기준이나 별도의 Accessibility 기능을 확정하지 않는다.

---

## 34. Safe Areas

UI Control은 iPhone의 Dynamic Island, Notch, Home Indicator와 충돌하지 않아야 한다.

Camera Preview가 Full Screen일 경우에도 Interactive Control은 Safe Area를 고려한다.

Landscape Mode에서도 Control이 안전하게 배치되어야 한다.

---

## 35. Portrait and Landscape UI

Mellow는 Project Orientation에 따라 실제 Camera와 Editing UI도 적절하게 대응해야 한다.

9:16 Project에서는 Portrait 중심의 Layout을 제공한다.

16:9 Project에서는 Landscape 상태에서도 Camera Control과 Editing Control이 자연스럽게 사용할 수 있어야 한다.

Landscape 지원을 단순히 Portrait UI를 회전한 형태로 처리하지 않는다.

실제 iPhone 크기와 Safe Area를 기준으로 별도 Layout 검증을 수행한다.

---

## 36. Confirmed Design Decisions

현재 확정된 Design 및 UX 결정은 다음과 같다.

- 기존 프로젝트를 탐색하는 전용 화면의 명칭은 `Recent Projects`를 사용한다.
- 사용자에게 `Draft`라는 내부 개념을 주요 UI 용어로 노출하지 않는다.
- New Vlog 생성 시 프로젝트 이름 입력 단계를 두지 않는다.
- Launch에서 9:16 또는 16:9를 선택한 뒤 저장하고 Camera로 진입한다.
- 프로젝트 화면 비율은 생성 이후 자동 변경하지 않는다.
- 기기 방향이 Project Orientation과 다르면 조용한 회전 안내를 표시한다.
- Camera Preview는 촬영 화면의 가장 중요한 시각 요소다.
- 하나의 Clip은 최대 5초까지 자유롭게 촬영한다.
- 사용자는 선택한 최대 Duration 이전 언제든 녹화를 종료할 수 있다.
- 선택한 최대 Duration에 도달하면 자동으로 녹화를 종료한다.
- Recording Progress는 Record Button 주변의 Progress Ring 방향을 우선한다.
- 큰 Countdown 숫자는 사용하지 않는다.
- Recording Start에는 Haptic을 사용하지 않는다.
- Successful Manual Stop과 Successful selected-maximum Auto-stop 완료 시 동일한 Recording 종료 의미의 subtle completion haptic을 제공한다.
- Haptic은 기존 Visual Recording State / Circular Progress / Completion State를 보조하며 종료 직전 예고 신호로 사용하지 않는다.
- Front / Rear Camera Switch는 녹화하지 않는 상태에서만 가능하다.
- 녹화 중 Camera Switch는 허용하지 않는다.
- Rear Camera는 기본 1× Wide를 사용하며 Preview와 Recording 중 1× 이상 Continuous Zoom을 지원한다.
- Rear Zoom은 같은 Recording과 Timer를 유지하며 0.5× Ultra Wide / Telephoto / Lens Selector 및 Front Camera Zoom은 MVP에서 제공하지 않는다.
- Front Preview와 Direct-recorded Front Clip의 Preview / Editing / Export는 동일한 Mirrored Appearance를 유지하며 Mirror Toggle은 제공하지 않는다.
- Camera 또는 Microphone Permission이 없으면 Direct Recording을 시작하거나 무음 Video로 대체하지 않고 Photos Import는 계속 사용할 수 있다.
- Project Orientation mismatch, Face Up / Down / Unknown / Unstable 상태에서는 새 Recording을 시작하지 않고 quiet Rotate Device Guidance를 제공한다.
- Mid-record Rotation은 현재 Recording을 자동 Stop / Restart하거나 Project Orientation을 변경하지 않으며 다음 Recording 전에 Orientation을 다시 확인한다.
- Photos에서 가져온 영상 원본 길이는 제한하지 않는다.
- Imported Video에서 사용할 구간은 최대 5초다.
- Project Orientation과 다른 Imported Video는 기본적으로 Fill + Crop 처리한다.
- 사용자가 Imported Video의 Framing을 조절할 수 있어야 한다.
- Clip 삭제는 즉시 적용하고 Undo를 제공한다.
- Project 삭제는 Confirmation을 요구한다.
- Project Rename은 MVP에서 제공하지 않는다.
- Clip Duplicate는 MVP에서 제공하지 않는다.
- Clip Split은 MVP에서 제공하지 않는다.
- Export 이후 Draft를 자동 삭제하지 않는다.
- 0 Clip Project는 정상적인 Draft이며 Recent에서 다시 열 수 있고 Recording과 Import를 허용하지만 Full Preview와 Export는 비활성화한다.
- Unavailable Clip은 기존 Timeline Position에 유지하고 Replace 또는 Delete Action에 접근할 수 있어야 하며 자동 삭제, 자동 대체 또는 조용한 Preview / Export 생략을 하지 않는다.
- Individual Clip Preview는 Healthy Clip의 current effective edited result를 제공하고 다른 Clip의 Unavailable 상태 때문에 차단하지 않으며 Unavailable Clip 자체에는 Video Preview를 제공하지 않는다.
- Full Vlog Preview와 Export는 current Clip Order, Trim, Framing / Scale / Position, Transform, Project Orientation, Front Mirroring, SDR 및 Audio Inclusion의 동일한 Composition Semantics를 사용하고 MVP에서 자동 Video / Audio Transition을 삽입하지 않는다.
- Composition에 영향을 주는 Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경 후 다음 유효 Preview는 최신 Project State를 사용한다.
- Project-level Corruption은 다른 Draft에서 격리된 안전한 Failure Presentation을 제공해야 하며 정확한 UI와 Copy는 별도 UX Gate에서 결정한다.
- Export Rendering Success와 Photos Save Success를 구분하여 표시하며 `Saved to Photos`는 실제 Photos Save가 성공한 뒤에만 사용한다.
- Photos Save Failure는 Render Failure로 표시하지 않고 같은 Local Result의 Save Retry와 Share를 제공하며 Share Cancel은 Result를 유지한다.
- Photos Save에 성공하지 않은 Result Flow 종료는 명시적 Discard Confirmation을 요구하고 Export 이후 Draft를 자동 삭제하지 않는다.
- UI는 Content-first 원칙을 따른다.
- Brand Screen에서는 따뜻한 Mellow 스타일을 사용하고 Camera 및 Video Screen에서는 콘텐츠 가독성을 우선한다.

---

## 37. Open Design Decisions

### Decision Timing and Classification

아래 Pending 선택지는 그대로 유지하며 실제 선택은 사용자 승인으로 확정한다.

**Structural / Implementation-blocking Decision**은 핵심 Layout, Control Placement와 정보 Hierarchy, 주요 Interaction / Gesture, 화면 간 Navigation처럼 구현 구조에 영향을 주는 선택이다.

해당 UI를 구현한 뒤 구조를 선택하지 않으며 이를 필요로 하는 가장 이른 Phase의 구현 시작 전에 결정해야 한다.

**Polish / Non-blocking Decision**은 이미 승인된 구조를 유지하는 Spacing, Visual Balance, Corner Radius, 비구조적인 Typography, Visual Hierarchy 미세 조정과 Subtle Motion / Animation Refinement다.

이러한 Refinement는 Phase 12까지 조정할 수 있지만 기능, Layout 구조 또는 기존 Accessibility 기준 충족에 영향을 주면 Structural Decision으로 분류하여 해당 Phase 이전에 해결한다.

| Owning Phase 이전 Gate | Structural Pending 범위 | Phase 12까지 가능한 비구조적 Refinement |
| --- | --- | --- |
| Phase 2 — Home / Recent / New Vlog | Resolved by ADR-028: Adaptive Thumbnail Grid, 최소 Item 정보, Format-first Launch, 전용 Orientation 화면, Item Menu → System Alert, 동일 Item의 0 clips 표현 | 승인된 Layout의 Spacing, 시각적 균형, 기존 Placeholder의 Visual Tuning |
| Phase 3 — Camera Foundation | Resolved 2026-09-13: Full-bleed Camera Preview, UI-only 1–5s Selector / 기본 3s, Flip / Compact Content, 조용한 Mismatch, Camera-only Permission 안내와 Rear 1.0×–2.0× Pinch / Transient Indicator. ADR-032로 Portrait-only V1, Splash 진입과 Camera Chrome Projects Access가 추가되고 Landscape Camera Layout / Control Rail은 V1 범위에서 제외 | Control의 비구조적인 시각 조정과 Portrait Visual Polish |
| Phase 4 — Recording | 확정된 Circular Progress Ring 안에서의 Layout-level 표현, 현재 녹화 시간 표시의 구체적인 배치와 저장 완료 Feedback의 비 Haptic Presentation 구조 | 승인된 Recording 구조의 Visual / Motion Refinement |
| Phase 5 — Clip Management | Resolved by ADR-034 / ADR-035 / ADR-036: Projects 전용 Pushed 화면(ADR-035, Bottom Sheet 아님)에 항상 두 중앙 Action `Start New Project` / `Load Existing Project`(ADR-036, List / Card 없음)와 대체 확인, Ordered Thumbnail Strip(Thumbnail + Compact Duration, Color-only 아닌 Selected State), Long Press + Drag / Move Earlier·Later Reorder, 선택 Clip Delete + Bottom `Clip deleted` + `Undo` Snackbar, 조용한 Project Duration과 명시적 `Add Clips`, Unavailable Clip Placeholder + 명시적 Replace / Delete, Large Preview Shell(실제 Playback은 Phase 8), Camera Content Slot의 저장 Project Representative Thumbnail 승격 | 승인된 Delete / Undo Surface와 Clip 표현의 Visual Tuning, Localization Copy, Undo Window |
| Phase 6 — Import Selection | 이 Phase가 이미 구현하는 최대 5초 Segment Selection의 최소 Control / Interaction 구조와 그 구조에 영향을 주는 Trim / Crop 화면 분리 결정 | 승인된 Import Selection의 비구조적 Visual Tuning |
| Phase 7 — Trim / Framing / Text | 명시적 T Tool의 세부 UX와 Text 정책, Trim / Crop 화면 구성, Primary Trim Interaction, Thumbnail Filmstrip / Scrubbing 구조와 Time Precision 표현, Drag / Position Framing 세부 구조, Pinch 포함 여부, Crop Reset 필요 여부, Portrait / Landscape Editing Control 배치 | 승인된 구조의 Trim Handle Visual과 Spacing Refinement |
| Phase 8 — Full Vlog Preview | Playback Control Structure / Hierarchy, Preview 진입·종료와 Project 화면 복귀 Navigation, Scrubber와 Empty / Unavailable Project Preview Block의 상태 표현이 해당 UI 구현에 영향을 주는 부분 | 승인된 Control의 Visual Hierarchy 미세 조정 |
| Phase 9 — Export | Export Action 배치, Exporting / local result ready / Saved to Photos / Photos save failed / Sharing / Share cancelled or returned Result State Presentation, Save Retry Placement, Share / Done 배치와 unsaved Discard Confirmation, Storage Preflight와 Render Failure 및 Empty / Unavailable Project Export Block의 상태 표현이 UI 구조에 영향을 주는 부분 | 승인된 Export UI의 Visual Balance와 Spacing Refinement |

Phase 3은 Camera Shell과 현재 Phase의 Control 구조만 구현하며 이후 Phase의 Recording / Import 기능을 미리 구현하지 않는다.

Phase 4 전용 표현이 Phase 3 Layout 구조에 이미 영향을 준다면 필요한 공통 구조 결정만 Phase 3 이전에 해결한다.

Phase 6에서 구간 선택을 실제로 구현하므로 그 최소 구조를 Phase 7이나 Phase 12까지 미루지 않으며 Phase 7은 이미 승인된 부분을 재사용하고 나머지 Trim / Framing 구조를 구현 전에 결정한다.

이미 확정된 New Vlog의 Primary Action 역할, Project Orientation 고정, Front / Rear Camera, 최대 5초 Recording과 Circular Progress Ring, Drag Framing / Reorder, Share / Done 및 Draft 유지 동작은 다시 Open으로 만들지 않는다.

Rear 1× Wide와 1× 이상 Continuous Zoom, 0.5× / Telephoto / Lens Selector 및 Front Zoom 제외, Front Mirrored Preview / Result Parity와 Permission / Orientation 동작은 ADR-023을 따르며 다시 Open으로 만들지 않는다.

Rear Zoom 구조는 1.0×–2.0× Pinch와 Gesture 중 Transient Numeric Indicator로 승인되었으며 Persistent Button / Slider는 제공하지 않는다.

Clip Delete / Undo Presentation 선택은 `FEATURES.md`의 F-MVP-025와 ADR-021의 즉시 UI 제거, 가장 최근 삭제 한 건의 Undo, 새 Delete 시 이전 Opportunity 종료, Process 종료 후 Undo 미유지와 동일 Clip Identity / Media 복원 의미를 변경하지 않는다.

Trim / Framing 구조는 ADR-022의 Working Media Crop bake-in 금지와 Metadata 기반 Framing 계약을 유지한다.

ADR-013의 Shared Preview / Export Composition 실행 계약과 ADR-025로 확정된 Export Result Lifecycle은 이 표에서 다시 결정하지 않으며 Background Export, 재Export가 필요한 경우의 Retry 세부 정책과 Exact Result UI는 해당 UI 구현 전에 해결해야 한다는 시점만 정의한다.

Recording Start에는 Haptic 없음, Successful Manual Stop / selected-maximum Auto-stop에는 subtle completion haptic이라는 승인 정책은 29절을 따르며 이 Structural UX 분류로 다시 Open으로 만들지 않는다.

Error / Interruption Haptic은 별도 Pending이며 정확한 구현과 Completion 의미 안의 Tuning은 미확정 구현 세부사항으로 유지한다.

ADR-026의 Empty Project, Unavailable Clip, Preview / Export Eligibility와 Project-level Corruption 격리 동작은 확정되어 있으며 이 표에서 다시 Open으로 만들지 않는다.

Phase 2 Empty Project의 동일 Item / Neutral Placeholder 구조는 ADR-028로 확정하며 비구조적 Visual Tuning, Corrupted Project의 Exact Visual, Replace UI와 Thumbnail Crop / Frame Presentation은 각 Owning Gate에서 결정한다.

Accepted Representative Source와 Derived-data 책임은 다시 Open으로 만들지 않는다.

Phase 12는 핵심 UX 구조를 처음 선택하거나 대규모 Structural Redesign을 수행하는 Phase가 아니며 구조 변경이 필요하면 `ROADMAP.md`의 Exception and Replanning Protocol을 따른다.

### Home

- Recent Adaptive Thumbnail Grid와 최소 Item 정보 — Resolved by ADR-028.
- Launch Orientation Chooser와 기존 Project 진입 Action — Resolved by ADR-028; Orientation Chooser는 ADR-032로 V1에서 제거되고 Projects 진입은 Camera Chrome으로 이동한다.
- 0 Clip Project의 동일 Item / Neutral Placeholder 구조 — Resolved by ADR-028; 비구조적 Visual Tuning은 유지.

### Orientation

- 9:16 / 16:9 선택 화면의 정확한 Visual Style
- Orientation mismatch 안내의 정확한 Icon / Wording / Banner / Toast / Overlay 형태, Animation과 위치
- 정확한 Orientation Detection API / Threshold / Debounce는 구현 세부사항으로 유지

### Camera

- Record Button 정확한 Size
- Recording Timer 표시 여부
- Camera Switch 위치
- Import 버튼 위치
- Clips 진입 방식
- Camera UI Overlay 배치
- Rear Zoom의 최종 Gesture / Interaction, Zoom Factor Indicator와 Visual Feedback
- Rear Zoom의 Maximum Product Quality Limit과 Interaction Sensitivity
- Camera / Microphone Permission 안내의 정확한 Layout과 Copy

### Recording

- 선택한 최대 Duration의 종료 전 어느 시점부터 Visual 종료 Feedback을 강화할지
- 승인된 Completion 의미 안의 정확한 Haptic 구현과 Timing Tuning
- Recording Error / Interruption Haptic 정책
- 자동 종료 시 Animation
- Clip 저장 완료 Feedback

### Imported Video

- Trim과 Crop을 하나의 화면에서 처리할지
- 두 단계로 분리할지
- Crop 시 Pinch to Zoom을 MVP에 포함할지
- Crop Reset 기능 필요 여부

### Project

- ADR-030의 Ordered Thumbnail Strip 안에서의 세부 Layout
- ADR-030의 Long Press + Drag 및 Non-drag Accessibility 대안의 세부 표현
- Project 전체 Duration 표시 위치
- Add Clip Action의 위치
- Unavailable Clip의 Exact Icon, Placeholder, Label, Color와 Replace / Delete Button Hierarchy
- Replacement의 Trim, Framing, Transform, Thumbnail Reset을 사용자에게 알리는 방식

### Trim

- Thumbnail Filmstrip 사용 여부
- Trim Handle Visual
- Time Precision
- Scrubbing UX

### Preview

- Playback Control 형태
- Scrubber 제공 여부
- Preview에서 빠르게 Clip으로 돌아가는 Interaction
- Empty / Unavailable Project에서 Full Preview가 Blocked일 때의 Exact State Presentation
- Preview Entry / Exit Transition과 Fullscreen Behavior

### Export

- Export Action의 위치
- Export Progress UI
- 완료 화면 구성
- Share와 Done의 Visual Priority
- Export Rendering Success와 Photos Save Success의 상태 표현
- Photos Save Failure, Save Retry와 Share의 배치
- unsaved Result의 Discard Confirmation Presentation
- Empty / Unavailable Project에서 Export가 Blocked일 때의 Exact State Presentation

### Brand

- 최종 Color Palette
- Typography
- Corner Radius System
- Icon Style
- Animation Curve
- Logo 사용 위치

이 Open Decision은 실제 화면 Prototype과 iPhone 사용성을 확인하되 Structural 항목은 해당 Owning Phase 구현 전에 사용자 승인을 받고 Polish 항목은 기존 구조와 Accessibility 기준을 유지하는 범위에서 Phase 12까지 조정한다.
