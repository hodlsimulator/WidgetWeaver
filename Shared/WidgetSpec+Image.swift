//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public func normalised() -> PixelSize {
        PixelSize(
            width: max(1, width),
            height: max(1, height)
        )
    }
}

public struct NormalisedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func normalised() -> NormalisedRect {
        let w = width.isFinite ? width : 1
        let h = height.isFinite ? height : 1
        let safeW = min(1, max(0.02, w))
        let safeH = min(1, max(0.02, h))

        let x0 = x.isFinite ? x : 0
        let y0 = y.isFinite ? y : 0

        let safeX = min(1 - safeW, max(0, x0))
        let safeY = min(1 - safeH, max(0, y0))

        return NormalisedRect(
            x: safeX,
            y: safeY,
            width: safeW,
            height: safeH
        )
    }
}

public struct WidgetImageSpec: Codable, Hashable, Sendable {
    public enum Backing: String, Codable, Hashable, Sendable {
        case none
        case solid
        case gradient
    }

    public var backing: Backing
    public var solidColorHex: String?
    public var gradientTopHex: String?
    public var gradientBottomHex: String?

    public var imageSourceFileName: String?
    public var imageFit: ImageFit?
    public var imageOpacity: Double?

    public init(
        backing: Backing,
        solidColorHex: String? = nil,
        gradientTopHex: String? = nil,
        gradientBottomHex: String? = nil,
        imageSourceFileName: String? = nil,
        imageFit: ImageFit? = nil,
        imageOpacity: Double? = nil
    ) {
        self.backing = backing
        self.solidColorHex = solidColorHex
        self.gradientTopHex = gradientTopHex
        self.gradientBottomHex = gradientBottomHex
        self.imageSourceFileName = imageSourceFileName
        self.imageFit = imageFit
        self.imageOpacity = imageOpacity
    }

    public func normalised() -> WidgetImageSpec {
        var s = self
        s.imageOpacity = imageOpacity?.clamped(to: 0...1)
        return s
    }
}

public enum ImageFit: String, Codable, Hashable, Sendable {
    case fill
    case fit
}

public struct ImageLayoutSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case none
        case oneUp
        case oneUpBackground
        case twoUp
        case twoUpBackground
        case threeUp
        case threeUpBackground
        case fourUp
        case fourUpBackground
        case smartPhoto
        case smartPhotoShuffle
    }

    public var kind: Kind
    public var images: [WidgetImageSpec]

    public var smartPhoto: SmartPhotoSpec?

    public init(kind: Kind, images: [WidgetImageSpec] = [], smartPhoto: SmartPhotoSpec? = nil) {
        self.kind = kind
        self.images = images
        self.smartPhoto = smartPhoto
    }

    public func normalised() -> ImageLayoutSpec {
        var s = self
        s.images = images.map { $0.normalised() }
        s.smartPhoto = smartPhoto?.normalised()
        return s
    }
}

public struct SmartPhotoVariantSpec: Codable, Hashable, Sendable {
    public var renderFileName: String
    public var cropRect: NormalisedRect
    public var pixelSize: PixelSize

    /// Optional straightening angle applied before cropping (degrees).
    /// Nil (or effectively zero) means no straightening.
    public var straightenDegrees: Double?

    /// Optional clockwise quarter-turn rotation (90° steps) applied before straightening.
    /// Nil (or effectively zero) means no rotation.
    public var rotationQuarterTurns: Int?

    public init(
        renderFileName: String,
        cropRect: NormalisedRect,
        pixelSize: PixelSize,
        straightenDegrees: Double? = nil,
        rotationQuarterTurns: Int? = nil
    ) {
        self.renderFileName = renderFileName
        self.cropRect = cropRect
        self.pixelSize = pixelSize
        self.straightenDegrees = straightenDegrees
        self.rotationQuarterTurns = rotationQuarterTurns
    }

    public func normalised() -> SmartPhotoVariantSpec {
        let normalisedDegrees: Double? = {
            guard let d = straightenDegrees else { return nil }
            let clamped = d.clamped(to: -45...45)
            if abs(clamped) < 0.0001 { return nil }
            return clamped
        }()

        let normalisedQuarterTurns: Int? = {
            guard let t = rotationQuarterTurns else { return nil }
            let m = ((t % 4) + 4) % 4
            if m == 0 { return nil }
            return m
        }()

        return SmartPhotoVariantSpec(
            renderFileName: SmartPhotoSpec.sanitisedFileName(renderFileName),
            cropRect: cropRect.normalised(),
            pixelSize: pixelSize.normalised(),
            straightenDegrees: normalisedDegrees,
            rotationQuarterTurns: normalisedQuarterTurns
        )
    }
}

public struct SmartPhotoSpec: Codable, Hashable, Sendable {
    public var masterFileName: String
    public var small: SmartPhotoVariantSpec
    public var medium: SmartPhotoVariantSpec
    public var large: SmartPhotoVariantSpec

    public init(
        masterFileName: String,
        small: SmartPhotoVariantSpec,
        medium: SmartPhotoVariantSpec,
        large: SmartPhotoVariantSpec
    ) {
        self.masterFileName = masterFileName
        self.small = small
        self.medium = medium
        self.large = large
    }

    public func normalised() -> SmartPhotoSpec {
        SmartPhotoSpec(
            masterFileName: Self.sanitisedFileName(masterFileName),
            small: small.normalised(),
            medium: medium.normalised(),
            large: large.normalised()
        )
    }

    public static func sanitisedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "image" }
        return trimmed
    }
}

public struct SmartPhotoShuffleSpec: Codable, Hashable, Sendable {
    public var manifestFileName: String
    public var entryIDs: [String]?

    public init(manifestFileName: String, entryIDs: [String]? = nil) {
        self.manifestFileName = manifestFileName
        self.entryIDs = entryIDs
    }

    public func normalised() -> SmartPhotoShuffleSpec {
        var s = self
        s.manifestFileName = SmartPhotoSpec.sanitisedFileName(manifestFileName)
        if let ids = entryIDs?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            s.entryIDs = ids.isEmpty ? nil : ids
        }
        return s
    }
}

public struct WidgetTextSpec: Codable, Hashable, Sendable {
    public enum Alignment: String, Codable, Hashable, Sendable {
        case leading
        case centre
        case trailing
    }

    public var text: String
    public var fontName: String?
    public var fontSize: Double
    public var colorHex: String
    public var alignment: Alignment
    public var opacity: Double

    public init(
        text: String,
        fontName: String? = nil,
        fontSize: Double,
        colorHex: String,
        alignment: Alignment,
        opacity: Double = 1.0
    ) {
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.alignment = alignment
        self.opacity = opacity
    }

    public func normalised() -> WidgetTextSpec {
        var s = self
        s.fontSize = max(1, fontSize)
        s.opacity = opacity.clamped(to: 0...1)
        s.text = text
        s.colorHex = colorHex
        return s
    }
}

public struct WidgetSpec: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var layout: ImageLayoutSpec?
    public var titleText: WidgetTextSpec?
    public var subtitleText: WidgetTextSpec?

    public init(
        id: String,
        name: String,
        layout: ImageLayoutSpec? = nil,
        titleText: WidgetTextSpec? = nil,
        subtitleText: WidgetTextSpec? = nil
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.titleText = titleText
        self.subtitleText = subtitleText
    }

    public func normalised() -> WidgetSpec {
        var s = self
        s.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        s.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.layout = layout?.normalised()
        s.titleText = titleText?.normalised()
        s.subtitleText = subtitleText?.normalised()
        return s
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
