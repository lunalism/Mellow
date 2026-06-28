# Mellow — 프로젝트 메모리 (Claude Code)

Mellow는 일상의 따뜻한 순간을 필름 감성으로 기록하는 미니 브이로그 & 필름 카메라 iOS 앱이다.
무드: 한낮 햇살 · 카페 · 아늑한 힐링. 따뜻하고 살짝 빛바랜 "필름 다이어리".

## 스택
- 네이티브 iOS — SwiftUI + AVFoundation + CoreImage/Metal
- iOS 우선, v1은 **라이트 모드 고정**(다크모드 v1.1)
- 최소 배포 타깃: **iOS 17** (변경 시 docs/PRD 갱신)
- **완전 로컬 앱 — 서버·계정·로그인 없음**

## 핵심 제약 (IMPORTANT)
- 필터는 **비파괴**: 원본 + 필터 ID를 저장하고 표시·익스포트 시 렌더한다. 원본을 덮어쓰지 말 것.
- 색은 **디자인 토큰만** 사용(디자인 시스템의 `mellow*` Color). 순수 검정(`#000`) 금지 → **들린 블랙 `#3B362E`**.
- 필터는 **큐레이션 8종**(Sunday=기본 / Honey / Breeze / Hush / Olive / Linen / Ember / Velvet). 임의 추가 금지.
- 프리뷰 = 캡처 = 익스포트 **같은 파이프라인**(WYSIWYG, GPU/Metal 경로).
- 회원가입·계정·온보딩 화면 만들지 말 것(첫 실행 권한 프라이밍만).

## 문서 (작업 전 참조)
- `docs/Mellow_PRD_v0.2.md` — 제품 정의(무엇을/왜)
- `docs/Mellow_Design_System_v0.2.md` — 색·토큰·타이포·질감
- `docs/Mellow_UI_Interaction_Guide_v0.1.md` — 컴포넌트·모션·햅틱·접근성
- `docs/Mellow_Screen_Flow_Map_IA_v0.1.md` — 화면 지도·내비게이션
- `docs/Mellow_Phase1_CameraCore_Spec_v0.2.md` — **현재 작업(Phase 1)**

## 현재 단계
Phase 1 — 카메라 코어: 라이브 필터 프리뷰 + 사진 촬영 + 비파괴 저장.
구현 기준 = `docs/Mellow_Phase1_CameraCore_Spec_v0.2.md`.

## 작업 방식
- **개발/디버깅 관련 대화만 영어로 유지**하여 맥락을 간결하게.
- 변경은 작게, 자주 검증(검증의 검증의 검증).
- **검증은 항상 실기기 + 클린 설치.** 시뮬레이터엔 카메라가 없어 더미 모드로만 돌므로, 카메라·프리뷰·캡처 검증은 시뮬레이터로 대체 불가.
  - 빌드·실행 전 연결된 실기기를 인식할 것 (`xcrun devicectl list devices`). 실기기가 없으면 **멈추고 알릴 것 — 시뮬레이터로 폴백 금지.**
  - 설치 시 기존 앱을 먼저 삭제하고 새로 설치(클린 설치). iOS 17+이므로 `xcrun devicectl` 사용, 서명 필요 시 `-allowProvisioningUpdates`.
  - 기기 빌드·설치가 어떤 이유로든(서명·프로비저닝·신뢰) 실패하면 **멈추고 정확한 에러를 보고할 것 — 시뮬레이터로 폴백 금지.**
- **시뮬레이터 더미 모드는 `#if targetEnvironment(simulator)` 컴파일 타임으로만 진입.** 실기기 빌드엔 더미가 들어가지 않아야 함(런타임 상태로 더미 띄우지 말 것).
- **버전 관리:** 빌드가 통과하고(해당되면 실기기 검증까지) 하나의 논리적 단위가 끝나면 그때 커밋·푸시할 것. 컴파일 안 되는 중간 상태는 커밋 금지 — 어느 커밋으로 되돌려도 빌드되는 히스토리를 유지. 커밋 메시지는 간결한 영어 한 줄(예: `Stage 1: live camera preview on device`). 푸시 전 변경 파일을 먼저 보여줄 것.
- **발열·성능은 누적 검증 항목.** 각 단계는 정지 화면뿐 아니라 1~2분 연속 사용 후 발열·프레임 드랍을 확인할 것. 특히 필터·그레인·영상이 얹히는 단계 이후 GPU 부하가 커지므로, 프리뷰=캡처=익스포트 경로가 실기기 최저 타깃에서 30fps+를 유지하고 과열되지 않는지 본다.
  - 발열 watch — Stage 4c: mild heat felt during heavy testing (rapid capture + full-res detail view + delete animations, while charging). Pre-measurement, cause unconfirmed; likely amplified by test intensity + charging, not normal use. TODO before Phase 2 (video): profile once with Instruments (Time Profiler / GPU / Allocations). Suspects to check: CIContext reuse (one shared context vs per-render), fullCache + thumbnail cache memory caps, whether the MTKView render loop idles when the preview isn't changing, and whether full-res detail renders are released promptly.