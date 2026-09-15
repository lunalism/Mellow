import UIKit
import XCTest
@testable import Mellow

/// Visual-state selection for the Projects screen: copy per state and a deterministic placeholder
/// fallback. No thumbnail subsystem is involved — an image is only ever what the caller supplied.
final class ProjectsEntryContentTests: XCTestCase {
    private let image = UIImage(systemName: "film")!

    func testNoProjectShowsPlaceholderAndNoProjectCopy() {
        let content = ProjectsEntryContent.resolve(hasSavedProject: false, representativeImage: nil)
        XCTAssertEqual(content.visual, .placeholder)
        XCTAssertEqual(content.headline, "아직 프로젝트가 없어요")
        XCTAssertEqual(content.supporting, "촬영한 순간들을 골라\n첫 번째 Vlog를 만들어보세요.")
    }

    func testNoProjectIgnoresAnySuppliedImage() {
        let content = ProjectsEntryContent.resolve(hasSavedProject: false, representativeImage: image)
        XCTAssertEqual(content.visual, .placeholder, "no Project can never claim a representative image")
    }

    func testSavedProjectWithoutImageFallsBackToPlaceholder() {
        let content = ProjectsEntryContent.resolve(hasSavedProject: true, representativeImage: nil)
        XCTAssertEqual(content.visual, .placeholder)
        XCTAssertEqual(content.headline, "이어서 만들래요?")
        XCTAssertEqual(content.supporting, "마지막으로 저장한 프로젝트가 있어요.")
    }

    func testSavedProjectWithInjectedImageSelectsIt() {
        let content = ProjectsEntryContent.resolve(hasSavedProject: true, representativeImage: image)
        XCTAssertEqual(content.visual, .image(image))
        XCTAssertEqual(content.headline, "이어서 만들래요?")
    }
}
