//
//  SmartPhotoManualCropRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import UIKit

enum SmartPhotoManualTransformError: LocalizedError, Sendable {
    case masterDecodeFailed
    case jpegEncodeFailed

    var errorDescription: String? {
        switch self {
        case .masterDecodeFailed:
            return "Could not decode the source image."
        case .jpegEncodeFailed:
            return "Could not encode the rendered image."
        }
    }
}

enum SmartPhotoManualCropRenderer {
    static func normalisedStraightenDegrees(_ degrees: Double) -> Double? {
        guard degrees.isFinite else { return nil }
        let clamped = degrees.clamped(to: -45...45)
        if abs(clamped) < 0.0001 { return nil }
        return clamped
    }

    static func normalisedRotationQuarterTurns(_ quarterTurns: Int) -> Int? {
        let normalised = normalisedQuarterTurns(quarterTurns)
        if normalised == 0 { return nil }
        return normalised
    }

    static func previewImage(master: UIImage, rotationQuarterTurns: Int) -> UIImage {
        let base = normalisedOrientation(master)
        guard let sourceCg = base.cgImage else { return base }

        let turns = normalisedQuarterTurns(rotationQuarterTurns)
        guard turns != 0 else { return base }

        let rotated = rotateCGImageQuarterTurns(sourceCg, quarterTurns: turns) ?? sourceCg
        return UIImage(cgImage: rotated, scale: 1, orientation: .up)
    }

    static func render(
        master: UIImage,
        cropRect: NormalisedRect,
        straightenDegrees: Double,
        rotationQuarterTurns: Int,
        targetPixels: PixelSize
    ) -> UIImage {
        let safeCrop = cropRect.normalised()
        let safeTarget = targetPixels.normalised()

        let base = normalisedOrientation(master)
        guard let sourceCg = base.cgImage else { return base }

        let turns = normalisedQuarterTurns(rotationQuarterTurns)
        let baseRotatedCg = rotateCGImageQuarterTurns(sourceCg, quarterTurns: turns) ?? sourceCg

        let straightenedCg: CGImage
        if abs(straightenDegrees) < 0.0001 {
            straightenedCg = baseRotatedCg
        } else {
            straightenedCg = rotateCGImageWithinBounds(baseRotatedCg, degrees: straightenDegrees) ?? baseRotatedCg
        }

        let w = straightenedCg.width
        let h = straightenedCg.height

        let cropPixels = CGRect(
            x: CGFloat(safeCrop.x) * CGFloat(w),
            y: CGFloat(safeCrop.y) * CGFloat(h),
            width: CGFloat(safeCrop.width) * CGFloat(w),
            height: CGFloat(safeCrop.height) * CGFloat(h)
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        let cropped = straightenedCg.cropping(to: cropPixels) ?? straightenedCg

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let targetSize = CGSize(width: safeTarget.width, height: safeTarget.height)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: .up)
            croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func encodeJPEG(image: UIImage, startQuality: CGFloat, maxBytes: Int) throws -> Data {
        var q = min(0.95, max(0.1, startQuality))
        let minQ: CGFloat = 0.65

        guard var data = image.jpegData(compressionQuality: q) else {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        var steps = 0
        while data.count > maxBytes && q > minQ && steps < 6 {
            q = max(minQ, q - 0.05)
            guard let next = image.jpegData(compressionQuality: q) else { break }
            data = next
            steps += 1
        }

        if data.isEmpty {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        return data
    }

    private static func normalisedQuarterTurns(_ quarterTurns: Int) -> Int {
        let m = quarterTurns % 4
        if m < 0 { return m + 4 }
        return m
    }

    private static func normalisedOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        guard let cg = image.cgImage else { return image }

        let w = cg.width
        let h = cg.height

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    private static func rotateCGImageQuarterTurns(_ cgImage: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = normalisedQuarterTurns(quarterTurns)
        guard turns != 0 else { return cgImage }

        let w = cgImage.width
        let h = cgImage.height

        let outW = (turns % 2 == 0) ? w : h
        let outH = (turns % 2 == 0) ? h : w

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: format)
        let img = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))

            switch turns {
            case 1:
                // 90° clockwise
                ctx.cgContext.translateBy(x: CGFloat(outW), y: 0)
                ctx.cgContext.rotate(by: CGFloat.pi / 2.0)
            case 2:
                // 180°
                ctx.cgContext.translateBy(x: CGFloat(outW), y: CGFloat(outH))
                ctx.cgContext.rotate(by: CGFloat.pi)
            case 3:
                // 90° counter-clockwise
                ctx.cgContext.translateBy(x: 0, y: CGFloat(outH))
                ctx.cgContext.rotate(by: -CGFloat.pi / 2.0)
            default:
                break
            }

            let source = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            source.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        return img.cgImage
    }

    private static func rotateCGImageWithinBounds(_ cgImage: CGImage, degrees: Double) -> CGImage? {
        let radians = CGFloat(degrees * Double.pi / 180.0)
        let w = cgImage.width
        let h = cgImage.height

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let img = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            ctx.cgContext.translateBy(x: CGFloat(w) / 2.0, y: CGFloat(h) / 2.0)
            ctx.cgContext.rotate(by: radians)
            ctx.cgContext.translateBy(x: -CGFloat(w) / 2.0, y: -CGFloat(h) / 2.0)

            let source = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            source.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        return img.cgImage
    }
}
