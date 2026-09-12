import XCTest

final class MellowUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertTrue(app.exists)
    }
}
