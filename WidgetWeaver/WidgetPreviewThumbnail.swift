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
        renderSize: CGSize,
        colorScheme: ColorScheme,
        rendererScale: CGFloat,
        dependencyFingerprint: String
    ) -> String {
        let fingerprint = Self.contentFingerprint(for: spec)

        let updatedMs = Int(spec.updatedAt.timeIntervalSince1970 * 1000.0)
        let w = Int((renderSize.width * 10.0).rounded())
        let h = Int((renderSize.height * 10.0).rounded())
        let s = Int((rendererScale * 10.0).rounded())
        let scheme = (colorScheme == .dark) ? "dark" : "light"

        return "\(spec.id.uuidString)|\(fingerprint)|\(updatedMs)|\(family)|\(w)x\(h)|\(scheme)|\(s)|\(dependencyFingerprint)"
    }

    func renderThumbnail(
        spec: WidgetSpec,
        family: WidgetFamily,
        renderSize: CGSize,
        colorScheme: ColorScheme,
        rendererScale: CGFloat
    ) -> UIImage? {
        guard #available(iOS 16.0, *) else { return nil }

        let content = WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .frame(width: renderSize.width, height: renderSize.height)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(renderSize)
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
            if #available(iOS 16.0, *) {
                renderedBody(renderImmediately: true)
            } else {
                legacyLiveBody
            }
        case .rasterCached:
            if #available(iOS 16.0, *) {
                renderedBody(renderImmediately: false)
            } else {
                legacyLiveBody
            }
        }
    }

    private var legacyLiveBody: some View {
        let base = WidgetPreview.widgetSize(for: family)
        let s = WidgetPreviewMetrics.thumbnailScale(nativeSize: base, targetHeight: height, allowUpscale: false)
        let displaySize = WidgetPreviewMetrics.scaledSize(baseSize: base, scale: s, displayScale: displayScale)

        return WidgetWeaverSpecView(spec: spec, family: family, context: .preview)
            .frame(width: base.width, height: base.height)
            .scaleEffect(s, anchor: .center)
            .frame(width: displaySize.width, height: displaySize.height, alignment: .center)
            .clipped()
    }

    @available(iOS 16.0, *)
    private func renderedBody(renderImmediately: Bool) -> some View {
        let base = WidgetPreview.widgetSize(for: family)
        let s = WidgetPreviewMetrics.thumbnailScale(nativeSize: base, targetHeight: height, allowUpscale: false)
        let displaySize = WidgetPreviewMetrics.scaledSize(baseSize: base, scale: s, displayScale: displayScale)

        let rendererScale = min(displayScale, 2.0)
        let dependencyFingerprint = buildDependencyFingerprint()

        let key = WidgetPreviewThumbnailRasterCache.shared.makeKey(
            spec: spec,
            family: family,
            renderSize: base,
            colorScheme: colorScheme,
            rendererScale: rendererScale,
            dependencyFingerprint: dependencyFingerprint
        )

        let taskID = "\(key)|\(thumbnailRenderingEnabled ? 1 : 0)|\(renderImmediately ? 1 : 0)"

        let cornerRadius = scaledWidgetCornerRadius(scale: s)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return Group {
            if let img = image, imageKey == key {
                thumbnailImage(img, size: displaySize, shape: shape)
            } else if let cached = WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) {
                thumbnailImage(cached, size: displaySize, shape: shape)
            } else {
                placeholder(size: displaySize, shape: shape)
            }
        }
        .task(id: taskID) {
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

            if !renderImmediately {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
            }

            if let cached = WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) {
                image = cached
                imageKey = key
                return
            }

            if let rendered = WidgetPreviewThumbnailRasterCache.shared.renderThumbnail(
                spec: spec,
                family: family,
                renderSize: base,
                colorScheme: colorScheme,
                rendererScale: rendererScale
            ) {
                WidgetPreviewThumbnailRasterCache.shared.store(rendered, forKey: key)
                image = rendered
                imageKey = key
            }
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ image: UIImage, size: CGSize, shape: RoundedRectangle) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: size.width, height: size.height, alignment: .center)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func placeholder(size: CGSize, shape: RoundedRectangle) -> some View {
        ZStack {
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

    private func scaledWidgetCornerRadius(scale: CGFloat) -> CGFloat {
        let base: CGFloat = (UIDevice.current.userInterfaceIdiom == .pad) ? 24 : 22
        return WidgetPreviewMetrics.floorToPixel(base * max(0, scale), scale: max(1, displayScale))
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
