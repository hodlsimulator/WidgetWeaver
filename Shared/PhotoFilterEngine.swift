//
//  PhotoFilterEngine.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreImage)
import CoreImage
#endif

#if canImport(UIKit) && canImport(CoreImage)

/// Non-destructive photo filter renderer.
///
/// This performs all work at render time and never mutates persisted image bytes.
public final class PhotoFilterEngine: @unchecked Sendable {
    public static let shared = PhotoFilterEngine()

    private let context: CIContext

    private init() {
        self.context = CIContext(options: nil)
    }

    /// Applies a filter spec to an image.
    ///
    /// - Returns: A filtered image, or the original image on any failure.
    public func apply(to image: UIImage, spec: PhotoFilterSpec) -> UIImage {
        guard let cleaned = spec.normalisedOrNil() else { return image }

        let t = cleaned.intensity.normalised().clamped(to: 0.0...1.0)
        if t <= 0.0 { return image }

        guard let baseCI = CIImage(image: image) else { return image }

        let originalCI: CIImage = {
            if image.imageOrientation == .up { return baseCI }
            let exif = Self.exifOrientation(for: image.imageOrientation)
            return baseCI.oriented(forExifOrientation: exif)
        }()

        let originalExtent = originalCI.extent
        guard !originalExtent.isEmpty else { return image }

        guard let filteredCI = fullyFilteredImage(for: cleaned.token, input: originalCI) else { return image }
        guard let blendedCI = blend(original: originalCI, filtered: filteredCI, intensity: t) else { return image }

        let outputCI = blendedCI.cropped(to: originalExtent)

        guard let cg = context.createCGImage(outputCI, from: originalExtent) else { return image }

        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    private static func exifOrientation(for orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }

    private func fullyFilteredImage(for token: PhotoFilterToken, input: CIImage) -> CIImage? {
        switch token {
        case .none:
            return input
        case .noir:
            return input.applyingFilter("CIPhotoEffectNoir")
        case .mono:
            return input.applyingFilter("CIPhotoEffectMono")
        case .chrome:
            return input.applyingFilter("CIPhotoEffectChrome")
        case .fade:
            return input.applyingFilter("CIPhotoEffectFade")
        case .instant:
            return input.applyingFilter("CIPhotoEffectInstant")
        case .process:
            return input.applyingFilter("CIPhotoEffectProcess")
        case .transfer:
            return input.applyingFilter("CIPhotoEffectTransfer")
        case .sepia:
            return input.applyingFilter(
                "CISepiaTone",
                parameters: [
                    kCIInputIntensityKey: 1.0
                ]
            )
        }
    }

    private func blend(original: CIImage, filtered: CIImage, intensity: Double) -> CIImage? {
        let t = intensity.normalised().clamped(to: 0.0...1.0)

        if t <= 0.0 { return original }
        if t >= 1.0 { return filtered }

        let f = CIFilter(name: "CIDissolveTransition")
        f?.setValue(original, forKey: kCIInputImageKey)
        f?.setValue(filtered, forKey: kCIInputTargetImageKey)
        f?.setValue(t, forKey: kCIInputTimeKey)
        return f?.outputImage
    }
}

#elseif canImport(UIKit)

public final class PhotoFilterEngine: @unchecked Sendable {
    public static let shared = PhotoFilterEngine()

    private init() {}

    public func apply(to image: UIImage, spec: PhotoFilterSpec) -> UIImage {
        image
    }
}

#endif
