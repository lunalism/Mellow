import SwiftUI
import XCTest
@testable import Mellow

/// Canonical Mellow Signature Colors (DESIGN.md): exact foundation values and gradient order.
final class MellowDesignSystemTests: XCTestCase {
    private func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    func testFoundationPaletteMatchesCanonicalValues() {
        XCTAssertEqual(hex(MellowDesignSystem.signaturePeach50), 0xFFD7C7)
        XCTAssertEqual(hex(MellowDesignSystem.signaturePeach100), 0xFFB89C)
        XCTAssertEqual(hex(MellowDesignSystem.signaturePeach300), 0xFF8A65)
        XCTAssertEqual(hex(MellowDesignSystem.signatureOrange400), 0xFF7A45)
        XCTAssertEqual(hex(MellowDesignSystem.signatureOrange500), 0xFF5E3A)
    }

    func testSignatureGradientIsPeach300ToOrange400ToOrange500() {
        XCTAssertEqual(MellowDesignSystem.signatureGradientColors.map(hex), [0xFF8A65, 0xFF7A45, 0xFF5E3A])
    }

    func testSignatureForegroundIsNearBlackNotWhite() {
        XCTAssertEqual(hex(MellowDesignSystem.signatureForeground), 0x1C1C1E)
    }
}
