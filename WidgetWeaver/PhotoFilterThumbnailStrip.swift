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

struct PhotoFilterThumbnailSource: Hashable {
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

@MainActor
final class PhotoFilterThumbnailProvider: ObservableObject {
    @Published private(set) var thumbnails: [PhotoFilterToken: UIImage] = [:]

    private var loadTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
    }

    func thumbnail(for token: PhotoFilterToken) -> UIImage? {
        thumbnails[token]
    }

    func load(source: PhotoFilterThumbnailSource?, maxPixel: Int = 180) {
        loadTask?.cancel()
        thumbnails = [:]

        guard let source else { return }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            guard let (base, identity) = await Self.loadBaseImage(source: source, maxPixel: maxPixel) else {
                self.thumbnails = [:]
                return
            }

            for token in PhotoFilterToken.allCases {
                if Task.isCancelled { return }

                let key = Self.cacheKey(identity: identity, token: token)

                if let cached = Self.cache.object(forKey: key) {
                    self.thumbnails[token] = cached
                    continue
                }

                let generated: UIImage = await Task.detached(priority: .utility) {
                    if token == .none { return base }
                    let spec = PhotoFilterSpec(token: token, intensity: 1.0)
                    return PhotoFilterEngine.shared.apply(to: base, spec: spec)
                }.value

                if Task.isCancelled { return }

                let cost = Self.estimatedDecodedByteCount(generated)
                Self.cache.setObject(generated, forKey: key, cost: cost)

                self.thumbnails[token] = generated

                await Task.yield()
            }
        }
    }

    // MARK: - Cache

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 128
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    private static func cacheKey(identity: String, token: PhotoFilterToken) -> NSString {
        "\(identity)|\(token.rawValue)" as NSString
    }

    private static func estimatedDecodedByteCount(_ image: UIImage) -> Int {
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

    // MARK: - Base image load

    private static func loadBaseImage(source: PhotoFilterThumbnailSource, maxPixel: Int) async -> (UIImage, String)? {
        await Task.detached(priority: .utility) {
            let px = max(1, maxPixel)

            if let img = AppGroup.loadWidgetImage(fileName: source.primaryFileName, maxPixel: px) {
                let identity = fileIdentity(fileName: source.primaryFileName)
                return (img, identity)
            }

            if let fallback = source.fallbackFileName,
               let img = AppGroup.loadWidgetImage(fileName: fallback, maxPixel: px)
            {
                let identity = fileIdentity(fileName: fallback)
                return (img, identity)
            }

            return nil
        }.value
    }

    nonisolated private static func fileIdentity(fileName: String) -> String {
        let url = AppGroup.imageFileURL(fileName: fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return fileName
        }

        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        return "\(fileName)|\(size)|\(Int64(mod))"
    }
}

struct PhotoFilterThumbnailStrip: View {
    let imageSpec: ImageSpec
    let family: WidgetFamily
    @Binding var selection: PhotoFilterToken

    @StateObject private var provider = PhotoFilterThumbnailProvider()

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    private struct LoadKey: Hashable {
        let source: PhotoFilterThumbnailSource?
        let updateToken: Int
        let family: WidgetFamily
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken
        let source = PhotoFilterThumbnailSource.make(from: imageSpec, family: family)

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(PhotoFilterToken.allCases) { token in
                    thumbnailButton(for: token)
                }
            }
            .padding(.vertical, 4)
        }
        .task(id: LoadKey(source: source, updateToken: smartPhotoShuffleUpdateToken, family: family)) {
            provider.load(source: source)
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
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary)

                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
