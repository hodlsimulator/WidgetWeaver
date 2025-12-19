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

        let accent = closestAccentToken(to: stats.accentCandidate, avgSaturation: stats.averageSaturation)
        let background = suggestBackground(accent: accent, averageLuminance: stats.averageLuminance, averageSaturation: stats.averageSaturation)

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
    var averageLuminance: CGFloat
    var averageSaturation: CGFloat
    var accentCandidate: UIColor

    static func make(from image: UIImage) -> ImageStats? {
        guard let cg = image.cgImage ?? image.normalisedCGImage() else { return nil }

        let target = CGSize(width: 56, height: 56)
        guard let bytes = cg.rgbaBytesDownsampled(to: target) else { return nil }

        let pixelCount = max(1, bytes.count / 4)

        var sumR: CGFloat = 0
        var sumG: CGFloat = 0
        var sumB: CGFloat = 0

        var sumLum: CGFloat = 0
        var sumSat: CGFloat = 0

        var bestScore: CGFloat = -1
        var bestColor = UIColor.systemBlue

        // Iterate all pixels; keep it simple and deterministic.
        var i = 0
        while i + 3 < bytes.count {
            let r = CGFloat(bytes[i]) / 255.0
            let g = CGFloat(bytes[i + 1]) / 255.0
            let b = CGFloat(bytes[i + 2]) / 255.0
            let a = CGFloat(bytes[i + 3]) / 255.0

            i += 4
            if a < 0.05 { continue }

            sumR += r
            sumG += g
            sumB += b

            // WCAG-ish relative luminance.
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sumLum += lum

            let u = UIColor(red: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0
            var s: CGFloat = 0
            var v: CGFloat = 0
            _ = u.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            sumSat += s

            // Candidate for accent: prefer vivid colours that are not too dark/light.
            if v < 0.10 || v > 0.98 { continue }
            if s < 0.12 { continue }

            // Score tuned to favour saturated mid-bright colours.
            let score = CGFloat(pow(Double(s), 1.15) * pow(Double(v), 0.85))
            if score > bestScore {
                bestScore = score
                bestColor = u
            }
        }

        let inv = 1.0 / CGFloat(pixelCount)
        let avgR = sumR * inv
        let avgG = sumG * inv
        let avgB = sumB * inv

        let avgLum = sumLum * inv
        let avgSat = sumSat * inv

        // If the image is mostly grey, use the average colour as the candidate (keeps mapping stable).
        let candidate: UIColor
        if avgSat < 0.14 {
            candidate = UIColor(red: avgR, green: avgG, blue: avgB, alpha: 1)
        } else {
            candidate = bestColor
        }

        return ImageStats(
            averageLuminance: avgLum,
            averageSaturation: avgSat,
            accentCandidate: candidate
        )
    }
}

private func closestAccentToken(to color: UIColor, avgSaturation: CGFloat) -> AccentToken {
    // When an image is low-saturation overall, the accent tends to look better as grey.
    if avgSaturation < 0.12 {
        return .gray
    }

    guard let target = HSB(color: color) else {
        return .blue
    }

    let palette: [(AccentToken, UIColor)] = [
        (.blue, .systemBlue),
        (.teal, .systemTeal),
        (.green, .systemGreen),
        (.orange, .systemOrange),
        (.pink, .systemPink),
        (.purple, .systemPurple),
        (.red, .systemRed),
        (.gray, .systemGray),
        (.yellow, .systemYellow),
        (.indigo, .systemIndigo),
    ]

    var best: AccentToken = .blue
    var bestDistance: CGFloat = .greatestFiniteMagnitude

    for (token, ui) in palette {
        guard let p = HSB(color: ui) else { continue }
        let d = target.distance(to: p)
        if d < bestDistance {
            bestDistance = d
            best = token
        }
    }

    // If the candidate is low saturation, grey wins even if hue distance says otherwise.
    if target.s < 0.18 {
        return .gray
    }

    return best
}

private func suggestBackground(accent: AccentToken, averageLuminance: CGFloat, averageSaturation: CGFloat) -> BackgroundToken {
    if averageLuminance < 0.25 {
        return .midnight
    }

    if averageSaturation < 0.10 {
        return (averageLuminance < 0.45) ? .subtleMaterial : .plain
    }

    switch accent {
    case .orange, .red:
        return .sunset

    case .pink, .yellow:
        return .candy

    case .purple, .indigo:
        return (averageLuminance < 0.45) ? .midnight : .aurora

    case .teal, .green:
        return .aurora

    case .gray:
        return (averageLuminance < 0.45) ? .midnight : .subtleMaterial

    case .blue:
        return .radialGlow
    }
}

private struct HSB: Hashable {
    var h: CGFloat
    var s: CGFloat
    var b: CGFloat

    init?(color: UIColor) {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: nil) else {
            return nil
        }
        self.h = h
        self.s = s
        self.b = b
    }

    func distance(to other: HSB) -> CGFloat {
        // Hue is circular: 0.0 and 1.0 are the same.
        let dhRaw = abs(h - other.h)
        let dh = min(dhRaw, 1.0 - dhRaw)
        let ds = abs(s - other.s)
        let db = abs(b - other.b)

        // Weighted for perceptual usefulness.
        return (dh * 2.0) + (ds * 0.8) + (db * 0.4)
    }
}

private extension CGImage {
    func rgbaBytesDownsampled(to size: CGSize) -> [UInt8]? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        let totalBytes = h * bytesPerRow

        var bytes = [UInt8](repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
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
