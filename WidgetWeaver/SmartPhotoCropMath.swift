//
//  SmartPhotoCropMath.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import UIKit

enum SmartPhotoCropMath {
    static func pixelSnappedRect(_ rect: NormalisedRect, masterPixels: PixelSize, rectAspect: Double) -> NormalisedRect {
        let a = max(0.0001, rectAspect)
        var r = clampRect(rect, rectAspect: a)

        let stepX = 1.0 / Double(max(1, masterPixels.width))
        let stepY = 1.0 / Double(max(1, masterPixels.height))

        let snappedX = (r.x / stepX).rounded() * stepX
        let snappedY = (r.y / stepY).rounded() * stepY

        r = NormalisedRect(x: snappedX, y: snappedY, width: r.width, height: r.height)
        return clampRect(r, rectAspect: a)
    }

    static func toggleZoomRect(current: NormalisedRect, rectAspect: Double, anchor: CGPoint) -> NormalisedRect {
        let a = max(0.0001, rectAspect)

        let maxW = min(1.0, a)
        let minW = min(maxW, 0.08)

        let zoomedOutThreshold = maxW * 0.92
        let targetW: Double
        if current.width >= zoomedOutThreshold {
            targetW = max(minW, current.width / 2.0)
        } else {
            targetW = maxW
        }

        let targetH = targetW / a

        let ax = min(1.0, max(0.0, Double(anchor.x)))
        let ay = min(1.0, max(0.0, Double(anchor.y)))

        let proposed = NormalisedRect(
            x: ax - (targetW / 2.0),
            y: ay - (targetH / 2.0),
            width: targetW,
            height: targetH
        )

        return clampRect(proposed, rectAspect: a)
    }

    static func pixelSize(of image: UIImage) -> PixelSize {
        if let cg = image.cgImage {
            return PixelSize(width: cg.width, height: cg.height).normalised()
        }

        let w = Int((image.size.width * image.scale).rounded())
        let h = Int((image.size.height * image.scale).rounded())
        return PixelSize(width: max(1, w), height: max(1, h)).normalised()
    }

    static func safeAspect(width: Int, height: Int) -> Double {
        let w = max(1, width)
        let h = max(1, height)
        return Double(w) / Double(h)
    }

    static func aspectFitRect(container: CGSize, imageAspect: Double) -> CGRect {
        let cw = max(1.0, container.width)
        let ch = max(1.0, container.height)
        let containerAspect = Double(cw / ch)

        let w: CGFloat
        let h: CGFloat

        if containerAspect > imageAspect {
            h = ch
            w = CGFloat(Double(ch) * imageAspect)
        } else {
            w = cw
            h = CGFloat(Double(cw) / imageAspect)
        }

        let x = (cw - w) / 2.0
        let y = (ch - h) / 2.0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func clampWidth(_ proposedWidth: Double, rectAspect: Double) -> Double {
        let a = max(0.0001, rectAspect)
        let maxWidth = min(1.0, a)
        let minWidth = min(maxWidth, 0.08)

        return min(maxWidth, max(minWidth, proposedWidth))
    }

    static func clampRect(_ rect: NormalisedRect, rectAspect: Double) -> NormalisedRect {
        let a = max(0.0001, rectAspect)

        let w = clampWidth(rect.width, rectAspect: a)
        let h = w / a

        var x = rect.x
        var y = rect.y

        x = min(max(0.0, x), 1.0 - w)
        y = min(max(0.0, y), 1.0 - h)

        return NormalisedRect(x: x, y: y, width: w, height: h).normalised()
    }
}
