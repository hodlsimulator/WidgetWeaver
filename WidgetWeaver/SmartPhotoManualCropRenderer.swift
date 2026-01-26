//
//  SmartPhotoManualCropRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

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
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))

        let cropPixels = CGRect(
            x: CGFloat(safeCrop.x) * CGFloat(w),
            y: CGFloat(safeCrop.y) * CGFloat(h),
            width: CGFloat(safeCrop.width) * CGFloat(w),
            height: CGFloat(safeCrop.height) * CGFloat(h)
        )
        .integral
        .intersection(imageBounds)

        let cropped = rotatedCg.cropping(to: cropPixels) ?? rotatedCg

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let targetSize = CGSize(width: CGFloat(safeTarget.width), height: CGFloat(safeTarget.height))
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: .up)
            croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Encodes JPEG bytes via ImageIO with explicit orientation metadata `1`.
    ///
    /// This avoids UIKit’s `jpegData` path (which can be memory-heavy) and guarantees:
    /// - pixels are already `.up`
    /// - metadata orientation is `1`
    /// - alpha is not preserved (opaque draw when needed)
    static func encodeJPEG(image: UIImage, startQuality: CGFloat, maxBytes: Int) throws -> Data {
        let orientedUp = normalisedOrientation(image)
        let preparedImage = ensureOpaquePixelFormatIfNeeded(orientedUp)

        guard let cgImage = preparedImage.cgImage else {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        var q = min(0.95, max(0.1, startQuality))
        let minQ: CGFloat = 0.65

        var data = try autoreleasepool(invoking: { try encodeImageIOJPEG(cgImage: cgImage, quality: q) })

        var steps = 0
        while data.count > maxBytes && q > minQ && steps < 6 {
            q = max(minQ, q - 0.05)
            data = try autoreleasepool(invoking: { try encodeImageIOJPEG(cgImage: cgImage, quality: q) })
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
        let size = CGSize(width: CGFloat(w), height: CGFloat(h))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func rotateCGImageWithinBounds(_ cgImage: CGImage, degrees: Double) -> CGImage? {
        let radians = CGFloat(degrees * Double.pi / 180.0)
        let w = cgImage.width
        let h = cgImage.height
        let size = CGSize(width: CGFloat(w), height: CGFloat(h))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            ctx.cgContext.translateBy(x: size.width / 2.0, y: size.height / 2.0)
            ctx.cgContext.rotate(by: radians)
            ctx.cgContext.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)

            let source = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            source.draw(in: CGRect(origin: .zero, size: size))
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
        let sourceSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        let targetSize: CGSize = (t % 2 == 0) ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)

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
            c.translateBy(x: -sourceSize.width / 2.0, y: -sourceSize.height / 2.0)

            let source = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            source.draw(in: CGRect(origin: .zero, size: sourceSize))
        }

        return img.cgImage
    }

    // MARK: - ImageIO JPEG (orientation=1, alpha-free)

    private static func encodeImageIOJPEG(cgImage: CGImage, quality: CGFloat) throws -> Data {
        let q = min(max(quality, 0.0), 1.0)

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: q,
            kCGImagePropertyOrientation: 1
        ]

        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        return out as Data
    }

    private static func ensureOpaquePixelFormatIfNeeded(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        if isAlphaFree(cgImage.alphaInfo) { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let size = CGSize(width: CGFloat(width), height: CGFloat(height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func isAlphaFree(_ alphaInfo: CGImageAlphaInfo) -> Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            return false
        }
    }
}
