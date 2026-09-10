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

**새 Vlog 생성**

↓

**9:16 또는 16:9 선택**

↓

**영상 Clip 촬영 또는 Photos에서 영상 가져오기**

↓

**추가 Clip 촬영 및 가져오기**

↓

**Clip 확인 및 정리**

↓

**Clip 순서 변경**

↓

**각 Clip의 사용할 구간 선택 및 Trim**

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

### Required

- 새로운 Vlog 프로젝트 생성
- Project orientation 선택
- Orientation 선택 후 촬영 또는 Clip 추가 흐름으로 진입
- 프로젝트 생성 날짜 및 시간 기록
- 프로젝트 마지막 수정 시각 기록

### Not Required

- 프로젝트 설명
- 프로젝트 태그
- 프로젝트 카테고리

---

## F-MVP-002 — Project Orientation

새로운 프로젝트를 만들 때 사용자는 프로젝트의 화면 비율을 선택한다.

MVP에서 지원하는 화면 비율은 다음 두 가지다.

- Portrait — 9:16
- Landscape — 16:9

선택한 화면 비율은 해당 프로젝트가 유지되는 동안 변경되지 않는다.

기기의 물리적인 회전만으로 프로젝트의 화면 비율이 자동 변경되지 않는다.

### Required Behavior

9:16 프로젝트는 세로 촬영, 세로 Preview, 세로 Export를 기준으로 동작한다.

16:9 프로젝트는 가로 촬영, 가로 Preview, 가로 Export를 기준으로 동작한다.

---

# 5. MVP — Project Drafts

## F-MVP-003 — Multiple Draft Projects

사용자는 여러 개의 미완성 Vlog 프로젝트를 동시에 보관할 수 있어야 한다.

하나의 프로젝트를 완료하지 않았다는 이유로 새로운 프로젝트 생성을 제한하지 않는다.

---

## F-MVP-004 — Automatic Draft Saving

사용자가 별도의 저장 버튼을 누르지 않아도 현재 프로젝트 상태를 자동으로 보존한다.

앱 재실행 또는 기기 재부팅 후에도 자동 저장된 로컬 Draft를 다시 열 수 있어야 한다.

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

Draft의 대표 이미지는 첫 번째 사용 가능한 Clip의 Thumbnail을 기본값으로 사용한다.

프로젝트에 아직 Clip이 없다면 기본 placeholder를 표시한다.

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

---

## F-MVP-013 — Front Camera

Mellow는 iPhone의 Front Camera를 이용한 영상 촬영을 지원한다.

사용자는 녹화하지 않는 idle 상태에서 Rear Camera와 Front Camera를 전환할 수 있어야 한다.

Front Camera와 Rear Camera의 동시 촬영은 MVP 범위에 포함하지 않는다.

---

## F-MVP-014 — Camera Switching

사용자는 녹화하지 않는 idle 상태에서 Rear Camera와 Front Camera를 전환할 수 있어야 한다.

Recording 중 Camera Switching은 허용하지 않는다.

---

# 7. MVP — Recording Duration

## F-MVP-015 — Maximum Clip Recording Duration

Mellow에서 직접 촬영하는 하나의 Clip은 최대 10초까지 녹화할 수 있다.

사용자는 10초 이전에는 원하는 시점에 자유롭게 녹화를 종료할 수 있다.

녹화 시간이 10초에 도달하면 Mellow가 자동으로 녹화를 종료한다.

### Required

- 녹화 시작 후 자유로운 수동 종료
- 최대 녹화 시간 10초
- 10초 도달 시 자동 종료
- 촬영 중 현재 녹화 시간 확인
- 자동 종료된 Clip의 정상 저장
- 자동 종료 이후 정상적인 다음 촬영 가능

### Excluded from MVP

- 1초, 3초, 5초 등의 고정 녹화 시간 Preset
- 10초를 초과하는 단일 Clip 촬영
- Recording pause
- Recording resume

---

## F-MVP-016 — Recording Progress Feedback

사용자는 현재 Clip의 녹화 진행 상태와 10초 제한을 자연스럽게 인지할 수 있어야 한다.

Recording Progress는 Record Button 주변의 Progress Ring을 중심으로 표현하며 큰 Countdown 숫자는 사용하지 않는다.

구체적인 Progress 표현과 10초 도달 전 피드백의 세부 동작은 `DESIGN.md`에서 결정한다.

---

# 8. MVP — Audio Recording

## F-MVP-017 — Record Audio

영상 촬영 시 기본적으로 Microphone Audio를 함께 녹음한다.

### Required

- Microphone permission 처리
- Video와 Audio 동기화
- Microphone permission 거부 상태 처리
- 녹화된 Audio를 Preview 및 Export에 유지

---

# 9. MVP — Import from Photos

## F-MVP-018 — Import Existing Video

사용자는 iPhone Photos Library의 기존 영상을 현재 Vlog 프로젝트에 추가할 수 있어야 한다.

Photos에서 가져오는 원본 영상 자체의 길이에는 제한을 두지 않는다.

4K를 포함한 고해상도 Source Video를 Import할 수 있다.

고해상도 Source Import 지원은 HDR/SDR 처리 정책의 확정을 의미하지 않는다.

---

## F-MVP-019 — Imported Video Duration Policy

가져온 원본 영상의 길이가 10초를 초과하더라도 Import 자체를 제한하지 않는다.

사용자는 원본 영상 안에서 최대 10초 길이의 원하는 구간을 선택하여 프로젝트에 추가한다.

### Required

- 원본 영상의 전체 길이와 관계없이 Import 가능
- 사용 구간의 시작점 선택
- 사용 구간의 종료점 선택
- 선택 가능한 최대 구간 길이 10초
- 10초보다 짧은 영상은 전체 길이 사용 가능
- 원본 영상의 비파괴적 처리

### Example

원본 영상 길이가 2분 14초라면 사용자는 `00:37.2 → 00:45.8` 구간을 선택하여 8.6초 Clip으로 프로젝트에 추가할 수 있다.

---

## F-MVP-020 — Normalize Clip Duration Rule

Mellow 프로젝트에서 사용하는 하나의 최종 Clip은 촬영 방식과 관계없이 최대 10초다.

직접 촬영한 Clip과 Photos에서 가져온 Clip은 이후 Clip 관리, Preview, Trim, Export 단계에서 가능한 한 동일한 구조로 취급한다.

---

## F-MVP-021 — Imported Media Safety

사용자가 Imported Clip 추가를 확정하면 프로젝트에서 사용할 Project-owned Local Media를 생성한다.

4K를 포함한 고해상도 Source는 선택된 최대 10초 Segment를 기준으로 1080p Working Media를 생성하는 방향을 사용한다.

정상적으로 Project-owned Media가 생성되어 추가된 Clip은 이후 Photos 원본이 삭제되어도 Draft에 유지되어야 한다.

Draft를 삭제할 때는 Mellow 내부 복사본만 삭제하며 Photos의 원본 영상에는 영향을 주지 않는다.

Photos 원본은 Import, 정규화 또는 편집 과정에서도 수정하거나 삭제하지 않는다.

미디어 저장은 `ARCHITECTURE.md`의 확정된 기준을 따르며 정규화·복구의 미결 세부 정책은 임의로 확정하지 않는다.

---

# 10. MVP — Orientation Handling for Imported Video

## F-MVP-022 — Imported Orientation Handling

Photos에서 가져오는 영상의 원본 화면 비율이 현재 프로젝트의 화면 비율과 다를 수 있다.

예를 들어 9:16 프로젝트에 16:9 영상을 가져올 수 있다.

이 경우 Mellow는 프로젝트 화면 비율에 맞게 해당 영상을 처리해야 한다.

### Required Behavior

- 기본 Layout은 Fill + Crop이다.
- 프로젝트 Canvas를 채우고 초과 영역을 Crop한다.
- 사용자가 Framing 위치를 조정할 수 있어야 한다.

Fit과 Background Blur는 MVP에서 제공하지 않는다.

세부 Crop UI와 Pinch to Zoom 지원 여부는 아직 확정하지 않는다.

---

# 11. MVP — Clip Management

## F-MVP-023 — Clip List

현재 Vlog 프로젝트에 포함된 모든 Clip을 사용자가 확인할 수 있어야 한다.

각 Clip을 시각적으로 구분할 수 있어야 한다.

### Candidate Information

- Thumbnail
- Duration
- Clip source
- 현재 순서

정확한 UI는 `DESIGN.md`에서 정의한다.

---

## F-MVP-024 — Add Additional Clips

사용자는 프로젝트를 생성한 이후에도 새로운 Clip을 계속 추가할 수 있어야 한다.

새로운 Clip은 Mellow Camera로 촬영하거나 Photos Library에서 Import할 수 있다.

---

## F-MVP-025 — Delete Clip

사용자는 필요하지 않은 Clip을 현재 Vlog 프로젝트에서 제거할 수 있어야 한다.

개별 Clip 삭제는 즉시 UI에 반영하고 Undo를 제공한다.

Undo Window와 연속 삭제, 재정렬, 앱 종료 시의 세부 동작은 아직 확정하지 않는다.

Clip 삭제는 Photos Library의 원본 영상에 영향을 주지 않는다.

---

## F-MVP-026 — Reorder Clips

사용자는 프로젝트에 포함된 Clip의 순서를 변경할 수 있어야 한다.

변경된 순서는 Preview와 Export 결과에 동일하게 반영되어야 한다.

---

# 12. MVP — Clip Trim

## F-MVP-027 — Trim Recorded Clip

사용자는 직접 촬영한 Clip의 시작점과 종료점을 조정할 수 있어야 한다.

Trim 작업은 원본 Clip을 직접 수정하지 않는 비파괴 방식으로 처리한다.

---

## F-MVP-028 — Trim Imported Clip

사용자는 Photos에서 가져온 영상에서 프로젝트에 사용할 최대 10초의 구간을 선택할 수 있어야 한다.

프로젝트에 추가한 이후에도 허용된 범위 내에서 선택 구간을 다시 조정할 수 있는 방향을 우선한다.

Re-trim을 Materialized Segment 내부로 제한할지 원본 Source 전체 범위까지 허용할지와 Source Reference 유지 여부는 아직 확정하지 않는다.

---

## F-MVP-029 — Simple Trim Experience

Mellow의 Trim은 전문 영상 편집 수준의 정밀한 Timeline을 목표로 하지 않는다.

Trim UX는 빠르고 이해하기 쉬운 조작을 가장 우선한다.

### Required

- 시작점 조절
- 종료점 조절
- 선택된 구간 Preview
- 현재 Clip 길이 확인
- 최대 10초 규칙 유지
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

구체적인 구현 방식은 `ARCHITECTURE.md`에서 정의한다.

---

# 14. MVP — Preview

## F-MVP-033 — Clip Preview

사용자는 개별 Clip을 재생하여 촬영 또는 Import 결과를 확인할 수 있어야 한다.

현재 Trim 범위가 존재한다면 해당 범위를 기준으로 Preview한다.

---

## F-MVP-034 — Full Vlog Preview

사용자는 현재 프로젝트 전체를 하나의 Vlog처럼 연속 재생하여 확인할 수 있어야 한다.

### Preview Must Reflect

- Clip order
- 각 Clip의 Trim
- Fill + Crop 및 사용자 Framing
- Project orientation
- Video
- Recorded audio

초기 MVP에서는 Clip 사이에 특별한 Transition 효과를 제공하지 않는다.

---

# 15. MVP — Export

## F-MVP-035 — Export Vlog

사용자는 현재 프로젝트를 하나의 완성된 영상 파일로 Export할 수 있어야 한다.

### Required

- 모든 Clip 결합
- Clip 순서 반영
- 각 Clip의 Trim 반영
- Fill + Crop 및 사용자 Framing 반영
- Project orientation 유지
- Audio 유지
- 안정적인 영상 파일 생성

### Confirmed Video Standard

MVP 표준 Working Media와 Output Profile은 1080p / 30 fps다.

- Portrait 9:16 Output: 1080 × 1920
- Landscape 16:9 Output: 1920 × 1080

Mellow Camera의 기본 Capture Profile도 1080p / 30 fps다.

720p Export, 4K Export와 60 fps Export는 MVP에서 제공하지 않으며 사용자에게 Export Resolution이나 Frame Rate 선택을 제공하지 않는다.

Codec, Container, HDR/SDR, Background Export와 Retry 세부 정책은 아직 확정하지 않는다.

Export 후에도 Draft를 유지하며 iOS Share Sheet로 완성된 Video를 공유할 수 있어야 한다.

---

## F-MVP-036 — Save to Photos

완성된 Vlog는 사용자의 iPhone Photos Library에 저장할 수 있어야 한다.

### Required

- 필요한 Photos permission 처리
- Export 진행 상태 표시
- Export 성공 피드백
- Export 실패 피드백
- 정상적인 영상 파일 저장

---

## F-MVP-037 — Preserve Original Media

Preview와 Export 과정은 사용자의 원본 영상 및 원본 Photos Asset을 파괴적으로 변경하지 않는다.

---

# 16. MVP — Permissions

## F-MVP-038 — Camera Permission

Mellow Camera를 처음 사용할 때 필요한 시점에 Camera permission을 요청한다.

권한이 거부된 경우 사용자가 문제와 해결 방법을 이해할 수 있는 상태를 제공한다.

---

## F-MVP-039 — Microphone Permission

Audio가 포함된 영상 촬영을 위해 필요한 시점에 Microphone permission을 요청한다.

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

---

## F-MVP-042 — Safe Clip Storage

촬영이 정상적으로 완료된 Clip은 즉시 안전한 로컬 저장소에 보존한다.

사용자가 아직 Vlog를 Export하지 않았다는 이유로 촬영한 Clip이 쉽게 유실되어서는 안 된다.

---

# 18. MVP — Basic App Areas

Mellow MVP는 최소한 다음 제품 영역을 가진다.

### Home

새 Vlog를 만들고 기존 Vlog 프로젝트를 다시 여는 공간이다.

기존 프로젝트 영역의 사용자-facing 명칭은 `Recent`를 사용한다.

내부 Domain에서는 `Draft`라는 기술 용어를 사용할 수 있다.

### Orientation Selection

새 프로젝트의 9:16 또는 16:9 비율을 선택한다.

### Camera

새로운 Clip을 촬영한다.

### Video Import

Photos Library의 기존 영상을 프로젝트에 추가한다.

### Project / Clips

촬영하거나 가져온 Clip을 확인하고 정리한다.

### Trim

각 Clip에서 실제 Vlog에 사용할 구간을 결정한다.

### Preview

현재 프로젝트의 전체 결과를 확인한다.

### Export

완성된 Vlog를 하나의 영상으로 생성하고 저장한다.

정확한 Screen Architecture와 Navigation은 `DESIGN.md`에서 정의한다.

---

# 19. Post-MVP — Camera Controls

Tap to Focus, Exposure Control, Zoom, Torch는 MVP에 포함하지 않으며 도입 시점과 세부 정책은 Post-MVP에서 검토한다.

## F-POST-001 — Tap to Focus

사용자가 Camera Preview의 특정 영역을 선택하여 Focus를 지정할 수 있는 기능을 검토한다.

---

## F-POST-002 — Exposure Control

사용자가 촬영 중 간단하게 Exposure를 조절할 수 있는 기능을 검토한다.

---

## F-POST-003 — Zoom

Rear Camera 촬영 중 Zoom을 조절할 수 있는 기능을 검토한다.

지원 범위와 Lens 전환 정책은 추후 결정한다.

---

## F-POST-004 — Torch

Rear Camera 촬영 중 Torch를 사용할 수 있는 기능을 검토한다.

---

# 20. Post-MVP — Text

## F-POST-005 — Text Overlay

사용자는 Vlog 위에 짧은 Text를 추가할 수 있는 기능을 향후 사용할 수 있다.

### Candidate Features

- Text input
- Font selection
- Text size
- Position
- Alignment
- Basic color

Mellow의 단순성을 해치지 않는 범위에서 기능 범위를 결정한다.

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
5. 사용자가 원하는 시점에 녹화를 종료하거나 10초에 도달하여 자동 종료된다.
6. 추가 Clip을 촬영할 수 있다.
7. Photos Library에서 기존 영상을 가져올 수 있다.
8. 긴 Imported Video에서 최대 10초의 원하는 구간을 선택할 수 있다.
9. 촬영 또는 Import한 Clip을 확인할 수 있다.
10. 불필요한 Clip 삭제가 즉시 UI에 반영되고 Undo를 사용할 수 있다.
11. Clip의 순서를 변경할 수 있다.
12. 각 Clip의 시작점과 종료점을 Trim할 수 있다.
13. 전체 Vlog를 Preview할 수 있다.
14. 프로젝트 비율에 맞는 1080p / 30 fps 영상으로 Export할 수 있다.
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
- 하나의 촬영 Clip은 최대 10초다.
- 사용자는 10초 이전에는 자유롭게 녹화를 종료할 수 있다.
- 촬영 시간이 10초에 도달하면 자동으로 녹화를 종료한다.
- 고정 촬영 시간 Preset은 MVP에 포함하지 않는다.
- Recording Pause / Resume는 MVP에서 제공하지 않는다.
- Photos Library의 기존 영상을 프로젝트에 Import할 수 있다.
- Imported Video 원본의 길이는 제한하지 않는다.
- Imported Video에서는 프로젝트에 사용할 최대 10초 구간을 선택한다.
- 4K를 포함한 고해상도 Source Import를 허용하며 선택된 Segment를 기준으로 1080p Working Media를 생성하는 방향을 사용한다.
- 정상적으로 추가된 Project-owned Clip은 이후 Photos 원본이 삭제되어도 Draft에 유지한다.
- 프로젝트에서 사용하는 하나의 최종 Clip 길이는 최대 10초다.
- Project orientation은 9:16 Portrait와 16:9 Landscape를 지원한다.
- 하나의 프로젝트에서는 하나의 Orientation을 유지한다.
- Imported Video의 Aspect mismatch 기본 정책은 Fill + Crop이며 사용자가 Framing 위치를 조정할 수 있다.
- Fit과 Background Blur는 MVP에서 제공하지 않는다.
- 개별 Clip 삭제는 즉시 UI에 반영하고 Undo를 제공한다.
- 프로젝트 전체 삭제는 Confirmation 이후 실행한다.
- 전체 Vlog의 총 재생 시간에는 고정 최대 제한을 두지 않는다.
- 하나의 Vlog에 포함할 수 있는 Clip 개수에도 고정 최대 제한을 두지 않는다.
- 여러 개의 미완성 Vlog 프로젝트를 동시에 저장할 수 있다.
- Draft에는 자동 만료 기간을 두지 않는다.
- Draft는 사용자가 직접 삭제하기 전까지 유지한다.
- 프로젝트 상태는 자동 저장하며 앱 재실행과 기기 재부팅 후에도 로컬 Draft를 유지한다.
- 앱 삭제 및 기기 교체 이후 복구와 iCloud 동기화·복구는 MVP 보장에 포함하지 않는다.
- 프로젝트 이름 입력 Prompt는 MVP에서 제공하지 않는다.
- 프로젝트 이름은 생성 날짜 및 시간을 기준으로 자동 생성한다.
- Project Rename은 MVP에서 제공하지 않는다.
- Home의 기존 프로젝트 영역은 `Recent`로 표시하며 내부 Domain에서는 `Draft` 용어를 사용할 수 있다.
- Draft의 대표 Thumbnail은 첫 번째 사용 가능한 Clip을 기준으로 한다.
- Export 이후에도 Draft를 자동 삭제하지 않는다.
- Draft를 다시 열어 수정하고 다시 Export할 수 있다.
- MVP 표준 Video Profile은 1080p / 30 fps이며 Portrait Output은 1080 × 1920, Landscape Output은 1920 × 1080이다.
- 720p Export, 4K Export와 60 fps Export는 MVP에서 제공하지 않는다.
- Save to Photos와 iOS Share Sheet를 제공한다.
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
- Post-MVP Zoom 도입 시점 및 지원 범위
- Post-MVP Torch 도입 시점 및 세부 동작
- Camera Lens 선택 정책
- Front Camera 영상 Mirror 처리 정책

## Recording

- 최소 Clip 길이 제한 여부
- 촬영 시작 시 Haptic Feedback 사용 여부
- 촬영 종료 시 Haptic Feedback 사용 여부
- 10초 자동 종료 직전 Feedback 방식
- 앱이 Background로 이동할 때 촬영 중 Clip 처리 정책

## Orientation

- Orientation 선택 화면의 정확한 UX
- 9:16 프로젝트 촬영 중 기기를 가로로 들었을 때 제공하는 회전 안내의 구체적인 형태와 위치
- 16:9 프로젝트 촬영 중 기기를 세로로 들었을 때 제공하는 회전 안내의 구체적인 형태와 위치

## Imported Video

- Trim과 Crop의 세부 화면 구성
- Crop 시 Pinch to Zoom 지원 여부
- Imported Clip의 Re-trim 범위 및 Source Reference 유지 여부
- Working Media 정규화의 세부 정책
- Post-MVP Fit 또는 Background Blur 도입 여부

## Project

- Recent의 List 또는 Grid Layout과 세부 표시 정보
- 프로젝트 자동 표시 이름의 구체적인 날짜 및 시간 Format
- Draft 삭제 전 Confirmation의 세부 UI
- Draft 저장 실패 처리 및 자동 복구의 세부 정책
- Storage Threshold와 Warning 기준
- Draft Storage 사용량 표시 여부
- 프로젝트 Rename 기능의 Post-MVP 추가 여부
- Export 완료 프로젝트와 미완성 프로젝트의 UI 구분 여부

## Clip Management

- Clip 삭제 Undo lifecycle의 세부 동작
- Post-MVP Clip Duplicate 도입 여부
- Post-MVP Clip Split 도입 여부
- 개별 Clip Mute 기능 필요 여부

## Export

- Video Codec
- File Container
- Video Bitrate, Audio Format 및 Audio Bitrate
- HDR/SDR, Dolby Vision 및 Color Space 처리 정책
- 고정된 1080p / 30 fps 범위 내 Export Quality 선택 기능 제공 여부
- Export 및 Share 화면의 세부 UX
- Export 중 앱 Background 이동 처리 방식
- Export 실패 후 Retry 방식

## Audio

- 전체 프로젝트 Audio On / Off 기능
- 개별 Clip Mute 기능
- 개별 Clip Volume 조절 기능

## Future Editing

- Text 기능의 구체적인 범위
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
