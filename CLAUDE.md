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
- 한국어로 소통.
- 변경은 작게, 자주 검증(검증의 검증의 검증).
- **실기기 테스트 필수** — 시뮬레이터엔 카메라가 없어 더미 모드로만 확인됨.