import AVFoundation
import Foundation

/// 같은 회전각을 가진 클립 묶음.
struct ClipGroup: Identifiable {
    let rotationDegrees: Int
    let specs: [ClipSpec]

    var id: Int { rotationDegrees }
    var label: String { "\(rotationDegrees)°×\(specs.count)" }
}

/// 스파이크 클립 저장소. Documents/spike 평면 디렉터리 하나를 본다.
/// 세션 디렉터리 구조(Documents/sessions/{uuid}/clips/)는 Phase 2 다.
enum ClipLibrary {

    static func directory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("spike", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    struct ScanResult {
        var groups: [ClipGroup] = []
        /// 비디오 트랙을 읽지 못해 그룹에 넣지 못한 파일.
        var skipped: [String] = []
    }

    /// **파일명이 아니라 preferredTransform 의 회전각으로 묶는다.**
    ///
    /// 파일명에 박힌 자세는 촬영 시점의 UIDevice 값이라 실제로 기록된 transform 과
    /// 어긋날 수 있다(오염 클립이 그 경우다). 무엇보다 병합 가능 여부를 결정하는 것은
    /// transform 이지 파일명이 아니다. 묶는 기준을 판정 기준과 일치시킨다.
    static func scan() async -> ScanResult {
        let directory = directory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let movies = urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result = ScanResult()
        var buckets: [Int: [ClipSpec]] = [:]

        for url in movies {
            do {
                let spec = try await ClipSpec.load(from: url)
                guard let degrees = spec.videoRotationDegrees else {
                    result.skipped.append("\(url.lastPathComponent) (비디오 트랙 읽기 실패)")
                    continue
                }
                buckets[degrees, default: []].append(spec)
            } catch {
                result.skipped.append("\(url.lastPathComponent) (로드 실패)")
            }
        }

        result.groups = buckets
            .map { ClipGroup(rotationDegrees: $0.key, specs: $0.value) }
            .sorted { $0.rotationDegrees < $1.rotationDegrees }
        return result
    }
}
