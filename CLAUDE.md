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
  - **하드 프리즈**(보관함→카메라 복귀 시 프리뷰 사망, 앱 강제종료 필요): **e41c756으로 해결된 것으로 추정 — 추적 확증은 아님**(수정 후 재현 시도 A×3/B×2/C×5 전부 클린). 메커니즘 추정: 고정된 버퍼가 plain startRunning(풀 재사용)을 넘어 살아남고, freeze 오버레이는 **presented 프레임에서만** 해제되므로 복귀 세션이 첫 프레임을 못 내면 보관함 왕복으로는 영구 복구 불가. **freeze-overlay 스톨 감지 + 복구 SHIPPED** — 감지(47253f1, 텔레메트리) + 복구 킥(eff2b1c, production 세션 재시작·캡 3회, 2026-07-19 실기기 검증)이 재발 시 자동 복구한다. 남은 조각이던 frozen/overlay 갈라짐 레이스는 **해결됨(`c97bf1c`)** — 아래 항목.
  - **계측 기록 정정 (2026-07-18):** [MTRACE4]의 "단계별 카운터 + 2s 플러시" 코드는 **커밋된 적 없음** — e41c756 이전에 제거된 일시적 디버그 계측이었다(`git log -S MTRACE`로 확인). 커밋되어 재사용 가능한 인프라는 `ThermalDiagnostics.swift`(`#if DEBUG`) 하나다: 프레임 하트비트(recordFrame), 10s SAMPLE 라인, EVENT 라인, ACTIVITY 태그. 여기에 **MTRACE5 스톨 감지**(47253f1)가 추가됨: SAMPLE에 `commitAge=<ms>`, arm 사이클당 1회 `MTRACE5 EVENT stall_detected`, 폴트 인젝션 플래그 `suppressRenderForTesting`. 폴트 인젝션 훅 추가(`42ebcbf`): `delayPresentedHideForTesting` — presented-handler hide 본문 전체(세대 검사 포함)를 지정 간격만큼 지연해 레이스 검증용 윈도우를 벌린다. 향후 레이스 검증에 재사용 가능. 테스트 중 오버레이가 지연만큼 머무는 시각 효과는 **정상**(스톨 아님) — SAMPLE 라인의 commitAge가 계속 살아 있는 것으로 실제 스톨과 구분된다. **eff2b1c부터 워치독 코어(500ms 틱, 임계 2s, 기준 = max(arm, 마지막 렌더 커밋); CameraPreviewView.Coordinator)·커밋 하트비트·오버레이 미러는 production 코드다**(복구 킥이 Release에서 돌아야 하므로) — EVENT 로깅(stall_detected / recovery_kick / recovery_gave_up / kick_skipped_interrupted)과 폴트 인젝션만 DEBUG로 남았고, SAMPLE의 commitAge는 provider 글루로 승격된 값을 읽는다.
  - **MTRACE5 검증 절차 (2026-07-18 실기기 통과):** 폴트 인젝션 토글은 **Mellow 모듈의 Swift 프레임에 멈춘 상태에서만** lldb로 가능 — 시스템 코드에서 pause하면 "undeclared identifier"로 실패한다. 절차: `ThermalDiagnostics.start()`의 SAMPLE write 라인에 브레이크포인트 → 정지 시 `expr ThermalDiagnostics.suppressRenderForTesting = true`(해제는 `false`). 검증 결과: arm 사이클당 정확히 1회 stall_detected EVENT(~2.0–2.1s), overlay-visible 게이팅은 네거티브 컨트롤로 확인, 정상 presented-handler 해제 경로 무손상.
  - **복구 킥 검증 (2026-07-19 실기기 통과, eff2b1c):** 킥 캡 1→2→3 → `recovery_gave_up` → 터미널 침묵을 독립 2사이클로 확인. re-arm은 캡을 리셋하지 않음(터미널 상태에서 보관함 왕복 → 킥 없이 gave_up만 재기록). 시도 리셋은 "킥 후 실제 커밋 관측" 단일 지점 — 2번째 사이클이 attempt=1로 시작함을 확인. 지연 start가 SwiftUI 엣지를 정상 생성(킥당 idle→previewing ACTIVITY 쌍). 정상 해제 경로 무손상. ⚠️ 인터럽션 게이트(`kick_skipped_interrupted`)는 구현됐지만 **실기기 미검증** — 인터럽션 옵저버 작업 때 함께 검증할 것.
  - **frozen/overlay 갈라짐 레이스: FIXED (`c97bf1c` 세대 토큰 가드, 검증 훅 `42ebcbf`, 2026-07-20 실기기 검증 통과).** 레이스: renderFrame이 encode 시점에 frozen을 내리고 오버레이 hide는 present 시점 main-hop으로 늦게 도착 — 그 갭에 freeze(with:)가 오면 overlay-visible early-return이 frozen 재세트를 건너뛰어, frozen=false + 오버레이 표시 + pending hide가 새 freeze 의도를 무시하고 오버레이를 걷어내는 갈라짐(들린 블랙 노출). 수정 = **freeze 세대 토큰**(freezeLock 하 `freezeGeneration`): freeze(with:)마다 증가(early-return 경로도 frozen 재세트 + 세대 증가), renderFrame은 **진입 시점**(블로킹 nextDrawable 전) 세대를 캡처해 `frozen && 세대 불변`일 때만 frozen을 내리며, presented-handler hide는 **발화 시점** 세대 일치 시에만 실행(불일치 시 스킵 + DEBUG `MTRACE5 EVENT stale_hide_skipped`). 설계 이력: 최초 "hide 직전 frozen 재검사" 방식은 Codex 교차 리뷰에서 구멍 2개 발견 — (1) 낙오 프레임이 frozen을 다시 내려 더 오래된 hide가 재검사를 통과, (2) nextDrawable에 블록돼 있던 pre-freeze 프레임이 freeze 후 세대를 캡처해 post-freeze 프레임으로 위장 — 최종형(진입 세대 + 발화 시점 비교)이 둘 다 봉쇄, 3차 리뷰 클린. 검증(2026-07-20 실기기): delayed-hide 인터리빙 테스트에서 stale_hide_skipped 2회(오버레이 보존, 들린 블랙 플래시 없음), 회귀 패스(필터 사이클링·보관함 왕복 ×10·캡처)에서 이벤트 0회·오버레이 정상 사이클.
  - 낮은 우선순위 백로그 — **낙오 프레임 질문:** freeze **후에** renderFrame에 진입한 프레임은 세대가 일치해 freeze를 정당하게 해제한다(그 hide는 generation-fresh). c97bf1c 이전부터 있던 동작으로 커밋 3 범위 밖. 마일드 프리즈 패턴 (b) "보관함 복귀로 풀리는 one-shot freeze"와 관련 가능성 있음.
  - 낮은 우선순위 백로그 — **AVCaptureSession 인터럽션/에러 옵저버 부재:** `wasInterruptedNotification` / `interruptionEnded` / `runtimeError`를 아무 데서도 구독하지 않는다. 복구 킥은 현재 동기 `session.isInterrupted` 판독으로만 게이트 — 옵저버 기반 게이트(인터럽션 종료 시 재판정 등)로 보강할 것.
  - 낮은 우선순위 백로그 — **시뮬레이터 빌드 깨짐 (e41c756부터):** `CAMetalDrawable.addPresentedHandler`가 시뮬레이터 SDK에 없어 컴파일 실패(실기기 빌드는 정상). 시뮬 빌드가 필요해지면 `#if !targetEnvironment(simulator)` 가드로 해당 경로를 감쌀 것.
  - 발열 watch — Stage 4c: **RESOLVED for stills (2026-07-18).** Mild heat during heavy testing was profiled with Instruments; all suspects (CIContext reuse, cache growth, render-loop idling, full-res retention) came back clean — see "Thermal Profiling Baseline (2026-07-18)" below. Video re-profiling still required before Phase 2.
- **필터 스와치 팔레트: DONE (2026-07-20, `b4732fd`, 실기기 시각 검증 통과 — 필터별 구분 스와치 확인, 레거시 사진 무영향).** 9종 스와치 색의 단일 진실 공급원은 `MellowFilterRoster`(Entry.swatch + `swatchColor(forSlug:)`) — PhotoInfoSheet의 인포 시트 12pt 원이 소비하고, 미상/레거시 slug과 합성 original은 `.mellowAccent`로 안전 폴백(낡은 original→latte 매핑은 제거). 팔레트: hazy `#C9C2B8` · ember `#C97B5A` · sunday `#C97F3E`(=`.mellowAmber` 토큰) · honey `#D9A441` · hush `#A8ADB5` · winter `#9FB4C7` · travel `#7FA08C` · moonrise `#8B87A8` · color `#C46A79`. **기록 정정:** 낡은 3종 스와치 코드는 "FilterPreset line 35"가 아니라 `PhotoInfoSheet.swatchColor()`에 있었다(이번에 제거). FilterPreset은 색 데이터를 가진 적 없음(타입 자체는 아래 항목대로 은퇴 완료).
- **FilterPreset 은퇴: DONE (2026-07-22, 2커밋).** 소스 전수 조사로 100% 데드 코드 확정(영속성 무관 — `Capture.filterID`는 순수 String, 선택 필터는 미영속; Codable 아님) 후 제거. 커밋 1(`f4759e1`): 유일한 외부 코드 의존이던 데드 `FrameProcessor.apply(preset:)` 삭제 + 헤더 주석 실경로(`CameraPreviewView.Coordinator.render`의 LUT CIFilter)로 정정. 커밋 2(최종): `FilterPreset.swift` 파일 삭제(파일 전용 헬퍼 colorControls/channelGains/liftShadows 포함 — 다른 사용처 없음, synced group이라 pbxproj 무수정) + 5개 파일의 낡은 `FilterPreset.makeChain`/`preset(for:)` 주석을 실제 LUT 경로로 스크럽. 렌더·저장·익스포트 로직 무변경(주석 전용 + 데드 코드 삭제).
- 낮은 우선순위 백로그 — **`FrameProcessor.crossfade` 데드 코드:** 호출처 0(선언뿐 — L3 Decision B "즉시 스왑, 크로스페이드 없음"으로 사장). 단, Phase 1 Spec §4.2가 여전히 크로스페이드를 명세하므로 **삭제 전 기획 결정 필요**(스펙을 따라 되살릴지, 스펙 노트와 함께 은퇴할지). 임의 삭제 금지.
- 낮은 우선순위 백로그 — **LUT 프리페치 패스스루 창의 WYSIWYG 위반 (Codex 적대 리뷰 2026-07-22 발견):** 선택 slug의 LUT가 아직 로드되지 않은 동안 프리뷰는 패스스루로 표시되는데, 그 상태에서 촬영하면 slug이 그대로 저장돼 썸네일·상세·익스포트는 LUT 적용본으로 렌더된다 — 프리뷰(무필터)와 결과물(필터됨)이 갈라지는 좁은 창. 수정 = 캡처 또는 필터 선택을 LUT 레디니스로 게이트 — **동작 변경이라 기획 결정 필요, 임의 구현 금지.** .lutbin 프리컴파일 이후 이 창은 매우 짧을 것으로 예상.

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