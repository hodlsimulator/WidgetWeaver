//
//  SmartPhotoCropEditorDebugOverlay.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import SwiftUI
import UIKit
import Vision

#if DEBUG

struct SmartPhotoDebugOverlayView: View {
    let displayRect: CGRect
    let detection: SmartPhotoDetection

    var body: some View {
        ZStack {
            if let face = detection.faceRect {
                LineOverlayView(
                    rect: mapRect(face),
                    lineWidth: 2,
                    opacity: 0.95
                )
            }

            if let eyes = detection.eyePoints {
                DotOverlayView(
                    points: eyes.map(mapPoint(_:)),
                    radius: 4,
                    opacity: 0.95
                )
            }

            if let horizon = detection.horizonLine {
                LineSegmentOverlayView(
                    a: mapPoint(horizon.a),
                    b: mapPoint(horizon.b),
                    lineWidth: 2,
                    opacity: 0.95
                )
            }

            if let saliency = detection.saliencyPoints, !saliency.isEmpty {
                DotOverlayView(
                    points: saliency.map(mapPoint(_:)),
                    radius: 3,
                    opacity: 0.75
                )
            }

            if let textRects = detection.textRects, !textRects.isEmpty {
                ForEach(Array(textRects.enumerated()), id: \.offset) { _, r in
                    LineOverlayView(
                        rect: mapRect(r),
                        lineWidth: 1,
                        opacity: 0.6
                    )
                }
            }
        }
    }

    private func mapPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: displayRect.minX + p.x * displayRect.width,
            y: displayRect.minY + p.y * displayRect.height
        )
    }

    private func mapRect(_ r: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + r.minX * displayRect.width,
            y: displayRect.minY + r.minY * displayRect.height,
            width: r.width * displayRect.width,
            height: r.height * displayRect.height
        )
    }
}

struct LineOverlayView: View {
    let rect: CGRect
    let lineWidth: CGFloat
    let opacity: Double

    var body: some View {
        Path { path in
            path.addRect(rect)
        }
        .stroke(.green.opacity(opacity), lineWidth: lineWidth)
    }
}

struct DotOverlayView: View {
    let points: [CGPoint]
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        ForEach(Array(points.enumerated()), id: \.offset) { _, p in
            Circle()
                .fill(.red.opacity(opacity))
                .frame(width: radius * 2, height: radius * 2)
                .position(p)
        }
    }
}

struct LineSegmentOverlayView: View {
    let a: CGPoint
    let b: CGPoint
    let lineWidth: CGFloat
    let opacity: Double

    var body: some View {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
        }
        .stroke(.yellow.opacity(opacity), lineWidth: lineWidth)
    }
}

#endif

extension UIImage {
    func jpegDataSafe(compressionQuality: CGFloat) -> Data? {
        jpegData(compressionQuality: compressionQuality)
    }
}

struct StraightenGridOverlay: View {
    let rect: CGRect
    let divisions: Int

    var body: some View {
        Path { path in
            guard divisions >= 2 else { return }
            let dx = rect.width / CGFloat(divisions)
            let dy = rect.height / CGFloat(divisions)

            for i in 1..<divisions {
                let x = rect.minX + CGFloat(i) * dx
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + CGFloat(i) * dy
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.22), lineWidth: 1)
    }
}

struct CropThirdsGridOverlay: View {
    let frame: CGRect
    let divisions: Int

    var body: some View {
        Path { path in
            guard divisions >= 2 else { return }
            let dx = frame.width / CGFloat(divisions)
            let dy = frame.height / CGFloat(divisions)

            for i in 1..<divisions {
                let x = frame.minX + CGFloat(i) * dx
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))

                let y = frame.minY + CGFloat(i) * dy
                path.move(to: CGPoint(x: frame.minX, y: y))
                path.addLine(to: CGPoint(x: frame.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.45), lineWidth: 1)
    }
}
