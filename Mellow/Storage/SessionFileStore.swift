import Foundation

// 세션 영상 파일의 **유일한 경로 소유자** (2-3).
//
// 다른 곳에서 세션 디렉터리 경로를 조합하지 않는다. 2-4(클립 저장) ·
// 2-5(클립 삭제) · 2-12(세션 삭제) · 2-16(정합성 복구) · 2-D(정규화)가
// 전부 여기를 거친다.
//
// UIKit·SwiftData 에 의존하지 않는다. `ClipSpec` / `ClipMerger` 와 같은
// 제약이며, Mac 에서 swiftc 로 단독 실행할 수 있어야 실기기 왕복 없이
// 경로·삭제·목록을 반복해서 확인할 수 있다.
//
// **`Session` / `Clip` 객체가 아니라 `UUID` 와 파일명을 받는다.** 파일시스템만
// 다루는 타입이 SwiftData 모델을 알 이유가 없고, `@Model` 객체는 메인
// 컨텍스트에 묶여 있어 인자로 돌리면 격리 문제를 이 층까지 끌고 온다.
//
// **루트를 주입받는다.** 앱은 `.shared`(= `Documents/`)를 쓰고, 확인용
// 하네스는 임시 디렉터리를 준다. 전역 상수로 박아두면 Mac 에서 돌릴 때
// 사용자의 실제 `~/Documents` 를 건드리게 된다.

// MARK: - 실패 분류

/// 파일시스템 실패. **호출부가 구분해야 하는 것만 케이스로 둔다.**
enum SessionFileError: Error, CustomStringConvertible {
    /// 저장 공간 부족. **2-14가 이걸 구분해야 한다** — 나머지와 뭉뚱그리면
    /// "공간을 비우세요" 를 말할 근거가 사라진다.
    case outOfSpace
    /// 읽기·쓰기 권한 거부.
    case notPermitted
    /// 그 밖의 실패. 원인을 그대로 들고 간다.
    case failed(underlying: Error)

    var description: String {
        switch self {
        case .outOfSpace:
            return "저장 공간이 부족합니다"
        case .notPermitted:
            return "파일에 접근할 수 없습니다"
        case .failed(let underlying):
            return "파일 작업에 실패했습니다 — \(underlying)"
        }
    }

    /// `NSError` 를 위 세 가지로 접는다. 코드 대조는 여기 한 곳에만 둔다.
    static func mapping(_ error: Error) -> SessionFileError {
        if let already = error as? SessionFileError { return already }
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
             (NSPOSIXErrorDomain, Int(ENOSPC)):
            return .outOfSpace
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSCocoaErrorDomain, NSFileReadNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)),
             (NSPOSIXErrorDomain, Int(EPERM)):
            return .notPermitted
        default:
            return .failed(underlying: error)
        }
    }
}

// MARK: - 경로와 디렉터리

struct SessionFileStore {

    /// 앱이 쓰는 인스턴스. 영상은 `Documents/sessions/` 아래에 쌓인다.
    static let shared = SessionFileStore(documentsDirectory: URL.documentsDirectory)

    /// 이 저장소의 뿌리. 보통 `Documents/`.
    let documentsDirectory: URL

    // MARK: 경로 조합
    //
    // **절대 경로를 저장하지 않는다** (PRD 7장). iOS 는 앱 재설치·복원 시
    // 컨테이너 경로가 바뀐다. 그래서 이 타입에는 경로를 **돌려주는** API 만
    // 있고 경로를 **받아 보관하는** API 가 없다. 저장되는 것은
    // `Session.id` 와 `Clip.fileName` 뿐이며 절대 경로는 매번 조합한다.

    /// 모든 세션 디렉터리의 부모. `Documents/sessions/`
    var sessionsRoot: URL {
        documentsDirectory.appending(path: "sessions", directoryHint: .isDirectory)
    }

    /// `Documents/sessions/{id}/`
    func sessionDirectory(_ id: UUID) -> URL {
        sessionsRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// `Documents/sessions/{id}/clips/`
    func clipsDirectory(_ id: UUID) -> URL {
        sessionDirectory(id).appending(path: "clips", directoryHint: .isDirectory)
    }

    /// `Documents/sessions/{id}/clips/{fileName}`
    ///
    /// **디렉터리가 없어도 조합만 한다.** 존재 여부는 확인하지 않으며
    /// 이 호출은 실패하지 않는다 — 없는 파일의 경로를 물어보는 것은
    /// 2-16 이 늘 하는 일이다.
    func clipURL(fileName: String, in id: UUID) -> URL {
        clipsDirectory(id).appending(path: fileName, directoryHint: .notDirectory)
    }

    // MARK: 생성

    /// 세션 디렉터리를 `clips/` 까지 만든다. 이미 있으면 아무 일도 하지 않는다.
    ///
    /// **메타데이터보다 먼저 성공해야 한다.** 디렉터리 없이 `Session` 만
    /// 만들어지면 클립을 쓸 자리가 없는 세션이 남는다 (2-6).
    @discardableResult
    func createSessionDirectory(_ id: UUID) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: clipsDirectory(id),
                                                    withIntermediateDirectories: true)
            try excludeSessionsRootFromBackup()
            return sessionDirectory(id)
        } catch {
            throw SessionFileError.mapping(error)
        }
    }

    // MARK: 들이기

    /// 밖에서 만들어진 파일을 세션으로 들인다. **이동이다.**
    ///
    /// 녹화가 끝난 파일은 `temporaryDirectory` 에 있다. 목적지와 같은 볼륨
    /// (둘 다 앱 컨테이너)이라 이동은 rename 이고 디스크를 두 배로 쓰지 않는다.
    /// 순서와 근거는 `ClipStore.save(clipAt:...)` 참고 (2-4).
    ///
    /// **실패하면 원본은 제자리에 남는다.** `moveItem` 이 원본을 건드리기
    /// 전에 실패하므로 재시도 여지가 그대로다.
    ///
    /// 목적지 디렉터리가 없으면 만든다. 2-6 이 세션을 만들 때 이미 있지만
    /// 지워졌을 가능성이 있어 보장하고 간다.
    ///
    /// - Note: 목적지에 같은 이름이 이미 있으면 실패한다. 조용히 덮어쓰지
    ///   않는다 — 클립 파일명은 클립 id 에서 나오므로 겹치면 그것 자체가
    ///   버그다 (2-4).
    func adopt(fileAt source: URL, as fileName: String, in id: UUID) throws {
        do {
            try FileManager.default.createDirectory(at: clipsDirectory(id),
                                                    withIntermediateDirectories: true)
            try excludeSessionsRootFromBackup()
            try FileManager.default.moveItem(at: source,
                                             to: clipURL(fileName: fileName, in: id))
        } catch {
            throw SessionFileError.mapping(error)
        }
    }

    // MARK: 삭제

    /// 세션 디렉터리를 통째로 지운다 (2-12).
    ///
    /// - Returns: 실제로 지웠으면 `true`, **이미 없었으면 `false`.**
    ///   없는 것을 지우려 한 것은 실패가 아니다 — 2-16 이 메타데이터만 남은
    ///   세션을 정리할 때 정상적으로 밟는 경로다. 진짜 실패만 throw 한다.
    @discardableResult
    func removeSessionDirectory(_ id: UUID) throws -> Bool {
        try remove(sessionDirectory(id))
    }

    /// 클립 파일 하나를 지운다 (2-5).
    ///
    /// - Returns: 실제로 지웠으면 `true`, 이미 없었으면 `false`.
    @discardableResult
    func removeClip(fileName: String, in id: UUID) throws -> Bool {
        try remove(clipURL(fileName: fileName, in: id))
    }

    /// 임시 디렉터리를 지운다 (2-18). 이미 없으면 `false`.
    @discardableResult
    func removeScratchDirectory(at url: URL) throws -> Bool {
        try remove(url)
    }

    private func remove(_ url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            throw SessionFileError.mapping(error)
        }
    }

    // MARK: 목록

    /// 세션 디렉터리에 **실제로 있는** 클립 파일명.
    ///
    /// 2-16 의 고아 파일 정리에 필요하다. 메타데이터에 없는 파일을 찾으려면
    /// 파일시스템 쪽 목록이 있어야 한다. 정리 자체는 여기서 하지 않는다.
    ///
    /// **디렉터리가 없으면 빈 배열이다.** 그것이 2-16 에게는 "파일이 하나도
    /// 없다" 와 같은 뜻이고, 메타데이터만 남은 세션에서 정상적으로 나오는
    /// 상태다. 권한 문제 같은 진짜 실패는 그대로 throw 된다.
    func clipFileNames(in id: UUID) throws -> [String] {
        try names(in: clipsDirectory(id))
            .filter { fileName in
                let url = clipURL(fileName: fileName, in: id)
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
    }

    /// `sessions/` 아래에 **실제로 있는** 세션 디렉터리의 id.
    ///
    /// 2-16 이 메타데이터에 없는 세션 디렉터리를 찾는 데 쓴다.
    /// 이름이 UUID 로 읽히지 않는 디렉터리는 우리가 만든 것이 아니므로 건너뛴다.
    func sessionIDs() throws -> [UUID] {
        try names(in: sessionsRoot).compactMap(UUID.init(uuidString:))
    }

    private func names(in directory: URL) throws -> [String] {
        do {
            return try FileManager.default
                .contentsOfDirectory(at: directory,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
                .map(\.lastPathComponent)
                .sorted()
        } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileReadNoSuchFileError {
            return []
        } catch {
            throw SessionFileError.mapping(error)
        }
    }

    // MARK: 정규화용 임시 자리 (2-18)

    /// 정규화 결과를 쓸 임시 디렉터리.
    ///
    /// **`replaceItemAt` 이 원자적이려면 교체 대상과 같은 볼륨이어야 한다.**
    /// 볼륨이 다르면 rename 이 아니라 복사 후 삭제가 되어 중간 상태가 생긴다.
    /// 2-18 은 "교체 중 죽어도 파일은 원본이거나 교정본이거나 둘 중 하나" 를
    /// 요구하므로 이 조건이 정확성의 일부다.
    ///
    /// `.itemReplacementDirectory` 는 `appropriateFor:` 로 준 URL 과 같은
    /// 볼륨에 자리를 잡아주는 API 다. 경로를 손으로 조합하지 않고 이것을 쓴다.
    ///
    /// 호출 때마다 **새 디렉터리**가 만들어진다. 다 쓰면
    /// `removeScratchDirectory(at:)` 로 지우는 것은 호출자 책임이다.
    func makeScratchDirectory(forSession id: UUID) throws -> URL {
        do {
            // appropriateFor 로 주는 URL 이 실제로 있어야 볼륨을 판정할 수 있다.
            try FileManager.default.createDirectory(at: clipsDirectory(id),
                                                    withIntermediateDirectories: true)
            return try FileManager.default.url(for: .itemReplacementDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: clipsDirectory(id),
                                               create: true)
        } catch {
            throw SessionFileError.mapping(error)
        }
    }

    // MARK: iCloud 백업 제외

    /// `sessions/` 를 iCloud 백업에서 제외한다.
    ///
    /// **제외하는 쪽으로 결정했다** (2-3). 맞바꾼 것은 Tasks.md 2-3 참고.
    /// 요약하면 완성본은 사진 앱에 저장되어 그쪽에서 백업되고, `sessions/` 는
    /// 그 완성본을 만들기 위한 작업 파일이다. 클립 30개가 570MB 라 백업에
    /// 넣으면 사용자의 iCloud 용량을 조용히 먹는다.
    ///
    /// 루트에만 걸면 하위 전체에 적용된다. 세션마다 걸 필요가 없다.
    private func excludeSessionsRootFromBackup() throws {
        var root = sessionsRoot
        let current = try? root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard current?.isExcludedFromBackup != true else { return }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try root.setResourceValues(values)
        } catch {
            throw SessionFileError.mapping(error)
        }
    }
}
