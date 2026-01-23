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

        // Edge pinning reduces jitter when the rect is already at, or extremely near, the bounds.
        let maxX = 1.0 - r.width
        let maxY = 1.0 - r.height
        let halfStepX = stepX / 2.0
        let halfStepY = stepY / 2.0

        if abs(r.x) <= halfStepX { snappedX = 0.0 }
        if abs(r.y) <= halfStepY { snappedY = 0.0 }
        if abs(r.x - maxX) <= halfStepX { snappedX = maxX }
        if abs(r.y - maxY) <= halfStepY { snappedY = maxY }

        snappedX = min(max(0.0, snappedX), maxX)
        snappedY = min(max(0.0, snappedY), maxY)

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

        let maxWidth = min(1.0, a)
        let wInFallback = maxWidth

        let wCandidate: Double = {
            if rect.width.isFinite, rect.width > 0.0 { return rect.width }
            if rect.height.isFinite, rect.height > 0.0 { return rect.height * a }
            return wInFallback
        }()

        var w = clampWidth(wCandidate, rectAspect: a)
        var h = w / a

        if !h.isFinite || h <= 0.0 {
            w = maxWidth
            h = w / a
        }

        let inputWForCentre: Double = {
            if rect.width.isFinite, rect.width > 0.0 { return rect.width }
            return w
        }()

        let inputHForCentre: Double = {
            if rect.height.isFinite, rect.height > 0.0 { return rect.height }
            return inputWForCentre / a
        }()

        let cx = xIn + (inputWForCentre / 2.0)
        let cy = yIn + (inputHForCentre / 2.0)

        var x = cx - (w / 2.0)
        var y = cy - (h / 2.0)

        let maxX = max(0.0, 1.0 - w)
        let maxY = max(0.0, 1.0 - h)

        x = min(max(0.0, x), maxX)
        y = min(max(0.0, y), maxY)

        // Right/bottom edge pinning protects against floating point drift after clamping.
        if x + w > 1.0 { x = max(0.0, 1.0 - w) }
        if y + h > 1.0 { y = max(0.0, 1.0 - h) }

        x = min(max(0.0, x), maxX)
        y = min(max(0.0, y), maxY)

        if abs(x) <= clampEpsilon { x = 0.0 }
        if abs(y) <= clampEpsilon { y = 0.0 }
        if abs(maxX - x) <= clampEpsilon { x = maxX }
        if abs(maxY - y) <= clampEpsilon { y = maxY }

        #if DEBUG
        let minWidth = min(maxWidth, minimumWidthFraction)
        assert(w.isFinite && h.isFinite && x.isFinite && y.isFinite)
        assert(w >= minWidth - clampEpsilon && w <= maxWidth + clampEpsilon)
        assert(h > 0.0 && h <= 1.0 + clampEpsilon)
        assert(x >= -clampEpsilon && y >= -clampEpsilon)
        assert(x + w <= 1.0 + clampEpsilon)
        assert(y + h <= 1.0 + clampEpsilon)
        #endif

        return NormalisedRect(x: x, y: y, width: w, height: h)
    }

    static func straightenConstrainedRect(_ rect: NormalisedRect, rectAspect: Double, imageAspect: Double, straightenDegrees: Double) -> NormalisedRect {
        let base = clampRect(rect, rectAspect: rectAspect)
        let degrees = sanitise(straightenDegrees, fallback: 0.0)
        if abs(degrees) < 0.01 { return base }
        let radians = abs(degrees) * Double.pi / 180.0
        let safeBounds = straightenSafeBounds(imageAspect: imageAspect, radians: radians)
        return clampRect(base, rectAspect: rectAspect, within: safeBounds)
    }

    static func straightenSafeBounds(imageAspect: Double, radians: Double) -> NormalisedRect {
        let angle = abs(sanitise(radians, fallback: 0.0))
        if angle < 1.0e-8 { return NormalisedRect(x: 0, y: 0, width: 1, height: 1) }

        let aspect = max(minimumRectAspect, abs(sanitise(imageAspect, fallback: 1.0)))
        let w = aspect
        let h = 1.0

        let (safeW, safeH) = rotatedRectWithMaxArea(width: w, height: h, radians: angle)
        let wf = min(1.0, max(0.0, safeW / w))
        let hf = min(1.0, max(0.0, safeH / h))

        let x = 0.5 - (wf / 2.0)
        let y = 0.5 - (hf / 2.0)
        return NormalisedRect(x: x, y: y, width: wf, height: hf).normalised()
    }

    static func clampRect(_ rect: NormalisedRect, rectAspect: Double, within bounds: NormalisedRect) -> NormalisedRect {
        let a = safeRectAspect(rectAspect)
        let b = bounds.normalised()

        let bx = sanitise(b.x, fallback: 0.0)
        let by = sanitise(b.y, fallback: 0.0)
        let bw = sanitise(b.width, fallback: 1.0)
        let bh = sanitise(b.height, fallback: 1.0)

        let maxW = max(0.0, min(bw, bh * a))
        let minW = min(maxW, minimumWidthFraction)

        let xIn = sanitise(rect.x, fallback: bx)
        let yIn = sanitise(rect.y, fallback: by)

        let wCandidate: Double = {
            if rect.width.isFinite, rect.width > 0.0 { return rect.width }
            if rect.height.isFinite, rect.height > 0.0 { return rect.height * a }
            return maxW
        }()

        var w = sanitise(wCandidate, fallback: maxW)
        w = min(maxW, max(minW, w))
        var h = w / a

        if !h.isFinite || h <= 0.0 {
            w = maxW
            h = (a > minimumRectAspect) ? (w / a) : bh
        }

        let inputWForCentre: Double = {
            if rect.width.isFinite, rect.width > 0.0 { return rect.width }
            return w
        }()

        let inputHForCentre: Double = {
            if rect.height.isFinite, rect.height > 0.0 { return rect.height }
            return inputWForCentre / a
        }()

        let cx = xIn + (inputWForCentre / 2.0)
        let cy = yIn + (inputHForCentre / 2.0)

        var x = cx - (w / 2.0)
        var y = cy - (h / 2.0)

        let minX = bx
        let minY = by
        let maxX = bx + bw - w
        let maxY = by + bh - h

        x = min(max(minX, x), maxX)
        y = min(max(minY, y), maxY)

        if x + w > bx + bw { x = max(minX, (bx + bw) - w) }
        if y + h > by + bh { y = max(minY, (by + bh) - h) }

        x = min(max(minX, x), maxX)
        y = min(max(minY, y), maxY)

        if abs(x - minX) <= clampEpsilon { x = minX }
        if abs(y - minY) <= clampEpsilon { y = minY }
        if abs(maxX - x) <= clampEpsilon { x = maxX }
        if abs(maxY - y) <= clampEpsilon { y = maxY }

        #if DEBUG
        assert(w.isFinite && h.isFinite && x.isFinite && y.isFinite)
        assert(w >= minW - clampEpsilon && w <= maxW + clampEpsilon)
        assert(h > 0.0 && h <= bh + clampEpsilon)
        assert(x >= bx - clampEpsilon && y >= by - clampEpsilon)
        assert(x + w <= bx + bw + clampEpsilon)
        assert(y + h <= by + bh + clampEpsilon)
        #endif

        return NormalisedRect(x: x, y: y, width: w, height: h)
    }

    private static func rotatedRectWithMaxArea(width: Double, height: Double, radians: Double) -> (Double, Double) {
        let w = abs(sanitise(width, fallback: 1.0))
        let h = abs(sanitise(height, fallback: 1.0))
        let angle = abs(sanitise(radians, fallback: 0.0))

        if w <= clampEpsilon || h <= clampEpsilon || angle <= clampEpsilon {
            return (w, h)
        }

        let widthIsLonger = w >= h
        let sideLong = widthIsLonger ? w : h
        let sideShort = widthIsLonger ? h : w

        let sinA = abs(sin(angle))
        let cosA = abs(cos(angle))

        let nearHalfTurn = abs(sinA - cosA) < clampEpsilon
        let fullyConstrained = sideShort <= (2.0 * sinA * cosA * sideLong)

        if fullyConstrained || nearHalfTurn {
            let x = 0.5 * sideShort
            if widthIsLonger {
                let rw = x / max(clampEpsilon, sinA)
                let rh = x / max(clampEpsilon, cosA)
                return (rw, rh)
            }

            let rw = x / max(clampEpsilon, cosA)
            let rh = x / max(clampEpsilon, sinA)
            return (rw, rh)
        }

        let cos2A = (cosA * cosA) - (sinA * sinA)
        if abs(cos2A) < clampEpsilon { return (w, h) }

        let rw = (w * cosA - h * sinA) / cos2A
        let rh = (h * cosA - w * sinA) / cos2A
        return (max(0.0, rw), max(0.0, rh))
    }

}
