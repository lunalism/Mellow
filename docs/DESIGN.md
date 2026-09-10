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

Mellow의 브랜드 화면에서는 Cream 계열의 따뜻한 배경과 부드러운 Neutral Color를 사용할 수 있다.

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

- Home
  - New Vlog
    - Orientation Selection
      - Camera
      - Project
  - Recent
    - Existing Project
      - Project

Project 내부의 주요 흐름은 다음과 같다.

- Camera
- Import Video
- Clip Organizer
- Trim / Crop
- Preview
- Export

사용자가 기능 구조를 이해하기 위해 복잡한 Navigation Hierarchy를 학습할 필요가 없어야 한다.

---

## 6. Home

Home은 Mellow의 시작점이다.

Home의 가장 중요한 두 가지 역할은 새로운 Vlog를 시작하는 것과 기존 Vlog를 다시 여는 것이다.

### Primary Content

- Mellow Branding
- New Vlog
- Recent Vlogs

`New Vlog`는 Home에서 가장 명확한 Primary Action이어야 한다.

`Recent`는 사용자가 이전 프로젝트를 다시 찾을 수 있는 공간이다.

사용자 UI에서 `Draft`라는 내부 개념을 주요 명칭으로 사용하지 않는다.

---

## 7. Recent

최근 작업한 Vlog 프로젝트를 카드 또는 유사한 시각적 단위로 표시한다.

프로젝트는 마지막 수정 시각을 기준으로 최근 항목부터 표시하는 방향을 우선한다.

### Recommended Project Information

- Thumbnail
- 자동 생성된 날짜 및 시간 이름
- Clip 개수
- 현재 총 Vlog 길이
- Last edited
- Project orientation

한 카드에 너무 많은 Metadata를 표시하지 않는다.

Thumbnail은 첫 번째 사용 가능한 Clip을 기본 대표 이미지로 사용한다.

Clip이 없는 프로젝트는 Mellow 스타일의 Placeholder를 표시한다.

---

## 8. New Vlog

사용자가 `New Vlog`를 누르면 프로젝트 이름을 입력하도록 요구하지 않는다.

프로젝트 생성 흐름은 가능한 짧게 유지한다.

기본 흐름은 다음과 같다.

1. `New Vlog`
2. `9:16` 또는 `16:9` 선택
3. Camera 진입

사용자가 촬영 전에 입력해야 하는 필수 Text Field는 두지 않는다.

---

## 9. Orientation Selection

새 프로젝트를 만들 때 화면 비율을 선택한다.

MVP에서는 다음 두 가지 선택지만 제공한다.

### Portrait

**9:16**

세로 기반의 Mini Vlog를 위한 모드다.

### Landscape

**16:9**

가로 기반의 Mini Vlog를 위한 모드다.

두 옵션은 기술적인 설정 항목처럼 보이지 않고 시각적으로 이해하기 쉬운 선택지로 표현한다.

화면 비율 Preview 또는 간단한 Visual Representation을 사용할 수 있다.

선택 이후 별도의 Confirm Step 없이 바로 Camera로 진입하는 방향을 우선한다.

---

## 10. Orientation Behavior

프로젝트 Orientation은 프로젝트 생성 시 결정되고 프로젝트가 유지되는 동안 변경하지 않는다.

기기의 물리적 회전으로 프로젝트 비율을 자동 변경하지 않는다.

### 9:16 Project

사용자가 iPhone을 Portrait 방향으로 들고 촬영하도록 유도한다.

기기가 Landscape 방향으로 회전된 경우 촬영 화면 위에 조용한 Orientation 안내를 표시한다.

### 16:9 Project

사용자가 iPhone을 Landscape 방향으로 들고 촬영하도록 유도한다.

기기가 Portrait 방향인 경우 가로 방향으로 돌리라는 안내를 표시한다.

Orientation mismatch 상태를 오류처럼 강하게 표현하지 않는다.

안내는 영상 Preview를 크게 가리지 않아야 한다.

---

## 11. Camera Screen

Camera는 Mellow에서 가장 중요한 화면이다.

사용자는 Camera를 열었을 때 별도의 설명 없이 바로 촬영 방법을 이해할 수 있어야 한다.

Camera Preview가 화면의 대부분을 차지해야 한다.

### Primary Controls

- Record
- Front / Rear Camera Switch
- Recorded Clips 진입
- Import Video
- Back 또는 Project Exit

Primary Record Button은 촬영 화면에서 가장 명확한 Action이어야 한다.

기타 Control은 Record Button보다 시각적 우선순위가 낮아야 한다.

---

## 12. Recording Interaction

사용자가 Record Button을 누르면 즉시 녹화를 시작한다.

사용자는 10초 이전 언제든 Record Button을 다시 눌러 녹화를 종료할 수 있다.

10초에 도달하면 Mellow가 자동으로 Recording을 종료한다.

고정된 1초, 3초, 5초 등의 Recording Preset은 제공하지 않는다.

녹화 중 Pause / Resume 기능은 제공하지 않는다.

---

## 13. Recording Feedback

Record Button 주변에 10초 Recording Progress를 표현하는 Circular Progress 형태를 우선 검토한다.

Progress 표현은 Timer를 읽지 않아도 촬영 종료가 가까워지고 있음을 직관적으로 알 수 있게 해야 한다.

화면 중앙에 큰 Countdown 숫자를 표시하지 않는다.

마지막 구간에서는 Progress 변화와 Subtle Haptic을 통해 자동 종료가 가까워졌음을 자연스럽게 알릴 수 있다.

정확한 Haptic Timing은 실제 Device Test 후 결정한다.

---

## 14. Camera Switching

Front Camera와 Rear Camera 전환은 녹화하지 않는 상태에서만 가능하다.

Recording 중에는 Camera Switch 기능을 비활성화한다.

사용자가 촬영 중 Camera Switch Control을 실수로 누르더라도 현재 Recording이 손상되지 않아야 한다.

Front와 Rear Camera 동시 촬영은 MVP에 포함하지 않는다.

---

## 15. Import Video

사용자는 Camera 또는 Project 화면에서 기존 Photos Library 영상을 추가할 수 있어야 한다.

Import 기능은 Camera 촬영보다 숨겨져서는 안 되지만 Record Button보다 높은 시각적 우선순위를 갖지 않는다.

Photos에서 영상을 선택하면 원본 영상의 길이에 관계없이 사용할 수 있어야 한다.

10초보다 긴 영상은 Import 이후 사용할 최대 10초 구간을 선택한다.

10초보다 짧은 영상은 전체 영상을 기본 선택 상태로 보여줄 수 있다.

---

## 16. Imported Video Trim

Imported Video의 Trim 화면은 원본 전체 영상에서 사용할 구간을 선택하는 역할을 한다.

사용자는 시작점과 종료점을 조절할 수 있어야 한다.

선택된 구간은 최대 10초를 초과할 수 없다.

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

Project Screen은 현재 Vlog를 구성하는 Clip을 관리하는 공간이다.

사용자는 이 화면에서 현재 Vlog의 전체 구조를 빠르게 이해할 수 있어야 한다.

주요 기능은 다음과 같다.

- Clip 확인
- Clip 순서 변경
- Clip 삭제
- Clip Trim
- 새 Clip 촬영
- Video Import
- 전체 Preview
- Export

전문적인 Video Timeline Interface를 그대로 복제하지 않는다.

---

## 19. Clip Representation

각 Clip은 Thumbnail을 중심으로 표현한다.

필요한 경우 Clip Duration을 함께 표시한다.

직접 촬영한 Clip과 Imported Clip을 시각적으로 지나치게 다르게 표현할 필요는 없다.

사용자에게 중요한 것은 Clip의 출처보다 Vlog에서 어떻게 사용되는지다.

---

## 20. Reorder Clips

사용자는 Drag Interaction을 통해 Clip 순서를 변경할 수 있어야 한다.

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

---

## 22. Delete Project

전체 Project 삭제는 Clip 삭제보다 훨씬 큰 결과를 가져오기 때문에 Confirmation을 요구한다.

Confirmation은 Project와 Mellow 내부 미디어가 삭제된다는 사실을 명확하게 설명해야 한다.

Photos Library의 원본 영상에는 영향을 주지 않는다는 점을 필요에 따라 안내한다.

Destructive Action은 시각적으로 명확하게 구분한다.

---

## 23. Full Vlog Preview

사용자는 현재 Project 전체를 실제 Export 결과와 유사한 형태로 연속 재생할 수 있어야 한다.

Preview에서는 다음 요소를 반영한다.

- Clip order
- Trim
- Crop
- Project orientation
- Video
- Audio

Clip 사이에는 MVP에서 특별한 Transition을 적용하지 않는다.

---

## 24. Export

Export는 Project 작업의 명확한 Completion Action으로 제공한다.

사용자가 Export 버튼을 눌렀다고 Project가 삭제되거나 완료 상태로 강제 전환되지는 않는다.

Export는 현재 Project State를 기준으로 하나의 결과 Video를 생성하는 동작이다.

Export에는 시간이 걸릴 수 있으므로 진행 상태를 사용자에게 표시해야 한다.

Export가 성공하면 `Saved to Photos` 상태를 보여주고 `Share`와 `Done` Action을 제공한다.

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

Camera, Microphone, Photos 권한은 실제 기능을 처음 사용하는 시점에 Contextual하게 요청한다.

사용자가 권한을 거부한 경우 Mellow가 해당 권한을 왜 필요로 하는지 짧고 명확하게 설명한다.

Settings 이동이 필요한 경우 적절한 Action을 제공한다.

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

Haptic Feedback은 중요한 Action에 선택적으로 사용한다.

후보 사용 지점은 다음과 같다.

- Recording start
- Recording stop
- 10초 자동 종료 직전
- 10초 자동 종료
- Clip reorder placement
- Export completion

모든 Button Tap에 Haptic을 사용하지 않는다.

Haptic은 실제 iPhone 테스트를 통해 강도와 빈도를 조정한다.

---

## 30. Color Direction

Mellow의 Brand UI는 따뜻한 Cream 계열을 기본 방향으로 사용한다.

기존 브랜드 방향의 기본 Background Reference는 다음과 같다.

`#F4EBDD`

Camera 또는 Video 위 Overlay UI에서는 높은 가독성이 필요하므로 Dark Neutral과 White 계열을 사용할 수 있다.

Pure Black을 브랜드 화면의 기본 컬러로 과도하게 사용하지 않는다.

Camera 화면에서는 콘텐츠 가독성을 위해 필요한 경우 Black 계열을 사용할 수 있다.

정확한 Color Token은 실제 UI Prototype을 통해 확정한다.

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

- Home에서 미완성 프로젝트 영역의 주요 명칭은 `Recent`를 사용한다.
- 사용자에게 `Draft`라는 내부 개념을 주요 UI 용어로 노출하지 않는다.
- New Vlog 생성 시 프로젝트 이름 입력 단계를 두지 않는다.
- New Vlog를 누르면 9:16 또는 16:9를 선택한 뒤 Camera로 진입한다.
- 프로젝트 화면 비율은 생성 이후 자동 변경하지 않는다.
- 기기 방향이 Project Orientation과 다르면 조용한 회전 안내를 표시한다.
- Camera Preview는 촬영 화면의 가장 중요한 시각 요소다.
- 하나의 Clip은 최대 10초까지 자유롭게 촬영한다.
- 사용자는 10초 이전 언제든 녹화를 종료할 수 있다.
- 10초에 도달하면 자동으로 녹화를 종료한다.
- Recording Progress는 Record Button 주변의 Progress Ring 방향을 우선한다.
- 큰 Countdown 숫자는 사용하지 않는다.
- 자동 종료가 가까워졌음을 Subtle Haptic으로 알리는 방향을 검토한다.
- Front / Rear Camera Switch는 녹화하지 않는 상태에서만 가능하다.
- 녹화 중 Camera Switch는 허용하지 않는다.
- Photos에서 가져온 영상 원본 길이는 제한하지 않는다.
- Imported Video에서 사용할 구간은 최대 10초다.
- Project Orientation과 다른 Imported Video는 기본적으로 Fill + Crop 처리한다.
- 사용자가 Imported Video의 Framing을 조절할 수 있어야 한다.
- Clip 삭제는 즉시 적용하고 Undo를 제공한다.
- Project 삭제는 Confirmation을 요구한다.
- Project Rename은 MVP에서 제공하지 않는다.
- Clip Duplicate는 MVP에서 제공하지 않는다.
- Clip Split은 MVP에서 제공하지 않는다.
- Export 이후 Draft를 자동 삭제하지 않는다.
- Export 완료 후 iOS Share Sheet를 제공한다.
- UI는 Content-first 원칙을 따른다.
- Brand Screen에서는 따뜻한 Mellow 스타일을 사용하고 Camera 및 Video Screen에서는 콘텐츠 가독성을 우선한다.

---

## 37. Open Design Decisions

### Home

- Recent Project를 List 또는 Grid 중 어떤 형태로 표시할지
- New Vlog 버튼의 정확한 Placement
- Empty State Visual

### Orientation

- 9:16 / 16:9 선택 화면의 정확한 Visual Style
- Orientation mismatch 안내의 형태와 위치

### Camera

- Record Button 정확한 Size
- Recording Timer 표시 여부
- Camera Switch 위치
- Import 버튼 위치
- Clips 진입 방식
- Camera UI Overlay 배치

### Recording

- 10초 마지막 몇 초부터 종료 Feedback을 강화할지
- Haptic 정확한 Timing
- 자동 종료 시 Animation
- Clip 저장 완료 Feedback

### Imported Video

- Trim과 Crop을 하나의 화면에서 처리할지
- 두 단계로 분리할지
- Crop 시 Pinch to Zoom을 MVP에 포함할지
- Crop Reset 기능 필요 여부

### Project

- Clip Organizer가 Horizontal Strip인지 Grid인지
- Reorder Interaction의 정확한 형태
- Project 전체 Duration 표시 위치
- Add Clip Action의 위치

### Trim

- Thumbnail Filmstrip 사용 여부
- Trim Handle Visual
- Time Precision
- Scrubbing UX

### Preview

- Playback Control 형태
- Scrubber 제공 여부
- Preview에서 빠르게 Clip으로 돌아가는 Interaction

### Export

- Export Action의 위치
- Export Progress UI
- 완료 화면 구성
- Share와 Done의 Visual Priority

### Brand

- 최종 Color Palette
- Typography
- Corner Radius System
- Icon Style
- Animation Curve
- Logo 사용 위치

이 Open Decision은 실제 화면 Prototype과 iPhone 사용성을 확인한 후 순차적으로 확정한다.