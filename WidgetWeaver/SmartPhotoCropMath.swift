//
//  SmartPhotoCropMath.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import UIKit

enum SmartPhotoCropMath {
    private static let clampEpsilon: Double = 1.0e-6
    private static let minimumRectAspect: Double = 0.0001
    private static let minimumWidthFraction: Double = 0.08

    private static func sanitise(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return value
    }

    private static func safeRectAspect(_ rectAspect: Double) -> Double {
        let a = sanitise(rectAspect, fallback: 1.0)
        return max(minimumRectAspect, a)
    }

    static func pixelSnappedRect(_ rect: NormalisedRect, masterPixels: PixelSize, rectAspect: Double) -> NormalisedRect {
        let a = safeRectAspect(rectAspect)
        var r = clampRect(rect, rectAspect: a)

        let stepX = 1.0 / Double(max(1, masterPixels.width))
        let stepY = 1.0 / Double(max(1, masterPixels.height))

        var snappedX = (r.x / stepX).rounded() * stepX
        var snappedY = (r.y / stepY).rounded() * stepY

        // Edge pinning avoids jitter when the rect is already at, or extremely near, the bounds.
        let maxX = 1.0 - r.width
        let maxY = 1.0 - r.height
        let halfStepX = stepX / 2.0
        let halfStepY = stepY / 2.0

        if abs(r.x) <= halfStepX { snappedX = 0.0 }
        if abs(r.y) <= halfStepY { snappedY = 0.0 }
        if abs(r.x - maxX) <= halfStepX { snappedX = maxX }
        if abs(r.y - maxY) <= halfStepY { snappedY = maxY }

        r = NormalisedRect(x: snappedX, y: snappedY, width: r.width, height: r.height)
        return clampRect(r, rectAspect: a)
    }

    static func toggleZoomRect(current: NormalisedRect, rectAspect: Double, anchor: CGPoint) -> NormalisedRect {
        let a = safeRectAspect(rectAspect)

        let maxW = min(1.0, a)
        let minW = min(maxW, minimumWidthFraction)

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
        let a = safeRectAspect(rectAspect)
        let maxWidth = min(1.0, a)
        let minWidth = min(maxWidth, minimumWidthFraction)

        let w = sanitise(proposedWidth, fallback: maxWidth)
        let clamped = min(maxWidth, max(minWidth, w))

        if abs(clamped - minWidth) <= clampEpsilon { return minWidth }
        if abs(clamped - maxWidth) <= clampEpsilon { return maxWidth }
        return clamped
    }

    static func clampRect(_ rect: NormalisedRect, rectAspect: Double) -> NormalisedRect {
        let a = safeRectAspect(rectAspect)

        let xIn = sanitise(rect.x, fallback: 0.0)
        let yIn = sanitise(rect.y, fallback: 0.0)
        let wIn = sanitise(rect.width, fallback: min(1.0, a))

        var w = clampWidth(wIn, rectAspect: a)
        var h = w / a

        if !h.isFinite || h <= 0.0 {
            h = 1.0
            w = min(1.0, a)
        }

        if h > 1.0 {
            h = 1.0
            w = min(1.0, a)
        }

        var x = xIn
        var y = yIn

        let maxX = max(0.0, 1.0 - w)
        let maxY = max(0.0, 1.0 - h)

        x = min(max(0.0, x), maxX)
        y = min(max(0.0, y), maxY)

        let right = x + w
        if right > 1.0 {
            x = max(0.0, x - (right - 1.0))
        }

        let bottom = y + h
        if bottom > 1.0 {
            y = max(0.0, y - (bottom - 1.0))
        }

        x = min(max(0.0, x), maxX)
        y = min(max(0.0, y), maxY)

        if abs(x) <= clampEpsilon { x = 0.0 }
        if abs(y) <= clampEpsilon { y = 0.0 }
        if abs(maxX - x) <= clampEpsilon { x = maxX }
        if abs(maxY - y) <= clampEpsilon { y = maxY }

        return NormalisedRect(x: x, y: y, width: w, height: h)
    }
}
