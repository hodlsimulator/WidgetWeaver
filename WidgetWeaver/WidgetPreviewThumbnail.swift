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

// MARK: - External dependency fingerprints (shared, cheap per-cell)

@MainActor
final class WidgetPreviewThumbnailDependencies: ObservableObject {
    static let shared = WidgetPreviewThumbnailDependencies()

    @Published private(set) var variablesFingerprint: String = "0000000000000000"
    @Published private(set) var weatherFingerprint: String = "0000000000000000"

    private let userDefaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var recomputeTask: Task<Void, Never>?

    private init(userDefaults: UserDefaults = AppGroup.userDefaults) {
        self.userDefaults = userDefaults

        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRecompute(delayNanoseconds: 150_000_000)
            }
        }

        scheduleRecompute(delayNanoseconds: 0)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        recomputeTask?.cancel()
    }

    func dependencyFingerprint(for spec: WidgetSpec) -> String {
        if spec.usesWeatherRendering() {
            return "\(variablesFingerprint).\(weatherFingerprint)"
        }
        return variablesFingerprint
    }

    private func scheduleRecompute(delayNanoseconds: UInt64) {
        recomputeTask?.cancel()

        recomputeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard !Task.isCancelled else { return }

            // Extract inputs on the main actor (UserDefaults is not Sendable).
            let variablesData = self.userDefaults.data(forKey: "widgetweaver.variables.v1") ?? Data()

            let locationData = self.userDefaults.data(forKey: WidgetWeaverWeatherStore.Keys.locationData) ?? Data()
            let snapshotData = self.userDefaults.data(forKey: WidgetWeaverWeatherStore.Keys.snapshotData) ?? Data()
            let attributionData = self.userDefaults.data(forKey: WidgetWeaverWeatherStore.Keys.attributionData) ?? Data()

            let unitPreferenceRaw = self.userDefaults.string(forKey: WidgetWeaverWeatherStore.Keys.unitPreference) ?? ""
            let lastErrorRaw = self.userDefaults.string(forKey: WidgetWeaverWeatherStore.Keys.lastError) ?? ""

            let (variables, weather) = await Task.detached(priority: .utility) {
                Self.computeFingerprints(
                    variablesData: variablesData,
                    locationData: locationData,
                    snapshotData: snapshotData,
                    attributionData: attributionData,
                    unitPreferenceRaw: unitPreferenceRaw,
                    lastErrorRaw: lastErrorRaw
                )
            }.value

            if self.variablesFingerprint != variables {
                self.variablesFingerprint = variables
            }
            if self.weatherFingerprint != weather {
                self.weatherFingerprint = weather
            }
        }
    }

    nonisolated private static func computeFingerprints(
        variablesData: Data,
        locationData: Data,
        snapshotData: Data,
        attributionData: Data,
        unitPreferenceRaw: String,
        lastErrorRaw: String
    ) -> (String, String) {
        let variables = fnv1a64Hex(variablesData)

        let weatherParts: [String] = [
            fnv1a64Hex(locationData),
            fnv1a64Hex(snapshotData),
            fnv1a64Hex(attributionData),
            fnv1a64Hex(Data(unitPreferenceRaw.utf8)),
            fnv1a64Hex(Data(lastErrorRaw.utf8)),
        ]

        let weather = weatherParts.joined(separator: ".")
        return (variables, weather)
    }

    nonisolated private static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for b in data {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

@MainActor
final class WidgetPreviewThumbnailCacheSignal: ObservableObject {
    static let shared = WidgetPreviewThumbnailCacheSignal()

    @Published private(set) var pulse: UInt64 = 0

    private var scheduledTask: Task<Void, Never>?

    private init() {}

    func bumpCoalesced() {
        if scheduledTask != nil { return }

        scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.pulse &+= 1
            self.scheduledTask = nil
        }
    }
}

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
        WidgetPreviewThumbnailCacheSignal.shared.bumpCoalesced()
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
        let v = spec.normalised().hashValue
        let u = UInt64(bitPattern: Int64(v))
        return String(format: "%016llx", u)
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

    @ObservedObject private var deps = WidgetPreviewThumbnailDependencies.shared
    @ObservedObject private var cacheSignal = WidgetPreviewThumbnailCacheSignal.shared

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
        let _ = cacheSignal.pulse

        let base = WidgetPreview.widgetSize(for: family)
        let s = WidgetPreviewMetrics.thumbnailScale(nativeSize: base, targetHeight: height, allowUpscale: false)
        let displaySize = WidgetPreviewMetrics.scaledSize(baseSize: base, scale: s, displayScale: displayScale)

        let rendererScale = min(displayScale, 2.0)
        let dependencyFingerprint = deps.dependencyFingerprint(for: spec)

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
}

// MARK: - Cache warming

extension WidgetPreviewThumbnail {
    @MainActor
    static func preheat(
        specs: [WidgetSpec],
        families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge],
        colorScheme: ColorScheme,
        displayScale: CGFloat
    ) async {
        guard #available(iOS 16.0, *) else { return }

        let rendererScale = min(displayScale, 2.0)

        var seen = Set<UUID>()
        let dedupedSpecs = specs.filter { seen.insert($0.id).inserted }

        for spec in dedupedSpecs {
            guard !Task.isCancelled else { return }

            let dependencyFingerprint = WidgetPreviewThumbnailDependencies.shared.dependencyFingerprint(for: spec)

            for family in families {
                guard !Task.isCancelled else { return }

                let base = WidgetPreview.widgetSize(for: family)

                let key = WidgetPreviewThumbnailRasterCache.shared.makeKey(
                    spec: spec,
                    family: family,
                    renderSize: base,
                    colorScheme: colorScheme,
                    rendererScale: rendererScale,
                    dependencyFingerprint: dependencyFingerprint
                )

                if WidgetPreviewThumbnailRasterCache.shared.cachedImage(forKey: key) != nil {
                    continue
                }

                if let rendered = WidgetPreviewThumbnailRasterCache.shared.renderThumbnail(
                    spec: spec,
                    family: family,
                    renderSize: base,
                    colorScheme: colorScheme,
                    rendererScale: rendererScale
                ) {
                    WidgetPreviewThumbnailRasterCache.shared.store(rendered, forKey: key)
                }

                await Task.yield()
            }
        }
    }
}
