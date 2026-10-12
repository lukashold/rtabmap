import Foundation

/// Indicators from a small grayscale preview, not evidence of motion,
/// reconstruction quality, dimensional accuracy, or a reason to delete a photo.
struct PhotoQuality {
    enum Hint: String { case dark = "qualityDark", bright = "qualityBright", lowContrast = "qualityTexture", weakEdges = "qualityEdges" }
    let laplacianVariance: Double
    let contrastDeviation: Double
    let darkFraction: Double
    let brightFraction: Double
    var hint: Hint? {
        if darkFraction > 0.65 { return .dark }
        if brightFraction > 0.65 { return .bright }
        if contrastDeviation < 8 { return .lowContrast }
        if laplacianVariance < 20 { return .weakEdges }
        return nil
    }

    /// Caller supplies an aspect-preserving preview no larger than 128 px per
    /// side. Bounds are checked before indexing, including malformed dimensions.
    static func analyze(grayscale: [UInt8], width: Int, height: Int) -> PhotoQuality? {
        guard (3...128).contains(width), (3...128).contains(height), grayscale.count == width * height else { return nil }
        var sum = 0.0, squares = 0.0, dark = 0, bright = 0
        for sample in grayscale {
            let value = Double(sample); sum += value; squares += value * value
            if sample < 20 { dark += 1 }
            if sample > 235 { bright += 1 }
        }
        let count = Double(grayscale.count)
        let mean = sum / count
        let contrast = sqrt(max(0, squares / count - mean * mean))
        var lapSum = 0.0, lapSquares = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let lap = Double(Int(grayscale[i - 1]) + Int(grayscale[i + 1]) +
                                 Int(grayscale[i - width]) + Int(grayscale[i + width]) - 4 * Int(grayscale[i]))
                lapSum += lap; lapSquares += lap * lap
            }
        }
        let interior = Double((width - 2) * (height - 2))
        let lapMean = lapSum / interior
        return PhotoQuality(laplacianVariance: max(0, lapSquares / interior - lapMean * lapMean),
            contrastDeviation: contrast, darkFraction: Double(dark) / count, brightFraction: Double(bright) / count)
    }
}
