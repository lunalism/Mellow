import SwiftUI

enum MellowDesignSystem {
    static let brandBackground = Color(uiColor: .systemBackground)
    // Small metadata uses label contrast; font size carries its secondary hierarchy.
    static let secondaryText = Color(uiColor: .label)

    // MARK: - Mellow Signature Colors (DESIGN.md "Mellow Signature Colors")

    /// Foundation palette — the warm family promoted from the Recording Progress Ring. Canonical
    /// values; identical in Light and Dark (the foreground adapts to them, never the reverse).
    static let signaturePeach50 = Color(hex: 0xFFD7C7)
    static let signaturePeach100 = Color(hex: 0xFFB89C)
    static let signaturePeach300 = Color(hex: 0xFF8A65)
    static let signatureOrange400 = Color(hex: 0xFF7A45)
    static let signatureOrange500 = Color(hex: 0xFF5E3A)

    /// Signature Gradient stops: Peach 300 → Orange 400 → Orange 500. Positive creation / capture /
    /// primary-action energy; never for destructive, error, warning or disabled controls.
    static let signatureGradientColors: [Color] = [signaturePeach300, signatureOrange400, signatureOrange500]

    /// Horizontal Signature Gradient for rectangular primary actions.
    static let signatureGradient = LinearGradient(
        colors: signatureGradientColors, startPoint: .leading, endPoint: .trailing
    )

    /// Foreground for text / symbols on the Signature Gradient. Near-black in both appearances: the
    /// palette does not carry white text at normal sizes, so readability wins over "light on brand".
    static let signatureForeground = Color(hex: 0x1C1C1E)
}

extension Color {
    /// Opaque sRGB colour from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
