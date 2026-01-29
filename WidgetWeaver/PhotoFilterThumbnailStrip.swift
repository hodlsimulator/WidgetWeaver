//
//  PhotoFilterThumbnailStrip.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

@preconcurrency import Foundation
import SwiftUI
import WidgetKit
@preconcurrency import UIKit

// MARK: - Background-safe work helpers

private enum PhotoFilterThumbnailWork {
    final class Cache: @unchecked Sendable {
        private let cache: NSCache<NSString, UIImage>

        init() {
            let c = NSCache<NSString, UIImage>()
            c.countLimit = 128
            c.totalCostLimit = 24 * 1024 * 1024
            self.cache = c
        }

        func object(forKey key: NSString) -> UIImage? {
            cache.object(forKey: key)
        }

        func setObject(_ image: UIImage, forKey key: NSString, cost: Int) {
            cache.setObject(image, forKey: key, cost: cost)
        }
    }

    static let cache = Cache()

    static func cacheKey(identity: String, token: PhotoFilterToken) -> NSString {
        "\(identity)|\(token.rawValue)" as NSString
    }

    static func estimatedDecodedByteCount(_ image: UIImage) -> Int {
        if let cg = image.cgImage {
            let bytes = Int64(cg.bytesPerRow) * Int64(cg.height)
            if bytes > Int64(Int.max) { return Int.max }
            if bytes <= 0 { return 1 }
            return Int(bytes)
        }

        let w = Int64(image.size.width * image.scale)
        let h = Int64(image.size.height * image.scale)
        let bytes = w * h * 4
        if bytes > Int64(Int.max) { return Int.max }
        if bytes <= 0 { return 1 }
        return Int(bytes)
    }

    static func loadBaseImage(source: PhotoFilterThumbnailSource, maxPixel: Int) -> (UIImage, String)? {
        let px = max(1, maxPixel)

        if let img = AppGroup.loadWidgetImage(fileName: source.primaryFileName, maxPixel: px) {
            let identity = fileIdentity(fileName: source.primaryFileName, maxPixel: px)
            return (img, identity)
        }

        if let fallback = source.fallbackFileName,
           let img = AppGroup.loadWidgetImage(fileName: fallback, maxPixel: px)
        {
            let identity = fileIdentity(fileName: fallback, maxPixel: px)
            return (img, identity)
        }

        return nil
    }

    static func fileIdentity(fileName: String, maxPixel: Int) -> String {
        let url = AppGroup.imageFileURL(fileName: fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "\(fileName)|px=\(maxPixel)"
        }

        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        return "\(fileName)|\(size)|\(Int64(mod))|px=\(maxPixel)"
    }
}

// MARK: - Source identity

struct PhotoFilterThumbnailSource: Hashable, Sendable {
    let primaryFileName: String
    let fallbackFileName: String?

    static func make(from imageSpec: ImageSpec, family: WidgetFamily) -> PhotoFilterThumbnailSource? {
        let base = sanitisedFileName(imageSpec.fileName)
        guard !base.isEmpty else { return nil }

        if let sp = imageSpec.smartPhoto {
            let manifestFile = (sp.shuffleManifestFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !manifestFile.isEmpty {
                guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFile) else { return nil }
                guard let entry = manifest.entryForRender() else { return nil }
                let chosen = (entry.fileName(for: family) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let safe = sanitisedFileName(chosen)
                guard !safe.isEmpty else { return nil }
                return PhotoFilterThumbnailSource(primaryFileName: safe, fallbackFileName: nil)
            }
        }

        let perFamily = sanitisedFileName(imageSpec.fileNameForFamily(family))
        if !perFamily.isEmpty, perFamily != base {
            return PhotoFilterThumbnailSource(primaryFileName: perFamily, fallbackFileName: base)
        }

        return PhotoFilterThumbnailSource(primaryFileName: base, fallbackFileName: nil)
    }

    private static func sanitisedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }
}

// MARK: - Provider

@MainActor
final class PhotoFilterThumbnailProvider: ObservableObject {
    @Published private(set) var thumbnails: [PhotoFilterToken: UIImage] = [:]

    private var loadTask: Task<Void, Never>?
    private var activeRequestID: UUID?

    deinit {
        loadTask?.cancel()
    }

    func thumbnail(for token: PhotoFilterToken) -> UIImage? {
        thumbnails[token]
    }

    func cancel(clearThumbnails: Bool = true) {
        loadTask?.cancel()
        loadTask = nil
        activeRequestID = nil

        if clearThumbnails {
            thumbnails = [:]
        }
    }

    func load(source: PhotoFilterThumbnailSource?, maxPixel: Int) {
        loadTask?.cancel()
        thumbnails = [:]

        guard let source else {
            activeRequestID = nil
            return
        }

        let requestID = UUID()
        activeRequestID = requestID

        let px = max(1, maxPixel)

        loadTask = Task.detached(priority: .utility) { [source] in
            guard let (base, identity) = PhotoFilterThumbnailWork.loadBaseImage(source: source, maxPixel: px) else {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeRequestID == requestID else { return }
                    self.thumbnails = [:]
                }
                return
            }

            for token in PhotoFilterToken.allCases {
                if Task.isCancelled { return }

                let key = PhotoFilterThumbnailWork.cacheKey(identity: identity, token: token)

                if let cached = PhotoFilterThumbnailWork.cache.object(forKey: key) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        guard self.activeRequestID == requestID else { return }
                        self.thumbnails[token] = cached
                    }
                    continue
                }

                if Task.isCancelled { return }

                let generated: UIImage = autoreleasepool {
                    if token == .none { return base }
                    let spec = PhotoFilterSpec(token: token, intensity: 1.0)
                    return PhotoFilterEngine.shared.apply(to: base, spec: spec)
                }

                if Task.isCancelled { return }

                let cost = PhotoFilterThumbnailWork.estimatedDecodedByteCount(generated)
                PhotoFilterThumbnailWork.cache.setObject(generated, forKey: key, cost: cost)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeRequestID == requestID else { return }
                    self.thumbnails[token] = generated
                }

                await Task.yield()
            }
        }
    }
}

// MARK: - Strip UI

struct PhotoFilterThumbnailStrip: View {
    let imageSpec: ImageSpec
    let family: WidgetFamily
    @Binding var selection: PhotoFilterToken

    @StateObject private var provider = PhotoFilterThumbnailProvider()

    @Environment(\.displayScale) private var displayScale

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    private enum Metrics {
        static let thumbnailSize: CGFloat = 56
        static let placeholderCornerRadius: CGFloat = 12

        static func maxPixel(displayScale: CGFloat) -> Int {
            let s = max(1.0, displayScale)
            let px = Int(ceil(thumbnailSize * s))
            return min(max(64, px), 256)
        }
    }

    private struct LoadKey: Hashable {
        let source: PhotoFilterThumbnailSource?
        let updateToken: Int
        let family: WidgetFamily
        let maxPixel: Int
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken
        let source = PhotoFilterThumbnailSource.make(from: imageSpec, family: family)
        let maxPixel = Metrics.maxPixel(displayScale: displayScale)

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(PhotoFilterToken.allCases) { token in
                    thumbnailButton(for: token)
                }
            }
            .padding(.vertical, 4)
        }
        .task(id: LoadKey(source: source, updateToken: smartPhotoShuffleUpdateToken, family: family, maxPixel: maxPixel)) {
            provider.load(source: source, maxPixel: maxPixel)
        }
        .onDisappear {
            provider.cancel()
        }
    }

    @ViewBuilder
    private func thumbnailButton(for token: PhotoFilterToken) -> some View {
        let isSelected = (selection == token)
        let thumb = provider.thumbnail(for: token)

        Button {
            selection = token
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: Metrics.placeholderCornerRadius, style: .continuous)
                            .fill(.quaternary)

                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.placeholderCornerRadius, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Metrics.placeholderCornerRadius, style: .continuous)
                            .stroke(.tint, lineWidth: 2)
                    }
                }

                Text(token.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 60)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(token.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
