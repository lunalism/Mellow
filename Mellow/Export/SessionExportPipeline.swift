import Foundation
import AVFoundation

// 세션 저장 파이프라인 (2-12a). URL 목록 in → 사진 앱 저장 완료 out.
//
// 1-18~1-19 에서 검증된 경로(권한 → 병합 → passthrough 익스포트 → 사진 앱
// 저장)를 그대로 쓴다. 단계별 구현은 기존 static 셋(`ClipMerger` ·
// `ClipExporter` · `PhotoLibrarySaver`)의 재사용이고, 이 파일이 새로 하는
// 일은 그 셋을 상태 없이 한 줄로 꿰는 것뿐이다.
//
// `SaveToPhotosController` 를 승격하지 않고 새로 잘랐다.
// - 그쪽은 계측 장치다. `@Published` 상태 머신 · 구간별 시간 · 라운드
//   히스토리가 본체에 얽혀 있고, 재인코딩·방향 교정 측정까지 실려 있다.
//   프로브로 남아 3-13 에서 통째로 사라진다
// - 이쪽은 값만 다룬다. SwiftData 를 모르고(import 없음) 상태를 갖지 않는다.
//   `SessionStore.close` 가 하네스에서 스텁으로 갈아끼울 수 있는 것이 이
//   성질 덕이다 — 붙박이로 넣으면 close 의 가드·실패 경로를 스텁 없이
//   검증할 수 없다 (2-8 하네스 9군이 밟았던 종류의 검증 공백)
//
// # 실패 지점별 결과는 두 케이스로 접힌다
//
// - **여기서 던진다** → 세션 무변화 + **사진 앱에 에셋 없음**
// - **여기가 성공하고 `isClosed` 기록이 실패한다** → 세션 열림 + **사진 앱에
//   에셋 있음** (재닫기 시 완성본 중복 생성 가능 — 허용. Tasks.md 2-12a AC)
//
// 앞 케이스의 근거: 에셋 생성(`PHAssetCreationRequest.forAsset()` +
// `addResource`)과 성공 판정이 **같은 `PHPhotoLibrary.performChanges` 단위**
// 안에 있다 (`PhotoLibrarySaver.save`). `performChanges` 는 던지면 그 변경
// 단위가 통째로 적용되지 않으므로, 사진 저장이 마지막 단계인 이상 "던졌는데
// 에셋이 생긴" 상태는 없다.

/// 파이프라인 자체 실패. 권한은 `PhotoLibrarySaveError.permissionDenied` 로,
/// 익스포트·사진 저장은 각자의 에러로 그대로 던진다 — 이미 분류돼 있는 것을
/// 다시 접지 않는다. 여기 있는 것은 그 사이 틈 둘뿐이다.
enum SessionExportError: Error, CustomStringConvertible {
    /// 병합이 성립하지 않았다 (`MergeReport.fatal`).
    case merge(String)
    /// 컴포지션 스냅샷을 만들지 못했다.
    case snapshot

    var description: String {
        switch self {
        case .merge(let reason):
            return "병합에 실패했습니다 — \(reason)"
        case .snapshot:
            return "컴포지션 스냅샷을 만들지 못했습니다."
        }
    }
}

enum SessionExportPipeline {

    /// 클립들을 한 편으로 만들어 사진 앱에 넣는다.
    ///
    /// `SessionStore.close` 의 기본 파이프라인이다. 입력 URL 이 비어 있지
    /// 않다는 것은 호출자(`close` 의 클립 0개 가드)가 보장한다.
    ///
    /// # tmp 잔여물은 이 함수 소유다
    ///
    /// 익스포트 출력은 tmp 의 회차별 디렉터리에 만들고, 성공·실패 불문
    /// best-effort 로 디렉터리째 지운다. `PhotoLibrarySaver.save` 가 임시
    /// 파일 소유권을 가져가므로(성공·실패 모두 파일을 지운다) 여기서 지울
    /// 것은 보통 빈 디렉터리와, 익스포트가 도중에 던졌을 때의 반쯤 쓰인
    /// 파일이다. 삭제 실패는 로그만 남긴다 — tmp 고아는 3-17 범주다.
    static func saveToPhotos(clips urls: [URL]) async throws {

        // 0) 권한 — 병합·익스포트보다 먼저 해결한다 (1-18 확정 순서).
        //    미결정 상태의 시스템 팝업 대기(실측 22.7초)가 저장 구간에 섞이면
        //    안 되고, 거부 상태라면 병합·익스포트가 통째로 헛일이기 때문이다.
        let permission = await PhotoLibrarySaver.requestPermission()
        guard permission.isAuthorized else {
            throw PhotoLibrarySaveError.permissionDenied(permission)
        }

        // 1) 병합 — 파일을 쓰지 않는다. 편집 목록을 만드는 것뿐이다.
        let merge = await ClipMerger.merge(urls)
        if let fatal = merge.fatal {
            throw SessionExportError.merge(fatal)
        }
        // AVMutableComposition 은 가변 객체다. 익스포트 중에 바뀌지 않도록
        // 스냅샷을 뜬다 (1-17과 같은 판단).
        guard let asset = merge.composition.copy() as? AVComposition else {
            throw SessionExportError.snapshot
        }

        // 2) 익스포트 — passthrough. 재인코딩 없음.
        //
        // 회차마다 디렉터리를 새로 잡는다. 같은 출력 디렉터리에 쌓으며
        // 반복하면 익스포트가 밀리는 현상이 있었다 (1-17, 원인 미특정).
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mellow-close-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch,
                                                 withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: scratch)
            } catch {
                print("[close] ✕ tmp 정리 실패 \(scratch.lastPathComponent) — \(error)."
                      + " 고아로 남으며 3-17 범주다")
            }
        }

        let output = scratch.appendingPathComponent("session.mov")
        let outcome = try await ClipExporter.export(asset,
                                                    preset: ClipExporter.passthroughPreset,
                                                    to: output,
                                                    as: .mov)

        // 3) 사진 앱 저장 — 마지막 단계다. 여기서 던지면 에셋이 없다(파일
        //    상단 주석). 복사(moveFile: false)로 확정된 경로 그대로다 —
        //    실패 시 재시도는 보관이 아니라 재익스포트로 한다.
        _ = try await PhotoLibrarySaver.save(temporaryVideoAt: outcome.outputURL,
                                             moveFile: false)
    }
}
