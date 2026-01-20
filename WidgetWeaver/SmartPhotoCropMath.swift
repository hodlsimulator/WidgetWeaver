//
//  SmartPhotoCropMath.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import UIKit

enum SmartPhotoCropMath {
    static func safeAspect(width: Int, height: Int) -> Double {
        let w = max(1, width)
        let h = max(1, height)
        return Double(w) / Double(h)
    }

    static func pixelSize(of image: UIImage) -> PixelSize {
        if let cg = image.cgImage {
            return PixelSize(width: cg.width, height: cg.height)
        }
        let w = Int(max(1, image.size.width * image.scale))
        let h = Int(max(1, image.size.height * image.scale))
        return PixelSize(width: w, height: h)
    }

    static func aspectFitRect(containerSize: CGSize, imageAspect: Double, padding: CGFloat) -> CGRect {
        let w = max(0, containerSize.width - padding * 2)
        let h = max(0, containerSize.height - padding * 2)

        let containerAspect = (h == 0) ? 1 : Double(w / h)

        if containerAspect > imageAspect {
            let targetH = h
            let targetW = CGFloat(imageAspect) * targetH
            let x = (containerSize.width - targetW) / 2
            let y = (containerSize.height - targetH) / 2
            return CGRect(x: x, y: y, width: targetW, height: targetH)
        } else {
            let targetW = w
            let targetH = targetW / CGFloat(imageAspect)
            let x = (containerSize.width - targetW) / 2
            let y = (containerSize.height - targetH) / 2
            return CGRect(x: x, y: y, width: targetW, height: targetH)
        }
    }

    static func clampWidth(_ width: Double, rectAspect: Double) -> Double {
        let maxWidth = min(1.0, rectAspect)
        return min(maxWidth, max(0.02, width))
    }

    static func clampRect(_ rect: NormalisedRect, rectAspect: Double) -> NormalisedRect {
        let width = clampWidth(rect.width, rectAspect: rectAspect)
        let height = width / rectAspect

        let x = min(1 - width, max(0, rect.x))
        let y = min(1 - height, max(0, rect.y))

        return NormalisedRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Manual rotation helpers

    static func normalisedRotationQuarterTurns(_ quarterTurns: Int) -> Int {
        let m = quarterTurns % 4
        if m < 0 { return m + 4 }
        return m
    }

    static func rotationLabel(forQuarterTurns quarterTurns: Int) -> String {
        let turns = normalisedRotationQuarterTurns(quarterTurns)
        switch turns {
        case 0: return "0°"
        case 1: return "90°"
        case 2: return "180°"
        case 3: return "270°"
        default: return "0°"
        }
    }

    static func rectAspect(
        originalMasterPixels: PixelSize,
        quarterTurns: Int,
        targetPixels: PixelSize
    ) -> Double {
        let turns = normalisedRotationQuarterTurns(quarterTurns)
        let effectivePixels: PixelSize = (turns % 2 == 0)
            ? originalMasterPixels
            : PixelSize(width: originalMasterPixels.height, height: originalMasterPixels.width)

        let masterAspect = safeAspect(width: effectivePixels.width, height: effectivePixels.height)
        let targetAspect = safeAspect(width: targetPixels.width, height: targetPixels.height)
        return targetAspect / masterAspect
    }

    static func rotatedCropRectForQuarterTurn(
        current: NormalisedRect,
        clockwise: Bool,
        oldRectAspect: Double,
        newRectAspect: Double
    ) -> NormalisedRect {
        let safeCurrent = current.normalised()

        let oldMaxWidth = max(0.0001, min(1.0, oldRectAspect))
        let zoomFraction = min(1.0, max(0.05, safeCurrent.width / oldMaxWidth))

        let cx = safeCurrent.x + safeCurrent.width / 2
        let cy = safeCurrent.y + safeCurrent.height / 2

        let newCenterX: Double
        let newCenterY: Double
        if clockwise {
            newCenterX = 1.0 - cy
            newCenterY = cx
        } else {
            newCenterX = cy
            newCenterY = 1.0 - cx
        }

        let newMaxWidth = min(1.0, newRectAspect)
        let newWidth = clampWidth(newMaxWidth * zoomFraction, rectAspect: newRectAspect)
        let newHeight = newWidth / newRectAspect

        let proposed = NormalisedRect(
            x: newCenterX - newWidth / 2,
            y: newCenterY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )

        return clampRect(proposed, rectAspect: newRectAspect)
    }
}
