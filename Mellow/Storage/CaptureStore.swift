import Foundation

enum CaptureStoreError: Error {
    case write(Error)    // 저장공간 부족 등
    case delete(Error)   // 메타데이터 영속화 실패 (삭제 롤백됨)
}

/// 로컬 캡처 저장소 (Phase 1 Spec §8). 원본 JPEG는 파일로, 메타데이터는 JSON으로.
///
/// 앱 샌드박스 `Documents/Originals/`에 원본을, `Documents/captures.json`에 기록을 둔다.
/// 앱 재실행 시 JSON에서 복원되어 캡처가 유지된다.
///
/// TODO(후속 단계 — 지금 구현 금지): iOS 사진 보관함으로 **익스포트**는 별도의 **옵트인**
///   액션으로 추가한다(`NSPhotoLibraryAddUsageDescription` 필요, PHPhotoLibrary로 저장).
///   현재 저장은 **앱 샌드박스 전용**으로 유지 — 사진 앱에 자동 기록하지 않는다.
final class CaptureStore {
    static let shared = CaptureStore()

    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "com.chrisholic.mellow.capturestore")
    private(set) var captures: [Capture] = []

    private var documents: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var originalsDir: URL { documents.appendingPathComponent("Originals", isDirectory: true) }
    private var metadataURL: URL { documents.appendingPathComponent("captures.json") }

    private init() {
        try? fm.createDirectory(at: originalsDir, withIntermediateDirectories: true)
        load()
    }

    /// 캡처의 원본 파일 URL(상대 파일명으로부터 복원).
    func url(for capture: Capture) -> URL {
        originalsDir.appendingPathComponent(capture.originalFilename)
    }

    /// 가장 최근 캡처(없으면 nil). 큐에서 읽어 save와의 경쟁을 피한다(스레드 안전).
    var latest: Capture? { queue.sync { captures.first } }

    /// 전체 캡처 스냅샷, **최신순**(Stage 4b-2 갤러리 단일 데이터 소스). 큐에서 읽어 스레드 안전.
    var allNewestFirst: [Capture] { queue.sync { captures.sorted { $0.createdAt > $1.createdAt } } }

    /// 원본 JPEG를 저장하고 메타데이터를 영속화. 저장공간 부족 등으로 쓰기 실패 시 throw.
    @discardableResult
    func save(imageData: Data, filterID: String, ratio: AspectRatio, createdAt: Date) throws -> Capture {
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        let fileURL = originalsDir.appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            throw CaptureStoreError.write(error)
        }

        let capture = Capture(id: id,
                              type: .photo,
                              originalFilename: filename,
                              filterID: filterID,
                              ratio: ratio,
                              createdAt: createdAt)
        queue.sync {
            captures.insert(capture, at: 0)   // 최신순
            persist()
        }
        return capture
    }

    /// 캡처 1장 삭제 (Stage 4c). 멀티 삭제와 **하나의 알고리즘**을 쓰도록 `deleteMany`에 위임한다.
    @discardableResult
    func delete(_ capture: Capture) throws -> [Capture] {
        try deleteMany([capture.id])
    }

    /// 캡처 여러 장 일괄 삭제 (Stage 2a 그리드 멀티 삭제). 비파괴 스토어 무결성상 **레코드 + 파일
    /// 둘 다** 지워야 하며, 어느 한쪽만 남는 일(고스트 레코드 / 오펀 파일)이 없어야 한다.
    ///
    /// 평면 파일+JSON 스토어라 진짜 트랜잭션은 불가능하므로 **레코드 우선**으로 지운다:
    /// 1) 메모리에서 선택분 모두 제거 → captures.json을 **한 번만** 원자적으로 다시 쓴다(배치 일관성).
    ///    실패하면 메모리 상태를 **전체 롤백하고 throw** → 아무것도 안 지워진 일관 상태(UI가 에러 표시).
    /// 2) 레코드가 디스크에서 확실히 사라진 뒤에만 원본 파일들을 제거(이미 없으면 성공으로 간주).
    /// 이 순서라 **고스트 레코드는 절대 생기지 않는다**(이웃 열기 시 빈 화면/크래시 방지).
    /// 잔여 위험은 오직 "JSON은 썼는데 우리 샌드박스 파일 제거가 throw"라는 사실상 불가능한
    /// 경우의 오펀 파일뿐 — 보이지 않고 추후 정리 가능. 삭제 후 최신순 스냅샷을 돌려준다.
    @discardableResult
    func deleteMany(_ ids: Set<UUID>) throws -> [Capture] {
        try queue.sync {
            let removed = captures.filter { ids.contains($0.id) }
            guard !removed.isEmpty else { return captures.sorted { $0.createdAt > $1.createdAt } }
            let snapshot = captures
            captures.removeAll { ids.contains($0.id) }
            do {
                try persistThrowing()                     // 단 한 번의 원자적 쓰기(배치 전부 or 전무)
            } catch {
                captures = snapshot                       // 전체 롤백 → 일관 상태(미삭제)
                throw CaptureStoreError.delete(error)
            }
            // 레코드는 확정 삭제됨. 이제 파일들 제거(베스트 에포트) — 실패해도 고스트는 불가.
            for cap in removed {
                let fileURL = originalsDir.appendingPathComponent(cap.originalFilename)
                if fm.fileExists(atPath: fileURL.path) {
                    try? fm.removeItem(at: fileURL)
                }
            }
            return captures.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Private (queue에서만)

    private func persist() {
        try? persistThrowing()
    }

    /// captures.json 원자적 쓰기. 삭제 경로는 실패를 감지해야 하므로 throw 버전을 쓴다.
    private func persistThrowing() throws {
        let data = try JSONEncoder().encode(captures)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([Capture].self, from: data) else { return }
        captures = decoded
    }
}
