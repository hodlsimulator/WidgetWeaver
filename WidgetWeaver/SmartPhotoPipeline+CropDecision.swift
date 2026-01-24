//
//  SmartPhotoPipeline+CropDecision.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import Foundation
import UIKit
import WidgetKit

// MARK: - Crop decision

struct SmartPhotoVariantPlan {
    var cropRect: NormalisedRect
}

enum SmartPhotoVariantBuilder {
    static func buildVariant(
        family: WidgetFamily,
        targetPixels: PixelSize,
        detection: SmartPhotoDetection,
        analysisSize: CGSize
    ) -> SmartPhotoVariantPlan {
        let targetAspect = CGFloat(targetPixels.width) / CGFloat(max(1, targetPixels.height))

        let crop: CGRect
        if detection.kind == .none || detection.boxes.isEmpty {
            crop = centredCropRect(imageSize: analysisSize, targetAspect: targetAspect)
        } else {
            crop = subjectCropRect(
                imageSize: analysisSize,
                targetAspect: targetAspect,
                detection: detection,
                family: family
            )
        }

        let norm = NormalisedRect(
            x: Double(crop.minX / analysisSize.width),
            y: Double(crop.minY / analysisSize.height),
            width: Double(crop.width / analysisSize.width),
            height: Double(crop.height / analysisSize.height)
        ).normalised()

        return SmartPhotoVariantPlan(cropRect: norm)
    }

    private static func centredCropRect(imageSize: CGSize, targetAspect: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let imageAspect = imageSize.width / imageSize.height

        var cropW: CGFloat
        var cropH: CGFloat

        if imageAspect > targetAspect {
            cropH = imageSize.height
            cropW = cropH * targetAspect
        } else {
            cropW = imageSize.width
            cropH = cropW / targetAspect
        }

        let x = (imageSize.width - cropW) / 2.0
        let y = (imageSize.height - cropH) / 2.0
        return CGRect(x: x, y: y, width: cropW, height: cropH)
    }

    private static func subjectCropRect(
        imageSize: CGSize,
        targetAspect: CGFloat,
        detection: SmartPhotoDetection,
        family: WidgetFamily
    ) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)

        let ranked = detection.boxes

        var selected: [CGRect] = []
        var effectiveKind: SmartPhotoSubjectKind = detection.kind

        switch family {
        case .systemSmall:
            if let pair = pickPairForSmall(detection: detection, imageSize: imageSize) {
                selected = pair.boxes
                effectiveKind = pair.kind
            } else {
                selected = Array(ranked.prefix(1))
                effectiveKind = detection.kind
            }

        case .systemMedium:
            selected = Array(ranked.prefix(2))
            effectiveKind = detection.kind

        case .systemLarge:
            selected = ranked
            effectiveKind = detection.kind

        default:
            selected = Array(ranked.prefix(1))
            effectiveKind = detection.kind
        }

        guard !selected.isEmpty else {
            return centredCropRect(imageSize: imageSize, targetAspect: targetAspect)
        }

        let expanded = selected.map { expandSubjectBox($0, kind: effectiveKind, family: family, imageSize: imageSize).intersection(bounds) }
        var unionRect = expanded.first ?? centredCropRect(imageSize: imageSize, targetAspect: targetAspect)
        for r in expanded.dropFirst() {
            unionRect = unionRect.union(r)
        }

        let padScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.20
            case .systemMedium: return 1.15
            case .systemLarge: return 1.10
            default: return 1.15
            }
        }()

        // Padding is about safety; centre remains based on the subject union.
        let focus = scaleRect(unionRect, factor: padScale).intersection(bounds)

        // Small uses the union centre to keep pairs fairly centred, even if padding is clipped.
        // Medium/Large keep the previous behaviour (centre from the padded focus rect).
        var centre = CGPoint(x: focus.midX, y: focus.midY)
        if family == .systemSmall {
            centre = CGPoint(x: unionRect.midX, y: unionRect.midY)
        }

        var baseW = focus.width
        var baseH = focus.height
        let focusAspect = max(0.0001, baseW) / max(0.0001, baseH)

        if focusAspect > targetAspect {
            baseH = baseW / targetAspect
        } else {
            baseW = baseH * targetAspect
        }

        let extraScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.06
            case .systemMedium: return 1.04
            case .systemLarge: return 1.02
            default: return 1.04
            }
        }()

        var cropW = baseW * extraScale
        var cropH = baseH * extraScale

        let minDimFrac: CGFloat = {
            switch family {
            case .systemSmall: return 0.38
            case .systemMedium: return 0.40
            case .systemLarge: return 0.55
            default: return 0.40
            }
        }()

        let minW = imageSize.width * minDimFrac
        let minH = imageSize.height * minDimFrac

        // Minimum size that still preserves the padded subject union.
        var minAllowedW = baseW
        var minAllowedH = baseH
        if minAllowedW < minW {
            minAllowedW = minW
            minAllowedH = minAllowedW / targetAspect
        }
        if minAllowedH < minH {
            minAllowedH = minH
            minAllowedW = minAllowedH * targetAspect
        }
        if minAllowedW > imageSize.width {
            minAllowedW = imageSize.width
            minAllowedH = minAllowedW / targetAspect
        }
        if minAllowedH > imageSize.height {
            minAllowedH = imageSize.height
            minAllowedW = minAllowedH * targetAspect
        }

        if cropW < minW {
            cropW = minW
            cropH = cropW / targetAspect
        }
        if cropH < minH {
            cropH = minH
            cropW = cropH * targetAspect
        }

        if cropW > imageSize.width {
            cropW = imageSize.width
            cropH = cropW / targetAspect
        }
        if cropH > imageSize.height {
            cropH = imageSize.height
            cropW = cropH * targetAspect
        }

        if effectiveKind == .face || effectiveKind == .human {
            let biasFactor: CGFloat = {
                switch effectiveKind {
                case .face:
                    switch family {
                    case .systemSmall: return 0.12
                    case .systemMedium: return 0.08
                    case .systemLarge: return 0.05
                    default: return 0.08
                    }

                case .human:
                    switch family {
                    case .systemSmall: return 0.10
                    case .systemMedium: return 0.07
                    case .systemLarge: return 0.05
                    default: return 0.07
                    }

                default:
                    return 0
                }
            }()

            if biasFactor > 0 {
                let biasHeight = (family == .systemSmall) ? unionRect.height : focus.height
                centre.y -= biasHeight * biasFactor
            }
        }

        // Small-specific clamp to avoid extreme zoom-out.
        if family == .systemSmall {
            let maxCropAreaFracSmall: CGFloat = 0.75
            let imageArea = max(1, imageSize.width * imageSize.height)
            let maxArea = imageArea * maxCropAreaFracSmall
            let cropArea = cropW * cropH

            if cropArea > maxArea {
                let maxWByArea = sqrt(maxArea * targetAspect)
                let maxWByBounds = min(imageSize.width, imageSize.height * targetAspect)
                let maxW = min(maxWByArea, maxWByBounds)
                let maxH = maxW / targetAspect

                if maxW >= minAllowedW && maxH >= minAllowedH {
                    cropW = min(cropW, maxW)
                    cropH = cropW / targetAspect
                }
            }
        }

        // Soft clamp for small: try shrinking toward the minimum acceptable size before shifting to bounds.
        if family == .systemSmall {
            let maxWBoundForCentre = 2.0 * min(centre.x, imageSize.width - centre.x)
            let maxHBoundForCentre = 2.0 * min(centre.y, imageSize.height - centre.y)
            let maxWCentred = min(maxWBoundForCentre, maxHBoundForCentre * targetAspect)
            let maxHCentred = maxWCentred / targetAspect

            if cropW > maxWCentred, maxWCentred >= minAllowedW, maxHCentred >= minAllowedH {
                cropW = maxWCentred
                cropH = maxHCentred
            }
        }

        var x = centre.x - cropW / 2.0
        var y = centre.y - cropH / 2.0

        x = min(max(0, x), imageSize.width - cropW)
        y = min(max(0, y), imageSize.height - cropH)

        return CGRect(x: x, y: y, width: cropW, height: cropH).intersection(bounds)
    }

    private struct SmartPhotoPairChoice {
        var boxes: [CGRect]
        var score: CGFloat
    }

    private struct SmartPhotoPairCandidate {
        var kind: SmartPhotoSubjectKind
        var boxes: [CGRect]
        var score: CGFloat
    }

    private static func pickPairForSmall(detection: SmartPhotoDetection, imageSize: CGSize) -> (kind: SmartPhotoSubjectKind, boxes: [CGRect])? {
        var candidates: [SmartPhotoPairCandidate] = []

        func kindWeight(_ kind: SmartPhotoSubjectKind) -> CGFloat {
            switch kind {
            case .face:
                return 1.00
            case .human:
                return 0.97
            case .animal:
                return 0.94
            case .saliency:
                return 0.88
            case .none:
                return 0
            }
        }

        let perKind: [(SmartPhotoSubjectKind, [CGRect])] = [
            (.face, detection.faces),
            (.human, detection.humans),
            (.animal, detection.animals),
            (.saliency, detection.saliency)
        ]

        for (kind, boxes) in perKind {
            guard boxes.count >= 2 else { continue }
            if let choice = bestPairCandidate(from: boxes, imageSize: imageSize) {
                candidates.append(SmartPhotoPairCandidate(kind: kind, boxes: choice.boxes, score: choice.score))
            }
        }

        candidates.append(contentsOf: syntheticFacePartnerCandidates(detection: detection, imageSize: imageSize))

        guard !candidates.isEmpty else { return nil }

        let chosen = candidates.max { lhs, rhs in
            let l = lhs.score * kindWeight(lhs.kind)
            let r = rhs.score * kindWeight(rhs.kind)

            if abs(l - r) > 0.0005 {
                return l < r
            }

            return lhs.score < rhs.score
        }

        guard let best = chosen else { return nil }
        return (kind: best.kind, boxes: best.boxes)
    }

    private static func syntheticFacePartnerCandidates(detection: SmartPhotoDetection, imageSize: CGSize) -> [SmartPhotoPairCandidate] {
        guard !detection.faces.isEmpty else { return [] }
        guard imageSize.width > 1, imageSize.height > 1 else { return [] }

        let faces = Array(detection.faces.prefix(2))
        let humans = Array(detection.humans.prefix(6))
        let animals = Array(detection.animals.prefix(6))
        let saliency = Array(detection.saliency.prefix(8))

        func normalised(_ r: CGRect) -> CGRect {
            CGRect(
                x: r.minX / imageSize.width,
                y: r.minY / imageSize.height,
                width: r.width / imageSize.width,
                height: r.height / imageSize.height
            )
        }

        func area(_ r: CGRect) -> CGFloat {
            max(0, r.width) * max(0, r.height)
        }

        func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let unionA = area(a) + area(b) - interA
            return unionA > 0 ? interA / unionA : 0
        }

        func overlapRatioMin(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let minA = min(area(a), area(b))
            return minA > 0 ? interA / minA : 0
        }

        func score(_ r: CGRect) -> CGFloat {
            let a = area(r)
            let cx = r.midX
            let cy = r.midY
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist: CGFloat = 0.70710678
            let prox = max(0, 1.0 - min(1.0, dist / maxDist))
            return a * 0.6 + prox * 0.4
        }

        let minEachArea: CGFloat = 0.015
        let minUnionArea: CGFloat = 0.06
        let maxHorizontalSeparation: CGFloat = 0.60
        let maxVerticalSeparation: CGFloat = 0.35
        let maxIou: CGFloat = 0.55
        let minUnionAspect: CGFloat = 0.35
        let maxUnionAspect: CGFloat = 2.80

        func pairPassesBaseConstraints(_ a: CGRect, _ b: CGRect) -> Bool {
            let aArea = area(a)
            let bArea = area(b)
            let union = a.union(b)
            let unionArea = area(union)

            if (aArea < minEachArea || bArea < minEachArea) && unionArea < minUnionArea {
                return false
            }

            let dx = abs(a.midX - b.midX)
            let dy = abs(a.midY - b.midY)

            if dx > maxHorizontalSeparation { return false }
            if dy > maxVerticalSeparation { return false }

            if iou(a, b) > maxIou { return false }
            if overlapRatioMin(a, b) > 0.85 { return false }

            let aspect = union.width / max(0.0001, union.height)
            if aspect < minUnionAspect || aspect > maxUnionAspect {
                return false
            }

            return true
        }

        func bestFacePairCandidate(from faces: [CGRect], imageSize: CGSize) -> SmartPhotoPairChoice? {
            guard faces.count >= 2 else { return nil }

            var best: SmartPhotoPairChoice? = nil

            for i in 0..<(faces.count - 1) {
                for j in (i + 1)..<faces.count {
                    let a = faces[i]
                    let b = faces[j]
                    let na = normalised(a)
                    let nb = normalised(b)

                    guard pairPassesBaseConstraints(na, nb) else { continue }

                    let union = na.union(nb)
                    let unionScore = score(union)

                    let aScore = score(na)
                    let bScore = score(nb)

                    let balance = min(aScore, bScore) / max(0.0001, max(aScore, bScore))
                    let s = unionScore * 0.7 + balance * 0.3

                    if let current = best {
                        if s > current.score {
                            best = SmartPhotoPairChoice(boxes: [a, b], score: s)
                        }
                    } else {
                        best = SmartPhotoPairChoice(boxes: [a, b], score: s)
                    }
                }
            }

            return best
        }

        func bestPartnerForFace(_ face: CGRect, partnerRects: [CGRect], partnerKind: SmartPhotoSubjectKind) -> SmartPhotoPairCandidate? {
            let nFace = normalised(face)
            let faceScore = score(nFace)

            func facePartnerAllowed(face: CGRect, partner: CGRect, partnerKind: SmartPhotoSubjectKind) -> Bool {
                let dx = abs(face.midX - partner.midX)
                let dy = abs(face.midY - partner.midY)

                let dxLimit: CGFloat
                let dyLimit: CGFloat

                switch partnerKind {
                case .human:
                    dxLimit = 0.55
                    dyLimit = 0.35
                case .animal:
                    dxLimit = 0.58
                    dyLimit = 0.38
                case .saliency:
                    dxLimit = 0.60
                    dyLimit = 0.40
                default:
                    dxLimit = 0.60
                    dyLimit = 0.40
                }

                if dx > dxLimit { return false }
                if dy > dyLimit { return false }

                if iou(face, partner) > 0.55 { return false }
                if overlapRatioMin(face, partner) > 0.85 { return false }

                let union = face.union(partner)
                let aspect = union.width / max(0.0001, union.height)
                if aspect < minUnionAspect || aspect > maxUnionAspect {
                    return false
                }

                return true
            }

            var bestPartner: (rect: CGRect, kind: SmartPhotoSubjectKind, pairScore: CGFloat)? = nil

            func considerPartners(kind: SmartPhotoSubjectKind, list: [CGRect]) {
                for p in list {
                    let np = normalised(p)
                    guard facePartnerAllowed(face: nFace, partner: np, partnerKind: kind) else { continue }

                    let union = nFace.union(np)
                    let unionScore = score(union)

                    let partnerScore = score(np)
                    let balance = min(faceScore, partnerScore) / max(0.0001, max(faceScore, partnerScore))
                    let s = unionScore * 0.7 + balance * 0.3

                    if let current = bestPartner {
                        if s > current.pairScore {
                            bestPartner = (rect: p, kind: kind, pairScore: s)
                        }
                    } else {
                        bestPartner = (rect: p, kind: kind, pairScore: s)
                    }
                }
            }

            considerPartners(kind: partnerKind, list: partnerRects)

            guard let best = bestPartner else { return nil }
            return SmartPhotoPairCandidate(kind: best.kind, boxes: [face, best.rect], score: best.pairScore)
        }

        var out: [SmartPhotoPairCandidate] = []

        if let facesChoice = bestFacePairCandidate(from: faces, imageSize: imageSize) {
            out.append(SmartPhotoPairCandidate(kind: .face, boxes: facesChoice.boxes, score: facesChoice.score))
        }

        for face in faces {
            if let c = bestPartnerForFace(face, partnerRects: humans, partnerKind: .human) {
                out.append(c)
            }
            if let c = bestPartnerForFace(face, partnerRects: animals, partnerKind: .animal) {
                out.append(c)
            }
            if let c = bestPartnerForFace(face, partnerRects: saliency, partnerKind: .saliency) {
                out.append(c)
            }
        }

        // Only keep reasonable candidates.
        out = out.filter {
            let a = normalised($0.boxes[0])
            let b = normalised($0.boxes[1])
            return pairPassesBaseConstraints(a, b)
        }

        // De-duplicate by geometry.
        func key(_ c: SmartPhotoPairCandidate) -> String {
            func round2(_ v: CGFloat) -> Int { Int((v * 100.0).rounded()) }
            let a = normalised(c.boxes[0])
            let b = normalised(c.boxes[1])
            let s = [a, b].sorted { $0.minX < $1.minX }
            return "\(round2(s[0].minX)):\(round2(s[0].minY)):\(round2(s[0].width)):\(round2(s[0].height))|\(round2(s[1].minX)):\(round2(s[1].minY)):\(round2(s[1].width)):\(round2(s[1].height))"
        }

        var seen: Set<String> = []
        var unique: [SmartPhotoPairCandidate] = []
        for c in out.sorted(by: { $0.score > $1.score }) {
            let k = key(c)
            if seen.contains(k) { continue }
            seen.insert(k)
            unique.append(c)
        }

        return unique
    }

    private static func bestPairCandidate(from boxes: [CGRect], imageSize: CGSize) -> SmartPhotoPairChoice? {
        guard boxes.count >= 2 else { return nil }
        guard imageSize.width > 1, imageSize.height > 1 else { return nil }

        func normalised(_ r: CGRect) -> CGRect {
            CGRect(
                x: r.minX / imageSize.width,
                y: r.minY / imageSize.height,
                width: r.width / imageSize.width,
                height: r.height / imageSize.height
            )
        }

        func area(_ r: CGRect) -> CGFloat {
            max(0, r.width) * max(0, r.height)
        }

        func score(_ r: CGRect) -> CGFloat {
            let a = area(r)
            let cx = r.midX
            let cy = r.midY
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist: CGFloat = 0.70710678
            let prox = max(0, 1.0 - min(1.0, dist / maxDist))
            return a * 0.6 + prox * 0.4
        }

        let minEachArea: CGFloat = 0.015
        let minUnionArea: CGFloat = 0.06
        let maxHorizontalSeparation: CGFloat = 0.60
        let maxVerticalSeparation: CGFloat = 0.35
        let maxIou: CGFloat = 0.55
        let minUnionAspect: CGFloat = 0.35
        let maxUnionAspect: CGFloat = 2.80

        func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let unionA = area(a) + area(b) - interA
            return unionA > 0 ? interA / unionA : 0
        }

        func overlapRatioMin(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let minA = min(area(a), area(b))
            return minA > 0 ? interA / minA : 0
        }

        func pairPassesBaseConstraints(_ a: CGRect, _ b: CGRect) -> Bool {
            let aArea = area(a)
            let bArea = area(b)
            let union = a.union(b)
            let unionArea = area(union)

            if (aArea < minEachArea || bArea < minEachArea) && unionArea < minUnionArea {
                return false
            }

            let dx = abs(a.midX - b.midX)
            let dy = abs(a.midY - b.midY)

            if dx > maxHorizontalSeparation { return false }
            if dy > maxVerticalSeparation { return false }

            if iou(a, b) > maxIou { return false }
            if overlapRatioMin(a, b) > 0.85 { return false }

            let aspect = union.width / max(0.0001, union.height)
            if aspect < minUnionAspect || aspect > maxUnionAspect {
                return false
            }

            return true
        }

        var best: SmartPhotoPairChoice? = nil

        for i in 0..<(boxes.count - 1) {
            for j in (i + 1)..<boxes.count {
                let a = boxes[i]
                let b = boxes[j]
                let na = normalised(a)
                let nb = normalised(b)

                guard pairPassesBaseConstraints(na, nb) else { continue }

                let union = na.union(nb)
                let unionScore = score(union)

                let aScore = score(na)
                let bScore = score(nb)

                let balance = min(aScore, bScore) / max(0.0001, max(aScore, bScore))
                let s = unionScore * 0.7 + balance * 0.3

                if let current = best {
                    if s > current.score {
                        best = SmartPhotoPairChoice(boxes: [a, b], score: s)
                    }
                } else {
                    best = SmartPhotoPairChoice(boxes: [a, b], score: s)
                }
            }
        }

        return best
    }

    private static func scaleRect(_ rect: CGRect, factor: CGFloat) -> CGRect {
        guard factor.isFinite, factor > 0 else { return rect }
        let w = rect.width * factor
        let h = rect.height * factor
        let x = rect.midX - w / 2.0
        let y = rect.midY - h / 2.0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func expandSubjectBox(_ rect: CGRect, kind: SmartPhotoSubjectKind, family: WidgetFamily, imageSize: CGSize) -> CGRect {
        let isSmall = family == .systemSmall

        let basePad: CGFloat = {
            switch kind {
            case .face: return isSmall ? 0.35 : 0.30
            case .human: return isSmall ? 0.30 : 0.26
            case .animal: return isSmall ? 0.22 : 0.20
            case .saliency: return isSmall ? 0.16 : 0.14
            case .none: return 0.0
            }
        }()

        let xPad = rect.width * basePad
        let yPad = rect.height * basePad

        var expanded = rect.insetBy(dx: -xPad, dy: -yPad)

        // If a box is extremely small, add a minimum padding based on image size.
        let minPad = min(imageSize.width, imageSize.height) * (isSmall ? 0.02 : 0.015)
        if expanded.width < rect.width + (2.0 * minPad) {
            let delta = ((rect.width + (2.0 * minPad)) - expanded.width) / 2.0
            expanded = expanded.insetBy(dx: -delta, dy: 0)
        }
        if expanded.height < rect.height + (2.0 * minPad) {
            let delta = ((rect.height + (2.0 * minPad)) - expanded.height) / 2.0
            expanded = expanded.insetBy(dx: 0, dy: -delta)
        }

        return expanded
    }
}
