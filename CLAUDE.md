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
- 필터는 **큐레이션 9종**(표시 순서: Hazy / Ember / **Sunday=기본** / Honey / Hush / Winter / Travel / Moonrise / Color — 단일 진실 공급원 `MellowFilterRoster.swift`). 임의 추가 금지.
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
- **알려진 특성 — 첫 설치 첫 프리뷰 프레임 ~230ms 지연 (버그 아님).** CIColorCube Metal 셰이더의 설치당 1회 컴파일 비용(OS 셰이더 캐시가 재설치 시 초기화됨). iPhone 12 실측(2026-07-16): 첫 설치 frame 0 렌더 233ms → 다음 콜드런치 18ms → 정상 ~0.5ms. 프레임은 전부 필터 적용 상태로 렌더됨(패스스루 아님 — 첫 프레임이 늦게 뜰 뿐). 실사용에선 권한 다이얼로그 뒤라 체감 없음 → **프리워밍은 의도적으로 보류**(핫패스 코드 추가 대비 이득이 QA 시나리오뿐). 클린 설치 후 QA에서 이 지연을 보더라도 재조사하지 말 것.
- **프리뷰 프리즈 2종 — 해결 이력 (2026-07-16, `e41c756`).** 근본 원인: 캡처 픽셀버퍼 풀 고갈. 라이브 프리뷰의 slug당 영속 CIFilter가 마지막 inputImage(카메라 CVPixelBuffer 참조 CIImage)를 전환 후에도 계속 보유 → 서로 다른 필터 ~7종을 빠르게 오가면 풀(~6개, iPhone 12)이 전부 고정되어 captureOutput이 **조용히** 멈춘다.
  - **소프트 프리즈**(빠른 필터 전환 → 마지막 프레임 정지, 보관함 왕복/카메라 전환으로 복구): **해결 확정** — 렌더 직후 `filter.setValue(nil, forKey: kCIInputImageKey)` + freeze 변환 후 `lastImage` 해제. [MTRACE4] 단계별 카운터 실측으로 원인 추적(기존 "렌더 큐 백로그" 가설은 **반박됨** — 프리즈 중 videoQueue는 유휴, 공급이 죽은 것). 검증: 9종 전체 67회 전환/80초, 30fps 유지, 공급 드랍 0. ⚠️ 이 두 해제 라인을 지우지 말 것 — 지우면 프리즈가 돌아온다.
  - **하드 프리즈**(보관함→카메라 복귀 시 프리뷰 사망, 앱 강제종료 필요): **e41c756으로 해결된 것으로 추정 — 추적 확증은 아님**(수정 후 재현 시도 A×3/B×2/C×5 전부 클린). 메커니즘 추정: 고정된 버퍼가 plain startRunning(풀 재사용)을 넘어 살아남고, freeze 오버레이는 **presented 프레임에서만** 해제되므로 복귀 세션이 첫 프레임을 못 내면 보관함 왕복으로는 영구 복구 불가. **재발 감시 대상** — MTRACE5 스톨 감지(아래)가 DEBUG 빌드에서 상시 감시한다.
  - **계측 기록 정정 (2026-07-18):** [MTRACE4]의 "단계별 카운터 + 2s 플러시" 코드는 **커밋된 적 없음** — e41c756 이전에 제거된 일시적 디버그 계측이었다(`git log -S MTRACE`로 확인). 커밋되어 재사용 가능한 인프라는 `ThermalDiagnostics.swift`(`#if DEBUG`) 하나다: 프레임 하트비트(recordFrame), 10s SAMPLE 라인, EVENT 라인, ACTIVITY 태그. 여기에 **MTRACE5 스톨 감지**(47253f1, 텔레메트리 전용 — 복구·클리어 없음)가 추가됨: SAMPLE에 `commitAge=<ms>`, arm 사이클당 1회 `MTRACE5 EVENT stall_detected`, 폴트 인젝션 플래그 `suppressRenderForTesting`. 워치독(500ms 틱, 임계 2s, 기준 = max(arm, 마지막 렌더 커밋))은 CameraPreviewView.Coordinator에 있다.
  - **MTRACE5 검증 절차 (2026-07-18 실기기 통과):** 폴트 인젝션 토글은 **Mellow 모듈의 Swift 프레임에 멈춘 상태에서만** lldb로 가능 — 시스템 코드에서 pause하면 "undeclared identifier"로 실패한다. 절차: `ThermalDiagnostics.start()`의 SAMPLE write 라인에 브레이크포인트 → 정지 시 `expr ThermalDiagnostics.suppressRenderForTesting = true`(해제는 `false`). 검증 결과: arm 사이클당 정확히 1회 stall_detected EVENT(~2.0–2.1s), overlay-visible 게이팅은 네거티브 컨트롤로 확인, 정상 presented-handler 해제 경로 무손상.
  - 낮은 우선순위 백로그 — **시뮬레이터 빌드 깨짐 (e41c756부터):** `CAMetalDrawable.addPresentedHandler`가 시뮬레이터 SDK에 없어 컴파일 실패(실기기 빌드는 정상). 시뮬 빌드가 필요해지면 `#if !targetEnvironment(simulator)` 가드로 해당 경로를 감쌀 것.
  - 발열 watch — Stage 4c: **RESOLVED for stills (2026-07-18).** Mild heat during heavy testing was profiled with Instruments; all suspects (CIContext reuse, cache growth, render-loop idling, full-res retention) came back clean — see "Thermal Profiling Baseline (2026-07-18)" below. Video re-profiling still required before Phase 2.

## Thermal Profiling Baseline (2026-07-18)

Instruments on iPhone 12, Release build, cool indoor conditions.
**Verdict: no thermal issues in the stills pipeline — all hypotheses tested, zero optimizations needed.** Thermal state remained Nominal across all scenarios (5min idle preview, 1min rapid 9-filter cycling, 2min detail-view open/close ×10, 2min gallery↔camera round-trips ×10).

- **H1 render-loop idling: REJECTED.** Metal System Trace showed ~15 encoders/sec, frame-driven (not 60Hz display-driven). Encoder time 307ms total over 146s (~0.2% GPU), max 840µs/frame.
- **H2 CIContext duplication: REJECTED.** CI::MetalContext total cost ~0.9s over a 5min session — negligible.
- **H3 full-res CIImage retention: CLEAR (indirect evidence).** Allocations showed IOSurface 8 persistent vs 59 transient during detail-view cycling; flat memory graph, no staircase. Follow-up: use Mark Generation for direct proof only if an anomaly appears.
- **H4 unbounded cache growth: CLEAR.** CoreImage persistent stable at ~30MiB (LUT cubes + CI residents); total app persistent ~100MiB.

Cost profile insight: dominant CPU cost during interaction is SwiftUI/UIKit update cycles (Main Thread 50–60% of CPU time in all interactive scenarios), NOT CI/Metal rendering. Per-second CPU: idle ~7%, filter cycling ~29%, detail view ~21%, gallery round-trip ~15%. All healthy for iPhone 12.

Watch items (observations, not bugs):
- Low-light auto-exposure drops capture to ~15fps (measured at night indoors); verify ~30fps in bright conditions. Standard AVFoundation behavior, not a bug.
- RenderBox glyph rendering visible during rapid filter cycling; negligible at current volume.

**Phase 2 gate:** this baseline covers the STILLS pipeline only. Video recording adds encoding + sustained load — re-run the same Instruments set (Time Profiler + Thermal, Metal System Trace, Allocations) with video scenarios before/during Phase 2 work.