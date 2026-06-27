import Foundation

enum CaptureStoreError: Error {
    case write(Error)   // 저장공간 부족 등
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

    // MARK: - Private (queue에서만)

    private func persist() {
        guard let data = try? JSONEncoder().encode(captures) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([Capture].self, from: data) else { return }
        captures = decoded
    }
}
