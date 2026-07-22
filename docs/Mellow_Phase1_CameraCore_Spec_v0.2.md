# Mellow — Phase 1: 카메라 코어 상세 스펙 v0.2

> **[은퇴 노트 2026-07-22]** 본문 §4.5·§5·§12의 `FilterPreset` 타입은 구현 과정에서
> `MellowFilterRoster`(9종 로스터·slug 단일 진실 공급원) + `LUTStore`/`LUTFilter`(.cube LUT
> 렌더 경로)로 대체되었고, 2026-07-22 코드베이스에서 제거되었다. §4.2 크로스페이드는 즉시
> 스왑으로 대체 결정(L3 Decision B)되어 미사용. 본문은 역사적 기록으로 원문 유지.

> **목적.** '돌아가는 카메라'를 처음 확보한다. 라이브 필터 프리뷰가 돌고, 사진을 찍어 저장하는 것까지.
> **연결 문서.** PRD v0.2 · 디자인 시스템 v0.2.
> **v0.2 변경.** 필터 전환 인터랙션(§4) 추가 — 이중 입력 · 크로스페이드 · 디텐트 햅틱.

---

## 1. 범위

### 이 Phase에서 만드는 것
- `AVCaptureSession` 기반 카메라 구동 (전/후면).
- **라이브 필터 프리뷰** (Metal 렌더, WYSIWYG).
- 필터 파이프라인 **뼈대** + 스텁 필터 1~2종(예: Sunday, Honey)을 연결해 동작 검증.
- 컨트롤: 셔터, 비율(9:16·4:3·1:1·2:1), 노출, 전/후면, 플래시, 필터 피커(전환 인터랙션 포함).
- 사진 1장 촬영 → **비파괴 저장**(원본 + 필터 ID) → 보관함 썸네일 갱신.

### 이 Phase에서 안 하는 것 (다음 단계)
- 8종 필터 LUT 풀구현 + 강도 슬라이더 → **Phase 2**.
- 영상 녹화·연결·BGM → **Phase 4**.
- 갤러리 화면 고도화 → **Phase 3**.
- 날짜 스탬프 렌더, 시즌 필터.

> 한 줄: **"카메라가 돌고, 필터 입힌 프리뷰가 보이고, 사진이 찍혀 저장된다"** 까지가 Phase 1의 끝.

---

## 2. 화면 구성

세 영역으로 나뉜다. 배경 chrome은 **페이퍼(`#F4EEE1`)**, 무거운 가죽 ❌.

### 2.1 상단 바
| 요소 | 동작 |
| --- | --- |
| 플래시 | off / on / auto 토글 |
| 비율 칩 | 9:16 / 4:3 / 1:1 / 2:1 순환 |
| 설정 | 설정 화면 진입 (Phase 1엔 최소) |

### 2.2 프리뷰 영역
- 선택 비율로 크롭된 **라이브 필터 프리뷰** (둥근 모서리 16px).
- 탭 → 해당 지점 초점·노출(AF/AE) 락.
- **좌우 스와이프 → 필터 전환** (§4).
- 노출 보정(EV) 인디케이터 표시.

### 2.3 하단
| 요소 | 동작 |
| --- | --- |
| 필름통 필터 피커 | 가로 스크롤. 칩 = 필름 시그니처색 + 이름. 탭 선택 + 뷰파인더 스와이프와 동기화. 선택 시 앰버 링. 기본 = **Sunday** (상세 §4) |
| 셔터 | 큰 원형, 앰버 링(`#C97F3E`) + 크림 중앙. 탭 = 촬영, 햅틱 |
| 전/후면 전환 | 카메라 토글 |
| 보관함 썸네일 | 최근 촬영 미리보기 → 보관함 진입 |

---

## 3. 컨트롤 명세

| 컨트롤 | 상태/값 | 기본 | 비고 |
| --- | --- | --- | --- |
| 셔터 | idle / capturing / saving | idle | 촬영 중 중복 탭 무시 |
| 비율 | 9:16 / 4:3 / 1:1 / 2:1 | 4:3 | 프리뷰 즉시 크롭 반영 |
| 노출(EV) | -2.0 ~ +2.0 / 자동 | 자동 | 슬라이더 + 자동 버튼 |
| 카메라 | 후면 / 전면 | 후면 | 전환 시 세션 재구성 |
| 플래시 | off / on / auto | off | 전면은 화면 플래시(후순위) |
| 필터 | 8종 중 1 (Phase1은 스텁 1~2) | Sunday | 탭/스와이프, 크로스페이드+햅틱 (§4) |
| 줌 | 0.5x / 1x / 2x (기기 지원 시) | 1x | 핀치 + 프리셋 |

---

## 4. 필터 전환 인터랙션

> Mellow는 **실시간 WYSIWYG 진영**이다 (구닥·mood.camera식 '미리보기 없음' ❌). Retrica·PICNIC처럼 찍기 전에 보여주되, 우리만의 결(부드러운 모션·촉감)을 입힌다.

### 4.1 입력 (이중)
- **뷰파인더 좌우 스와이프** → 다음/이전 필름으로 빠르게 순환.
- **하단 필름통 스트립 탭** → 특정 필름 콕 선택.
- 둘은 **동기화**된다: 스와이프하면 스트립도 따라 스크롤, 탭하면 프리뷰도 즉시 전환.
- 모든 전환은 프리뷰에 **즉시** 반영.

### 4.2 전환 모션
- 필터 간 **부드러운 크로스페이드 ~180ms** (하드컷 ❌). '느긋한 모션' 원칙.
- 선택된 필름통 칩: 살짝 떠오르며 앰버 링 — 스큐어모픽 '필름 장전' 느낌.

### 4.3 햅틱
- 필름이 한 칸 넘어갈 때마다 **디텐트 햅틱** (가벼운 selection / 소프트 임팩트) — 우리가 정한 "필름 만지는 촉감"의 핵심 순간.

### 4.4 범위 메모
- **강도 조절은 Phase 2** (Retrica·Dazz의 더블탭=강도를 후속에서).
- 칩 미리보기: Phase 1은 **시그니처 색 + 이름**. 궁극적으로 각 칩이 라이브 피드를 작게 틴트(골드 스탠다드, Retrica식)하는 건 **폴리시 단계 과제**.
- **메뉴 관리(추가/삭제/정렬) 없음** — 큐레이션 8종이라 불필요. Dazz식 카메라 셸프 관리의 무거움을 피한다(미니멀 강점).

### 4.5 구현 메모
- 스와이프 = `selectedFilter` 인덱스 ±1. 크로스페이드는 직전/현재 두 `FilterPreset` 출력을 alpha 블렌딩하며 렌더.
- 햅틱: `UISelectionFeedbackGenerator` 또는 소프트 `UIImpactFeedbackGenerator`.

---

## 5. 상태 머신

### 5.1 카메라 권한
```
notDetermined → (요청) → authorized → 정상 진입
                       ↘ denied/restricted → 안내 화면(설정으로 유도)
```
- 거부 시: 따뜻한 톤의 안내 + "설정에서 권한 켜기" 버튼. 앱이 죽지 않는다.

### 5.2 세션 상태
```
configuring → running ⇄ interrupted(전화·다른 앱 카메라) 
running → stopped(백그라운드 진입)
* 오류 → error 상태 + 재시도 UI
```

### 5.3 캡처 상태
```
idle → capturing → saving → idle
                          ↘ failed → 토스트 + idle 복귀
```

---

## 6. 촬영 플로우

1. 셔터 탭 → 상태 `capturing`, 햅틱 + 셔터 애니메이션.
2. 현재 프레임(고해상도) 캡처.
3. **비파괴 저장:** 원본 풀해상도 + 선택 필터 ID + 비율 + 촬영시각 메타를 보관함에 기록. (필터는 표시·익스포트 시 렌더.)
4. 썸네일은 *필터 적용된* 미리보기로 갱신.
5. 상태 `idle` 복귀.

> 표시/공유 시 원본에 필터를 on-the-fly 렌더 → 나중에 필터 교체 가능, 화질 손실 최소. (Phase 4 영상 익스포트와 같은 파이프라인 재사용.)

---

## 7. 라이브 프리뷰 파이프라인 (아키텍처)

```
AVCaptureSession
  └─ AVCaptureVideoDataOutput (BGRA)
        └─ CMSampleBuffer  ──(background queue)──►  FrameProcessor
                                                      │ CIImage 변환
                                                      │ FilterPreset 체인 적용 (GPU)
                                                      ▼
                                              MetalPreviewView (MTKView)
                                                  CIContext(Metal) 렌더
```

- **프리뷰와 캡처는 같은 파이프라인** → WYSIWYG (프리뷰 색 = 저장 색).
- 세션·프레임 처리는 백그라운드 큐, 렌더는 Metal. UI 스레드 블로킹 금지.
- 디바이스 회전·미러링(전면) 처리.

### 클래스 구조 (스텁 시그니처)
```swift
// 세션 수명주기
final class CameraSessionManager: NSObject {
    let session = AVCaptureSession()
    func configure(position: AVCaptureDevice.Position)
    func start(); func stop()
    var onFrame: ((CMSampleBuffer) -> Void)?   // VideoDataOutput delegate → 콜백
}

// 프레임 처리: CMSampleBuffer → 필터된 CIImage
struct FrameProcessor {
    var preset: FilterPreset
    let context: CIContext                       // Metal 기반
    func process(_ sampleBuffer: CMSampleBuffer) -> CIImage
}

// 필터 프리셋 (Phase 1은 스텁 1~2종, Phase 2에서 8종 풀구현)
struct FilterPreset: Identifiable {
    let id: String            // "sunday", "honey" ...
    let displayName: String
    func makeChain(for input: CIImage, intensity: Double) -> CIImage
}

// Metal 프리뷰 (MTKView 래핑, CIImage 렌더 + 크로스페이드 블렌딩)
final class MetalPreviewView: MTKView, MTKViewDelegate {
    var image: CIImage?
    func crossfade(from: CIImage, to: CIImage, progress: Double)  // §4.2
}

// SwiftUI 바인딩
@MainActor final class CameraViewModel: ObservableObject {
    @Published var selectedFilter: FilterPreset
    @Published var ratio: AspectRatio
    @Published var exposure: Float
    @Published var cameraState: CameraState
    func capturePhoto()
    func cycleFilter(by delta: Int)   // §4.1 스와이프 (+1 / -1), 햅틱 동반
    func selectFilter(_ preset: FilterPreset)  // §4.1 스트립 탭
}
```

---

## 8. 데이터 모델 (캡처 기록)

```swift
struct Capture: Identifiable, Codable {
    let id: UUID
    let type: CaptureType        // .photo (Phase 4에서 .video)
    let originalURL: URL         // 앱 샌드박스 원본
    let filterID: String         // 비파괴 핵심
    let ratio: AspectRatio
    let createdAt: Date
}
```
- v1 저장소: 로컬(파일 + 경량 메타 스토어). 클라우드는 향후.

---

## 9. 디자인 토큰 적용

| 화면 요소 | 토큰 |
| --- | --- |
| 배경 chrome | `mellowPaper` `#F4EEE1` |
| 본문·아이콘 | `mellowTextPrimary` `#4A443A` |
| 셔터 링 | `mellowAccent` `#C97F3E` |
| 셔터 중앙 | `mellowIvory` `#FBF8F1` |
| 선택 필터 링 | `mellowAccent` |
| 보더·구분 | `mellowBorder` `#EBDFCB` |
| 그림자 | `mellowShadow` `#3B362E` (순수 검정 ❌) |

---

## 10. 엣지 케이스 & 권한

- **권한 거부/제한:** 안내 화면, 앱 비충돌. "설정 열기".
- **시뮬레이터:** 카메라 없음 → 더미(정지 이미지) 프리뷰 모드로 폴백, 실기기 테스트 유도.
- **세션 인터럽션:** 전화·타 앱 카메라 점유 시 일시정지 → 복귀 시 자동 재개.
- **빠른 연속 전환:** 스와이프 난사 시 크로스페이드 큐가 밀리지 않게 디바운스/최신값 우선.
- **저조도:** 노이즈↑ — 그레인과 충돌 주의(Phase 2 튜닝).
- **발열/성능:** 장시간 프리뷰 시 프레임 드랍·발열 모니터. GPU 경로 강제.
- **저장공간 부족:** 캡처 실패 토스트 + 안내.
- **회전:** 가로/세로 대응, 전면 미러링 정상화.

---

## 11. 수용 기준 (Phase 1 Done)

- [ ] 앱 실행 → 권한 → **라이브 프리뷰가 끊김 없이** 표시 (목표 ~30fps+ 실기기).
- [ ] 필터 칩 탭 / 뷰파인더 스와이프 둘 다 전환 동작, 스트립과 **동기화**.
- [ ] 전환 시 **부드러운 크로스페이드(~180ms) + 디텐트 햅틱**.
- [ ] 비율 변경 시 프리뷰 크롭 즉시 반영.
- [ ] 셔터 → 사진 저장 → 썸네일 갱신 (비파괴: 원본+필터ID).
- [ ] 전/후면 전환, 노출 보정, 플래시 동작.
- [ ] 권한 거부·인터럽션·시뮬레이터에서 **크래시 없음**.
- [ ] 실기기(최저 타깃 아이폰)에서 발열·드랍 허용 범위.
- [ ] 프리뷰 색 = 저장 색 (WYSIWYG 검증).

---

## 12. 다음 단계 (Phase 2 연결)

- `FilterPreset.makeChain`에 **8종 LUT/CIFilter 체인** 풀구현.
- 필터 **강도 슬라이더** (더블탭 진입 검토).
- 필름통 칩 **라이브 틴트 썸네일**(골드 스탠다드).
- 그레인(영상용 움직이는 시드)·라이트릭·들린 블랙·비네팅·헐레이션.

---

*버전 v0.2 · 다음 갱신: Phase 1 구현 착수 후 실측 fps·발열 데이터 반영*