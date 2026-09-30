import Foundation

// The one ADR-047 working-raster calculation (ADR-047 Decision 1, ADR-048 Decision 2). Both the
// preflight working-raster feasibility gate and the Step 4A normalization plan call this; nothing
// else computes output sizes. Pure integer arithmetic: deterministic, overflow-free, no media.

/// An integral pixel raster in presentation orientation (after the preferred transform).
struct WorkingMediaRaster: Hashable, Sendable {
    let width: Int
    let height: Int

    var isPortrait: Bool { height > width }
}

/// An exact scale factor kept as a reduced rational so sizing never depends on floating point.
struct WorkingMediaScale: Hashable, Sendable {
    let numerator: Int
    let denominator: Int

    static let unity = WorkingMediaScale(reducing: 1, 1)

    fileprivate init(reducing numerator: Int, _ denominator: Int) {
        var a = numerator, b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        self.numerator = numerator / a
        self.denominator = denominator / a
    }
}

/// The sized output raster for one presentation raster. `scaled` is the proportional raster floored
/// to whole pixels before even alignment, so the at-most-one-pixel alignment loss per edge stays
/// visible (`scaled - output`) and is never confused with crop or fill.
struct WorkingMediaRasterPlan: Hashable, Sendable {
    let presentation: WorkingMediaRaster
    let scale: WorkingMediaScale
    let scaled: WorkingMediaRaster
    let output: WorkingMediaRaster

    var alignmentLoss: (width: Int, height: Int) {
        (scaled.width - output.width, scaled.height - output.height)
    }

    /// ADR-048 Decision 2: the aligned output must keep pixels on both edges and stay strictly
    /// portrait. An infeasible raster is a preflight rejection, never repaired by crop, pad,
    /// stretch, upscale or an added margin.
    var isFeasible: Bool { output.width > 0 && output.height > 0 && output.isPortrait }

    fileprivate init(presentation: WorkingMediaRaster, scale: WorkingMediaScale, scaled: WorkingMediaRaster, output: WorkingMediaRaster) {
        self.presentation = presentation
        self.scale = scale
        self.scaled = scaled
        self.output = output
    }
}

enum WorkingMediaRasterPolicy {
    /// Portrait 1080p-class envelope (short edge ≤ 1080, long edge ≤ 1920).
    static let envelope = WorkingMediaRaster(width: ImportPreflightPolicy.maximumShortEdge, height: ImportPreflightPolicy.maximumLongEdge)

    /// `scale = min(1.0, 1080 / width, 1920 / height)`, each scaled edge floored, then floored to an
    /// even integer. Never upscales, crops, pads or stretches; the input is the already-derived
    /// presentation raster and no natural-size edges are swapped here. `nil` only for a
    /// non-positive raster, which has no plan at all. Exact 128-bit integer arithmetic.
    static func plan(forPresentation presentation: WorkingMediaRaster) -> WorkingMediaRasterPlan? {
        let width = presentation.width, height = presentation.height
        guard width > 0, height > 0 else { return nil }

        let maxWidth = envelope.width, maxHeight = envelope.height
        let scale: WorkingMediaScale
        if width <= maxWidth, height <= maxHeight {
            scale = .unity
        } else if Int128(maxWidth) * Int128(height) <= Int128(maxHeight) * Int128(width) {
            // maxWidth / width <= maxHeight / height: the width edge binds.
            scale = WorkingMediaScale(reducing: maxWidth, width)
        } else {
            scale = WorkingMediaScale(reducing: maxHeight, height)
        }

        let scaled = WorkingMediaRaster(width: floorScaled(width, scale), height: floorScaled(height, scale))
        let output = WorkingMediaRaster(width: scaled.width - scaled.width % 2, height: scaled.height - scaled.height % 2)
        return WorkingMediaRasterPlan(presentation: presentation, scale: scale, scaled: scaled, output: output)
    }

    /// `floor(edge × scale)` for positive operands; the quotient never exceeds `edge`.
    private static func floorScaled(_ edge: Int, _ scale: WorkingMediaScale) -> Int {
        Int(Int128(edge) * Int128(scale.numerator) / Int128(scale.denominator))
    }
}
