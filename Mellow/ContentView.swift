import SwiftUI
import SwiftData
import CoreMedia
import UIKit

// 1-1 / 1-2 확인용 화면. 프리뷰와 디버그 오버레이만 있다.
// 녹화 버튼은 1-4 에서 붙인다.
struct ContentView: View {
    @StateObject private var controller = CaptureSessionController()
    @StateObject private var saver = SaveToPhotosController()
    @StateObject private var normalizer = ClipNormalizeController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPreview = false
    /// 하단 측정 버튼(1-13~1-21)을 접어 둔다. 2-A 검증에는 쓰지 않고
    /// 프리뷰만 가린다. 3-13 에서 측정 동선과 함께 통째로 사라진다.
    @State private var showingTools = false

    // 2-2 저장 확인용. 메인 컨텍스트만 쓴다 — 별도 컨텍스트를 만들지 않는다.
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.createdAt, order: .reverse) private var sessions: [Session]
    @State private var probeNote: String?

    /// **`startOrResume` 이 돌려준 세션.** 클립 저장·삭제가 전부 이것을 향한다.
    ///
    /// 예전에는 `sessions.first`(최신)를 썼는데, 그러면 **세션을 시작한 곳과
    /// 클립이 들어가는 곳이 달라질 수 있다.** 이어가기 후보에서 빠진 세션이
    /// 최신인 경우가 실제로 있다(방향이 없거나 깨진 세션). 그 상태로는 2-8이
    /// "첫 클립 저장과 방향 확정이 같은 저장 단위인가" 를 확인해도 무엇을
    /// 확인한 것인지 알 수 없다.
    ///
    /// **객체가 아니라 id 를 든다.** 저장 실패로 `rollback()` 이 돌면 인메모리
    /// 객체는 stale 로 남는다(CLAUDE.md "API 주의사항"). id 로 매번 다시 찾으면
    /// 사라진 세션은 자연히 `nil` 이 된다.
    @State private var activeSessionID: UUID?

    private var activeSession: Session? {
        activeSessionID.flatMap { id in sessions.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.setupState {
            case .configured:
                CameraPreviewView(session: controller.session) { layer in
                    controller.attach(previewLayer: layer)
                }
                .ignoresSafeArea()

            case .permissionBlocked:
                permissionMessage

            case .failed(let reason):
                message(title: "카메라를 시작할 수 없습니다", detail: reason)

            case .idle:
                ProgressView()
                    .tint(.white)
            }

            // 오버레이는 switch 밖에, **하나의 레이아웃 안에** 둔다.
            //
            // 좌상단과 우상단을 각각 `maxWidth: .infinity` 로 띄우면 둘이
            // 같은 자리를 차지해 글씨가 겹친다 (2-A 에서 드러남). 한 VStack
            // 안에 넣으면 겹칠 방법이 없고 가운데가 프리뷰로 비워진다.
            //
            // 저장 프로브가 switch 밖에 있어야 하는 이유는 그대로다 —
            // 시뮬레이터에는 카메라가 없어 setupState 가 .configured 로 가지
            // 않지만 저장 확인은 카메라와 무관해야 한다.
            VStack(spacing: 0) {
                topStrip
                Spacer(minLength: 0)
                bottomStrip
            }
        }
        .fullScreenCover(isPresented: $showingPreview) {
            PreviewScreen(urls: controller.recordedURLs) {
                showingPreview = false
            }
        }
        .task {
            // 2-A. 재실행 후 스토어와 파일이 함께 살아남았는지 이 한 줄이 판정한다.
            // 카메라 구성보다 먼저 찍는다 — 촬영 로그에 섞이면 읽기 어렵다.
            #if DEBUG
            StoreProbeLog.inventory(sessions, label: "앱 실행 직후")
            StoreProbeLog.selfTest(sessions)
            #endif

            CaptureTrace.shared.begin("최초 실행 (.task)")
            // 구성이 끝나는 시점에 세션을 시작해도 되는 상태인지 컨트롤러가 알아야 한다.
            controller.setSceneActive(scenePhase == .active)
            await controller.prepare()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                CaptureTrace.shared.begin("scenePhase → .active")
                controller.setSceneActive(true)
            case .background:
                CaptureTrace.shared.begin("scenePhase → .background")
                controller.setSceneActive(false)
            case .inactive:
                // 권한 팝업·제어 센터·알림 배너에서도 발생한다. 여기서 끄면 깜빡인다.
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - 오버레이 배치

    /// 촬영 디버그(좌)와 세션 상태(우). **HStack 이라 겹치지 않는다.**
    private var topStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            if controller.setupState == .configured {
                debugOverlay
            }
            Spacer(minLength: 0)
            sessionReadout
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// 프로브 버튼과 녹화 버튼. 측정 동선은 접혀 있다.
    private var bottomStrip: some View {
        VStack(spacing: 10) {
            probeButtons

            if showingTools, controller.setupState == .configured {
                measurementTools
            }

            if controller.setupState == .configured {
                recordButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    // MARK: - 디버그 오버레이

    // 0-6 에서 앱을 Portrait 로 잠갔다. 그 전제가 맞는지 확인하는 화면이다.
    // 폰을 눕혔을 때 capture 각도가 실제로 변하면 전제가 성립한다.
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("preview 각도", Self.describe(angle: controller.previewRotationAngle))
            row("capture 각도", Self.describe(angle: controller.captureRotationAngle))
            row("기기 방향", Self.describe(orientation: controller.deviceOrientation))
            row("세션", controller.isRunning ? "running" : "stopped")
            row("녹화", controller.isRecording ? "● recording" : "idle")
            row("클립", "\(controller.recordedURLs.count)개")
            if let outcome = controller.lastOutcome {
                row("직전", Self.describe(outcome: outcome))
            }
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 저장 확인 (2-2)

    // SwiftData 가 실제로 살아남는지 눈으로 보는 자리다. 게이트 2의
    // "앱을 강제 종료했다 켜도 세션과 클립이 그대로 남아 있다" 를 미리 본다.
    //
    // 3-13 에서 다른 측정 버튼과 함께 지운다. 그때까지 남기는 이유는
    // 2-3(파일 관리자) 이후로도 세션이 제대로 쌓이는지 확인할 자리가
    // 필요하기 때문이다. 홈 화면은 3-8 에서 만든다.
    /// 위에는 상태만 둔다. **버튼 줄이 넓어서 좌상단 디버그 패널과
    /// 겹치던 것이 겹침의 실제 원인이었다** — 버튼은 아래로 내렸다.
    private var sessionReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("세션 \(sessions.count)개")
                .font(.system(.footnote, design: .monospaced))

            // 최근 3개만. 목록 화면이 아니라 살아남았는지 보는 자리다.
            ForEach(sessions.prefix(3)) { session in
                Text(verbatim: "\(session.displayTitle) · \(session.clips.count)컷 · "
                     + Self.describe(session.orientationState)
                     + (session.isResumable ? "" : " · 이어가기 불가"))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let note = probeNote {
                Text(verbatim: note)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.8))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 210, alignment: .trailing)
    }

    private var probeButtons: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 2-6·2-7. **프로브가 자기 순서를 들고 있지 않는다** — 생성
                // 경로가 둘이 되면 실기기에서 검증한 것과 실사용이 갈린다.
                // 3-13 에서 이 버튼이 사라져도 `SessionStore` 는 남는다.
                Button {
                    do {
                        let start = try SessionStore(context: modelContext)
                            .startOrResume()
                        // 이후 클립 저장·삭제가 **이 세션**을 향한다.
                        activeSessionID = start.session.id
                        probeNote = start.isNew
                            ? "새 세션 \(start.session.displayTitle)"
                            : "이어가기 \(start.session.displayTitle)"
                              + " · \(start.session.clips.count)컷"
                        #if DEBUG
                        StoreProbeLog.started(start)
                        #endif
                    } catch {
                        probeNote = "세션 시작 실패: \(error)"
                        #if DEBUG
                        StoreProbeLog.failure("세션 시작", error)
                        #endif
                    }
                } label: {
                    pill("세션 시작")
                }

                // 2-4 확인용. **"세션 시작" 이 돌려준 세션에만 넣는다.**
                Button {
                    Task { await saveLastClipToActiveSession() }
                } label: {
                    pill("클립 저장")
                }
                .disabled(activeSession == nil || controller.recordedURLs.isEmpty)

                // 2-5 확인용. 2-11(마지막 컷 undo)이 아니다 — 여기서는
                // 진행 중 세션의 마지막 컷을 그냥 지운다.
                Button {
                    deleteLastClipOfActiveSession()
                } label: {
                    pill("컷 삭제")
                }
                .disabled(activeSession?.clips.isEmpty ?? true)
            }

            // 버튼이 다섯이 되어 한 줄에 들어가지 않는다. 파괴적인 것과
            // 읽기만 하는 것을 아래 줄로 내린다.
            HStack(spacing: 8) {
                Button {
                    for session in sessions {
                        // `try?` 로 삼키지 않는다. 프로브의 일은 어긋난 것을
                        // 드러내는 것인데, 디렉터리 삭제가 실패해도 메타데이터는
                        // 지워지므로 조용하면 고아 파일이 왜 생겼는지 알 수 없다.
                        // Codex 리뷰 ②와 같은 종류다.
                        do {
                            try SessionFileStore.shared.removeSessionDirectory(session.id)
                        } catch {
                            #if DEBUG
                            StoreProbeLog.failure(
                                "세션 디렉터리 삭제 \(session.id.uuidString)", error)
                            #endif
                        }
                        modelContext.delete(session)
                    }
                    probeNote = nil
                } label: {
                    pill("전부 삭제")
                }
                .disabled(sessions.isEmpty)

                // 2-5 의 재정렬은 **가운데를 지워야** 보인다. 위의 "컷 삭제" 는
                // 마지막 컷이라 뒤에 당길 것이 없어 order 가 그대로다.
                Button {
                    deleteMiddleClipOfActiveSession()
                } label: {
                    pill("가운데 삭제")
                }
                .disabled((activeSession?.clips.count ?? 0) < 3)

                // 2-A 계측. 지금 상태를 콘솔에 통째로 찍는다. 강제 종료 전후를
                // 같은 형식으로 비교하려고 열어뒀다. 3-13 에서 함께 지운다.
                //
                // 버튼째로 감싼다. 호출부만 비우면 릴리스에서 아무 일도
                // 일어나지 않는 버튼이 화면에 남는다.
                #if DEBUG
                Button {
                    StoreProbeLog.inventory(sessions, label: "버튼 요청")
                } label: {
                    pill("재고")
                }
                #endif

                // Phase 1 측정 동선은 접어 둔다. 2-A 에 쓰지 않으면서
                // 프리뷰를 통째로 가린다.
                Button {
                    showingTools.toggle()
                } label: {
                    pill(showingTools ? "도구 ▾" : "도구 ▸")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 마지막으로 찍은 클립을 **진행 중 세션**에 저장한다 (2-4 확인용).
    ///
    /// **`startOrResume` 이 돌려준 세션에 넣는다.** 최신 세션이 아니다 —
    /// 둘이 다를 수 있고, 다르면 2-8 이 무엇을 확인한 것인지 알 수 없다.
    ///
    /// **duration 은 파일에서 읽는다.** 버튼을 누른 시간이 아니다 (1-7).
    /// 1초 미만 폐기는 컨트롤러가 이미 걸러내므로 여기까지 오지 않는다.
    ///
    /// # 방향도 같은 `spec` 에서 나온다 (2-8)
    ///
    /// `duration` 을 얻으려고 이미 `ClipSpec.load` 를 `await` 하고 있으므로
    /// **방향 판정에 드는 추가 파일 I/O 가 없다.** 판정을 여기(async)에서
    /// 끝내고 `alsoApply` 에는 **값만** 넘긴다 — `ClipStore` 는 동기이고
    /// `@MainActor` 라 그 안에서 파일을 읽을 수 없다.
    ///
    /// **`captureRotationAngle` 을 쓰지 않는다.** 그것은 *지금* 각도이고,
    /// 녹화와 이 버튼 사이에 임의의 시간과 회전이 끼어든다. 클립별 방향의
    /// 진실은 파일에 기록된 `preferredTransform` 뿐이다.
    ///
    /// 계열 불일치(세로 세션에 가로 클립) 차단은 **여기 없다.** 2-9 의 몫이며
    /// 그때까지 열려 있는 알려진 갭이다.
    private func saveLastClipToActiveSession() async {
        guard let session = activeSession,
              let source = controller.recordedURLs.last else { return }
        do {
            let spec = try await ClipSpec.load(from: source)

            // 방향을 못 정하면 **저장하지 않는다.**
            //
            // 방향 없이 클립만 넣으면 세션이 `.missing` 이 되는데, 2-1 은 그
            // 상태를 "값이 있었는데 사라진 손상" 으로 정의했다. 정상 경로가
            // `.missing` 을 만들면 그 정의가 거짓이 되고 2-16 이 손상과
            // 정상을 가릴 수 없게 된다. 비디오 트랙이 없는 파일은 애초에
            // 병합·재생이 성립하지 않으므로 메타데이터만 남기는 쪽이 더 나쁘다.
            //
            // **파일은 지우지 않고 `forgetRecorded` 도 부르지 않는다.**
            // "어느 경우에도 녹화본을 지우지 않는다"가 계약이고, 목록에
            // 남겨둬야 재시도 여지가 있다.
            guard let video = spec.video else {
                probeNote = "저장 거부: 비디오 트랙 없음 — 파일은 남겨둔다"
                print("[clip] ✕ 저장 거부 \(source.lastPathComponent)"
                      + " — 비디오 트랙이 없다. 파일은 지우지 않는다")
                return
            }
            guard let orientation = video.orientation else {
                probeNote = "저장 거부: 방향 판정 불가 — 파일은 남겨둔다"
                print("[clip] ✕ 저장 거부 \(source.lastPathComponent)"
                      + " — 렌더 규격이 정사각이라 방향을 정할 수 없다."
                      + " 파일은 지우지 않는다")
                return
            }

            // **이번 호출이 실제로 방향을 정했는지**를 들고 있어야 한다.
            // 두 번째 이후 클립은 `.decided` 라 `false` 가 나오고 그것이
            // 정상이다. 저장이 실패했을 때 그 경우까지 되돌리면 **남의
            // 결정을 지운다** — 이미 스토어에 있던 방향이 사라진다.
            var decided = false
            #if DEBUG
            // 2-8. 이 클립에서 도출한 방향. 두 번째 이후 클립은 가드에 막혀
            // 세션 방향을 바꾸지 않으므로, 이 줄이 없으면 도출이 틀려도
            // "세션 방향 유지 ✓" 로 통과해 버린다.
            print("[probe]   도출 방향=\(orientation.rawValue)"
                  + "  transform=\(ClipSpec.describe(transform: video.preferredTransform))")
            #endif
            let clip = try ClipStore(context: modelContext)
                .save(clipAt: source,
                      duration: CMTimeGetSeconds(spec.duration),
                      to: session,
                      alsoApply: { decided = $0.decideOrientation(orientation) },
                      revertOnFailure: { if decided { $0.undoOrientationDecision() } })
            #if DEBUG
            StoreProbeLog.savedClip(clip, in: session, from: source)
            #endif
            controller.forgetRecorded(source)
            probeNote = String(format: "저장 order=%d %.3fs", clip.order, clip.duration)
                + (decided ? " · 방향 확정 \(orientation.rawValue)"
                           : " · 방향 유지 \(Self.describe(session.orientationState))")
        } catch {
            probeNote = "저장 실패: \(error)"
            #if DEBUG
            StoreProbeLog.failure("클립 저장", error)
            #endif
        }
    }

    /// 진행 중 세션의 마지막 컷을 지운다 (2-5 확인용).
    ///
    /// 방향 초기화는 하지 않는다 — `sessionBecameEmpty` 를 받아 표시만 하고,
    /// 실제 초기화는 2-10 의 몫이다.
    private func deleteLastClipOfActiveSession() {
        guard let session = activeSession,
              let clip = session.orderedClips.last else { return }
        // 삭제 후에는 `clip` 을 읽지 않는다. 이름은 지우기 전에 챙긴다.
        #if DEBUG
        let fileName = clip.fileName
        #endif
        do {
            let result = try ClipStore(context: modelContext).delete(clip)
            probeNote = "삭제 남은 \(result.remainingCount)컷"
                + " 파일=\(result.fileRemoved ? "지움" : "없었음")"
                + (result.sessionBecameEmpty ? " · 비었음(2-10 대상)" : "")
            #if DEBUG
            StoreProbeLog.deletedClip(fileName: fileName, in: session, result: result)
            #endif
        } catch {
            probeNote = "삭제 실패: \(error)"
            #if DEBUG
            StoreProbeLog.failure("클립 삭제", error)
            #endif
        }
    }

    /// 진행 중 세션의 **가운데** 컷을 지운다 (2-5 재정렬 확인용).
    ///
    /// 마지막 컷 삭제는 뒤에 당길 것이 없어 `order` 가 그대로다. 재정렬이
    /// 실제로 도는지 보려면 뒤에 컷이 남아 있는 자리를 지워야 한다.
    private func deleteMiddleClipOfActiveSession() {
        guard let session = activeSession else { return }
        let ordered = session.orderedClips
        guard ordered.count >= 3 else { return }
        let clip = ordered[ordered.count / 2]

        #if DEBUG
        let fileName = clip.fileName
        print("[probe] 삭제 전 order 목록 = "
              + ordered.map { "\($0.order)" }.joined(separator: ","))
        #endif

        do {
            let result = try ClipStore(context: modelContext).delete(clip)
            probeNote = "가운데 삭제 남은 \(result.remainingCount)컷"
            #if DEBUG
            StoreProbeLog.deletedClip(fileName: fileName, in: session, result: result)
            #endif
        } catch {
            probeNote = "삭제 실패: \(error)"
            #if DEBUG
            StoreProbeLog.failure("가운데 삭제", error)
            #endif
        }
    }

    private static func describe(_ state: Session.OrientationState) -> String {
        switch state {
        case .unset: return "미정"
        case .missing: return "방향 없음(손상)"
        case .decided(let orientation): return orientation.rawValue
        case .corrupted(let raw): return "손상(\(raw))"
        }
    }

    // MARK: - 임시 컨트롤

    // Phase 1 확인용. UI 는 3-3 에서 제대로 만든다.
    //
    // **2-A 에서는 접어 둔다.** 이 줄들이 프리뷰를 거의 다 가려서 무엇을
    // 찍는지 볼 수 없다. "도구" 버튼으로 펼친다.
    private var measurementTools: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    Task { await controller.reportRecordedComparison() }
                } label: {
                    pill("전체 비교 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty)

                // 1-13 확인용 임시 동선. 제대로 된 화면은 3-12 에서 만든다.
                Button {
                    showingPreview = true
                } label: {
                    pill("미리보기 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty)
            }

            saveControls
            normalizeControls
        }
    }

    /// 탭하면 녹화 시작, 10초에 자동 정지, 그전에 끊고 싶으면 다시 탭 (1-6).
    ///
    /// 뷰에는 녹화 상태를 두지 않는다. 시작/정지 판단은 전부 컨트롤러의
    /// 의도가 하고, 여기서는 탭이 일어났다는 사실만 넘긴다.
    private var recordButton: some View {
        Button {
            controller.toggleRecording()
        } label: {
            Circle()
                .fill(controller.isRecordingRequested ? .red : .white)
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
        }
    }

    // MARK: - 사진 앱 저장 (1-18)

    // 1-18 확인용 임시 동선. 저장 화면은 3-13 에서 만든다.
    //
    // "파일 이동" 토글은 UI 가 아니라 계측 장치다. shouldMoveFile 을 켜고 끈 값을
    // 실기기에서 둘 다 재려고 열어뒀다. 판단이 끝나면 지운다.
    private var saveControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task { await saver.save(clips: controller.recordedURLs) }
                } label: {
                    pill("사진 앱에 저장 (\(controller.recordedURLs.count))")
                }
                .disabled(controller.recordedURLs.isEmpty || saver.state.isBusy)

                Button {
                    saver.moveFile.toggle()
                } label: {
                    pill(saver.moveFile ? "이동" : "복사")
                }
                .disabled(saver.state.isBusy)

                // 1-19 준비. 세션 방향 모델 선택지 (c) 판단에 이 값이 필요하다.
                // 사진 앱에 넣지 않고 재인코딩 비용만 잰다.
                Button {
                    Task { await saver.reencodeLastClip(controller.recordedURLs) }
                } label: {
                    pill("재인코딩 1개")
                }
                .disabled(controller.recordedURLs.isEmpty || saver.state.isBusy)

                // 1-21. 방향이 섞인 클립을 하나의 캔버스에 정방향으로 세운다.
                // 결과는 사진 앱에 넣는다 — 정방향인지는 눈으로 봐야 한다.
                Button {
                    Task { await saver.fixOrientationAndSave(clips: controller.recordedURLs) }
                } label: {
                    pill("방향 교정")
                }
                .disabled(controller.recordedURLs.count < 2 || saver.state.isBusy)
            }

            // 진행 중 / 완료 / 실패를 한 줄로. 실패 사유는 줄여 쓰지 않는다.
            Group {
                switch saver.state {
                case .idle:
                    if !saver.permission.isAuthorized && saver.permission != .undetermined {
                        Text(Self.describe(photoPermission: saver.permission))
                            .foregroundStyle(.orange)
                    }
                case .askingPermission, .merging, .exporting, .saving,
                     .reencoding, .fixingOrientation:
                    Text("\(saver.state.label)…  \(saver.timings.summary)")
                        .foregroundStyle(.white)
                case .saved(let timings):
                    Text("✓ 저장 완료  \(timings.summary)")
                        .foregroundStyle(.green)
                case .reencoded(let measurement):
                    Text("✓ 재인코딩  \(measurement.summary)")
                        .foregroundStyle(.green)
                case .orientationFixed(let measurement):
                    Text("✓ 방향 교정  \(measurement.summary)"
                         + (measurement.canvasMismatches == 0 ? "  여백 없음"
                            : "  ← 여백 \(measurement.canvasMismatches)개"))
                        .foregroundStyle(measurement.canvasMismatches == 0 ? .green : .orange)
                case .failed(let message):
                    Text("✕ \(message)")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)

            // 회차별로 느려지는지 눈으로 본다 (1-19). 형식은 병합/익스포트/저장=합계.
            if !saver.roundHistory.isEmpty {
                Text(saver.roundHistory.suffix(6).joined(separator: "  "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 단일 클립 정규화 측정 (B 라운드)

    // 1-21 의 클립당 2281ms 는 4클립을 한 번에 교정한 값을 나눈 것이라
    // 낙관적 하한이다. 실제 시나리오는 클립 하나가 단독으로, 카메라가 도는
    // 상태에서 정규화되는 것이다. 그 값을 재는 임시 동선이며 3-13 에서 지운다.
    //
    // "카메라" 버튼은 UI 가 아니라 측정 조건 스위치다. 세션을 멈춘 채로
    // 재면 B-1, 프리뷰가 살아 있는 채로 재면 B-2 다.
    private var normalizeControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 녹화 중에는 누를 수 없다. 컨트롤러는 세션을 멈추기 전에
                // stopRecording() 을 먼저 부르도록 요구하는데(setSceneActive 참고),
                // 여기서 stop() 을 바로 부르면 그 순서를 건너뛰어 녹화 중이던
                // 파일이 온전하지 않게 된다. 순서를 흉내내는 대신 상황 자체를
                // 막는다 — stopRecording() 은 비동기라 같은 큐에 stop() 을 바로
                // 얹으면 파일 마무리 전에 세션이 멈출 수 있고(2-15), 3-13 에서
                // 지울 측정 버튼 때문에 그 경로를 한 군데 더 늘릴 이유가 없다.
                //
                // isRecording 과 의도를 함께 본다. 탭 직후 콜백이 오기 전
                // (.starting) 구간은 isRecording 이 아직 false 다.
                Button {
                    if controller.isRunning { controller.stop() } else { controller.start() }
                } label: {
                    pill(controller.isRunning ? "카메라 정지" : "카메라 시작")
                }
                .disabled(normalizer.state.isBusy
                          || controller.isRecording
                          || controller.isRecordingRequested)

                // B-1 / B-2. 마지막 클립 하나를 3회 정규화한다.
                Button {
                    Task {
                        await normalizer.measureRepeat(controller.recordedURLs,
                                                       cameraRunning: controller.isRunning)
                    }
                } label: {
                    pill("정규화 ×3")
                }
                .disabled(controller.recordedURLs.isEmpty || normalizer.state.isBusy)

                // B-3. 마지막 4개를 연속으로. 발열 추이를 본다.
                Button {
                    Task {
                        await normalizer.measureSequence(controller.recordedURLs,
                                                         cameraRunning: controller.isRunning)
                    }
                } label: {
                    pill("연속 4개")
                }
                .disabled(controller.recordedURLs.count < 4 || normalizer.state.isBusy)

                // B-5. 교체가 성립하는지, 실패 시 원본이 살아남는지.
                Button {
                    Task { await normalizer.checkReplace(controller.recordedURLs) }
                } label: {
                    pill("교체 확인")
                }
                .disabled(controller.recordedURLs.isEmpty || normalizer.state.isBusy)

                // 조건을 바꿔 처음부터 다시 잴 때. 앱을 재실행하지 않고
                // 세로 다음 가로를 재는 경우가 있다.
                Button {
                    normalizer.clearHistory()
                } label: {
                    pill("기록 지우기")
                }
                .disabled(normalizer.history.isEmpty || normalizer.state.isBusy)
            }

            Group {
                switch normalizer.state {
                case .idle:
                    EmptyView()
                case .running(let label):
                    Text("\(label)…").foregroundStyle(.white)
                case .done(let summary):
                    Text("✓ \(summary)").foregroundStyle(.green)
                case .failed(let message):
                    Text("✕ \(message)").foregroundStyle(.red)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)

            // 조건을 바꿔가며 연달아 재는 화면이다. 직전 값을 덮어쓰면 콘솔을
            // 놓쳤을 때 앞 조건이 통째로 사라지므로 실행 내내 쌓아서 보여준다.
            if !normalizer.history.isEmpty {
                Text(normalizer.history.suffix(16).joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if !normalizer.replaceReport.isEmpty {
                Text(normalizer.replaceReport.joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// 사진 앱 권한 안내. 설정 앱으로 보내는 버튼은 2-13 에서 붙인다.
    private static func describe(photoPermission state: PermissionState) -> String {
        switch state {
        case .authorized:
            return ""
        case .undetermined:
            return "사진 앱 권한이 아직 결정되지 않았습니다."
        case .denied:
            return "사진 앱 접근이 거부되어 있습니다. 설정 > Mellow 에서 '사진 추가만'을 허용해 주세요."
        case .restricted:
            return "사진 앱 접근이 기기 정책으로 제한되어 있습니다."
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 92, alignment: .leading)
            Text(value)
        }
    }

    /// 각도는 가공하지 않고 원본 값을 그대로 보여준다.
    private static func describe(angle: CGFloat?) -> String {
        guard let angle else { return "—" }
        return "\(angle)"
    }

    /// 폐기된 경우가 조용히 묻히지 않도록 직전 결말을 그대로 보여준다.
    private static func describe(outcome: CaptureSessionController.ClipOutcome) -> String {
        switch outcome {
        case let .saved(seconds, hitLimit):
            return String(format: "저장 %.2fs", seconds) + (hitLimit ? " (10초 자동정지)" : "")
        case let .discarded(seconds):
            return String(format: "⌫ 폐기 %.2fs (1초 미만)", seconds)
        case let .failed(message):
            return "✕ \(message)"
        }
    }

    private static func describe(orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .unknown: return "unknown"
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        @unknown default: return "unknown(\(orientation.rawValue))"
        }
    }

    // MARK: - 권한 안내

    // 거부·제한 상태에서는 안내만 한다. 설정 앱으로 보내는 버튼은 2-13 에서 붙인다.
    private var permissionMessage: some View {
        let camera = controller.cameraPermission
        let microphone = controller.microphonePermission

        return message(
            title: "촬영 권한이 필요합니다",
            detail: [Self.describe(permission: camera, name: "카메라"),
                     Self.describe(permission: microphone, name: "마이크")]
                .compactMap { $0 }
                .joined(separator: "\n")
        )
    }

    private static func describe(permission: PermissionState, name: String) -> String? {
        switch permission {
        case .authorized:
            return nil
        case .undetermined:
            return "\(name) 권한이 아직 결정되지 않았습니다."
        case .denied:
            return "\(name) 권한이 거부되어 있습니다."
        case .restricted:
            return "\(name) 사용이 기기 정책으로 제한되어 있습니다."
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}
