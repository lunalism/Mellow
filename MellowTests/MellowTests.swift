import UIKit
import XCTest
@testable import Mellow

final class MellowTests: XCTestCase {
    func testBootstrap() {
        XCTAssertTrue(true)
    }

    /// The splash is the native launch presentation, so it has to be wired into the built product
    /// rather than faked in SwiftUI. This target is app-hosted, so `Bundle.main` is Mellow.app.
    func testLaunchPresentationUsesBrandedStoryboardAndSplashAsset() throws {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String, "LaunchScreen")
        XCTAssertNil(
            bundle.object(forInfoDictionaryKey: "UILaunchScreen"),
            "A generated empty launch screen would replace the branded one"
        )
        XCTAssertNotNil(bundle.url(forResource: "LaunchScreen", withExtension: "storyboardc"))
        XCTAssertNotNil(UIImage(named: "MellowSplashLogo"), "Splash artwork must ship in the asset catalog")
    }

    /// Renders the launch storyboard so the branded splash is verified as content, not just wiring:
    /// the logo resolves from the catalog and stays a centred, aspect-fit mark rather than a fill.
    @MainActor
    func testLaunchStoryboardRendersCenteredSplashLogo() throws {
        let storyboard = UIStoryboard(name: "LaunchScreen", bundle: .main)
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController())
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        let imageView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertNotNil(imageView.image, "Splash logo must resolve from the asset catalog")
        XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
        XCTAssertEqual(imageView.center.x, controller.view.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(imageView.center.y, controller.view.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(imageView.bounds.width, 160, accuracy: 0.5)
        XCTAssertEqual(imageView.bounds.height, 160, accuracy: 0.5)
        // No tagline, loading text or other launch copy.
        XCTAssertTrue(controller.view.subviews.compactMap { $0 as? UILabel }.isEmpty)
    }
}
