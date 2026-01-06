//
//  SmartPhotoQualityScorer.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation
import CoreGraphics
import ImageIO
import Vision

struct SmartPhotoQualityScorer: Sendable {
    struct Result: Hashable, Sendable {
        var score: Double
        var flags: [String]
    }

    static func score(localIdentifier: String, imageData: Data, preparedSmartPhoto: SmartPhotoSpec) throws -> Result {
        guard let cgImage = downsampleCGImage(data: imageData, maxPixel: 512) else {
            return Result(score: 0, flags: ["decode failed"])
        }

        var score: Double = 0
        var flags: [String] = []

        // Vision detection (cheap + explainable).
        let faceRequest = VNDetectFaceRectanglesRequest()
        var animalRequest: VNRecognizeAnimalsRequest?
        if #available(iOS 13.0, *) {
            animalRequest = VNRecognizeAnimalsRequest()
        }

        var requests: [VNRequest] = [faceRequest]
        if let animalRequest { requests.append(animalRequest) }

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform(requests)
        } catch {
            flags.append("vision failed")
        }

        let faces: [VNFaceObservation] = faceRequest.results ?? []
        if !faces.isEmpty {
            flags.append("faces \(faces.count)")
            score += min(2.4, Double(faces.count) * 1.0)
        }

        if let animalRequest {
            let animals = animalRequest.results ?? []
            if !animals.isEmpty {
                flags.append("animals \(animals.count)")
                score += min(1.6, Double(animals.count) * 0.8)
            }
        }

        // Sharpness/exposure proxies from luma.
        if let stats = LumaStats.analyse(cgImage: cgImage) {
            score += stats.sharpnessNorm * 1.6

            if stats.sharpnessNorm < 0.12 {
                flags.append("blurry")
                score -= 0.8
            }

            if stats.darkFraction > 0.65 {
                flags.append("too dark")
                score -= 1.4
            }

            if stats.brightFraction > 0.65 {
                flags.append("too bright")
                score -= 1.4
            }

            if stats.contrastNorm < 0.08 {
                flags.append("flat")
                score -= 0.6
            }
        }

        // Per-family "extreme zoom" penalty based on crop rect area.
        let zoom = zoomPenalty(preparedSmartPhoto)
        score -= zoom.penalty
        flags.append(contentsOf: zoom.flags)

        score = max(-10, min(10, score))
        flags = dedupePreservingOrder(flags)

        return Result(score: score, flags: flags)
    }

    // MARK: - Decode

    private static func downsampleCGImage(data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let clampedMaxPixel = max(1, maxPixel)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: clampedMaxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    // MARK: - Image stats

    private struct LumaStats: Sendable {
        var sharpnessNorm: Double
        var darkFraction: Double
        var brightFraction: Double
        var contrastNorm: Double

        static func analyse(cgImage: CGImage) -> LumaStats? {
            let w = cgImage.width
            let h = cgImage.height
            guard w > 1, h > 1 else { return nil }

            var pixels = [UInt8](repeating: 0, count: w * h)
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bitmapInfo = CGImageAlphaInfo.none.rawValue

            let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                ) else {
                    return false
                }

                ctx.interpolationQuality = .none
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }

            guard ok else { return nil }

            let n = Double(pixels.count)
            if n <= 1 { return nil }

            var sum = 0.0
            var darkCount = 0.0
            var brightCount = 0.0

            for p in pixels {
                let v = Double(p)
                sum += v
                if p < 20 { darkCount += 1 }
                if p > 235 { brightCount += 1 }
            }

            let mean = sum / n

            var varSum = 0.0
            for p in pixels {
                let d = Double(p) - mean
                varSum += d * d
            }

            let std = sqrt(varSum / n)
            let contrastNorm = min(1.0, std / 64.0)

            // Gradient magnitude proxy for sharpness.
            var gradSum = 0.0

            // Horizontal
            for y in 0..<h {
                let row = y * w
                for x in 0..<(w - 1) {
                    let a = Double(pixels[row + x])
                    let b = Double(pixels[row + x + 1])
                    gradSum += abs(a - b)
                }
            }

            // Vertical
            for y in 0..<(h - 1) {
                let row = y * w
                let nextRow = (y + 1) * w
                for x in 0..<w {
                    let a = Double(pixels[row + x])
                    let b = Double(pixels[nextRow + x])
                    gradSum += abs(a - b)
                }
            }

            let denom = Double((w - 1) * h + w * (h - 1))
            let gradMean = gradSum / max(1.0, denom)

            // Tuned so “normal” photos land around 0.2–0.7.
            let sharpnessNorm = min(1.0, gradMean / 18.0)

            return LumaStats(
                sharpnessNorm: sharpnessNorm,
                darkFraction: darkCount / n,
                brightFraction: brightCount / n,
                contrastNorm: contrastNorm
            )
        }
    }

    // MARK: - Crop penalties

    private static func zoomPenalty(_ sp: SmartPhotoSpec) -> (penalty: Double, flags: [String]) {
        var penalty = 0.0
        var flags: [String] = []

        func consider(_ variant: SmartPhotoVariantSpec?, label: String) {
            guard let variant else { return }
            let area = max(0.0, variant.cropRect.width) * max(0.0, variant.cropRect.height)

            if area < 0.14 {
                penalty += 1.4
                flags.append("extreme zoom \(label)")
            } else if area < 0.22 {
                penalty += 0.9
                flags.append("zoom \(label)")
            } else if area < 0.30 {
                penalty += 0.4
                flags.append("tight \(label)")
            }
        }

        consider(sp.small, label: "S")
        consider(sp.medium, label: "M")
        consider(sp.large, label: "L")

        return (penalty, flags)
    }

    // MARK: - Utilities

    private static func dedupePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(items.count)

        for s in items {
            if seen.insert(s).inserted {
                out.append(s)
            }
        }

        return out
    }
}
