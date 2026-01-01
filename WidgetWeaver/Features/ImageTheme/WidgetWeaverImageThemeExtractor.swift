//
//  WidgetWeaverImageThemeExtractor.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import Foundation
import UIKit

struct WidgetWeaverImageThemeSuggestion: Hashable {
    let accent: AccentToken
    let background: BackgroundToken
    let averageLuminance: Double
    let averageSaturation: Double

    var isDark: Bool { averageLuminance < 0.35 }
}

enum WidgetWeaverImageThemeExtractor {

    static func suggestTheme(from image: UIImage) -> WidgetWeaverImageThemeSuggestion {
        guard let stats = ImageStats.make(from: image) else {
            return WidgetWeaverImageThemeSuggestion(
                accent: .blue,
                background: .aurora,
                averageLuminance: 0.5,
                averageSaturation: 0.0
            )
        }

        let accent = suggestAccent(from: stats)
        let background = suggestBackground(accent: accent, stats: stats)

        return WidgetWeaverImageThemeSuggestion(
            accent: accent,
            background: background,
            averageLuminance: Double(stats.averageLuminance),
            averageSaturation: Double(stats.averageSaturation)
        )
    }
}

// MARK: - Internals

private struct ImageStats {
    let averageLuminance: CGFloat
    let luminanceStdDev: CGFloat
    let luminanceRange: CGFloat

    let averageSaturation: CGFloat
    let saturationP90: CGFloat

    /// Best hue bin centre in 0...1, based on per-pixel weighted accumulation.
    let huePeakHue: CGFloat?

    /// Strength of the best hue bin relative to all hue-eligible pixels (area-based).
    let huePeakStrengthAlpha: CGFloat

    /// Strength of the best hue bin relative to total hue weight (weight-based).
    let huePeakStrengthWeight: CGFloat

    /// Fraction of the image (alpha-weighted) considered hue-eligible.
    let huePixelShare: CGFloat

    /// Fraction of the image (alpha-weighted) inside the best hue bin.
    let bestHuePixelShare: CGFloat

    /// Average colour of the full image in linear RGB.
    let averageColorLinear: RGBLinear

    /// Representative colour for the best hue bin in linear RGB.
    let hueRepresentativeLinear: RGBLinear?

    static func make(from image: UIImage) -> ImageStats? {
        guard let cg = image.cgImage ?? image.normalisedCGImage() else { return nil }

        // Small fixed sample size keeps cost low and results stable.
        let target = CGSize(width: 64, height: 64)
        guard let bytes = cg.rgbaBytesDownsampled(to: target) else { return nil }

        let bytesPerPixel = 4
        let pixelCount = max(1, bytes.count / bytesPerPixel)

        // Saturation histogram for a cheap P90 estimate.
        let satBins = 32
        var satHistogram = [CGFloat](repeating: 0, count: satBins)

        // Hue histogram (10° bins).
        let hueBins = 36
        var hueWeight = [CGFloat](repeating: 0, count: hueBins)
        var hueAlpha = [CGFloat](repeating: 0, count: hueBins)
        var hueSumR = [CGFloat](repeating: 0, count: hueBins)
        var hueSumG = [CGFloat](repeating: 0, count: hueBins)
        var hueSumB = [CGFloat](repeating: 0, count: hueBins)

        var totalAlpha: CGFloat = 0

        var sumLum: CGFloat = 0
        var sumLum2: CGFloat = 0
        var lumMin: CGFloat = 1
        var lumMax: CGFloat = 0

        var sumSat: CGFloat = 0

        var sumLinR: CGFloat = 0
        var sumLinG: CGFloat = 0
        var sumLinB: CGFloat = 0

        var hueAlphaTotal: CGFloat = 0
        var hueWeightTotal: CGFloat = 0

        // Tuning constants for determinism.
        let alphaCutoff: CGFloat = 0.05
        let hueSatMin: CGFloat = 0.03

        let satFloor: CGFloat = 0.02
        let satRange: CGFloat = 0.30

        var i = 0
        while i + 3 < bytes.count {
            let rS = CGFloat(bytes[i]) / 255.0
            let gS = CGFloat(bytes[i + 1]) / 255.0
            let bS = CGFloat(bytes[i + 2]) / 255.0
            let a = CGFloat(bytes[i + 3]) / 255.0
            i += 4

            if a < alphaCutoff { continue }

            let rL = srgbToLinear(rS)
            let gL = srgbToLinear(gS)
            let bL = srgbToLinear(bS)

            let lum = (0.2126 * rL) + (0.7152 * gL) + (0.0722 * bL)

            let hsv = HSV(r: rS, g: gS, b: bS)

            totalAlpha += a

            sumLum += lum * a
            sumLum2 += lum * lum * a
            lumMin = min(lumMin, lum)
            lumMax = max(lumMax, lum)

            sumSat += hsv.s * a

            let satIndex = min(satBins - 1, max(0, Int(hsv.s * CGFloat(satBins))))
            satHistogram[satIndex] += a

            sumLinR += rL * a
            sumLinG += gL * a
            sumLinB += bL * a

            // Accent weighting: prefer some saturation, and prefer mid luminance.
            let satWeight = clamp((hsv.s - satFloor) / satRange, lower: 0, upper: 1)
            let lumWeight = clamp(1 - abs(lum - 0.5) * 2, lower: 0, upper: 1)
            let weight = a * (0.20 + 0.80 * satWeight) * (0.30 + 0.70 * lumWeight)

            if hsv.s >= hueSatMin {
                let h = hsv.h
                let bin = min(hueBins - 1, max(0, Int(h * CGFloat(hueBins))))

                hueWeight[bin] += weight
                hueSumR[bin] += rL * weight
                hueSumG[bin] += gL * weight
                hueSumB[bin] += bL * weight

                hueWeightTotal += weight

                hueAlpha[bin] += a
                hueAlphaTotal += a
            }
        }

        guard totalAlpha > 0 else { return nil }

        let invAlpha = 1 / totalAlpha

        let avgLum = sumLum * invAlpha
        let variance = max(0, (sumLum2 * invAlpha) - (avgLum * avgLum))
        let stdDev = sqrt(variance)

        let avgSat = sumSat * invAlpha

        let avgColor = RGBLinear(
            r: sumLinR * invAlpha,
            g: sumLinG * invAlpha,
            b: sumLinB * invAlpha
        )

        // P90 saturation estimate from histogram.
        let p90Target = totalAlpha * 0.90
        var running: CGFloat = 0
        var p90Bin = satBins - 1
        for b in 0..<satBins {
            running += satHistogram[b]
            if running >= p90Target {
                p90Bin = b
                break
            }
        }
        let satP90 = (CGFloat(p90Bin) + 0.5) / CGFloat(satBins)

        // Best hue bin.
        var bestBin = 0
        var bestWeight: CGFloat = 0
        for b in 0..<hueBins {
            let w = hueWeight[b]
            if w > bestWeight {
                bestWeight = w
                bestBin = b
            }
        }

        let huePeakHue: CGFloat?
        let huePeakStrengthAlpha: CGFloat
        let huePeakStrengthWeight: CGFloat
        let huePixelShare: CGFloat
        let bestHuePixelShare: CGFloat
        let hueRep: RGBLinear?

        if hueAlphaTotal > 0, bestWeight > 0, hueWeightTotal > 0 {
            huePeakHue = (CGFloat(bestBin) + 0.5) / CGFloat(hueBins)
            huePeakStrengthAlpha = hueAlpha[bestBin] / hueAlphaTotal
            huePeakStrengthWeight = bestWeight / hueWeightTotal
            huePixelShare = hueAlphaTotal / totalAlpha
            bestHuePixelShare = hueAlpha[bestBin] / totalAlpha

            hueRep = RGBLinear(
                r: hueSumR[bestBin] / bestWeight,
                g: hueSumG[bestBin] / bestWeight,
                b: hueSumB[bestBin] / bestWeight
            )
        } else {
            huePeakHue = nil
            huePeakStrengthAlpha = 0
            huePeakStrengthWeight = 0
            huePixelShare = 0
            bestHuePixelShare = 0
            hueRep = nil
        }

        // Range uses min/max luminance from the sample. Clamp for stability.
        let range = max(0, lumMax - lumMin)

        // pixelCount is unused after refactor but kept as a reminder of sample scale.
        _ = pixelCount

        return ImageStats(
            averageLuminance: avgLum,
            luminanceStdDev: stdDev,
            luminanceRange: range,
            averageSaturation: avgSat,
            saturationP90: satP90,
            huePeakHue: huePeakHue,
            huePeakStrengthAlpha: huePeakStrengthAlpha,
            huePeakStrengthWeight: huePeakStrengthWeight,
            huePixelShare: huePixelShare,
            bestHuePixelShare: bestHuePixelShare,
            averageColorLinear: avgColor,
            hueRepresentativeLinear: hueRep
        )
    }
}

private func suggestAccent(from stats: ImageStats) -> AccentToken {
    let y = stats.averageLuminance
    let avgSat = stats.averageSaturation
    let satP90 = stats.saturationP90

    let neutralAccent: AccentToken = (y < 0.28) ? .indigo : .gray

    // Very low saturation: treat as neutral unless there is a consistent tint.
    let isVeryLowSat = (avgSat < 0.055) && (satP90 < 0.12)
    let isLowSat = (avgSat < 0.10) && (satP90 < 0.22)

    let hasHue = (stats.huePeakHue != nil) && (stats.hueRepresentativeLinear != nil)

    let tintedGrey: Bool
    if isVeryLowSat {
        tintedGrey = (stats.huePixelShare > 0.65) && (stats.huePeakStrengthAlpha > 0.72)
    } else if isLowSat {
        tintedGrey = (stats.huePixelShare > 0.55) && (stats.huePeakStrengthAlpha > 0.62)
    } else {
        tintedGrey = false
    }

    if isVeryLowSat, !tintedGrey {
        return neutralAccent
    }

    // Decide whether the hue bin is strong enough to drive the accent.
    let hueDominant = (stats.bestHuePixelShare > 0.08) && (stats.huePeakStrengthWeight > 0.32)
    let hueAllowed = tintedGrey || hueDominant || (satP90 > 0.28)

    let baseColorLinear = (hueAllowed && hasHue) ? stats.hueRepresentativeLinear! : stats.averageColorLinear

    // Token from hue boundaries is stable thanks to hue binning.
    let hueToken: AccentToken? = stats.huePeakHue.map { accentTokenForHue(hue: $0) }

    let restrictedTokens: Set<AccentToken>?
    if isLowSat {
        restrictedTokens = [.gray, .indigo, .blue, .purple, .teal, .green, .orange]
    } else {
        restrictedTokens = nil
    }

    var distancePick = closestAccentTokenByDistance(to: baseColorLinear, limitTo: restrictedTokens)

    // If the distance match is ambiguous, prefer the hue bucket to avoid flicker.
    if let hueToken, restrictedTokens == nil {
        let ranks = rankedAccentTokensByDistance(to: baseColorLinear, limitTo: nil)
        if ranks.count >= 2 {
            let best = ranks[0]
            let second = ranks[1]

            // Ratio test on squared distances.
            let ratio = (second.distanceSquared > 0) ? (best.distanceSquared / second.distanceSquared) : 0
            if ratio > 0.92 {
                distancePick = hueToken
            }
        }
    }

    // Low-saturation tinted greys: clamp to a stable subset and avoid pale yellow.
    if isLowSat, let hueToken {
        if hueToken == .yellow {
            distancePick = .orange
        } else if restrictedTokens?.contains(hueToken) == true {
            distancePick = hueToken
        }
    }

    // Warm-bias guard: require stronger confidence before selecting red/orange/yellow.
    if distancePick == .red || distancePick == .orange || distancePick == .yellow {
        let confidence = max(stats.huePeakStrengthAlpha, stats.huePeakStrengthWeight)
        let area = stats.bestHuePixelShare

        if avgSat < 0.22, satP90 < 0.40, confidence < 0.58, area < 0.35 {
            // Fall back to the closest non-warm token.
            if let fallback = closestAccentTokenByDistanceExcludingWarm(to: baseColorLinear) {
                distancePick = fallback
            }
        }

        // Very bright images: yellow often reads as washed-out.
        if distancePick == .yellow, y > 0.82, avgSat < 0.35 {
            distancePick = .orange
        }
    }

    return distancePick
}

private func suggestBackground(accent: AccentToken, stats: ImageStats) -> BackgroundToken {
    let y = stats.averageLuminance
    let avgSat = stats.averageSaturation
    let satP90 = stats.saturationP90

    let lowContrast = (stats.luminanceStdDev < 0.10) || (stats.luminanceRange < 0.26)

    let isVeryBright = y > 0.78
    let isVeryDark = y < 0.22

    if isVeryBright {
        // Avoid washed-out looks.
        if avgSat < 0.12 || lowContrast {
            return .subtleMaterial
        }

        if accent == .yellow {
            return .subtleMaterial
        }

        return .accentGlow
    }

    if isVeryDark {
        // Dark photos tend to benefit from a controlled glow or glass.
        if avgSat < 0.12 {
            return lowContrast ? .subtleMaterial : .midnight
        }

        if lowContrast {
            return .subtleMaterial
        }

        switch accent {
        case .orange, .red:
            return (satP90 > 0.35) ? .sunset : .midnight
        case .pink, .yellow:
            return (satP90 > 0.35) ? .candy : .midnight
        case .teal, .green:
            return .aurora
        case .purple, .indigo:
            return .midnight
        case .gray:
            return .subtleMaterial
        case .blue:
            return .radialGlow
        }
    }

    // Mid-brightness.
    if avgSat < 0.10 {
        // Low-contrast neutral images: prefer material.
        if lowContrast {
            return .subtleMaterial
        }

        // High-contrast, brighter images can safely use plain.
        if y > 0.62 {
            return .plain
        }

        // A light touch of colour keeps things from feeling flat.
        return .accentGlow
    }

    // High colourfulness.
    if avgSat > 0.30 || satP90 > 0.55 {
        if lowContrast {
            return .solidAccent
        }

        switch accent {
        case .orange, .red:
            return .sunset
        case .pink, .yellow:
            return .candy
        case .teal, .green:
            return .aurora
        case .purple, .indigo:
            return (y < 0.42) ? .midnight : .aurora
        case .gray:
            return .subtleMaterial
        case .blue:
            return .radialGlow
        }
    }

    // Moderate saturation: keep conservative and readable.
    if lowContrast {
        return .subtleMaterial
    }

    switch accent {
    case .gray:
        return .subtleMaterial
    case .blue:
        return .radialGlow
    case .indigo, .purple:
        return (y < 0.38) ? .midnight : .radialGlow
    case .teal, .green:
        return .aurora
    case .orange, .red:
        return .sunset
    case .pink, .yellow:
        return .candy
    }
}

// MARK: - Colour helpers

private struct RGBLinear: Hashable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    func clamped01() -> RGBLinear {
        RGBLinear(
            r: clamp(r, lower: 0, upper: 1),
            g: clamp(g, lower: 0, upper: 1),
            b: clamp(b, lower: 0, upper: 1)
        )
    }

    func toSRGB() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = clamped01()
        return (
            r: linearToSrgb(c.r),
            g: linearToSrgb(c.g),
            b: linearToSrgb(c.b)
        )
    }
}

private struct HSV {
    var h: CGFloat
    var s: CGFloat
    var v: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC

        v = maxC
        s = (maxC <= 0) ? 0 : (delta / maxC)

        if delta <= 0 {
            h = 0
            return
        }

        var hue: CGFloat
        if maxC == r {
            hue = (g - b) / delta
            hue = hue.truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            hue = ((b - r) / delta) + 2
        } else {
            hue = ((r - g) / delta) + 4
        }

        hue /= 6
        if hue < 0 { hue += 1 }
        h = hue
    }
}

private func srgbToLinear(_ c: CGFloat) -> CGFloat {
    if c <= 0.04045 {
        return c / 12.92
    }
    return pow((c + 0.055) / 1.055, 2.4)
}

private func linearToSrgb(_ c: CGFloat) -> CGFloat {
    let x = clamp(c, lower: 0, upper: 1)
    if x <= 0.0031308 {
        return 12.92 * x
    }
    return (1.055 * pow(x, 1 / 2.4)) - 0.055
}

private func clamp(_ x: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
    min(upper, max(lower, x))
}

// MARK: - Accent token mapping

private struct AccentPaletteEntry {
    let token: AccentToken
    let linear: RGBLinear
}

private enum AccentPalette {
    static let entries: [AccentPaletteEntry] = [
        AccentPaletteEntry(token: .blue, linear: RGBLinear(r: srgbToLinear(0.00), g: srgbToLinear(0.48), b: srgbToLinear(1.00))),
        AccentPaletteEntry(token: .teal, linear: RGBLinear(r: srgbToLinear(0.00), g: srgbToLinear(0.66), b: srgbToLinear(0.64))),
        AccentPaletteEntry(token: .green, linear: RGBLinear(r: srgbToLinear(0.20), g: srgbToLinear(0.78), b: srgbToLinear(0.35))),
        AccentPaletteEntry(token: .orange, linear: RGBLinear(r: srgbToLinear(1.00), g: srgbToLinear(0.58), b: srgbToLinear(0.00))),
        AccentPaletteEntry(token: .pink, linear: RGBLinear(r: srgbToLinear(1.00), g: srgbToLinear(0.20), b: srgbToLinear(0.55))),
        AccentPaletteEntry(token: .purple, linear: RGBLinear(r: srgbToLinear(0.65), g: srgbToLinear(0.30), b: srgbToLinear(0.85))),
        AccentPaletteEntry(token: .red, linear: RGBLinear(r: srgbToLinear(1.00), g: srgbToLinear(0.23), b: srgbToLinear(0.19))),
        AccentPaletteEntry(token: .yellow, linear: RGBLinear(r: srgbToLinear(1.00), g: srgbToLinear(0.80), b: srgbToLinear(0.00))),
        AccentPaletteEntry(token: .gray, linear: RGBLinear(r: srgbToLinear(0.55), g: srgbToLinear(0.55), b: srgbToLinear(0.58))),
        AccentPaletteEntry(token: .indigo, linear: RGBLinear(r: srgbToLinear(0.35), g: srgbToLinear(0.34), b: srgbToLinear(0.84))),
    ]
}

private struct AccentDistanceRank {
    let token: AccentToken
    let distanceSquared: CGFloat
}

private func rankedAccentTokensByDistance(to color: RGBLinear, limitTo allowed: Set<AccentToken>?) -> [AccentDistanceRank] {
    let c = color.clamped01()

    var ranks: [AccentDistanceRank] = []
    ranks.reserveCapacity(AccentPalette.entries.count)

    for e in AccentPalette.entries {
        if let allowed, !allowed.contains(e.token) { continue }
        let dr = c.r - e.linear.r
        let dg = c.g - e.linear.g
        let db = c.b - e.linear.b
        let d2 = (dr * dr) + (dg * dg) + (db * db)
        ranks.append(AccentDistanceRank(token: e.token, distanceSquared: d2))
    }

    ranks.sort { $0.distanceSquared < $1.distanceSquared }
    return ranks
}

private func closestAccentTokenByDistance(to color: RGBLinear, limitTo allowed: Set<AccentToken>?) -> AccentToken {
    rankedAccentTokensByDistance(to: color, limitTo: allowed).first?.token ?? .blue
}

private func closestAccentTokenByDistanceExcludingWarm(to color: RGBLinear) -> AccentToken? {
    let excluded: Set<AccentToken> = [.red, .orange, .yellow]
    let ranks = rankedAccentTokensByDistance(to: color, limitTo: nil)
    for r in ranks {
        if excluded.contains(r.token) { continue }
        return r.token
    }
    return nil
}

private func accentTokenForHue(hue: CGFloat) -> AccentToken {
    let h = hue - floor(hue)
    let deg = h * 360

    // Boundaries chosen to reduce flicker when paired with 10° hue bins.
    if deg < 15 || deg >= 345 { return .red }
    if deg < 45 { return .orange }
    if deg < 70 { return .yellow }
    if deg < 155 { return .green }
    if deg < 195 { return .teal }
    if deg < 245 { return .blue }
    if deg < 275 { return .indigo }
    if deg < 315 { return .purple }
    return .pink
}

// MARK: - Image sampling

private extension CGImage {
    func rgbaBytesDownsampled(to size: CGSize) -> [UInt8]? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        let totalBytes = h * bytesPerRow

        var bytes = [UInt8](repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let baseAddress = raw.baseAddress else { return false }
            guard let ctx = CGContext(
                data: baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            ctx.interpolationQuality = .low
            ctx.setBlendMode(.copy)
            ctx.draw(self, in: rect)
            return true
        }

        return ok ? bytes : nil
    }
}

private extension UIImage {
    func normalisedCGImage() -> CGImage? {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false

        let rendered = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }

        return rendered.cgImage
    }
}
