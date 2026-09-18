# Mellow — Product Definition

## 1. Product Overview

### Product Name

**Mellow**

### Product Definition

Mellow는 일상의 짧은 순간들을 여러 개의 영상 클립으로 촬영하거나 Photos Library에서 가져와 간단하게 다듬고 하나의 미니 브이로그로 완성할 수 있는 **iPhone-only V1** 미니 브이로그 앱이다.

Mellow의 핵심은 복잡한 영상 편집이 아니다.

사용자가 특별한 편집 기술을 배우지 않아도

**촬영 → 이어 붙이기 → 간단히 다듬기 → 저장**

이라는 짧고 자연스러운 과정만으로
자신의 하루와 순간을 작은 영상으로 남길 수 있도록 하는 것이 목표다.

---

## 2. Product Vision

Mellow는 거창한 영상을 만드는 도구가 아니라
일상의 작은 순간을 부담 없이 영상으로 남기는 도구를 지향한다.

사용자는 특별한 날만 기록하지 않는다.

카페에서 마신 커피,
출근길의 풍경,
여행 중 잠깐 바라본 거리,
친구와의 짧은 순간,
집에서 보내는 평범한 저녁처럼

사진 한 장으로는 부족하지만
본격적인 영상 편집까지 할 필요는 없는 순간들이 있다.

Mellow는 이러한 순간들을
몇 초짜리 짧은 영상 클립으로 자연스럽게 모으고,
하나의 짧은 브이로그로 완성하는 경험을 제공한다.

Mellow가 궁극적으로 제공하고자 하는 것은

**“편집을 위한 영상 앱”이 아니라
“기록을 위한 영상 앱”이다.**

---

## 3. Product Philosophy

### Simple

Mellow는 기능의 수보다 사용 흐름의 단순함을 중요하게 생각한다.

영상 편집 경험이 없는 사용자도
별도의 학습 없이 사용할 수 있어야 한다.

복잡한 메뉴,
다단계 설정,
전문적인 편집 도구는 최소화한다.

### Capture First

Mellow에서 가장 중요한 행동은 편집이 아니라 촬영이다.

사용자가 앱을 실행한 후
가능한 빠르게 새로운 순간을 기록할 수 있어야 한다.

### Short by Nature

Mellow는 긴 영상을 제작하기 위한 앱이 아니다.

몇 초짜리 순간들을 짧게 기록하고,
여러 클립을 하나의 작은 이야기로 만드는 것을 기본 경험으로 한다.

### Calm

촬영과 편집 과정에서
UI가 사용자의 콘텐츠보다 더 강하게 드러나지 않아야 한다.

인터페이스는 차분하고 단순해야 하며
사용자의 영상이 항상 중심에 있어야 한다.

### Fast

촬영 후 결과물을 만드는 데 필요한 단계는 최소화한다.

불필요한 설정이나 편집 과정 때문에
사용자가 기록 자체를 포기하지 않도록 한다.

### Non-destructive

Photos Library의 원본 영상은 수정하거나 삭제하지 않는다.

편집 과정에서 원본 미디어를 직접 변경하거나 손상시키지 않으며,
완성된 결과물은 별도의 영상으로 생성하는 것을 기본 원칙으로 한다.

---

## 4. Problem

스마트폰으로 영상을 촬영하는 것은 매우 쉬워졌지만,
여러 개의 짧은 영상을 하나의 작은 브이로그로 만드는 과정은 여전히 번거롭다.

기본 카메라 앱은 영상을 촬영하는 데는 적합하지만
여러 순간을 하나의 기록으로 정리하는 경험은 제공하지 않는다.

반대로 기존 영상 편집 앱은 매우 강력하지만
간단한 일상 기록을 만들기에는 기능이 지나치게 많고 복잡한 경우가 있다.

타임라인,
레이어,
효과,
애니메이션,
컬러 그레이딩,
템플릿 등의 기능은 전문적인 결과물을 만드는 데는 유용하지만
단순히 오늘의 순간을 짧게 기록하고 싶은 사용자에게는 부담이 될 수 있다.

Mellow는 그 사이를 목표로 한다.

사용자는 영상 편집을 배우는 것이 아니라

**순간을 촬영하고,
필요한 부분만 남기고,
순서를 정리한 뒤,
하나의 영상으로 저장한다.**

---

## 5. Target Users

Mellow의 주요 사용자는
전문적인 영상 제작자가 아닌 일상적인 iPhone 사용자다.

대표적인 사용자는 다음과 같다.

- 하루의 짧은 순간들을 영상으로 남기고 싶은 사람
- Mini Vlog 형식의 콘텐츠를 좋아하는 사람
- 여행이나 일상을 짧은 영상으로 기록하는 사람
- Instagram Reels, TikTok, YouTube Shorts 등에 짧은 영상을 공유하는 사람
- 본격적인 영상 편집 앱은 너무 복잡하다고 느끼는 사람
- 긴 영상보다는 짧고 자연스러운 기록을 선호하는 사람
- 영상 편집 자체보다 기록 경험을 중요하게 생각하는 사람

---

## 6. Core User Experience

Mellow의 가장 기본적인 사용자 경험은 다음과 같다.

### Create

ADR-032에 따라 V1의 새 Capture는 `9:16 Portrait`만 사용한다.

사용자는 형식을 고르지 않고 앱을 열어 바로 촬영을 시작한다.

**Portrait — 9:16**

세로형 미니 브이로그를 위한 V1의 유일한 Capture 형식이다.

Shorts, Reels, TikTok 등
모바일 중심 콘텐츠와 일상 기록에 적합하다.

**Landscape — 16:9**

가로형 미니 브이로그를 위한 모드이며
여행 영상, 풍경, YouTube 스타일의 영상 기록에 적합하다.

ADR-032에 따라 새 Landscape Project 생성과 Landscape Camera Capture는 V1 이후로 유예한다.

이는 제품 범위 축소이며 Domain / Schema는 두 방향을 계속 표현한다.

---

## 7. Project Orientation Policy

Mellow의 제품 모델은 세로와 가로 프로젝트를 모두 표현하지만
ADR-032에 따라 V1이 새로 만들 수 있는 프로젝트는 `9:16 Portrait`뿐이다.

그러나 하나의 프로젝트에서는
하나의 화면 비율만 사용한다.

예를 들어 사용자가 새로운 프로젝트를 만들 때
9:16을 선택했다면 해당 프로젝트는 끝까지 9:16 프로젝트로 유지된다.

16:9 프로젝트 역시 동일하다.

촬영 중 기기의 물리적 방향이 바뀌었다는 이유만으로
프로젝트의 화면 비율이 자동으로 변경되지 않는다.

이 정책의 목적은 다음과 같다.

- 일관된 결과물 유지
- 촬영 중 실수 방지
- 클립 간 화면 비율 혼합 방지
- 편집 인터페이스 단순화
- Export 결과 예측 가능성 향상

프로젝트의 화면 비율은
콘텐츠 제작의 기본 속성으로 취급한다.

---

## 8. Core Vlog Flow

Mellow의 대표적인 사용자 흐름은 다음과 같다.

**Mellow 실행 / Splash**

↓

**Permission Onboarding (첫 실행 시에만 표시)**

↓

**Portrait Camera**

↓

**짧은 Clip을 여러 개 촬영 → 각각 Photos에 저장 (Project 없음)**

↓

**Projects → Select Clips (또는 Load Last Saved)**

↓

**선택한 Clip으로 하나의 저장 Project 구성, 필요 시 Photos Video Import**

↓

**촬영하거나 가져온 Clip 확인**

↓

**Clip 순서 정리**

↓

**각 Clip의 시작 / 끝 Trim**

↓

**전체 Vlog Preview**

↓

**Video Export**

↓

**Photos에 저장 / 공유**

이 흐름이 Mellow의 가장 중요한 제품 경험이다.

---

## 9. Core Product Areas

### Vlog Camera

Mellow에서 직접 짧은 영상 클립을 촬영한다.

카메라는 전문 촬영 도구가 아니라
빠르고 자연스럽게 순간을 기록하는 데 집중한다.

### Vlog Project

여러 개의 영상 클립을
하나의 미니 브이로그 프로젝트로 관리한다.

한 프로젝트에는

- Project orientation
- Video clips
- Clip order
- Clip trimming information
- Project duration
- Editing state

등의 정보가 포함될 수 있다.

Clip이 0개인 Project도 정상적인 Draft이며 Recent에 존재하고 다시 열 수 있다.

0 Clip Project는 Project Orientation을 유지한 채 Recording과 Photos Video Import를 시작할 수 있지만 Full Vlog Preview와 Export는 사용할 수 없다.

0 Clip 상태는 Corruption이 아니며 자동으로 삭제하지 않는다.

### Photos Video Import

Photos Library의 기존 영상을 MVP에서 프로젝트에 추가할 수 있다.

ADR-042에 따라 전체 길이가 1.0초 이상 5.0초 이하(양 끝 포함)인 영상만 받아들이며 1.0초 미만이거나 5.0초를 초과하는 영상은 가져오지 않는다. 긴 영상에서 최대 5초 구간을 골라 가져오는 기능은 제공하지 않는다.

### Clip Organizer

촬영하거나 가져온 영상들을 확인하고 브이로그에 사용할 클립과 순서를 관리한다.

### Simple Editor

선택한 Clip → 명시적인 `T` Tool → 해당 Clip의 Text 추가 / 수정 흐름을 제공하며 `T`는 Editor Tool Layout에서 발견하기 쉬워야 한다.

일반 Clip Tap은 선택만 하고 Text Entry를 열지 않는다.

Font 선택, Position, Size, Text Duration과 Animation 세부 정책은 Phase 7 구현 전 Gate에서 결정하며 복잡한 Typography / Effect Editor, Text Animation System, Keyframe, Multi-track Text Timeline과 Sticker는 추가하지 않는다.

ADR-032 이후 V1 구조는 Portrait Camera → Short Clip Capture → Clip Review / Management → Editor → Export를 하나의 Persisted Vlog Project 안에서 연결한다.

Camera Chrome은 두 Affordance를 분리한다(ADR-041): Upper-trailing `Projects`가 저장 Project 접근(Projects 화면 → Editor)이고, 좌하단 Compact Slot은 방금 촬영한 Direct Capture의 피드백(이후 별도 승인 시 Latest Capture Review)이다. 좌하단 Slot은 저장 Project Representative나 Editor 바로가기가 아니며 별도 Dashboard나 복잡한 Camera Timeline을 추가하지 않는다. Project Representative Thumbnail은 Projects 화면 같은 Project-oriented Surface에만 표시한다.

Editor는 큰 Preview를 Primary Visual Focus로 두고 단순한 Ordered Clip Thumbnail Strip, 명시적인 Clip Selection, 가벼운 Clip Tools와 Add Clip / Final Output Action으로 구성한다.

Clip Thumbnail의 Single Tap은 선택이며 Text Entry를 바로 열지 않는다.

Long Press + Drag로 순서를 바꾸고 Move Earlier / Move Later와 같은 Non-drag Accessibility 대안을 제공한다.

Trim / Text / Delete는 명시적인 Clip Action이다. Add Clip은 ADR-037에 따라 System PhotosPicker를 열어 Phase-5-ready Media를 현재 Project 끝에 추가하며 Camera를 열지 않는다(Camera로 촬영한 Clip은 Photos 저장 후 같은 경로로 추가한다). 각 기능은 기존 Owning Phase에서 구현한다.

Final Output의 정확한 Label과 동작은 Export Phase에서 결정하며 Toolbar Geometry를 이 결정에서 고정하지 않는다.

짧은 순간의 단순한 배열, 명시적 Control과 Capture에서 Composition으로 빠르게 이동하는 낮은 복잡도의 Mini Vlog Editor를 지향하며 Multi-track Timeline, Keyframe, Layer Stack과 복잡한 Effect System을 도입하지 않는다.

### Preview

Individual Clip Preview는 사용자가 현재 해당 Clip이 실제 Vlog에서 어떻게 보일지 확인하는 기능이며 Raw Source를 단순 재생하는 기능이 아니다.

Full Vlog Preview는 현재 Clip 순서와 편집 내용을 반영한 전체 결과물을 확인하는 기능이다.

### Export

편집이 완료된 미니 브이로그를
하나의 영상 파일로 만들어 저장한다.

---

## 10. MVP

Mellow의 첫 번째 목표는
많은 편집 기능을 구현하는 것이 아니다.

첫 번째 목표는

**여러 개의 짧은 순간을 촬영하여
하나의 완성된 미니 브이로그로 저장하는 경험**

을 완성하는 것이다.

### MVP Core Flow

**Mellow 실행 / Splash**

→

**Portrait Camera**

→

**여러 Clip 촬영 또는 Photos Video Import**

→

**Clip 확인**

→

**순서 변경**

→

**Trim**

→

**전체 Preview**

→

**Export**

### MVP Required Features

#### New Vlog

새로운 브이로그 프로젝트를 생성할 수 있다.

프로젝트 이름 입력 Prompt는 제공하지 않는다.

생성 날짜와 시간을 기반으로 자동 표시 이름을 사용하며 Rename은 MVP에서 제공하지 않는다.

구체적인 날짜 및 시간 표시 Format은 아직 확정하지 않는다.

#### Orientation Selection

ADR-032에 따라 V1은 형식 선택 단계를 제공하지 않으며 새 프로젝트는 항상 `9:16 Portrait`이다.

- 9:16 Portrait — V1 Capture 형식
- 16:9 Landscape — Domain / Schema 표현은 유지하며 새 생성은 V1 이후로 유예

선택된 화면 비율은 해당 프로젝트 내에서 유지한다.

#### Video Recording

Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration을 제공하고 기본 선택은 `3s`다.

선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있으며 Project-level 불변 속성이 아니다.

선택한 값은 다음 Clip의 최대 길이이며 정확히 그 길이로 출력해야 한다는 뜻이 아니다.

Source와 관계없이 Mellow Vlog의 모든 Clip은 `0 < effectiveClipDuration <= 5 seconds`를 만족한다.

예를 들어 3s 선택 후 1.4초에 수동 Stop하면 약 1.4초 Clip을 만든다.

Project Orientation은 기존 9:16 / 16:9 Project-level 불변 정책을 유지한다.

Mellow는 여러 짧은 순간을 하나의 이야기로 연결하는 Mini Vlog Camera다.

짧은 Clip은 리듬을 살리고 하나의 Clip이 Vlog를 지배하는 경향을 줄이며 1–5초는 엄격한 1–3초보다 유연하면서 Short-form 정체성을 유지한다.

사용자는 선택한 최대 Duration 전에 언제든 수동으로 Stop할 수 있고 선택한 최대 Duration에 도달하면 자동으로 Stop한다.

Recording Pause / Resume는 MVP에서 제공하지 않는다.

기본 Capture Profile은 1080p / 30 fps다.

Front Camera와 Rear Camera를 모두 지원하며 Camera Switching은 녹화하지 않는 idle 상태에서만 가능하다.

Recording 중 Camera Switching은 허용하지 않는다.

Rear Camera의 기본 Capture Device는 1× Wide Camera이며 사용자가 0.5× Ultra Wide, Telephoto 또는 물리 Lens를 직접 선택하는 Lens Selector UI는 MVP에서 제공하지 않는다.

Rear Camera는 1× 이상에서 Continuous Zoom을 지원하며 Recording 시작 전 Preview와 Recording 중 모두 사용할 수 있다.

Recording 중 Rear Zoom을 변경해도 현재 Recording을 Stop하거나 Restart하지 않고 새로운 Clip을 만들거나 선택한 최대 Duration Timer를 Reset하지 않으며 Project Orientation 또는 Aspect Ratio를 변경하지 않는다.

Phase 3에서 승인한 Rear Zoom 범위는 동일한 Rear 1× Wide Camera의 1.0×–2.0×이며 양 끝에서 Clamp하고 다른 Lens로 전환하지 않는다.

Rear Zoom은 Pinch-to-zoom을 사용하며 Persistent Button / Slider 없이 Gesture 중에만 작은 Numeric Indicator를 허용하고 Gesture Feel은 iPhone 12에서 조정할 수 있다.

Front Camera Zoom과 Mirror Toggle은 MVP에 포함하지 않는다.

Front Camera Preview는 Mirrored Appearance를 사용하며 Mellow에서 직접 촬영한 Front Clip도 이후 Preview, Editing과 Export에서 사용자가 촬영 중 본 Mirrored Framing을 유지한다.

ADR-033에 따라 Direct Recording에는 Camera 권한과 Photos Add 권한이 필요하며 Microphone은 선택 권한이다. Microphone이 거부되어도 무음으로 촬영할 수 있고 Camera는 `mic.slash` 상태를 조용히 표시한다. 성공한 Clip은 Photos에 직접 저장되며 Project를 만들지 않는다.

Camera 또는 Microphone Permission 문제는 Photos Video Import를 차단하지 않으며 Audio Track이 없는 Photos Source Video도 Import할 수 있다.

새 Recording은 Device Orientation이 Project Orientation과 일치할 때만 시작하며 Face Up, Face Down, Unknown 또는 안정적으로 판단할 수 없는 상태에서도 시작하지 않는다.

Orientation이 맞지 않으면 Project 비율을 변경하지 않고 조용한 Rotate Device 안내를 제공하며 Record Action, Progress와 선택한 최대 Duration Timer는 유효한 Orientation이 확인될 때까지 시작하지 않는다.

Recording 시작 후 Device를 회전해도 현재 Recording을 자동 Stop하거나 Restart하지 않고 Project Orientation과 Clip Aspect Ratio를 변경하지 않으며 Rear Zoom을 회전만으로 Reset하지 않는다.

다음 Clip Recording을 시작하기 전에는 Orientation Match를 다시 확인한다.

한 프로젝트에서 여러 클립을 연속해서 추가할 수 있다.

Recording Interruption은 Successful Manual Stop 또는 Successful Auto-stop으로 표시하지 않으며 생성된 Media는 ADR-020 / ADR-021의 Validation, Recovery와 Project Validity 계약을 따른다.

Interruption으로 생성된 Valid Partial Clip의 최종 처리와 Minimum Valid Clip Duration은 ADR-033으로 확정되었다: Direct Capture는 1.0초 이상이고 Finalization이 성공하면 Photos에 저장하고 1.0초 미만이면 폐기한다. Imported Photos Source의 최소 길이는 ADR-042로 1.0초로 확정되었다(별개 규칙).

#### Photos Video Import

Photos Library의 기존 Video를 프로젝트에 추가할 수 있다.

ADR-042에 따라 Mellow는 **선택한 Photos Video의 전체 길이**가 `1.0s <= duration <= 5.0s`(양 끝 포함)일 때만 그 Video를 받아들인다. 1.0초 미만이거나 5.0초를 초과하는 Source는 프로젝트에 가져오지 않으며 긴 Source에서 최대 5초 Segment를 선택하는 기능은 제공하지 않는다.

1.0초 이상 5.0초 이하인 Source Video는 전체 구간이 그대로 Clip이 된다. 정확히 1.0초와 5.0초는 허용되고 1.3초, 2.7초, 4.5초처럼 정수가 아닌 길이도 유효하며 Camera Preset은 Photos Import와 무관하다. 0.4초 / 0.8초 같은 1.0초 미만은 거부, 5.0초 초과는 거부, 0 이하 / 읽을 수 없음은 Invalid다. Imported 최소 1.0초는 Direct Capture 최소 1.0초(ADR-033)와 값이 같지만 별개의 규칙이다.

System PhotosPicker는 길이로 항목을 미리 숨기지 못하므로 사용자가 범위 밖 영상을 탭할 수 있다. Mellow는 Metadata 검사 후 해당 항목을 거부하고 Project-owned Media 생성, Clip Metadata Commit, 부분 Project 변경 없이 Photos 원본을 그대로 둔다. 단일 항목 선택과 Replace 후보에서 5.0초 초과 안내는 기존 `영상이 너무 길어요` / `5초 이하의 영상을 선택해주세요.`이고 1.0초 미만 안내는 `영상이 너무 짧아요` / `1초 이상의 영상을 선택해주세요.`다(ADR-042 Revision 2, 두 안내는 별개). 여러 영상을 고른 경우(Select Clips / Add)에는 ADR-042 Revision 3에 따라 길이 조건에 맞지 않는 영상만 제외하고 나머지 유효한 영상으로 계속 진행하며 통합 안내를 한 번 보여준다: `짧은 영상이 제외되었어요` / `1초 미만의 영상은 추가할 수 없어요.` / `긴 영상이 제외되었어요` / `5초를 초과한 영상은 추가할 수 없어요.` / `일부 영상이 제외되었어요` / `1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요.`. 모두 제외되면 프로젝트를 만들거나 바꾸지 않는다. Replace는 한 개 후보만 다루므로 후보가 조건에 맞지 않으면 기존 Clip을 그대로 두고 개별 안내로 거부한다. 세 경로가 같은 규칙을 사용한다.

ADR-043(Revision 1)에 따라 세로 형식이 아닌 영상 — preferredTransform 적용 후 세로가 가로보다 크지 않은 가로 영상과 정사각형 영상 — 은 V1에서 지원하지 않으며 하나의 "세로 형식이 아닌 영상"으로 취급한다(가로 / 정사각형을 구분한 별도 기능이나 안내 없음, 세로 변환 · 잘라내기 · 여백 채우기 · 회전 안내 없음). 여러 영상 선택(Select Clips / Add)에서는 해당 영상만 제외하고 세로 영상으로 계속 진행하며 그것이 유일한 제외 사유면 `일부 영상이 제외되었어요` / `세로 형식이 아닌 영상은 추가할 수 없어요.`를 한 번 보여주고(개수 표시 없음), 모두 세로 형식이 아니면 프로젝트를 만들거나 바꾸지 않는다. 단일 선택이나 Replace 후보가 세로 형식이 아니면 `지원하지 않는 영상이에요` / `세로 영상을 선택해주세요.`로 거부하고 기존 Clip을 그대로 둔다. 제외된 영상에는 어떤 Media 작업도 하지 않는다. 일반 iPhone 세로 촬영본(자연 크기 1920×1080이지만 세로로 표시되는 영상)과 좌우 반전된 세로 영상은 세로 영상이다. 이 동작은 승인된 정책이며 아직 구현되지 않았다(현재 Phase 5는 세로가 아닌 영상을 만나면 선택 전체를 거부한다).

ADR-044에 따라 V1 Photos Import는 iPhone 촬영 → Photos 선택 → Mellow 준비 Workflow를 위한 것이며 실제 Container가 QuickTime Movie인 영상만 받아들인다(H.264 / HEVC 모두). MP4 등 QuickTime이 아닌 영상은 파일 이름 확장자가 아니라 실제 Container 검사로 판별해 제외하며(`.mp4`를 `.mov`로 바꿔도 허용되지 않고, 진짜 QuickTime 파일은 `.mp4` 이름이어도 제외되지 않는다) 변환 · Remux · 변환 안내를 제공하지 않는다. 여러 영상 선택에서는 해당 영상만 제외하고 QuickTime 영상으로 계속하며 안내는 기존 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`(길이 / 세로 형식 사유와 복합이면 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`)를 쓴다. 모두 제외되면 프로젝트를 만들거나 바꾸지 않고 Replace 후보가 해당하면 거부하며 기존 Clip을 그대로 둔다. QuickTime이라는 사실만으로 자동 허용되지는 않으며 길이 · 세로 · 읽기 가능 등 다른 규칙을 모두 통과해야 한다. 이 동작은 승인된 정책이며 아직 구현되지 않았다(현재 Phase 5는 Container를 검사하지 않는다).

ADR-042 Revision 4에 따라 남은 세로 영상 중 준비(4K / HDR / Dolby Vision / 30 fps 초과 정규화)가 필요한 영상이 있으면 별도 확인 없이 자동으로 준비를 시작하고 `영상을 준비하고 있어요` / `잠시만 기다려주세요.` Sheet(진행 표시, 여러 개면 `2/5` 위치, `취소`)를 보여준다. 모두 바로 쓸 수 있는 영상이면 Sheet를 보이지 않는다. 준비가 끝나면 Sheet가 자동으로 닫히고 프로젝트 생성 / 추가 / 교체가 완료되며, 앞서 제외된 영상이 있었다면 통합 안내를 한 번 보여준다. 취소하면 임시 파일을 모두 지우고 프로젝트를 만들거나 바꾸지 않는다. 준비 중 실패하면 일부만 저장하지 않고 `영상을 준비하지 못했어요` / `프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.`와 `다시 시도` / `취소`를 보여준다. 저장 공간이 부족하면 영상을 만들기 전에 `저장 공간이 부족해요` / `영상을 추가하려면 기기의 저장 공간을 확보한 후 다시 시도해주세요.` / `확인`를 보여준다. 읽을 수 없거나 지원하지 않는 영상은 그 영상만 제외하고 `일부 영상을 추가할 수 없어요` / `읽을 수 없거나 지원하지 않는 영상은 제외되었어요.`(길이 사유와 함께면 `일부 영상이 제외되었어요` / `길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.`)를 한 번 보여준다. 이 동작은 승인된 정책이며 아직 구현되지 않았다. 5.0초 초과 거부는 Phase 5가 이미 구현했고 1.0초 미만 거부는 Phase 6 구현 요구사항이다.

SDR, HDR / Dolby Vision 및 4K를 포함한 고해상도 Source Import를 허용하며 30 fps보다 높은 Source도 가져올 수 있다.

5초 이하 전체 Source로 만드는 Project-owned Working Media는 1080p-class / 30 fps / SDR을 기준으로 한다.

HDR / Dolby Vision의 Dynamic Range와 HDR Metadata를 Working Media에 완전히 보존하는 것은 MVP 목표가 아니다.

Working Media를 만들 때 프로젝트 비율에 맞춘 Fill + Crop을 미리 적용하여 저장하지 않으며 이후 사용자가 Framing을 조정할 수 있도록 Source의 유효 화면 영역을 보존한다.

정상적으로 추가된 Clip은 Mellow가 소유한 로컬 미디어를 사용하며 이후 사용자가 Photos 원본을 삭제해도 Draft에 유지되어야 한다.

Photos 원본은 Import, 편집, Export 또는 프로젝트 삭제 과정에서 수정하거나 삭제하지 않는다.

Imported Clip의 Re-trim은 받아들여진 Project-owned Clip Media 범위 안에서만 가능하며 원본 Source Reference는 유지하지 않는다(ADR-042). Working Media Codec / Container, 정확한 SDR Color Profile / Tagging 및 Tone-mapping 구현 방법은 아직 확정하지 않는다.

1080p-class는 고해상도 Source를 제한·정규화하는 Working Target이며 저해상도 Source의 Upscaling 여부는 아직 확정하지 않는다.

#### Imported Orientation and Framing

가져온 Video와 프로젝트의 화면 비율이 다르면 기본적으로 Fill + Crop을 적용한다.

사용자는 Framing 위치를 조정할 수 있어야 한다.

Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 편집으로 유지하며 실제 화면 구성을 Preview와 Export에서 적용한다.

Fit과 Background Blur는 MVP에서 제공하지 않는다.

세부 Crop UI와 Pinch to Zoom 지원 여부는 아직 확정하지 않는다.

#### Recent and Local Drafts

Launch의 Upper Trailing 영역에 작은 Projects Button을 조용한 Secondary Access로 두고 Accessibility Label은 `Projects`로 제공한다.

ADR-033에 따라 탭하면 저장 Project가 없을 때 `Select Clips`, 있을 때 `Load Last Saved` / `Select Clips`를 제공하며 기존 Project를 열기 위해 새 Format을 선택할 필요가 없다.

큰 Existing-project Text CTA와 Launch의 Project Thumbnail / Metadata / Recent Grid는 제공하지 않으며 정확한 Iconography는 Phase 3 Visual 구현에서 정한다.

내부 Domain에서는 `Draft`라는 기술 용어를 사용할 수 있다.

여러 개의 Draft를 동시에 지원하며 별도의 Save Action 없이 프로젝트 상태를 자동 저장한다.

Draft는 사용자가 삭제하기 전까지 자동 만료하지 않으며 앱 재실행과 기기 재부팅 후에도 로컬에 유지한다.

Export 후에도 Draft를 유지하여 다시 열고 수정하거나 재Export할 수 있다.

Clip이 0개인 Project는 유효한 Draft로 Recent에 표시되고 다시 열 수 있으며 자동으로 삭제하지 않는다.

0 Clip Project에서는 Recording과 Photos Video Import를 계속 사용할 수 있지만 Full Vlog Preview와 Export는 비활성화한다.

Recent의 Project Representative Thumbnail Source는 현재 Project의 logical Clip Order에서 첫 번째 Healthy / Usable Clip이다.

Representative Source의 `첫 번째`는 Clip 생성 시각이나 Filename이 아니라 현재 logical Clip Order를 기준으로 판단하며 Unavailable Clip은 Representative Source가 될 수 없다.

0 Clip Project 또는 All-unavailable Project에는 usable Representative Source가 없으므로 다른 Project나 임의 Media를 재사용하지 않고 neutral 또는 generated Placeholder를 사용할 수 있다.

Representative Thumbnail은 Project나 Clip Media의 Source of Truth가 아닌 재생성 가능한 Derived / Cache Representation이며 Thumbnail Missing, Corruption, Generation Failure 또는 Cache Cleanup은 Project Corruption이나 Project / Clip Delete의 근거가 아니다.

Clip Add, Delete, Undo Restore, Replace 성공, Reorder, Availability Change와 Project Reload 또는 Reconciliation 뒤에는 현재 Representative Source를 다시 평가한다.

Replace가 완료되기 전 또는 실패한 경우에는 기존 Unavailable Placeholder와 현재 Representative Source 상태를 유지하며 성공한 Replace 뒤에만 current logical Clip Order를 기준으로 Representative Source를 다시 평가한다.

Representative Thumbnail은 가능한 범위에서 current effective edited appearance와 일치해야 하므로 Project Orientation, Framing, Transform, Direct-recorded Front Mirror Semantics 또는 SDR Interpretation이 바뀌면 기존 Derived Representation을 최신 결과로 영구 사용하지 않는다.

Thumbnail의 정확한 frame timestamp, Placeholder Visual, Image Format / Dimensions와 Cache Policy는 아직 확정하지 않는다.

프로젝트 전체 삭제에는 Confirmation이 필요하다.

앱 삭제 또는 기기 교체 이후의 복구는 MVP에서 보장하지 않으며 iCloud 동기화와 복구는 향후 검토 대상으로 유지한다.

#### Clip Management

촬영하거나 가져온 클립을 확인할 수 있다.

Committed Clip Metadata가 존재하더라도 참조 Media가 Missing, Unreadable, Corrupt, Validation 실패 또는 Expected Media Reference와 불일치할 수 있다.

이 경우 Project는 계속 열 수 있고 문제가 있는 Clip은 기존 Timeline 위치를 유지하는 사용자에게 보이는 Unavailable 상태로 남는다.

Mellow는 Unavailable Clip을 자동 삭제하거나 숨기거나 다른 Media로 자동 대체하지 않으며 Full Preview 또는 Export에서 조용히 건너뛰지 않는다.

다른 Healthy Clip은 개별 Preview, Trim, Reorder와 새 Clip 추가를 계속 사용할 수 있다.

사용자는 Unavailable Clip을 Replace 또는 Delete할 수 있다.

Replace는 기존 Logical Timeline Position을 유지하는 사용자 주도 동작이며 성공하기 전까지 Unavailable Placeholder를 유지한다.

Replace가 취소, Validation 실패, Storage 부족, Import 또는 Recording 실패, App Interruption으로 완료되지 않아도 Placeholder, Project와 다른 Clip은 유지한다.

Photos Video Import를 Replacement Source로 선택해도 Photos 원본은 수정하거나 삭제하지 않는다.

성공한 Replace는 해당 Slot을 원래 Timeline 위치에서 복구하고 Unrelated Clip의 순서를 변경하지 않는다.

Replacement Media와 기존 Trim, Framing, Transform 또는 Thumbnail Metadata의 Preserve / Reset 정책은 Replacement 구현 전에 별도 Technical / UX Gate에서 결정한다.

필요하지 않은 개별 Clip을 삭제하면 즉시 UI에서 제거하고 짧은 Undo Opportunity를 제공한다.

**ADR-038 (2026-09-16):** Editor는 우상단 상시 Undo / Redo로 이번 Session의 편집(Reorder, Delete, 이후 편집)을 시간 역순으로 되돌리고 다시 적용한다. (Superseded) MVP에서 사용자에게 노출되는 Undo는 가장 최근 Clip Delete Action 한 건이며 새로운 Clip을 삭제하면 이전 삭제의 Undo Opportunity는 종료된다.

Undo는 삭제했던 동일한 Clip과 기존 영상을 복원하며 같은 Clip을 중복 생성하지 않는다.

Undo Window 중 App Process가 종료되면 Undo Opportunity를 다음 실행까지 유지하지 않으며 재실행 시 해당 삭제는 확정된 것으로 취급하여 Clip을 다시 표시하지 않는다.

Undo 전에 다른 Clip의 순서를 변경했더라도 그 순서 변경을 되돌리지 않는다.

삭제한 Clip은 현재 Project 상태와 다른 Clip의 상대 순서를 존중하면서 삭제 당시 위치에 최대한 가깝게 일관된 기준으로 복원한다.

Undo / Redo 표현은 ADR-038(Editor 우상단 상시 Undo / Redo, Undo Window 없음)로 확정되었으며 세부 Animation / Haptic만 Tuning으로 남는다.

클립의 순서를 변경할 수 있다.

전체 Vlog Duration과 Clip Count에는 임의의 고정 Maximum을 두지 않는다.

Large Project는 실제 저장 공간, 성능 및 오류 처리로 관리하며 Storage 부족을 해결하기 위해 새로운 Duration 또는 Clip Count 제한을 추가하지 않는다.

Export의 Storage Requirement는 현재 Export Snapshot과 Project Duration을 기준으로 판단하며 공간이 충분하면 진행하고 부족하면 해당 Export만 차단한다.

Mellow는 Recording, Photos Import / Normalization과 Export 각각에 Operation-aware Storage Preflight를 적용한다.

각 Operation의 Required Free Space는 Operation Lifetime 동안 추가로 동시에 필요할 수 있는 Staging, Intermediate, Final 및 Recovery Media를 고려한 Estimated Peak Additional Storage와 Safety Reserve의 합으로 판단한다.

하나의 고정 Global Free-space Threshold를 모든 Media Operation의 기본 판단 기준으로 사용하지 않으며 Storage가 부족하면 기본적으로 해당 Operation만 시작하지 않는다.

Storage 부족을 앱 전체의 Fatal State로 취급하거나 다른 사용 가능한 기능을 자동으로 차단하지 않는다.

Storage 부족을 이유로 1080p / 30 fps, Audio, 최대 5초 Recording 또는 승인된 Import / Export 품질을 자동으로 낮추지 않는다.

Committed Clip, Draft, Project-owned Valid Media, Recovery Candidate, Undo Candidate, Active Usage Media 또는 다른 Project Media를 공간 확보 목적으로 자동 삭제하지 않는다.

Preflight를 통과해도 Runtime Disk Full 또는 Write Failure가 발생할 수 있으며 실패하거나 불완전한 결과를 성공으로 표시하거나 정상 Clip / Export로 Commit하지 않는다.

정확한 Safety Reserve, Operation별 Estimate Formula와 Warning 기준은 관련 Pipeline Profile과 iPhone 12 측정을 바탕으로 각 구현 Phase 전에 결정한다.

#### Trim

각 클립의 시작점과 끝점을 간단하게 조정할 수 있다.

Trim은 정밀한 전문 편집보다
빠르고 이해하기 쉬운 인터랙션을 우선한다.

#### Project Preview

Individual Clip Preview는 해당 Clip의 effective Trim, Project Orientation, current Framing / Scale / Position, applicable Transform, Direct-recorded Front Camera의 Mirrored Appearance, SDR 해석 및 존재하는 Audio를 반영한 effective edited result를 재생한다.

Individual Clip Preview는 Raw Source 또는 Raw Working Media를 Editing State 없이 직접 재생하는 기본 기능이 아니며 별도 `View Original` 기능은 MVP에 포함하지 않는다.

Audio Track이 없는 Photos Import Clip은 유효한 Silent Clip으로 취급하며 존재하는 Clip Audio는 Individual Clip Preview에 포함한다.

0 Clip Project에는 Individual Clip Preview 대상이 없으며 Full Vlog Preview와 Export도 제공하지 않는다.

Full Vlog Preview는 현재 Project의 Clip Order, effective Trim, Framing / Scale / Position, applicable Transform, Project Orientation, Mirroring Semantics, SDR 해석 및 Clip Audio Presence를 반영한 effective edited result를 현재 순서대로 재생한다.

Preview와 Export는 동일한 Project Editing Semantics를 사용하여 Clip Order, Trim, Framing / Scale / Position, Transform, Project Orientation, Front Camera Mirrored Appearance, SDR 해석 및 Audio Inclusion의 의미를 일치시킨다.

Preview와 Export가 서로 독립적인 Editing Rule을 다시 구현하지 않으며 Preview에서 본 의도적 Composition 의미는 동일한 Project State의 Export 결과와 가능한 한 일치해야 한다.

MVP의 Full Vlog Preview와 Export는 현재 Clip 순서를 직접 이어서 사용하며 Clip Boundary에 자동 Fade, Dissolve, Crossfade, Audio Fade 또는 Audio Crossfade를 삽입하지 않는다.

Full Vlog Preview는 하나 이상의 Usable Committed Clip, Unresolved Unavailable Clip 부재와 Valid Composition Source가 있을 때만 사용할 수 있다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project에서는 Full Vlog Preview를 제공하지 않으며 Healthy Clip의 Individual Clip Preview는 계속 가능하다.

Unavailable Clip 자체의 Video Preview는 제공하지 않고 기존 Replace 또는 Delete Flow를 사용한다.

MVP Preview는 SDR을 기준으로 하며 HDR / Dolby Vision Source에서 시작한 Clip도 SDR로 재생한다.

Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경으로 Composition 결과가 달라지면 이전 Preview Composition은 Stale로 간주하고 다음 유효 Preview는 최신 Project State를 사용한다.

Preview를 위해 매번 Full Vlog를 완성 Video File로 사전 Render하지 않으며 Preview용 Temporary 또는 Cached Derived Data가 필요할 경우에도 Committed Project Media로 취급하지 않는다.

#### Export

프로젝트의 모든 클립을 하나의 영상으로 결합하여 iPhone Photos에 저장할 수 있다.

Export는 하나 이상의 Usable Committed Clip, Unresolved Unavailable Clip 부재와 Valid Composition Source가 있을 때만 시작할 수 있다.

0 Clip Project 또는 Unresolved Unavailable Clip이 있는 Project는 Export할 수 없으며 손상된 Clip을 자동으로 생략한 결과를 생성하지 않는다.

MVP 표준 Output은 1080p / 30 fps / SDR이며 HDR Export는 MVP에서 제공하지 않는다.

- Portrait 9:16: 1080 × 1920
- Landscape 16:9: 1920 × 1080

Export Rendering은 현재 Project 상태의 Video를 생성하고 Output Validation을 통과한 Local Export Artifact를 만든 시점에 성공한다.

Photos Save는 성공한 Export Rendering 이후의 별도 동작이며 Photos Save의 성공은 Export Rendering Success의 조건이 아니다.

성공한 Local Export Artifact는 Photos Save, Photos Save Retry와 iOS Share Sheet에 같은 결과 파일로 재사용한다.

Photos Save가 실패해도 Export Rendering은 성공 상태로 유지하고 Local Export Artifact, Draft, Save Retry와 Share 가능 상태를 유지하며 사용자가 같은 Project를 다시 Export하도록 강제하지 않는다.

Share Cancel은 Export Failure가 아니며 Local Export Artifact와 Draft를 유지하고 Photos Save 또는 Share 재시도를 가능하게 한다.

Photos Save가 성공하면 `Saved to Photos` 상태를 표시할 수 있고 Share와 Done을 제공할 수 있다.

Photos Save에 성공하지 않은 Local Export Artifact를 Done 또는 결과 Flow 종료 시 자동으로 버리지 않으며 사용자가 명시적으로 Discard를 확인해야 한다.

Done 이후 Local Export Artifact Cleanup은 Active Consumer와 Retry 또는 Recovery Requirement가 없을 때만 가능하다.

Project Delete나 Mellow Local Cleanup은 이미 Photos에 저장된 외부 결과를 삭제하지 않는다.

Export는 Draft를 삭제하거나 작업을 강제로 종료하는 동작이 아니다.

Export Codec, Container, Bitrate, Audio Codec / Bitrate, 정확한 SDR Color Profile / Tagging, Background Export, Photos Save 시스템 실패 원인별 UX, 재Export가 필요한 경우의 Retry 세부 정책과 Export / Share 화면의 정확한 UI는 아직 확정하지 않는다.

원본 영상은 보존한다.

---

## 11. MVP UX Principle

MVP에서 중요한 것은 기능의 양이 아니라
전체 촬영 경험의 완성도다.

사용자가 처음 Mellow를 실행했을 때
별도의 설명이나 튜토리얼 없이도

**만들기 → 찍기 → 정리하기 → 저장하기**

라는 흐름을 이해할 수 있어야 한다.

전문적인 영상 편집 용어를 가능한 한 피한다.

사용자는 영상 편집자가 아니라
자신의 순간을 기록하는 사람으로 취급한다.

---

## 12. Out of Scope for Initial MVP

다음 기능은 Mellow의 초기 Vertical Slice에 포함하지 않는다.

### Photo

- 사진 촬영
- 사진 편집
- 사진 필터
- 사진 Export

Mellow는 초기 제품에서 사진 앱을 목표로 하지 않는다.

### Long Photos Video Segment Import

- 5초를 초과하는 Photos 영상의 Import
- 긴 원본 영상에서 최대 5초 구간을 골라 가져오는 Segment Selection
- 원본 영상 Reference 유지와 원본 전체 범위 Re-trim

ADR-042에 따라 Mellow는 전체 길이가 5초 이하인 Photos 영상만 받아들인다.

### Video Filters

초기 MVP에서는 색감 필터 기능을 제공하지 않는다.

영상 촬영과 간단 편집 경험이 안정적으로 완성된 이후
제품 방향과 기술 비용을 검토하여 결정한다.

### Advanced Color Editing

초기 MVP에서는 다음과 같은 기능을 제공하지 않는다.

- Exposure
- Contrast
- Saturation
- Curves
- LUT
- Professional color grading

### Advanced Video Editing

초기 MVP에서는 다음과 같은 전문 편집 기능을 목표로 하지 않는다.

- Multi-track timeline
- Layer editing
- Keyframes
- Masks
- Green screen
- Advanced transitions
- Motion graphics
- Complex speed curves

### Additional MVP Exclusions

- Project Rename
- Clip Split
- Clip Duplicate
- Fit Layout
- Background Blur
- 720p Export
- 4K Export
- 60 fps Export

### Advanced Camera Controls

Tap to Focus, Exposure Control, Front Camera Zoom, 0.5× Ultra Wide / Telephoto 선택, Lens Selector와 Torch는 Post-MVP 검토 대상으로 두며 MVP에 포함하지 않는다.

Rear Camera의 1× 이상 Continuous Zoom은 MVP에 포함하며 Phase 7의 Editing Framing과 별개의 Capture-time Camera Behavior로 취급한다.

도입 시점과 세부 동작은 아직 확정하지 않는다.

### Social Network

초기 Mellow 자체에는

- Feed
- Follow
- Like
- Comment
- Creator community

등의 소셜 네트워크 기능을 제공하지 않는다.

### Cloud-first Architecture

MVP의 핵심 미디어 작업은 Local-first로 동작하며 계정이나 서버 연결을 요구하지 않는다.

---

## 13. Future Product Areas

MVP 이후 Mellow의 핵심 경험을 해치지 않는 범위에서
추가 기능을 검토할 수 있다.

### Advanced Text

ADR-030의 가벼운 Clip Text / 명시적인 `T` Tool은 MVP이며 그 이상의 Text 확장만 Future 검토 대상이다.

### Music

사용자의 미니 브이로그에
간단하게 배경 음악을 추가하는 기능.

### Transitions

클립과 클립 사이에
Mellow 스타일의 단순한 전환 효과를 적용하는 기능.

### Video Look

복잡한 영상 보정보다
Mellow만의 일관된 영상 분위기를 제공하는 방식의 색감 기능.

### Mini Vlog Templates

편집을 자동화하거나 단순화할 수 있는
Mellow 스타일의 브이로그 구성 방식.

이 기능들은 현재 확정된 MVP 요구사항이 아니며
필요성과 제품 적합성을 검토한 후 결정한다.

---

## 14. Design Direction

Mellow의 디자인에서는
사용자의 영상이 항상 가장 중요한 시각 요소여야 한다.

앱 자체가 콘텐츠보다 더 눈에 띄어서는 안 된다.

Mellow의 전체적인 분위기는 다음 방향을 따른다.

- Calm
- Warm
- Minimal
- Soft
- Cozy
- Film-inspired
- Content-first
- Unobtrusive

강한 장식,
복잡한 버튼 구조,
불필요하게 많은 정보,
과도한 컬러 사용을 피한다.

UI는 촬영 중 사용자의 집중을 방해하지 않아야 한다.

구체적인

- Color
- Typography
- Spacing
- Components
- Iconography
- Motion
- Camera UI

규칙은 `DESIGN.md`에서 정의한다.

---

## 15. Product Differentiation

Mellow는 기능의 개수로
대형 영상 편집 앱과 경쟁하지 않는다.

차별점은 사용 경험에 있다.

### Mini Vlog First

일반적인 영상 편집 기능을 축소한 앱이 아니라
처음부터 짧은 일상 브이로그를 만들기 위해 설계한다.

### Recording-oriented

기존 영상을 편집하는 경험보다
순간을 바로 촬영하고 이어나가는 경험을 중요하게 생각한다.

### Low Editing Burden

사용자가 많은 편집 결정을 내리지 않아도
자연스러운 결과물을 만들 수 있어야 한다.

### Short Workflow

프로젝트를 시작하고
촬영하고
간단하게 정리하고
저장하는 과정이 짧아야 한다.

### Consistent Experience

Camera,
Clip management,
Editor,
Preview,
Export가

각각 다른 도구처럼 느껴지지 않고
하나의 연결된 흐름으로 느껴져야 한다.

---

## 16. Product Quality Bar

Mellow에서는
기능이 단순히 실행된다는 이유만으로
완성된 기능으로 판단하지 않는다.

### Recording Reliability

촬영 중 예기치 않은 오류로
사용자의 영상이 손실되어서는 안 된다.

### Playback Reliability

촬영된 클립과 프로젝트 Preview가
정상적으로 재생되어야 한다.

### Export Reliability

사용자가 만든 프로젝트를
일관된 결과물로 Export할 수 있어야 한다.

### Performance

촬영,
Clip 탐색,
Trim,
Preview 과정에서

불필요한 UI 지연이나 끊김이 없어야 한다.

### Orientation Correctness

9:16 프로젝트는
항상 올바른 9:16 결과물로 생성되어야 한다.

16:9 프로젝트 역시
항상 올바른 16:9 결과물로 생성되어야 한다.

### Original Preservation

사용자의 원본 영상 파일을
편집 과정에서 손상시키지 않는다.

### Error Handling

다음과 같은 상황을 정상적으로 처리해야 한다.

- Camera permission denied
- Microphone permission denied
- Photos permission denied
- Insufficient storage
- Recording failure
- Export failure
- Interrupted recording

오류가 발생했을 때
사용자가 다음 행동을 이해할 수 있어야 한다.

---

## 17. Product Development Strategy

Mellow는 Vertical Slice 방식으로 개발한다.

여러 기능을 동시에 부분적으로 구현하지 않는다.

하나의 사용자 흐름을
실제 iPhone에서 완전히 사용할 수 있는 상태까지 만든 후
다음 기능으로 확장한다.

### First Vertical Slice

**App Launch / Orientation Selection (New Vlog)**

→

**Record Clip**

→

**Record Additional Clips**

→

**Import Photos Video (entire source ≤ 5 seconds)**

→

**Reorder**

→

**Trim**

→

**Preview**

→

**Export**

첫 번째 Vertical Slice가 안정적으로 완성되기 전에는
고급 편집 기능을 우선하지 않는다.

---

## 18. Platform Strategy

### Initial Platform

Mellow V1은 **iPhone-only native application**으로 개발한다.

Swift와 SwiftUI를 사용하며 Minimum iOS는 iOS 18.0이다.

공식 Device Quality Baseline은 iPhone 12 and later이고 Primary Physical Test Device는 iPhone 12다.

`iPhone 12 and later`는 개발 및 QA 기준이며 App Store에서 이전 iPhone의 설치를 인위적으로 제한하는 조건이 아니다.

Mellow V1의 제품 UX, Navigation, Editing Interaction, Layout과 QA 기준은 iPhone을 대상으로 정의한다.

### iPad

Mellow V1은 **Native iPad를 지원하지 않는다.**

V1에서는 다음을 제공하지 않는다.

- iPad-specific Layout
- iPad-specific Navigation 또는 Editing UX
- iPad Multitasking Adaptation
- iPad-specific Asset
- iPad App Store Screenshot / Presentation

Native iPad 지원은 향후 명시적인 Product / Architecture Decision으로 별도 승인되기 전까지 도입하지 않는다.

Apple 플랫폼이 iPhone-only Build를 iPad에서 Compatibility Mode 등으로 실행하도록 허용하더라도 이는 Mellow가 지원하는 Native iPad 기능이나 제품 범위로 간주하지 않는다.

### Android

초기 범위에 포함하지 않는다.

iPhone 버전이 제품적으로 검증된 이후
Android 지원 여부를 별도로 결정한다.

미래의 Android 지원 가능성을 이유로
초기 iPhone 아키텍처를 불필요하게 복잡하게 만들지 않는다.

---

## 19. Monetization

Mellow의 수익화 방식은 아직 확정하지 않는다.

초기 제품에서는
핵심 사용 경험과 제품 적합성을 먼저 검증한다.

향후 다음과 같은 방식을 검토할 수 있다.

- Free core experience
- Premium features
- One-time purchase
- Subscription

구체적인 유료 기능,
가격,
무료 사용 범위는

제품 기능과 경쟁 앱 분석이 완료된 이후 결정한다.

**Status: TBD**

---

## 20. Success Criteria

Mellow MVP의 성공을
다운로드 수만으로 판단하지 않는다.

### Functional Success

사용자가 실제 iPhone에서

**프로젝트 생성 → 여러 클립 촬영 → 정리 → Preview → Export**

과정을 정상적으로 완료할 수 있다.

### Usability Success

영상 편집 경험이 없는 사용자도
별도의 설명 없이 핵심 사용 방법을 이해할 수 있다.

### Reliability Success

촬영 및 Export 과정에서
영상 손실이나 반복적인 Crash가 발생하지 않는다.

### Experience Success

일반적인 영상 편집 앱보다
브이로그 한 편을 만드는 과정이 단순하고 부담 없이 느껴진다.

### Identity Success

사용자가 Mellow를

**“영상 편집 앱”**

보다는

**“짧은 일상을 기록하는 앱”**

으로 인식할 수 있어야 한다.

---

## 21. Future Vision

Mellow는 장기적으로

**일상의 작은 순간들을 가장 자연스럽게 영상으로 기록하는 카메라**

가 되는 것을 목표로 한다.

사용자는 하루 동안 몇 번씩 Mellow를 열어
몇 초의 순간들을 기록할 수 있다.

그리고 하루가 끝났을 때
그 작은 순간들이 자연스럽게 하나의 미니 브이로그가 된다.

향후 Mellow가

- Music
- Advanced Text
- Transitions
- Video looks
- Templates
- Automated editing

등으로 확장되더라도

제품의 중심은 항상

**촬영과 기록**

이어야 한다.

새로운 기능을 추가할 때는 다음 질문을 기준으로 판단한다.

> Does this make capturing and remembering a moment simpler?

이 질문에 명확히 답할 수 없는 기능은
Mellow의 핵심 제품에 추가하지 않는 것을 기본 원칙으로 한다.

---

## 22. Confirmed Product Decisions

현재 확정된 제품 방향은 다음과 같다.

- Product name: Mellow
- Mellow는 Mini Vlog 앱이다.
- V1 지원 플랫폼은 iPhone이며 Mellow V1은 iPhone-only native application으로 개발한다.
- Native iPad 지원은 V1 범위에서 명시적으로 제외하며 별도 Product / Architecture Decision 없이 도입하지 않는다.
- iPad-specific Layout / Navigation / Editing UX / Multitasking Adaptation / Asset / App Store Presentation을 V1에 추가하지 않는다.
- Apple 플랫폼의 iPhone Compatibility Mode 실행 가능성은 Mellow의 Native iPad 지원으로 간주하지 않는다.
- Swift와 SwiftUI를 사용하며 Minimum iOS는 iOS 18.0이다.
- 공식 Device Quality Baseline은 iPhone 12 and later이며 Primary Physical Test Device는 iPhone 12다.
- iPhone 12 기준은 공식 개발 및 QA 기준이며 App Store 설치 제한 조건이 아니다.
- 사진 촬영 및 사진 편집 기능은 제품 범위에서 제외한다.
- 핵심 콘텐츠는 Video다.
- Mellow 내부에서 짧은 영상 Clip을 여러 개 촬영할 수 있다.
- 직접 촬영 Clip은 자유롭게 촬영하며 최대 5초다.
- 사용자는 선택한 최대 Duration 전에 수동 Stop할 수 있고 선택한 최대 Duration에 도달하면 자동 Stop한다.
- Camera는 `1s / 2s / 3s / 4s / 5s` 최대 Recording Duration을 제공하고 기본 선택은 `3s`다.
- 선택은 Camera / Capture-level 설정으로 Clip 사이에 변경할 수 있으며 Project-level 불변 속성이 아니다.
- Recording Pause / Resume는 MVP에서 제공하지 않는다.
- Front / Rear Camera를 지원하며 Camera Switching은 idle 상태에서만 가능하고 Recording 중에는 금지한다.
- Rear Camera의 기본 Capture Device는 1× Wide이며 1× 이상 Continuous Zoom을 Preview와 Recording 중 지원한다.
- Rear Zoom은 Recording을 Stop / Restart하거나 Clip을 분리하거나 선택한 최대 Duration Timer를 Reset하지 않으며 승인된 1.0×–2.0× Pinch와 Gesture 중 Transient Indicator만 제공한다.
- 0.5× Ultra Wide, Telephoto와 Lens Selector는 MVP에서 제공하지 않고 Front Camera Zoom도 MVP에서 제공하지 않는다.
- Front Camera Preview와 Mellow에서 직접 촬영한 Front Clip의 Preview / Editing / Export는 동일한 Mirrored Appearance를 유지하며 Mirror Toggle은 제공하지 않는다.
- Direct Recording에는 Camera와 Photos Add Permission이 필요하고 Microphone은 선택이며 거부 시 무음 Recording을 허용한다(ADR-033). Photos Import는 독립적으로 사용할 수 있고 Audio Track이 없는 Source도 허용한다.
- Recording은 Project를 만들지 않고 Camera Clip은 Photos에 저장되며, Direct Capture 최소 길이는 1.0초다(ADR-033).
- Recording Start에는 Project Orientation과 일치하는 Device Posture가 필요하며 Landscape Left / Right는 모두 Landscape Project에 유효하고 Face Up / Down / Unknown / Unstable 상태는 유효하지 않다.
- Mid-record Device Rotation은 현재 Recording을 자동 Stop / Restart하거나 Project Orientation / Clip Aspect Ratio를 변경하지 않고 Rear Zoom을 회전만으로 Reset하지 않으며 다음 Recording 전에 Orientation을 다시 확인한다.
- Recording Interruption은 Successful Manual / Auto-stop으로 표시하지 않고 Media Safety 계약을 따르며 Valid Partial Clip의 최종 처리(1.0초 이상 + Finalization 성공 시 저장, 미만 폐기)와 Direct Capture Minimum Valid Clip Duration(1.0초)은 ADR-033으로 확정되었다.
- Photos Video Import는 MVP 필수 기능이다.
- Photos Source는 전체 길이가 `1.0s <= duration <= 5.0s`(양 끝 포함)일 때만 가져오며 1.0초 미만 / 5.0초 초과 Source는 거부하고 Segment Selection은 제공하지 않는다(ADR-042).
- SDR, HDR / Dolby Vision, 4K / High-resolution 및 30 fps 초과 Source Import를 허용하며 Photos 원본은 수정하거나 삭제하지 않는다.
- 5초 이하 전체 Source의 Project-owned Working Media는 1080p-class / 30 fps / SDR을 기준으로 한다.
- Project Fill + Crop을 Working Media에 미리 적용하여 저장하지 않으며 이후 사용자 Framing에 필요한 Source의 유효 화면 영역을 보존한다.
- Trim / Fill + Crop / Framing은 가능한 한 Metadata 기반 비파괴 편집으로 유지한다.
- 프로젝트는 Portrait 9:16과 Landscape 16:9를 모두 지원한다.
- 화면 비율은 프로젝트를 생성할 때 선택한다.
- 하나의 프로젝트에서는 하나의 화면 비율을 유지한다.
- 촬영 중 기기의 회전만으로 프로젝트 화면 비율을 자동 변경하지 않는다.
- Imported Video의 Aspect mismatch 기본 정책은 Fill + Crop이며 사용자가 Framing 위치를 조정할 수 있어야 한다(ADR-043 Revision 1: 세로 Presentation 영상의 비율 불일치에 한하며 가로 / 정사각형 영상은 V1 Photos Import에서 제외된다).
- Fit과 Background Blur는 MVP에서 제공하지 않는다.
- MVP의 핵심 편집 기능은 Clip 관리, 순서 변경, Trim이다.
- 개별 Clip 삭제는 즉시 UI에 반영하고 짧은 Undo Opportunity를 제공하며 프로젝트 전체 삭제에는 Confirmation이 필요하다.
- 사용자에게 노출되는 Undo / Redo는 Editor Session 편집 History(ADR-038)이며 Process 종료 후에는 유지하지 않는다.
- Undo는 삭제했던 동일한 Clip과 기존 영상을 복원하며 Clip을 중복 생성하지 않는다.
- Undo Window 중 App Process가 종료되면 다음 실행에서 Undo를 제공하지 않고 해당 Clip 삭제를 확정된 상태로 유지한다.
- 재정렬 후 Undo는 다른 Clip의 순서 변경을 보존하며 현재 Project 상태를 존중하여 삭제 당시 위치에 최대한 가깝게 결정적으로 복원한다.
- 전체 Vlog Duration과 Clip Count에는 임의의 고정 Maximum을 두지 않는다.
- Recording, Photos Import / Normalization과 Export는 각각 Estimated Peak Additional Storage와 Safety Reserve를 사용하는 Operation-aware Storage Preflight를 수행한다.
- Storage 부족은 기본적으로 해당 Operation만 차단하며 앱 전체를 Low-storage Fatal State로 만들거나 다른 사용 가능한 기능을 자동 차단하지 않는다.
- Storage 부족을 이유로 승인된 1080p / 30 fps, Audio, Recording Duration, Import Working Media 또는 Export 품질을 자동 하향하지 않는다.
- Storage Pressure로 Draft, Committed Media, Recovery / Undo Candidate, Active Usage Media 또는 다른 Project Media를 자동 삭제하지 않는다.
- Runtime Disk Full 또는 Write Failure의 Partial / Incomplete Output을 정상 결과로 Commit하지 않고 기존 Committed Media와 Photos 원본을 보호한다.
- Domain은 Multiple Drafts를 표현하지만 V1 Product는 편집 가능한 저장 Project를 하나만 유지하며(ADR-033) 자동 저장하고 사용자가 대체 / 삭제하기 전까지 자동 만료하지 않는다.
- 로컬 Draft는 앱 재실행과 기기 재부팅 이후에도 유지한다.
- Clip이 0개인 Project는 정상적인 Draft이며 Recent에 표시되고 다시 열 수 있고 자동으로 삭제하지 않는다.
- 0 Clip Project는 Recording과 Photos Video Import를 허용하지만 Full Vlog Preview와 Export는 비활성화한다.
- 일부 Clip Media가 Unavailable이어도 Project와 Healthy Clip을 보호하며 해당 Clip을 기존 Timeline 위치에 남기고 사용자가 Replace 또는 Delete할 수 있게 한다.
- Unresolved Unavailable Clip은 Full Vlog Preview와 Export를 차단하며 Mellow는 해당 Clip을 자동 삭제, 자동 대체 또는 조용히 생략하지 않는다.
- All-unavailable Project도 Draft로 유지하며 새 Direct Recording, Photos Video Import, Replace와 Delete를 허용한다.
- 프로젝트 이름 입력 Prompt 없이 생성 날짜와 시간 기반 자동 표시 이름을 사용하며 Rename은 MVP에서 제공하지 않는다.
- V1 Projects Entry는 `Select Clips` / `Load Last Saved`이며 Multi-project `Recent Projects` Browser는 Post-V1 복원 결정으로 남긴다(ADR-033). 내부 Domain에서는 `Draft` 용어를 사용할 수 있다.
- Recent Project Representative Thumbnail은 current logical Clip Order의 첫 번째 Healthy / Usable Clip을 Source로 사용하고 Unavailable Clip을 건너뛰며 0 Clip 또는 All-unavailable Project에는 unrelated Media가 아닌 Placeholder를 사용한다.
- Representative Thumbnail은 Derived / Cache Data이므로 Thumbnail Missing, Corruption, Generation Failure 또는 Cache Cleanup이 Project / Clip Corruption, Delete 또는 사용 차단을 의미하지 않는다.
- Clip Add, Delete, Undo Restore, Replace 성공, Reorder, Availability Change, Project Reload 또는 Reconciliation 뒤에는 Representative Source를 다시 평가하고 Editing Appearance가 바뀌면 이전 Thumbnail을 영구 current Representative로 사용하지 않는다.
- Individual Clip Preview는 Raw Source가 아닌 현재 effective Trim, Framing / Scale / Position, Transform, Project Orientation, Front Mirroring, SDR 및 Audio를 반영한 effective edited result를 제공한다.
- Full Vlog Preview는 현재 Clip Order와 같은 effective Editing Semantics를 사용하며 MVP에서 자동 Video / Audio Transition을 삽입하지 않는다.
- Preview와 Export는 Clip Order, Trim, Framing / Scale / Position, Transform, Project Orientation, Front Mirrored Appearance, SDR 해석 및 Audio Inclusion을 같은 의미로 적용한다.
- Healthy Clip의 Individual Preview는 다른 Clip의 Unavailable 상태와 무관하게 가능하지만 Unavailable Clip 자체의 Video Preview는 제공하지 않는다.
- Composition에 영향을 주는 Clip Add, Delete, Replace, Reorder, Trim, Framing, Transform 또는 Media Availability 변경 뒤에는 다음 유효 Preview가 최신 Project State를 사용한다.
- MVP Preview는 SDR이며 Export는 1080p / 30 fps / SDR을 기준으로 하고 Portrait Output은 1080 × 1920, Landscape Output은 1920 × 1080이다.
- Preview와 Export의 Framing, Transform 및 SDR 색 해석은 가능한 한 일치해야 하며 HDR Export는 MVP에서 제공하지 않는다.
- 720p Export, 4K Export와 60 fps Export는 MVP에서 제공하지 않는다.
- Export Rendering Success와 Photos Save Success를 분리하며 Validation을 통과한 동일 Local Export Artifact를 Save, Save Retry와 Share에 재사용한다.
- Photos Save Failure는 Export Rendering Failure가 아니며 Local Export Artifact와 Draft를 유지하고 Save Retry와 Share를 제공한다.
- Share Cancel은 Export Failure가 아니며 Local Export Artifact와 Draft를 유지한다.
- Photos Save 성공 후 Share와 Done을 제공할 수 있고 Done 이후 Local Export Artifact Cleanup은 Active Consumer와 Retry 또는 Recovery Requirement가 없을 때만 가능하다.
- Photos Save에 성공하지 않은 Local Export Artifact는 Done 또는 결과 Flow 종료로 자동 삭제하지 않으며 사용자의 명시적 Discard가 필요하다.
- Project Delete와 Mellow Local Cleanup은 Photos에 저장된 외부 Export 결과를 삭제하지 않는다.
- Export 후에도 Draft를 유지하여 수정과 재Export를 지원한다.
- 핵심 미디어 작업은 Local-first로 동작한다.
- 앱 삭제 및 기기 교체 이후 복구와 iCloud 동기화·복구는 MVP 보장에 포함하지 않는다.
- Clip Split과 Duplicate는 MVP에서 제공하지 않는다.
- Focus, Exposure, Front Zoom, Lens Selector, Ultra Wide / Telephoto 선택과 Torch 등 Advanced Camera Controls는 Post-MVP 검토 대상이며 Rear 1× 이상 Continuous Zoom은 MVP 기능이다.
- 초기 MVP에서는 사진 필터 및 사진 편집 기능을 구현하지 않는다.
- 초기 MVP에서는 전문 영상 편집 기능을 목표로 하지 않는다.
- 사용자의 원본 영상은 보존한다.
- Native iPad 지원과 Android는 V1 지원 범위에서 제외한다.

---

## 23. Open Decisions

다음 항목은 확정된 MVP 결정의 세부사항 또는 향후 검토 사항이며 아직 확정하지 않는다.

- 세로/가로 프로젝트 선택 UI
- 프로젝트 자동 표시 이름의 구체적인 날짜 및 시간 Format
- Draft 저장 실패 처리 및 자동 복구의 세부 정책
- Unavailable Clip의 정확한 Visual Design과 Replace UI Flow — Resolved by ADR-040 / DESIGN 19절 STEP 13
- Replacement가 동일 Clip Identity를 유지할지 여부와 Trim, Framing, Transform, Thumbnail Metadata의 Preserve / Reset 및 사용자 Reset 안내 정책
- Project Metadata Corruption의 정확한 Recovery Algorithm과 안전한 Failure State의 UI Copy
- Representative Thumbnail의 정확한 frame timestamp, Placeholder Visual, Image Format / Dimensions, Cache Directory와 Eviction / Retry Policy
- (Resolved by ADR-038: Undo Window 불필요, 상시 Undo / Redo Control) Delete / Undo의 Animation, Haptic 및 세부 시각 처리
- Media의 Physical Deletion과 Active Usage Tracking의 구체적인 구현 방식
- Individual Clip Preview와 Full Vlog Preview의 정확한 Playback Controls, Scrubber, Navigation, Entry / Exit Transition 및 Fullscreen Behavior
- Preview Composition Cache의 정확한 정책과 Optimization Strategy
- Rear Zoom Maximum Product Quality Limit — Resolved: 2.0×, Minimum 1.0×
- Rear Zoom Interaction / Indicator — Resolved: 1.0×–2.0× Pinch, Gesture 중 Transient Numeric Indicator 허용, Persistent Button / Slider 없음
- 정확한 Orientation Detection API / Threshold / Debounce
- Camera / Microphone Permission 안내의 정확한 화면 구성과 Copy
- Minimum Valid Clip Duration — Direct Capture는 Resolved by ADR-033(1.0초); Imported Photos Source는 Resolved by ADR-042(1.0초)
- Recording Interruption에서 Valid Partial Clip의 최종 보존 / Commit / 폐기 정책 — Resolved by ADR-033
- Recording Error / Interruption Haptic 정책
- Post-MVP Front Camera Zoom 및 Advanced Lens Control 도입 시점과 지원 범위
- Post-MVP Flash / Torch 도입 시점 및 세부 동작
- Post-MVP Tap to Focus 도입 시점 및 세부 동작
- Post-MVP Exposure Control 도입 시점 및 세부 동작
- Imported Clip의 Re-trim 범위 및 Source Reference 유지 여부 — Resolved by ADR-042: Project-owned Clip Media 범위 안에서만 Re-trim, Source Reference 없음
- Crop UI와 Pinch to Zoom 지원 여부
- Working Media Codec / Container 및 정확한 SDR Color Profile / Tagging
- HDR / Dolby Vision Source의 SDR 변환을 위한 Tone-mapping 구현 방법
- 저해상도 Source의 Upscaling 정책 및 1080p-class Working Media의 구체적인 크기 기준
- 정확한 Safety Reserve 크기와 Operation별 Storage Estimate Formula
- Recording Estimate의 Capture Codec / Bitrate 상수와 Finalization Overhead
- Import / Export의 Temporary 또는 Recovery-safe Overlap Multiplier
- Storage Warning 기준과 Low-storage 화면의 정확한 Layout / Copy / Presentation
- Audio on/off 설정 여부
- Clip별 음소거 기능
- MVP Clip Text의 Font / Position / Size / Duration / Animation 세부 정책 — Before Phase 7
- Post-MVP Music 기능 범위
- Post-MVP Transition 기능 범위
- 향후 Video color / look 기능 도입 여부
- Export Codec, Container, Bitrate 및 Audio Format
- 고정된 1080p / 30 fps 범위 내 Export Quality 선택 기능 제공 여부
- Export Rendering과 Photos Save의 구분을 전제로 한 Export 및 Share 화면의 세부 UX, 정확한 Confirmation Copy와 Retry Button Placement
- Background Export와 재Export가 필요한 경우의 Retry 세부 정책
- Photos Save 시스템 실패 원인별 UX와 Share Sheet 이후 외부 App 동작
- 향후 Account 도입 여부
- 향후 iCloud synchronization 및 기기 교체 후 복구 제공 여부
- 향후 Analytics 사용 여부
- Monetization 방식
- Free / Premium 기능 구분

이 항목들은 이후 사용자 승인과 관련 문서 업데이트를 통해 순차적으로 결정하며 이미 확정된 MVP 결정을 다시 Open으로 취급하지 않는다.
