//
//  SmartPhotoCropRotationPreview.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import UIKit

enum SmartPhotoCropRotationPreview {
    static func normalisedQuarterTurns(_ quarterTurns: Int) -> Int {
        let t = quarterTurns % 4
        return (t + 4) % 4
    }

    static func rotatedPreviewImage(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let t = normalisedQuarterTurns(quarterTurns)
        guard t != 0 else { return image }

        let source = normalisedOrientation(image)
        let sourceSize = source.size
        let newSize: CGSize = (t % 2 == 0) ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)

        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2.0, y: newSize.height / 2.0)
            c.rotate(by: CGFloat(t) * (.pi / 2.0))
            source.draw(
                in: CGRect(
                    x: -sourceSize.width / 2.0,
                    y: -sourceSize.height / 2.0,
                    width: sourceSize.width,
                    height: sourceSize.height
                )
            )
        }
    }

    static func rotatePointCW(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(clamp01(1.0 - Double(point.y))),
            y: CGFloat(clamp01(Double(point.x)))
        )
    }

    static func rotatePointCCW(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(clamp01(Double(point.y))),
            y: CGFloat(clamp01(1.0 - Double(point.x)))
        )
    }

    static func rotateRectCW(_ rect: NormalisedRect) -> NormalisedRect {
        let center = CGPoint(
            x: CGFloat(rect.x + (rect.width / 2.0)),
            y: CGFloat(rect.y + (rect.height / 2.0))
        )
        let newCenter = rotatePointCW(center)

        let proposed = NormalisedRect(
            x: Double(newCenter.x) - (rect.height / 2.0),
            y: Double(newCenter.y) - (rect.width / 2.0),
            width: rect.height,
            height: rect.width
        )

        return clampedToUnitRect(proposed)
    }

    static func rotateRectCCW(_ rect: NormalisedRect) -> NormalisedRect {
        let center = CGPoint(
            x: CGFloat(rect.x + (rect.width / 2.0)),
            y: CGFloat(rect.y + (rect.height / 2.0))
        )
        let newCenter = rotatePointCCW(center)

        let proposed = NormalisedRect(
            x: Double(newCenter.x) - (rect.height / 2.0),
            y: Double(newCenter.y) - (rect.width / 2.0),
            width: rect.height,
            height: rect.width
        )

        return clampedToUnitRect(proposed)
    }

    static func remapCropRectCW(_ rect: NormalisedRect, targetRectAspect: Double) -> NormalisedRect {
        let a = max(0.0001, targetRectAspect)
        let area = rect.width * rect.height

        let w = sqrt(area * a)
        let h = w / a

        let center = CGPoint(
            x: CGFloat(rect.x + (rect.width / 2.0)),
            y: CGFloat(rect.y + (rect.height / 2.0))
        )
        let newCenter = rotatePointCW(center)

        let proposed = NormalisedRect(
            x: Double(newCenter.x) - (w / 2.0),
            y: Double(newCenter.y) - (h / 2.0),
            width: w,
            height: h
        )

        return clampedToUnitRect(proposed)
    }

    static func remapCropRectCCW(_ rect: NormalisedRect, targetRectAspect: Double) -> NormalisedRect {
        let a = max(0.0001, targetRectAspect)
        let area = rect.width * rect.height

        let w = sqrt(area * a)
        let h = w / a

        let center = CGPoint(
            x: CGFloat(rect.x + (rect.width / 2.0)),
            y: CGFloat(rect.y + (rect.height / 2.0))
        )
        let newCenter = rotatePointCCW(center)

        let proposed = NormalisedRect(
            x: Double(newCenter.x) - (w / 2.0),
            y: Double(newCenter.y) - (h / 2.0),
            width: w,
            height: h
        )

        return clampedToUnitRect(proposed)
    }

    private static func normalisedOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func clamp01(_ v: Double) -> Double {
        min(1.0, max(0.0, v))
    }

    private static func clampedToUnitRect(_ rect: NormalisedRect) -> NormalisedRect {
        let w = min(1.0, max(0.0001, rect.width))
        let h = min(1.0, max(0.0001, rect.height))

        var x = rect.x
        var y = rect.y

        x = min(max(0.0, x), 1.0 - w)
        y = min(max(0.0, y), 1.0 - h)

        return NormalisedRect(x: x, y: y, width: w, height: h)
    }
}
