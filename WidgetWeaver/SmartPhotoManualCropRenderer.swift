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

    static func render(
        master: UIImage,
        cropRect: NormalisedRect,
        straightenDegrees: Double,
        rotationQuarterTurns: Int = 0,
        targetPixels: PixelSize
    ) -> UIImage {
        let safeCrop = cropRect.normalised()
        let safeTarget = targetPixels.normalised()

        let base = normalisedOrientation(master)
        guard let sourceCg = base.cgImage else { return base }

        let t = normalisedQuarterTurns(rotationQuarterTurns)
        let quarterTurnedCg = (t == 0) ? sourceCg : (rotateCGImageQuarterTurns(sourceCg, quarterTurns: t) ?? sourceCg)

        let rotatedCg: CGImage
        if abs(straightenDegrees) < 0.0001 {
            rotatedCg = quarterTurnedCg
        } else {
            rotatedCg = rotateCGImageWithinBounds(quarterTurnedCg, degrees: straightenDegrees) ?? quarterTurnedCg
        }

        let w = rotatedCg.width
        let h = rotatedCg.height

        let cropPixels = CGRect(
            x: CGFloat(safeCrop.x) * CGFloat(w),
            y: CGFloat(safeCrop.y) * CGFloat(h),
            width: CGFloat(safeCrop.width) * CGFloat(w),
            height: CGFloat(safeCrop.height) * CGFloat(h)
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        let cropped = rotatedCg.cropping(to: cropPixels) ?? rotatedCg

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

    private static func normalisedQuarterTurns(_ quarterTurns: Int) -> Int {
        let t = quarterTurns % 4
        return (t + 4) % 4
    }

    private static func rotateCGImageQuarterTurns(_ cgImage: CGImage, quarterTurns: Int) -> CGImage? {
        let t = normalisedQuarterTurns(quarterTurns)
        guard t != 0 else { return cgImage }

        let w = cgImage.width
        let h = cgImage.height

        let targetSize: CGSize = (t % 2 == 0)
            ? CGSize(width: w, height: h)
            : CGSize(width: h, height: w)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let img = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let c = ctx.cgContext
            c.translateBy(x: targetSize.width / 2.0, y: targetSize.height / 2.0)
            c.rotate(by: CGFloat(t) * (.pi / 2.0))
            c.translateBy(x: -CGFloat(w) / 2.0, y: -CGFloat(h) / 2.0)

            let source = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            source.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        return img.cgImage
    }
}
