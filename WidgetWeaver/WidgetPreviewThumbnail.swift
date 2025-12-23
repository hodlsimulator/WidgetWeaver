//
//  WidgetPreviewThumbnail.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Split out of WidgetPreviewDock.swift on 12/23/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

// MARK: - Thumbnail raster cache (smooth scrolling)

@MainActor
private final class WidgetPreviewThumbnailRasterCache {
    static let shared = WidgetPreviewThumbnailRasterCache()

    private let cache: NSCache<NSString, UIImage>

    private init() {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 96
        self.cache = c
    }

    func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// Cache key changes whenever the spec content changes (even if `updatedAt` is not bumped yet),
    /// or when external rendering dependencies change (weather snapshot, variables, etc.).
    func makeKey(
        spec: WidgetSpec,
        family: WidgetFamily,
        size: CGSize,
        colorScheme: ColorScheme,
        screenScale: CGFloat,
        dependencyFingerprint: String
    ) -> String {
        let fingerprint = Self.contentFingerprint(for: spec)

        let updatedMs = Int(spec.updatedAt.timeIntervalSince1970 * 1000.0)
        let w = Int((size.width * 10.0).rounded())
        let h = Int((size.height * 10.0).rounded())
        let s = Int((screenScale * 10.0).rounded())
        let scheme = (colorScheme == .dark) ? "dark" : "light"

        return "\(spec.id.uuidString)|\(fingerprint)|\(updatedMs)|\(family)|\(w)x\(h)|\(scheme)|\(s)|\(dependencyFingerprint)"
    }

    func renderThumbnail(
        spec: WidgetSpec,
        family: WidgetFamily,
        baseSize: CGSize,
        scale: CGFloat,
        thumbnailSize: CGSize,
        colorScheme: ColorScheme,
        rendererScale: CGFloat
    ) -> UIImage? {
        guard #available(iOS 16.0, *) else { return nil }

        let cornerRadius: CGFloat = 12
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let content = WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .frame(width: baseSize.width, height: baseSize.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height, alignment: .center)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .clipped()
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(thumbnailSize)
        renderer.scale = rendererScale

        return renderer.uiImage
    }

    private static func contentFingerprint(for spec: WidgetSpec) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(spec.normalised())
            return fnv1a64Hex(data)
        } catch {
            return "0000000000000000"
        }
    }

    private static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for b in data {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Preview thumbnail

@MainActor
struct WidgetPreviewThumbnail: View {
    enum RenderingStyle: Hashable, Sendable {
        case rasterCached
        case live
    }

    let spec: WidgetSpec
    let family: WidgetFamily
    var height: CGFloat
    var renderingStyle: RenderingStyle = .rasterCached

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.wwThumbnailRenderingEnabled) private var thumbnailRenderingEnabled

    // These are inputs that can affect the rendered output without changing the WidgetSpec.
    // Including them in the raster cache key prevents the collapsed preview from showing stale thumbnails.
    @AppStorage("widgetweaver.variables.v1", store: AppGroup.userDefaults) private var variablesData: Data = Data()
    @AppStorage("widgetweaver.specs.v1", store: AppGroup.userDefaults) private var specsData: Data = Data()

    @AppStorage(WidgetWeaverWeatherStore.Keys.locationData, store: AppGroup.userDefaults) private var weatherLocationData: Data = Data()
    @AppStorage(WidgetWeaverWeatherStore.Keys.snapshotData, store: AppGroup.userDefaults) private var weatherSnapshotData: Data = Data()
    @AppStorage(WidgetWeaverWeatherStore.Keys.attributionData, store: AppGroup.userDefaults) private var weatherAttributionData: Data = Data()
    @AppStorage(WidgetWeaverWeatherStore.Keys.unitPreference, store: AppGroup.userDefaults) private var weatherUnitPreferenceRaw: String = ""
    @AppStorage(WidgetWeaverWeatherStore.Keys.lastError, store: AppGroup.userDefaults) private var weatherLastError: String = ""

    @State private var image: UIImage? = nil
    @State private var imageKey: String? = nil

    var body: some View {
        switch renderingStyle {
        case .live:
            liveBody
        case .rasterCached:
            if #available(iOS 16.0, *) {
                rasterisedBody
            } else {
                liveBody
            }
        }
    }

    @available(iOS 16.0, *)
    private var rasterisedBody: some View {
        let base = WidgetPreview.widgetSize(for: family)
        let scale = height / base.height
        let scaledWidth = base.width * scale
        let thumbSize = CGSize(width: scaledWidth, height: height)
        let rendererScale = min(displayScale, 2.0)

        let dependencyFingerprint = buildDependencyFingerprint()

        let key = WidgetPreviewThumbnailRasterCache.shared.makeKey(
            spec: spec,
            family: family,
            size: thumbSize,
            colorScheme: colorScheme,
            screenScale: rendererScale,
            dependencyFingerprint: dependencyFingerprint
        )

        let taskID = "\(key)|\(thumbnailRenderingEnabled ? 1 : 0)"

        return Group {
            if let img = image, imageKey == key {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: thumbSize.width, height: thumbSize.height, alignment: .center)
                    .accessibilityHidden(true)
            } else if let cached = WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) {
                Image(uiImage: cached)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: thumbSize.width, height: thumbSize.height, alignment: .center)
                    .accessibilityHidden(true)
            } else {
                placeholder(size: thumbSize)
            }
        }
        .task(id: taskID) {
            // Always drop any stale in-memory image when the key changes.
            if imageKey != key {
                image = nil
                imageKey = nil
            }

            guard thumbnailRenderingEnabled else { return }

            if let cached = WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) {
                image = cached
                imageKey = key
                return
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            if let cached = WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) {
                image = cached
                imageKey = key
                return
            }

            if let rendered = WidgetPreviewThumbnailRasterCache.shared.renderThumbnail(
                spec: spec,
                family: family,
                baseSize: base,
                scale: scale,
                thumbnailSize: thumbSize,
                colorScheme: colorScheme,
                rendererScale: rendererScale
            ) {
                WidgetPreviewThumbnailRasterCache.shared.store(rendered, forKey: key)
                image = rendered
                imageKey = key
            }
        }
    }

    private var liveBody: some View {
        let base = WidgetPreview.widgetSize(for: family)
        let scale = height / base.height
        let scaledWidth = base.width * scale

        return WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: scaledWidth, height: height, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10))
            )
            .clipped()
    }

    private func placeholder(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return ZStack {
            shape
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))

            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        .frame(width: size.width, height: size.height, alignment: .center)
        .accessibilityHidden(true)
    }

    private func buildDependencyFingerprint() -> String {
        let usesWeather = spec.normalised().usesWeatherRendering()

        var parts: [String] = []
        parts.append(fnv1a64Hex(variablesData))
        parts.append(fnv1a64Hex(specsData))

        if usesWeather {
            parts.append(fnv1a64Hex(weatherLocationData))
            parts.append(fnv1a64Hex(weatherSnapshotData))
            parts.append(fnv1a64Hex(weatherAttributionData))
            parts.append(fnv1a64Hex(Data(weatherUnitPreferenceRaw.utf8)))
            parts.append(fnv1a64Hex(Data(weatherLastError.utf8)))
        }

        return parts.joined(separator: ".")
    }

    private func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for b in data {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
