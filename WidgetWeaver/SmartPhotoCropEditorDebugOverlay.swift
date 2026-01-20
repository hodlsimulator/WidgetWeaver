//
//  SmartPhotoCropEditorDebugOverlay.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import SwiftUI
import UIKit
import Vision

// MARK: - Debug overlay support (Batch E)

enum SmartPhotoDebugSubjectKind: String {
    case face
    case human
    case animal
    case saliency
    case none

    var label: String {
        switch self {
        case .face: return "Face"
        case .human: return "Human"
        case .animal: return "Animal"
        case .saliency: return "Saliency"
        case .none: return "None"
        }
    }
}

struct SmartPhotoDebugDetection {
    var chosenKind: SmartPhotoDebugSubjectKind
    var chosenBoxes: [NormalisedRect]

    var faces: [NormalisedRect]
    var humans: [NormalisedRect]
    var animals: [NormalisedRect]
    var saliency: [NormalisedRect]
}

enum SmartPhotoDebugDetector {
    static func detect(masterData: Data) -> SmartPhotoDebugDetection? {
        guard let base = UIImage(data: masterData)?.ww_normalisedOrientation() else { return nil }
        let analysis = base.ww_downsampled(maxPixel: 1024)
        guard let cg = analysis.cgImage else { return nil }

        let faces = rank(rects: detectFaces(in: cg))
        let humans = rank(rects: detectHumans(in: cg))
        let animals = rank(rects: detectAnimals(in: cg))
        let saliency = rank(rects: detectSaliency(in: cg))

        let chosenKind: SmartPhotoDebugSubjectKind
        let chosenBoxes: [NormalisedRect]

        if faces.count >= 2 {
            chosenKind = .face
            chosenBoxes = faces
        } else if faces.count == 1 {
            if humans.count >= 2 {
                chosenKind = .human
                chosenBoxes = humans
            } else if saliency.count >= 2 {
                chosenKind = .saliency
                chosenBoxes = saliency
            } else {
                chosenKind = .face
                chosenBoxes = faces
            }
        } else {
            if !animals.isEmpty {
                chosenKind = .animal
                chosenBoxes = animals
            } else if !humans.isEmpty {
                chosenKind = .human
                chosenBoxes = humans
            } else if !saliency.isEmpty {
                chosenKind = .saliency
                chosenBoxes = saliency
            } else {
                chosenKind = .none
                chosenBoxes = []
            }
        }

        return SmartPhotoDebugDetection(
            chosenKind: chosenKind,
            chosenBoxes: chosenBoxes,
            faces: faces,
            humans: humans,
            animals: animals,
            saliency: saliency
        )
    }

    private static func detectFaces(in cgImage: CGImage) -> [NormalisedRect] {
        let req = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([req])
        } catch {
            return []
        }

        let results = req.results ?? []
        return results.map { toTopLeftNormalisedRect($0.boundingBox) }.filter { isUseful($0) }
    }

    private static func detectHumans(in cgImage: CGImage) -> [NormalisedRect] {
        guard #available(iOS 11.0, *) else { return [] }

        let req = VNDetectHumanRectanglesRequest()
        req.upperBodyOnly = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return []
        }

        let results = req.results ?? []
        return results.map { toTopLeftNormalisedRect($0.boundingBox) }.filter { isUseful($0) }
    }

    private static func detectAnimals(in cgImage: CGImage) -> [NormalisedRect] {
        guard #available(iOS 13.0, *) else { return [] }

        let req = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([req])
        } catch {
            return []
        }

        let results = req.results ?? []
        return results.map { toTopLeftNormalisedRect($0.boundingBox) }.filter { isUseful($0) }
    }

    private static func detectSaliency(in cgImage: CGImage) -> [NormalisedRect] {
        guard #available(iOS 13.0, *) else { return [] }

        let objReq = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attReq = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([objReq, attReq])
        } catch {
            return []
        }

        var out: [NormalisedRect] = []

        func append(from req: VNRequest) {
            guard let results = req.results as? [VNSaliencyImageObservation],
                  let obs = results.first,
                  let salient = obs.salientObjects
            else { return }

            out.append(contentsOf: salient.map { toTopLeftNormalisedRect($0.boundingBox) })
        }

        append(from: objReq)
        append(from: attReq)

        return out.filter { isUseful($0) }
    }

    private static func toTopLeftNormalisedRect(_ visionRect: CGRect) -> NormalisedRect {
        let x = Double(visionRect.minX)
        let y = Double(1.0 - visionRect.maxY)
        let w = Double(visionRect.width)
        let h = Double(visionRect.height)
        return NormalisedRect(x: x, y: y, width: w, height: h).normalised()
    }

    private static func isUseful(_ r: NormalisedRect) -> Bool {
        if r.width <= 0.0001 { return false }
        if r.height <= 0.0001 { return false }
        if r.x >= 1.0 || r.y >= 1.0 { return false }
        if (r.x + r.width) <= 0.0 { return false }
        if (r.y + r.height) <= 0.0 { return false }
        return true
    }

    private static func rank(rects: [NormalisedRect]) -> [NormalisedRect] {
        guard rects.count > 1 else { return rects }

        func area(_ r: NormalisedRect) -> Double { max(0.0, r.width) * max(0.0, r.height) }
        func dist2ToCentre(_ r: NormalisedRect) -> Double {
            let cx = r.x + (r.width / 2.0)
            let cy = r.y + (r.height / 2.0)
            let dx = cx - 0.5
            let dy = cy - 0.5
            return dx * dx + dy * dy
        }

        return rects.sorted { a, b in
            let aA = area(a)
            let bA = area(b)

            let threshold = max(0.00064, 0.01 * max(aA, bA))
            if abs(aA - bA) > threshold {
                return aA > bA
            }

            return dist2ToCentre(a) < dist2ToCentre(b)
        }
    }
}

struct SmartPhotoDebugOverlayView: View {
    let displayRect: CGRect
    let detection: SmartPhotoDebugDetection

    var body: some View {
        ZStack {
            boxes(detection.saliency, stroke: .orange.opacity(0.85), lineWidth: 1)
            boxes(detection.animals, stroke: .blue.opacity(0.9), lineWidth: 1)
            boxes(detection.humans, stroke: .green.opacity(0.9), lineWidth: 1)
            boxes(detection.faces, stroke: .yellow.opacity(0.95), lineWidth: 1)

            boxes(detection.chosenBoxes, stroke: .white.opacity(0.95), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private func boxes(_ rects: [NormalisedRect], stroke: Color, lineWidth: CGFloat) -> some View {
        Path { p in
            for r in rects {
                p.addRect(toViewRect(r))
            }
        }
        .stroke(stroke, lineWidth: lineWidth)
    }

    private func toViewRect(_ r: NormalisedRect) -> CGRect {
        CGRect(
            x: displayRect.minX + CGFloat(r.x) * displayRect.width,
            y: displayRect.minY + CGFloat(r.y) * displayRect.height,
            width: CGFloat(r.width) * displayRect.width,
            height: CGFloat(r.height) * displayRect.height
        )
    }
}

struct SmartPhotoDebugHUDView: View {
    let isDetecting: Bool
    let status: String
    let detection: SmartPhotoDebugDetection?

    var body: some View {
        let text: String = {
            if isDetecting {
                return "Debug overlay: Detecting…"
            }
            if !status.isEmpty {
                return "Debug overlay: \(status)"
            }
            if let d = detection {
                return "Debug overlay: \(d.chosenKind.label) • Faces \(d.faces.count) • Humans \(d.humans.count) • Animals \(d.animals.count) • Saliency \(d.saliency.count)"
            }
            return "Debug overlay: Ready"
        }()

        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.leading, 10)
    }
}

extension UIImage {
    func ww_normalisedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? self
    }

    func ww_downsampled(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0, maxSide > maxPixel else { return self }

        let ratio = maxPixel / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? self
    }
}
