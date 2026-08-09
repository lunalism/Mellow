# 인수인계 — Phase 0·1 → Phase 2

`Mellow_01` 채팅(Phase 0 ~ Phase 1)에서 `Mellow_02` 채팅(Phase 2)으로 넘기는 문서다.
Phase 2 를 시작할 때 이 파일과 `CLAUDE.md`, `Tasks.md` 를 읽으면 맥락이 선다.

기준 커밋: `d8a3c17`

---

## 1. 어디까지 왔나

**게이트 0 통과** (2026-08-09). 실기기 배포 확인, 자동 서명으로 동작.

**게이트 1 통과** (2026-08-10). 통과 조건 5개 전부 충족.
"10초 클립 여러 개가 재인코딩 없이 안 튀고 붙는지"라는 Phase 1 의 최대 리스크가
실측으로 해소됐다. 되돌아갈 조건(1-3 촬영 스펙 고정 방식 재검토)에 걸리지 않았다.

미착수는 **1-5(10초 자동 정지) · 1-6(녹화 버튼) · 1-7(1초 미만 폐기)** 셋뿐이고,
게이트와 무관한 촬영 편의 기능이라 Phase 2 에서 UI 와 함께 붙이기로 했다.

### 실측 요약 (iPhone 12, 20클립 486초)

|항목|값|
|---|---|
|익스포트 (20클립 486초)|**2,336 ms** — 1-19 기준 "3초 이내" 통과|
|실시간 대비|208배|
|크기 ÷ 소스 합|0.9990 (재인코딩 없음)|
|A/V 최종 어긋남|−0.02 s (0.6프레임), 클립당 −0.001 s, **추세 진동**|
|조립|100~172 ms|
|ready (탭 → 재생 가능)|194~336 ms|

세부 근거는 `Tasks.md` 의 `### 게이트 1 실측` 절에 있다.

---

## 2. 확정된 결정과 근거

`CLAUDE.md` 의 "확정된 설계 결정"이 정본이다. Phase 1 에서 **바뀐 것**과
**실측으로 닫힌 것**만 여기 정리한다.

### 바뀐 것

|항목|이전|지금|근거|
|---|---|---|---|
|코덱|H.264|**HEVC**|기본값이 hvc1 이고 9클립이 개입 없이 일치. 지정하면 출력 설정 경로가 늘고 재검증이 필요하다. 파일 크기도 유리|
|회전 기록|"세로 1080×1920 / 가로 1920×1080"|**인코딩 해상도는 방향과 무관하게 1920×1080**. 방향은 `preferredTransform` 에만 담긴다|1-11 실측. 세로로 찍은 클립도 encoded 1920×1080|
|화면 방향|Tasks 0-6 "잠그지 않는다"|**Portrait 고정**|가로 촬영은 인터페이스 회전이 아니라 기기 방향 감지로 처리|

### 실측으로 닫힌 것

- **촬영 스펙을 잠그지 않는다.** `sessionPreset` 도 `activeFormat` 도 지정하지 않는다.
  기본값이 이미 일정하고 20클립에서 흔들림이 없었다. 폴백 경로는 미리 만들지 않는다.
- **HDR 을 켜지 않는다.** 709 SDR 유지. 기본 카메라 앱은 HLG BT.2020 으로 찍지만,
  켜면 기기·조명에 따라 갈릴 여지가 생겨 "기본값이 일정하다"는 위 결정의 근거가 무너진다.
- **세션 방향은 섞으면 안 된다.** 컴포지션 비디오 트랙은 `preferredTransform` 을
  하나만 가진다. 섞으면 뒤 클립이 강제 회전되고, **passthrough 익스포트 결과물에도
  그대로 굳는다**(사진 앱 재생으로 확인).
- **스테레오 녹음.** `multichannelAudioMode = .stereo` (iOS 18+). 미지원 기기는 모노.
  한 기기 안에서는 일정하므로 세션 내 스펙 일치는 깨지지 않는다.

### 미해결 (결정 대기 목록 참조)

- 세션 방향을 3값(세로/가로좌/가로우)으로 둘지 — capture 각도가 자세마다 다르다
  (portrait 90° / landscapeLeft 0° / landscapeRight 180° / upsideDown 270°).
  가로좌와 가로우는 서로 못 붙는다. 차단 로직은 2-9.
- Swift 6 언어 모드 승격 — Phase 2 시작 시
- 다른 기기에서 녹음 품질 재확인

---

## 3. 코드 맵

```
Mellow/
├── MellowApp.swift
├── ContentView.swift          ← Phase 1 스파이크용 임시 호스트. Phase 3에서 교체
├── Capture/
│   ├── CameraPermissions.swift    권한 조회·요청 (1-1)
│   ├── CameraController.swift     세션 소유, RotationCoordinator, 녹화, 오디오 로깅
│   ├── CameraPreviewView.swift    layerClass 오버라이드 + didMoveToWindow
│   ├── MovieRecorder.swift        MovieFileOutput + NSObject 델리게이트 브리지
│   └── RotationDebugOverlay.swift 디버그 오버레이
├── Composition/
│   ├── ClipLibrary.swift          디렉터리 스캔 → 각도별 그룹
│   ├── ClipComposer.swift         컴포지션 조립 + 이음새 진단 (UI 비의존)
│   ├── CompositionController.swift 오케스트레이션 + AVPlayer + 익스포트
│   └── CompositionPlayerView.swift 전체화면 플레이어
├── Diagnostics/
│   └── ClipSpec.swift             클립 스펙 추출·대조 (UI 비의존)
└── Export/
    ├── PhotoLibrarySaver.swift    사진 앱 저장 (1-18)
    └── ClipExporter.swift         passthrough 익스포트 (1-17)
```

### 알아둘 구조적 판단

**`ClipSpec.swift` 와 `ClipComposer.swift` 에 UI 의존을 넣지 않는다.**
macOS 에서 `swiftc` 로 단독 컴파일해 돌릴 수 있어야 한다. 실제로 이 성질 덕에
"방향 섞은 병합에서 무슨 일이 일어나는가"를 기기 없이 Mac 에서 규명했다.
`CLAUDE.md` 의 `## Diagnostics` 에 제약으로 명시돼 있다.

**`RotationCoordinator` 는 `didMoveToWindow` 에서 만든다.** 조건은 소유가 아니라
레이어가 **윈도우에 붙어 있느냐**다. 안 붙어 있으면 preview 각도가 조용히 0 이 된다.
레이어에 강한 참조를 더 쥐면 증상은 같고 원인만 안 보이게 된다.

**컴포지션의 비디오·오디오 커서를 분리한다.** 하나로 통일하면 숫자는 예뻐지지만
A/V 어긋남을 관측할 수 없게 된다.

**녹화 시작 시점의 각도를 동결하고 녹화 중에는 바꾸지 않는다.** 가드가 컨트롤러와
`MovieRecorder` 양쪽에 있다. 실패하면 한 파일 안에서 방향이 섞이는데 파일에는
흔적이 남지 않는다.

**파일명은 메모리 카운터가 아니라 디스크의 최대 번호에서 이어붙인다.**
`clipCount` 로 이름을 짓다가 앱 재실행 시 충돌해 7번 중 3번의 녹화가
조용히 실패한 적이 있다(`error=Cannot Save`).

---

## 4. 도구와 명령

### 빌드·설치

`project.yml` 이 원본이다. **빌드 설정은 Xcode UI 가 아니라 `project.yml` 에서만 고친다.**

```bash
xcodegen generate

# 시뮬레이터 컴파일 확인
xcodebuild -project Mellow.xcodeproj -scheme Mellow -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build

# 실기기 컴파일만 (서명 없이)
xcodebuild -project Mellow.xcodeproj -scheme Mellow -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# 실기기 서명 빌드 — project.yml 에 팀을 넣지 않고 CLI 로만 넘긴다
xcodebuild -project Mellow.xcodeproj -scheme Mellow -sdk iphoneos \
  -destination 'id=<DEVICE_UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=T394S9X9HC -derivedDataPath <DD> build
```

`project.yml` 의 `# DEVELOPMENT_TEAM: XXXXXXXXXX` 주석은 **건드리지 않는다.**
`xcodegen generate` 마다 pbxproj 가 새로 생겨 Xcode GUI 선택이 날아가는 것은
XcodeGen 을 택한 대가로 감수하기로 했다.

### 기기 조작 (devicectl)

`xctrace` 에는 안 잡히지만 `devicectl` 로는 무선으로 접근된다.

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> <path>/Mellow.app
xcrun devicectl device uninstall app --device <UDID> com.chrisholic.mellow
xcrun devicectl device process launch --device <UDID> --console --terminate-existing com.chrisholic.mellow

# 앱 샌드박스에서 파일 꺼내기 (분석용)
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.chrisholic.mellow \
  --source Documents --destination <local>
```

`devicectl device orientation` 은 iPhone 12 가 지원하지 않는다. 물리 회전은 사람이 해야 한다.

### 진단 CLI

`ClipSpec` 은 UI 의존이 없어 macOS 에서 단독 컴파일된다.

```bash
xcrun swiftc -swift-version 5 -o clipspec Mellow/Diagnostics/ClipSpec.swift main.swift
./clipspec <file...>   # 각 파일 스펙 전문 + 2개 이상이면 compare()
```

`ClipComposer.swift` 를 함께 컴파일하면 컴포지션 조립과 이음새 진단도 Mac 에서 돌아간다.

### 콘솔 로그 접두어

|접두어|내용|
|---|---|
|`MROT`|회전 각도, KVO 콜백 카운터, 세션 상태|
|`MREC`|녹화 시작/종료, 소스 설정 스냅샷|
|`MAUD`|오디오 세션 런타임 값|
|`MSAVE`|사진 앱 저장|
|`MCOMP`|컴포지션 조립, 이음새 진단, 재생 준비 시간|
|`MEXP`|익스포트 소요·크기 비율·재인코딩 검증|

---

## 5. 방법에 대한 교훈

**판정 환경을 사용자 환경과 일치시켜야 한다.** 오디오가 먹먹하다는 문제를 Mac 에서
스펙트럼까지 재가며 쫓았는데, 아이폰 사진 앱에서 들으니 기본 카메라 앱과 차이가
없었다. 아이폰 스피커는 저역을 못 내서 iOS 가 재생 단에서 보정을 걸고 Mac 은 걸지 않는다.
**파일 스펙트럼이 다르다는 것과 사람 귀에 다르게 들린다는 것은 별개의 주장이다.**

**측정 도구를 먼저 만들면 그 뒤의 판단이 전부 빨라진다.** `ClipSpec` 을 1-8 순서보다
앞당겨 만든 덕에 1-3(스펙 고정), 1-10·1-11(회전 기록), 1-17(재인코딩 검증)이
전부 같은 도구로 확인됐다.

**증상을 덮는 코드를 넣기 전에 데이터를 모은다.** A/V drift 에 클램프를 넣지 않고
측정만 한 덕에 "구조적 누적이 아니라 반올림 잡음"이라는 결론이 나왔다.
넣었다면 존재하지 않는 문제를 위해 코드를 유지하게 됐을 것이다.

**"자연스러워 보인다"는 검증이 아니다.** 방향 섞은 병합이 화면상 자연스러워 보였지만,
렌더 프레임 크기를 재보니 뒤 클립이 강제 회전돼 있었다.

---

## 6. Phase 2 진입 시 확인할 것

1. **Swift 6 언어 모드 승격** — 지금 `SWIFT_VERSION = 5.0`.
   `@preconcurrency import AVFoundation` 과 `MovieRecorder: @unchecked Sendable` 이
   승격 시 재검토 대상이다. `CameraController` 의 `sessionQueue` 경계도 함께 본다.
2. **XcodeGen 프로젝트와 Xcode 템플릿 기본값 diff** — 결정 대기 목록 항목.
   특히 `SWIFT_DEFAULT_ACTOR_ISOLATION` / `SWIFT_APPROACHABLE_CONCURRENCY` 는
   지금 미설정이라 기본 액터 격리가 `MainActor` 가 아니다.
3. **세션 방향 3값 확정** (2-8, 2-9) — 위 "미해결" 참조.
4. **`ContentView.swift` 는 임시 호스트다.** Phase 3 에서 촬영 화면으로 교체한다.
5. **`Documents/spike/` 와 `Documents/exports/` 는 스파이크용 평면 디렉터리다.**
   Phase 2 의 `Documents/sessions/{uuid}/clips/` 로 옮겨야 한다(2-3).
6. **`.gitignore` 에 `.DS_Store` 변경이 워킹트리에 남아 있다.** 의도적으로 커밋하지 않았다.
