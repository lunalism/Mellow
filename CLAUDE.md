# 프로젝트: 멜로우 (Mellow)

10초 클립을 이어붙여 브이로그를 만드는 iOS 앱. 편집을 못하거나
귀찮아하는 사람도 "찍기만 하면 브이로그가 나오는" 경험을 목표로 한다.

## 제품 원칙
- 최상위 단위는 **세션**. 여행·나들이 같은 이벤트 하나에 10초 컷을 쌓고,
  세션을 닫으면 완성본이 나온다.
- 핵심 약속: **편집 화면을 열지 않아도 결과물이 완성된다.**
  기능 제안 시 이 약속을 해치는지 먼저 따져볼 것. 설정·옵션이 늘어나는
  방향의 제안은 기본적으로 보류한다.
- 촬영 중 사용자가 내려야 할 결정은 최소로. 자동화할 수 있으면 자동화한다.

## 기술 스택
- iOS 네이티브 / Swift / SwiftUI
- 촬영: AVFoundation (AVCaptureSession + AVCaptureMovieFileOutput)
- 편집·재생: AVMutableComposition + AVPlayer
- 내보내기: AVAssetExportSession
- 저장: 영상은 파일시스템(Documents/sessions/{uuid}/clips/),
  메타데이터는 SwiftData로 분리

## 확정된 설계 결정
- 촬영 스펙은 세션 단위로 고정. 세로 세션 1080×1920, 가로 세션 1920×1080,
  공통으로 30fps·H.264·AAC. 한 세션 안의 클립은 전부 동일 스펙이어야
  재인코딩 없는 병합이 가능하다.
- 세션 방향은 **세로/가로 2값**이며 첫 클립이 정한다. 세션 생성 시 묻지
  않고, 클립이 0개가 되면 미정으로 초기화된다.
- **계열 간(세로↔가로) 혼재는 차단한다.** 세로 세션에서 가로로 들면 녹화
  버튼이 비활성된다. 표시 규격이 1080×1920 / 1920×1080으로 달라
  맞추려면 필러박스가 생긴다.
- **계열 안의 180도 차이는 막지 않는다.** 가로 세션에서 폰을 반대로
  눕히거나 세로 세션에서 거꾸로 드는 경우다. 녹화를 허용하고, 저장
  직후 백그라운드에서 방향 교정 재인코딩(정규화)으로 세션 방향에
  맞춘다. 같은 캔버스를 정확히 채우므로 여백이 없다.
  - 사용자에게는 "가로로 돌려주세요"만 보이고 좌우는 앱이 맞춘다.
    그래서 `Orientation`이 2값으로 충분하다 — 정규화가 좌우 차이를
    흡수해 데이터에는 정방향 클립만 남는다.
  - 비용은 10초 클립 1개당 약 1.77초, 비트레이트 97.0% (iPhone 12 실측).
    확정 당시 근거였던 2.3초는 4클립 배치를 나눈 값이었고, 단독 정규화를
    따로 재니 그보다 빨랐다.
  - 정규화 구현은 Phase 2의 2-D 그룹 (2-17~2-21). 세션 방향을 정하는
    2-8과 계열 간 혼재를 막는 2-9가 선행 조건이다. 근거는 Tasks.md
    결정 대기 목록 "세션 방향 모델" 참고.
- 기기 회전에 따라 화면 구성이 바뀌는 대응은 하지 않는다.
- 미리보기는 익스포트 없이 AVMutableComposition을 AVPlayer에 직접 물려
  즉시 재생한다. 사용자에게 "합치는 중" 로딩을 보여주지 않는다.
- 내보내기는 두 경로로 나눈다.
  (1) 그냥 저장 = passthrough, 재인코딩 없음, 즉시
  (2) 꾸며서 저장 = 자막/BGM 포함, AVVideoComposition, 재인코딩 발생
- 자막은 완성본 전체에 상시 표시(좌하단 날짜, 우하단 도시).
  설계만 확정, 구현은 v0.2.
- v0.1은 iPhone 전용이다. iPad는 지원하지 않는다. 카메라를 들고 촬영하는
  제품 특성과, iPad에서 흔들리는 "첫 클립이 세션 방향을 정한다"는 설계
  전제 때문이다.
- 녹화 버튼은 **탭 방식**이다. 탭하면 시작, 10초에 자동 정지, 녹화 중
  다시 탭하면 조기 종료. 누르고 있는 방식은 폐기했다 — 10초는 손가락으로
  버티기에 길고, "언제 뗄지"를 계속 신경 쓰게 만들어 결정 최소화 원칙에
  어긋난다. 조기 종료를 남기는 이유는 없으면 모든 클립이 10초로 강제되기
  때문이다.
- 앱은 Portrait 전용으로 잠근다. 방향 감지는 `AVCaptureDevice.RotationCoordinator`가
  담당한다. 인터페이스 방향이 아니라 가속도계 기준 물리적 기기 방향을 추적하므로
  Portrait 잠금과 무관하게 동작한다.

  **실기기 실측 결과** (iPhone 12, 후면 광각, Portrait 잠금 상태.
  문서 기반 가정이 아니라 직접 측정한 값이다):

  | 기기 방향 | capture 각도 | preview 각도 |
  |---|---|---|
  | portrait | 90 | 90 |
  | landscapeLeft | 0 | 90 |
  | landscapeRight | 180 | 90 |
  | portraitUpsideDown | 270 | 90 |

  capture 각도는 기기 방향에 따라 정상적으로 변하고, preview 각도는 90으로
  고정된다. Portrait 잠금이 프리뷰 회전각을 상수로 만든다는 전제가 실측으로
  확인됐다. 네 방향 모두 확인 완료.

  각도 값을 방향 상수로 매핑하는 테이블은 만들지 않는다. 기기·카메라에 따라
  값이 다를 수 있어, 위 표는 iPhone 12 기준 참고치로만 쓴다.

## 실측 preferredTransform

녹화된 파일에 기록되는 회전 행렬. iPhone 12 실측이며, 앱을 재실행해도
같은 값이 재현된다. 8개 클립(4방향 × 짧은/긴)으로 확인했다.

| 방향 | capture | a | b | c | d | tx | ty |
|---|---|---|---|---|---|---|---|
| 세로 | 90 | 0.0 | 1.0 | -1.0 | 0.0 | 1080 | 0 |
| 거꾸로 | 270 | 0.0 | -1.0 | 1.0 | 0.0 | 0 | 1920 |
| 가로L | 0 | 1.0 | 0.0 | 0.0 | 1.0 | 0 | 0 |
| 가로R | 180 | -1.0 | 0.0 | 0.0 | -1.0 | 1920 | 1080 |

- 같은 방향이면 클립 길이와 무관하게 transform이 완전히 동일하다
  (7초 ~ 188초 확인).
- 90↔270, 0↔180은 각각 180도 회전 관계이며 **결과 표시 규격은 같다**
  (세로 계열 1080×1920, 가로 계열 1920×1080).
- 세로 계열과 가로 계열은 표시 규격 자체가 다르다.
- 이 표는 iPhone 12 기준이다. 각도→방향 매핑을 상수 테이블로
  하드코딩하지 않는다는 제약은 유지한다.

## 실기기에서 촬영한 파일 회수

앱이 임시 디렉터리에 쓴 클립을 Mac으로 가져올 수 있다.

```
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.lunalism.mellow \
  --source tmp --destination <로컬 경로>
```

Phase 1은 촬영한 클립 목록을 메모리에만 들고 있어서 앱을 재실행하면
사라진다. 이 명령은 그 제약을 우회한다 — 파일 자체는 임시 디렉터리에
남아 있으므로, 앱을 껐다 켠 뒤에도 지난 촬영분을 전부 가져올 수 있다.

용도:
- 콘솔 로그를 놓쳤을 때 파일에서 스펙·transform·duration을 되짚는다
- 병합 실험을 Mac에서 반복한다. `ClipSpec.swift`가 UIKit에 의존하지
  않으므로 `swiftc`로 바로 돌려볼 수 있다
- 실기기 촬영 한 번으로 여러 번의 실험 재료를 확보한다

Phase 2에서 파일 관리(2-3)와 SwiftData가 들어오면 앱 안에서 목록이
유지되지만, Mac에서 파일을 직접 뜯어보는 용도로는 계속 쓴다.

**Mac 검증 방식의 신뢰성 확인**: 병합 실험에서 예측한 값(10개 중 5개
어긋남, 빈 구간 5개, 총 99.585초)이 실기기 재생에서 정확히 재현됐다.
카메라가 필요 없는 검증은 Mac에서 먼저 돌리고 실기기로 확인하는 순서가
유효하다.

## 실측 성능 기준값

문서나 추정이 아니라 실기기에서 잰 값이다. 성능 논의는 여기서 출발한다.

- `AVCaptureSession.startRunning()`은 iPhone 12에서 약 **205ms** 소요.
  `stopRunning()`은 **147~158ms**. 백그라운드 체류 시간과 무관하다
  (2초 복귀와 30초 복귀의 차이가 8ms 이내).
- 이 시간은 프레임워크 내부 비용이다. 앱 코드 구간(디스패치·상태 반영)은
  전부 합쳐 1.3ms로, 최적화할 여지가 없다.
- 세션 시작 지연을 다룰 때 이 값이 기준이다. 205ms를 줄이려는 시도 대신
  그 시간 동안 무엇을 보여줄지를 다룬다.
- 재측정이 필요하면 `CaptureTrace`를 켠다. 기본은 꺼져 있고 릴리스 빌드에서는
  아예 컴파일되지 않는다. 실행 인자 `-MellowTrace`로 켠다:

  ```
  xcrun devicectl device process launch --console --terminate-existing \
    --device <UDID> com.lunalism.mellow -- -MellowTrace
  ```

  Xcode에서는 Scheme > Run > Arguments Passed On Launch에 넣는다.
  `--console`이 붙어 있어야 stdout이 보인다. 앱이 종료되면 콘솔 세션도
  끊기고, 재설치해도 끊긴다 — 그때는 다시 띄워야 한다.
- 알림 배너는 `wasInterrupted`를 발생시키지 않으며 세션도 멈추지 않는다.
  `scenePhase`는 `.active`로 재진입하지만 세션이 이미 running이라 호출이
  생략된다. `.inactive`에서 정지하지 않기로 한 결정이 실측으로 검증됨 —
  정지했다면 알림이 올 때마다 200ms 재시작이 발생했을 것이다.

**익스포트 (Mac M2)**

- passthrough는 실시간의 0.0029배, 재인코딩은 0.150배. 약 50배 차이.
- 재인코딩 출력이 원본의 68.2% 비트레이트로 떨어진다. **Mac 한정 현상이다** —
  실기기는 97.0%로 사실상 유지된다(아래). M2의 preset 동작이지 재인코딩의
  본질적 비용이 아니므로, 이 값을 근거로 `AVAssetWriter`를 꺼내지 마라.
- 성능 측정은 내부 SSD에서 한다. USB 외장은 22배 느리다.

**재인코딩은 Mac 값으로 실기기를 추정하지 마라.** 단일 10초 클립
재인코딩이 Mac M2 1553ms vs iPhone 12 **96ms**로 16배 역전된다.
passthrough는 반대로 Mac이 2.4배 빠르다(660 vs 277MB/s).
두 경로의 플랫폼 특성이 정반대이므로 비율 환산이 성립하지 않는다.

**실기기 익스포트·저장 (iPhone 12)**

- passthrough 익스포트 277MB/s. 클립 30개(300초·570MB) 저장 전체가
  중앙값 2.45초이며, 병합·익스포트·사진 앱 저장을 모두 포함한 값이다.
- 병합은 클립당 약 7.3ms로 안정적. 클립 수에 선형이다.
- **재인코딩은 경로에 따라 18~24배 갈린다.** 단순 재인코딩
  (`AVAssetExportPreset1920x1080`)은 10초 클립에 96ms(0.010배)로
  하드웨어 인코더를 타지만, `AVVideoComposition`을 붙인 방향 교정은
  단독 1770ms(18배) · 4클립 배치 클립당 2281ms(24배, 0.229배)다.
  픽셀을 다시 그려야 해서 그 경로를 못 탄다.
  **비용을 추정할 때 둘을 같은 것으로 보지 마라.**
- 재인코딩 출력 비트레이트는 원본의 97.0%. 화질은 사실상 유지된다.
- 사진 앱 저장은 570MB에 135~199ms.
- `shouldMoveFile`은 성능 차이가 없다(복사 146ms / 이동 163ms, 중앙값).
  복사(false)를 쓴다 — 실패 시 재시도 여지가 남는다.
- 익스포트 구간은 회차마다 1.8배까지 흔들린다. 사진 앱의 백그라운드
  에셋 처리와 겹치는 것이 유력한 원인이다.
- **단일 클립 방향 교정 정규화: 클립당 약 1.77초** (10초 클립 기준,
  세로·가로 동일). 1-21의 2281ms는 4클립 배치값이므로 단독 정규화
  비용으로 인용하지 마라. 고정비가 거의 없어 배치로 묶어도 이득이 없다.
  카메라 running 여부와 발열은 이 비용에 영향을 주지 않는다.
- **재인코딩 후 duration이 5980/600(9.966667s)으로 정규화된다.**
  원본 길이와 무관하게 같은 값으로 수렴하므로, 정규화한 클립의
  duration 메타데이터는 갱신해야 한다.

## SwiftData 사용 원칙

**메인 컨텍스트 전용이다 (2-2 확정).** 별도 `ModelContext`나 `ModelActor`를
만들지 않는다. 모든 읽기·쓰기는 `@Environment(\.modelContext)`로 받는
메인 컨텍스트에서 한다.

- 2-3 ~ 2-12가 전부 메인 컨텍스트로 충분하다
- 백그라운드에서 SwiftData를 쓰는 곳은 **2-18의 `Clip.duration` 갱신
  한 곳뿐**이다. 정규화가 끝난 뒤의 쓰기 한 번이라 급하지 않고 메인으로
  hop 하면 된다
- `ModelActor`를 지금 깔면 컨텍스트 간 동기화·`PersistentIdentifier`
  전달·두 컨텍스트가 같은 객체를 다르게 보는 문제가 **지금 없는 문제로
  새로 들어온다**
- 나중에 필요해지면 추가하는 것은 국소적이지만, 지금 깔았다가 걷어내는
  것은 그 위에 쌓인 2-3 ~ 2-12를 전부 건드려야 한다

`ModelContext`는 SDK에서 `@available(*, unavailable, message: "contexts
cannot be shared across concurrency contexts")`로 `Sendable`이 막혀 있다.
컨텍스트를 격리 경계 너머로 넘기는 것은 지원되지 않는 사용법이다.

**저장 위치가 갈라져 있다.**

- 메타데이터: `Library/Application Support/Mellow.store`
- 영상: `Documents/sessions/{uuid}/clips/`

## 파일 경로 규칙

**`SessionFileStore`만 세션 디렉터리 경로를 안다** (2-3). 다른 곳에서
경로를 조합하지 않는다. 2-4·2-5·2-12·2-16·2-D가 전부 이 타입을 거친다.

- **절대 경로를 저장하지 않는다.** iOS는 앱 재설치·복원 시 컨테이너 경로가
  바뀐다. 저장되는 것은 `Session.id`와 `Clip.fileName`뿐이고 절대 경로는
  매번 조합한다. 이 타입에는 경로를 **돌려주는** API만 있고 **받아 보관하는**
  API가 없다 — 규칙을 깰 표면 자체를 두지 않는다
- 루트를 주입받는다. 앱은 `SessionFileStore.shared`를 쓰고, Mac 하네스는
  임시 디렉터리를 준다. 전역 상수로 박으면 하네스가 실제 `~/Documents`를
  건드린다
- 삭제는 "이미 없음"(`false` 반환)과 실패(throw)를 구분한다
- **`sessions/`는 iCloud 백업에서 제외한다.** 완성본은 사진 앱에 저장되어
  그쪽에서 백업되고, `sessions/`는 그것을 만들기 위한 작업 파일이다.
  클립 30개가 570MB라 백업에 넣으면 사용자 iCloud 용량을 조용히 먹는다.
  **맞바꾼 것은 기기 복원 시 세션이 사라진다는 것이다.** Phase 4에서 다시 본다
- 정규화 임시 파일은 `.itemReplacementDirectory`에 만든다.
  `replaceItemAt`이 원자적이려면 같은 볼륨이어야 하기 때문이다

`Application Support`를 쓰는 이유는 스토어가 앱 내부 데이터이기 때문이다.
`Documents`는 사용자에게 보이는 자리이며 파일 공유를 켜면 노출된다.
**둘이 다른 디렉터리라는 사실이 2-16에서 중요하다** — 한쪽만 살아남는
복원이 성립하므로 고아 파일과 고아 메타데이터가 양방향으로 생길 수 있다.

`mainContext.autosaveEnabled`는 기본 `true`다(실측). 삽입·삭제가 명시적
`save()` 없이 반영된다.

## Swift 언어 모드

**언어 모드 5를 유지한다 (`SWIFT_VERSION: "5.0"`). 2-18 착수 직전에
다시 본다.**

언어 모드 6에서 깨지는 곳은 **3건 · 2파일**뿐이고 Phase 1 카메라
파이프라인은 0건이다. 그중 1건은 해소했고, 남은 2건은
`ClipNormalizeController`가 `AVComposition`을 격리 경계 너머로 보내는
문제다. **SDK 26.5에서도 `AVComposition`은 non-Sendable이라 0-4의 원인이
그대로다.** 제대로 고치려면 정규화 경로의 동시성 계약을 정해야 하는데,
그 계약의 소비자는 2-18이고 지금 정하면 3-13에서 삭제될 측정 코드에
맞춰 설계하게 된다. 자세한 근거와 실측은 Tasks.md "Swift 언어 모드
재검토 (2-2)" 참고.

## API 주의사항

**AVAssetExportSession API 현행 형태** (2026-08 확인)

- `export(to:as:)` async throws — 구 `exportAsynchronously`는 iOS 18에서 deprecated
- `determineCompatibility(ofExportPreset:with:outputFileType:)` —
  구 `exportPresets(compatibleWith:)`는 iOS 16에서 deprecated
- `states(updateInterval:)`는 iOS 18+라 배포 타깃 17에서 못 쓴다

**`AVMutableVideoComposition` 계열은 iOS 26/macOS 26에서 deprecated다.**
대체 `AVVideoComposition.Configuration`이 iOS 26+라 배포 타깃 17에서는
계속 구 API를 써야 한다. **iOS 17 타깃 컴파일 시 경고가 뜨지 않으므로
방치되기 쉽다.** v0.2 자막 구현이 이 API에 의존한다.

**SwiftData `#Predicate`는 enum을 지원하지 않는다** (2026-08, Xcode 26.6 /
SDK iOS 26.5 확인)

`Codable` enum을 `@Model` 프로퍼티로 두면 `Schema.CompositeAttribute`로
등록되고, CoreData가 그 이름으로 키패스를 찾지 못한다. SQLite 컬럼 자체는
`VARCHAR`에 평문(`"portrait"`)으로 들어가지만 조회가 안 된다.
**`Codable`을 떼는 것도 불가능하다** — `@Model` 프로퍼티는
`PersistentModel` 준수를 요구한다. 빠져나갈 구멍이 없다.

**배포 타깃 문제가 아니다.** 타깃을 26으로 올려도 동일하며 iOS 26
런타임에서 직접 확인했다.

**가장 위험한 형태**: `predicate { $0.orientation == nil }` 은
**컴파일이 깨끗하게 통과하고 런타임에 `NSInvalidArgumentException`으로
죽는다**(keypath not found). ObjC 예외라 Swift `catch`로 잡히지 않는다.
지역 변수 캡처 방식은 그나마 `SwiftDataError.unsupportedPredicate`로
던져지지만 조회가 되는 것은 아니다.

**따라서 raw value 저장이 우회안이 아니라 유일한 방법이다.**
enum은 API 표면에만 두고 저장·조회는 전부 `String`으로 한다.
predicate는 타입 안의 `static func` 팩토리로 만들어 `private` 저장
프로퍼티를 캡슐화한다. 계산 프로퍼티에 `@Transient`는 불필요하다 —
애초에 저장 대상이 아니다.

## 프로젝트 구조
- 프로젝트는 XcodeGen으로 관리한다. `project.yml`이 단일 소스다.
- `.xcodeproj`는 생성물이며 git에 없다. clone 직후 `xcodegen generate` 필수.
- `.pbxproj`를 직접 편집하지 않는다. 프로젝트 구조 변경은 `project.yml`만 고친다.
- Swift 파일을 추가한 뒤에는 `xcodegen generate`를 다시 실행한다.
- Xcode GUI에서 한 설정 변경은 다음 generate에 사라진다.
  서명(`DEVELOPMENT_TEAM`) 등 유지해야 할 설정은 `project.yml`에 기록한다.
- `Info.plist`도 `project.yml`의 `info.properties`에서 생성된다. 파일을 직접 고치지 않는다.

## 현재 개발 범위 (v0.1)
세션 생성 → 10초 촬영(자동 정지 · 마지막 컷 undo) → 순서대로 미리보기
재생 → 사진 앱에 한 편으로 저장. 여기까지만 만들고 실사용으로 검증한다.

범위 밖(나중): 자막, BGM·비트 전환, 클립 순서 변경, 주간 리캡 알림,
공유·소셜, 클라우드 백업.

## 참조 문서
- `PRD.md` — 기능 요구사항과 수용 기준. 무엇을 만들지의 기준
- `Tasks.md` — 실행 순서와 Phase별 게이트. 지금 어디까지 왔는지의 기준

## 대화 방식
- 한국어로 답한다.
- 코드는 SwiftUI + async/await 기준. 실제로 컴파일되는 수준으로 쓰고,
  빈 껍데기나 `// TODO` 로 때우지 않는다.
- AVFoundation은 버전별 API 변경이 잦으니, 최신 여부가 불확실한 API는
  추측하지 말고 확인하거나 불확실하다고 밝힌다.
- 확정된 결정과 제안을 섞어 말하지 않는다. 위 "확정된 설계 결정"을
  뒤집어야 할 이유를 발견하면 그 사실을 먼저 알린다.
- 작업 완료 시 Tasks.md의 해당 체크박스를 갱신한다.