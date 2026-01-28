//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

public enum ImageContentModeToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fill
    case fit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        }
    }
}

/// Backwards-compatible alias used by older specs/code.
public typealias ImageCropToken = ImageContentModeToken

// MARK: - Smart Photo metadata

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public func normalised() -> PixelSize {
        PixelSize(width: max(1, width), height: max(1, height))
    }
}

/// A rectangle in normalised 0...1 space, with origin at the top-left.
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
        func clamp01(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

        let nx = clamp01(x)
        let ny = clamp01(y)
        var nw = max(0.0, clamp01(width))
        var nh = max(0.0, clamp01(height))

        if nx + nw > 1.0 {
            nw = max(0.0, 1.0 - nx)
        }
        if ny + nh > 1.0 {
            nh = max(0.0, 1.0 - ny)
        }

        // Avoid degenerate rects which can cause downstream crop failures.
        if nw == 0.0 { nw = min(1.0, 0.0001) }
        if nh == 0.0 { nh = min(1.0, 0.0001) }

        return NormalisedRect(x: nx, y: ny, width: nw, height: nh)
    }
}

public struct SmartPhotoVariantSpec: Codable, Hashable, Sendable {
    public var renderFileName: String
    public var cropRect: NormalisedRect
    public var pixelSize: PixelSize

    /// Optional straightening angle applied before cropping (degrees).
    /// Nil (or effectively zero) means no straightening.
    public var straightenDegrees: Double?

    /// Optional quarter-turn rotation (0/90/180/270 degrees) applied before straightening + cropping.
    /// Nil (or effectively zero) means no quarter-turn rotation.
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
            guard let raw = rotationQuarterTurns else { return nil }
            let m = raw % 4
            let t = (m + 4) % 4
            if t == 0 { return nil }
            return t
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

    public var small: SmartPhotoVariantSpec?
    public var medium: SmartPhotoVariantSpec?
    public var large: SmartPhotoVariantSpec?

    public var algorithmVersion: Int
    public var preparedAt: Date


    /// Optional shuffle manifest file name stored in the App Group container.
    public var shuffleManifestFileName: String?
    public init(
        masterFileName: String,
        small: SmartPhotoVariantSpec?,
        medium: SmartPhotoVariantSpec?,
        large: SmartPhotoVariantSpec?,
        algorithmVersion: Int,
        preparedAt: Date,
        shuffleManifestFileName: String? = nil
    ) {

        self.masterFileName = masterFileName
        self.small = small
        self.medium = medium
        self.large = large
        self.algorithmVersion = algorithmVersion
        self.preparedAt = preparedAt
        self.shuffleManifestFileName = shuffleManifestFileName
    }

    public func normalised() -> SmartPhotoSpec {
        let safeShuffle: String? = {
            guard let raw = shuffleManifestFileName else { return nil }
            let safe = Self.sanitisedFileName(raw)
            return safe.isEmpty ? nil : safe
        }()

        return SmartPhotoSpec(
            masterFileName: Self.sanitisedFileName(masterFileName),
            small: small?.normalised(),
            medium: medium?.normalised(),
            large: large?.normalised(),
            algorithmVersion: max(0, algorithmVersion),
            preparedAt: preparedAt,
            shuffleManifestFileName: safeShuffle
        )
    }

    public static func sanitisedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }
}

// MARK: - Image spec

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var contentMode: ImageContentModeToken
    public var height: Double
    public var cornerRadius: Double

    /// Optional non-destructive photo filter configuration.
    /// - Backwards compatible: older stored specs will not contain this key.
    public var filter: PhotoFilterSpec?

    /// Optional smart photo payload (master + per-family renders).
    /// - Backwards compatible: older stored specs will not contain this key.
    public var smartPhoto: SmartPhotoSpec?

    public init(
        fileName: String,
        contentMode: ImageContentModeToken = .fill,
        height: Double = 120,
        cornerRadius: Double = 16,
        filter: PhotoFilterSpec? = nil,
        smartPhoto: SmartPhotoSpec? = nil
    ) {
        self.fileName = fileName
        self.contentMode = contentMode
        self.height = height
        self.cornerRadius = cornerRadius
        self.filter = filter
        self.smartPhoto = smartPhoto
    }

    public func normalised() -> ImageSpec {
        var s = self

        // Trim + strip any path components (defensive against imported specs).
        let trimmed = s.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        s.fileName = String(last.prefix(256))

        // Keep values in a sane range.
        s.height = s.height.clamped(to: 0...512)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...128)

        if let f = s.filter {
            s.filter = f.normalisedOrNil()
        } else {
            s.filter = nil
        }

        s.smartPhoto = s.smartPhoto?.normalised()

        return s
    }

    /// Base fileName + smart master + all render variants, sanitised and de-duped.
    public func allReferencedFileNames() -> [String] {
        var set = Set<String>()

        func insert(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let last = (trimmed as NSString).lastPathComponent
            let safe = String(last.prefix(256))
            guard !safe.isEmpty else { return }
            set.insert(safe)
        }

        insert(fileName)

        if let sp = smartPhoto {
            insert(sp.masterFileName)
            if let v = sp.small { insert(v.renderFileName) }
            if let v = sp.medium { insert(v.renderFileName) }
            if let v = sp.large { insert(v.renderFileName) }
        }

        return Array(set).sorted()
    }

    #if canImport(WidgetKit)
    public func fileNameForFamily(_ family: WidgetFamily) -> String {
        if let sp = smartPhoto {
            let candidate: String?

            switch family {
            case .systemSmall:
                candidate = sp.small?.renderFileName
            case .systemMedium:
                candidate = sp.medium?.renderFileName
            case .systemLarge:
                candidate = sp.large?.renderFileName
            default:
                candidate = nil
            }

            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let last = (trimmed as NSString).lastPathComponent
                return String(last.prefix(256))
            }
        }

        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }
    #endif

    // MARK: Codable compatibility (older specs may omit newer keys)

    private enum CodingKeys: String, CodingKey {
        case fileName
        case contentMode
        case height
        case cornerRadius
        case filter

        // Older key name used by an earlier schema.
        case crop

        // New optional payload.
        case smartPhoto
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let fileName = (try? c.decode(String.self, forKey: .fileName)) ?? ""

        let mode =
            (try? c.decode(ImageContentModeToken.self, forKey: .contentMode))
            ?? (try? c.decode(ImageContentModeToken.self, forKey: .crop))
            ?? .fill

        let height = (try? c.decode(Double.self, forKey: .height)) ?? 120
        let cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? 16

        let filter = try? c.decode(PhotoFilterSpec.self, forKey: .filter)
        let smart = try? c.decode(SmartPhotoSpec.self, forKey: .smartPhoto)

        self.init(
            fileName: fileName,
            contentMode: mode,
            height: height,
            cornerRadius: cornerRadius,
            filter: filter,
            smartPhoto: smart
        )

        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(height, forKey: .height)
        try c.encode(cornerRadius, forKey: .cornerRadius)

        if let filter = filter?.normalisedOrNil() {
            try c.encode(filter, forKey: .filter)
        }

        if let smartPhoto {
            try c.encode(smartPhoto, forKey: .smartPhoto)
        }

        // Backwards compatibility for older readers.
        try c.encode(contentMode, forKey: .crop)
    }
}


// MARK: - Referenced image file names (spec-level)

public extension WidgetSpec {
    /// Returns a de-duped list of all image file names referenced by this design, including:
    /// - base `image.fileName`
    /// - Smart Photo master + per-family renders (when present)
    /// - matched-set variants (Small / Medium / Large)
    func allReferencedImageFileNames() -> [String] {
        var set = Set<String>()

        func insert(_ image: ImageSpec?) {
            guard let image else { return }
            for name in image.allReferencedFileNames() {
                set.insert(name)
            }
        }

        insert(image)

        if let matchedSet {
            insert(matchedSet.small?.image)
            insert(matchedSet.medium?.image)
            insert(matchedSet.large?.image)
        }

        return Array(set).sorted()
    }
}

#if canImport(UIKit)
public extension ImageSpec {
    func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }

    #if canImport(WidgetKit)
    func loadUIImageFromAppGroup(family: WidgetFamily) -> UIImage? {
        AppGroup.loadUIImage(fileName: fileNameForFamily(family))
    }

    /// Loads the image used for rendering, preferring any Smart Photo per-family render when available.
    ///
    /// WidgetKit builds (app extensions) use an ImageIO downsampled single-decode path to reduce memory
    /// pressure and avoid multi-entry image caching.
    func loadUIImageForRender(family: WidgetFamily?, debugContext: WWPhotoLogContext? = nil) -> UIImage? {
        let isAppExtension: Bool = {
            let url = Bundle.main.bundleURL
            if url.pathExtension == "appex" { return true }
            return url.path.contains(".appex/")
        }()

        let shouldLog = (debugContext != nil)
        let ctx = WWPhotoLogContext(
            renderContext: debugContext?.renderContext,
            family: debugContext?.family,
            template: debugContext?.template,
            specID: debugContext?.specID,
            specName: debugContext?.specName,
            isAppExtension: isAppExtension
        )

        let activeFilter: PhotoFilterSpec? = {
            guard WidgetWeaverFeatureFlags.photoFiltersEnabled else { return nil }
            return filter?.normalisedOrNil()
        }()

        func applyFilterIfNeeded(_ image: UIImage?) -> UIImage? {
            guard let image else { return nil }
            guard let activeFilter else { return image }
            return PhotoFilterEngine.shared.apply(to: image, spec: activeFilter)
        }

        // Smart Photo shuffle uses a manifest JSON in the App Group to choose the current entry’s
        // per-family render file. This selection should apply in both the app preview and the
        // widget extension.
        let shuffleManifestFileName: String? = {
            guard let sp = smartPhoto else { return nil }
            let mf = (sp.shuffleManifestFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return mf.isEmpty ? nil : mf
        }()

        if shouldLog {
            WWPhotoDebugLog.appendLazy(
                category: "photo.resolve",
                throttleID: "resolve.begin.\(fileName)",
                minInterval: 15.0,
                context: ctx
            ) {
                let fam = family.map(String.init(describing:)) ?? "nil"
                return "loadUIImageForRender: begin baseFile=\(fileName) family=\(fam)"
            }
        }

        let resolvedFileName: String? = {
            guard let family else {
                if shouldLog {
                    WWPhotoDebugLog.appendLazy(
                        category: "photo.resolve",
                        throttleID: "resolve.noFamily.\(fileName)",
                        minInterval: 30.0,
                        context: ctx
                    ) {
                        "resolve: family nil -> baseFile=\(fileName)"
                    }
                }
                return fileName
            }

            if let manifestFile = shuffleManifestFileName {
                if shouldLog {
                    WWPhotoDebugLog.appendLazy(
                        category: "photo.resolve",
                        throttleID: "resolve.shuffle.\(manifestFile)",
                        minInterval: 20.0,
                        context: ctx
                    ) {
                        "resolve: shuffle enabled manifest=\(manifestFile)"
                    }
                }

                guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFile) else {
                    if shouldLog {
                        WWPhotoDebugLog.appendLazy(
                            category: "photo.resolve",
                            throttleID: "resolve.manifestMissing.\(manifestFile)",
                            minInterval: 20.0,
                            context: ctx
                        ) {
                            "resolve: manifest load failed manifest=\(manifestFile)"
                        }
                    }
                    return nil
                }

                guard let entry = manifest.entryForRender() else {
                    if shouldLog {
                        WWPhotoDebugLog.appendLazy(
                            category: "photo.resolve",
                            throttleID: "resolve.noPrepared.\(manifestFile)",
                            minInterval: 20.0,
                            context: ctx
                        ) {
                            "resolve: entryForRender nil manifestEntries=\(manifest.entries.count) currentIndex=\(manifest.currentIndex)"
                        }
                    }
                    return nil
                }

                let entryIndex = manifest.entries.firstIndex(where: { $0.id == entry.id }) ?? -1
                let chosen = entry.fileName(for: family)
                let isManual = entry.isManual(for: family)
                let trimmed = (chosen ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if shouldLog {
                        WWPhotoDebugLog.appendLazy(
                            category: "photo.resolve",
                            throttleID: "resolve.shuffle.chosen.\(manifestFile).\(trimmed)",
                            minInterval: 20.0,
                            context: ctx
                        ) {
                            "resolve: chosen entryID=\(entry.id) entryIndex=\(entryIndex) manual=\(isManual) file=\(trimmed)"
                        }
                    }
                    return trimmed
                }

                if shouldLog {
                    WWPhotoDebugLog.appendLazy(
                        category: "photo.resolve",
                        throttleID: "resolve.shuffle.emptyFile.\(manifestFile)",
                        minInterval: 20.0,
                        context: ctx
                    ) {
                        "resolve: entry fileName(for:) empty"
                    }
                }
                return nil
            }

            let fm = fileNameForFamily(family)
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.resolve",
                    throttleID: "resolve.smart.family.\(fm)",
                    minInterval: 30.0,
                    context: ctx
                ) {
                    "resolve: smartPhoto family candidate=\(fm)"
                }
            }
            return fm
        }()

        guard let resolvedFileName, !resolvedFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.resolve",
                    throttleID: "resolve.nil.\(fileName)",
                    minInterval: 30.0,
                    context: ctx
                ) {
                    "resolve: resolvedFileName nil baseFile=\(fileName)"
                }
            }
            return nil
        }

        if isAppExtension {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.resolve",
                    throttleID: "resolve.appex.load.\(resolvedFileName)",
                    minInterval: 20.0,
                    context: ctx
                ) {
                    "resolve: appex downsample begin file=\(resolvedFileName)"
                }
            }

            let img = AppGroup.loadWidgetImage(fileName: resolvedFileName, maxPixel: 1024, debugContext: ctx)
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.resolve",
                    throttleID: "resolve.appex.result.\(resolvedFileName)",
                    minInterval: 20.0,
                    context: ctx
                ) {
                    img == nil ? "resolve: appex downsample failed file=\(resolvedFileName)" : "resolve: appex downsample ok file=\(resolvedFileName)"
                }
            }
            return applyFilterIfNeeded(img)
        }

        if let img = AppGroup.loadUIImage(fileName: resolvedFileName) {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.resolve",
                    throttleID: "resolve.app.cached.\(resolvedFileName)",
                    minInterval: 30.0,
                    context: ctx
                ) {
                    "resolve: app cached ok file=\(resolvedFileName)"
                }
            }
            return applyFilterIfNeeded(img)
        }

        if shouldLog {
            WWPhotoDebugLog.appendLazy(
                category: "photo.resolve",
                throttleID: "resolve.app.loadFail.\(resolvedFileName)",
                minInterval: 30.0,
                context: ctx
            ) {
                "resolve: app load failed file=\(resolvedFileName)"
            }
        }

        if shuffleManifestFileName != nil {
            return nil
        }

        let base = AppGroup.loadUIImage(fileName: fileName)
        if shouldLog {
            WWPhotoDebugLog.appendLazy(
                category: "photo.resolve",
                throttleID: "resolve.app.base.\(fileName)",
                minInterval: 30.0,
                context: ctx
            ) {
                base == nil ? "resolve: app base load failed file=\(fileName)" : "resolve: app base ok file=\(fileName)"
            }
        }
        return applyFilterIfNeeded(base)
    }
    #endif
}
#endif
