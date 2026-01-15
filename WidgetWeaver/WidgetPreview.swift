//
//  WidgetPreview.swift
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

// MARK: - Live Preview
@MainActor
struct WidgetPreview: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    var maxHeight: CGFloat?
    var isLive: Bool = false

    @Environment(\.displayScale) private var displayScale

    // Forces a re-render when variables change in-app (including via AppIntent buttons).
    @AppStorage("widgetweaver.variables.v1", store: AppGroup.userDefaults)
    private var variablesData: Data = Data()

    // Forces a re-render when Smart Photo shuffle manifests are saved/advanced.
    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    var body: some View {
        let _ = variablesData

        let _ = smartPhotoShuffleUpdateToken

        let familySpec = spec.resolved(for: family)

        let usesTemplateTime = spec.normalised().usesTimeDependentRendering()

        let shuffleManifestFileName: String? = {
            let mf = (familySpec.image?.smartPhoto?.shuffleManifestFileName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return mf.isEmpty ? nil : mf
        }()

        let usesSmartPhotoShuffleRotation: Bool = {
            guard let mf = shuffleManifestFileName else { return false }
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return true }
            return manifest.rotationIntervalMinutes > 0
        }()

        let isTimeDependent = usesTemplateTime || usesSmartPhotoShuffleRotation

        Group {
            if isTimeDependent {
                // Preview mode should still advance time so Medium/Large never drift apart.
                //
                // Smart Photo shuffle is also time-dependent (rotation schedule) and should respond
                // promptly in the editor when “Next photo” is used.
                let interval: TimeInterval = {
                    if usesTemplateTime { return isLive ? 1 : 60 }
                    if usesSmartPhotoShuffleRotation { return isLive ? 5 : 60 }
                    return 60
                }()

                let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                TimelineView(.periodic(from: start, by: interval)) { ctx in
                    WidgetWeaverRenderClock.withNow(ctx.date) {
                        previewBody
                    }
                }
            } else {
                previewBody
            }
        }
        .frame(height: maxHeight)
        .contentShape(Rectangle())
        .clipped()
    }

    private static func sizingReferenceFamily(for family: WidgetFamily) -> WidgetFamily {
        switch family {
        case .systemSmall, .systemMedium:
            return .systemMedium
        case .systemLarge:
            return .systemLarge
        default:
            return .systemMedium
        }
    }

    private var previewBody: some View {
        GeometryReader { proxy in
            let screen = WidgetPreviewMetrics.currentScreen()

            let base = WidgetPreviewMetrics.widgetSize(for: family, screen: screen)
            let sizingBase = WidgetPreviewMetrics.widgetSize(for: Self.sizingReferenceFamily(for: family), screen: screen)

            let scale = WidgetPreviewMetrics.fitScale(
                contentSize: sizingBase,
                containerSize: proxy.size,
                allowUpscale: false
            )

            let scaled = WidgetPreviewMetrics.scaledSize(
                baseSize: base,
                scale: scale,
                displayScale: displayScale
            )

            WidgetWeaverSpecView(
                spec: spec,
                family: family,
                context: isLive ? .simulator : .preview
            )
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: scaled.width, height: scaled.height, alignment: .center)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    static func widgetSize(for family: WidgetFamily) -> CGSize {
        let screen = WidgetPreviewMetrics.currentScreen()
        return WidgetPreviewMetrics.widgetSize(for: family, screen: screen)
    }
}

// MARK: - Preview Metrics (single source of truth)

enum WidgetPreviewMetrics {
    struct Sizes {
        let small: CGSize
        let medium: CGSize
        let large: CGSize
    }

    @MainActor
    static func widgetSize(for family: WidgetFamily, screen: UIScreen) -> CGSize {
        let sizes = sizesForDevice(screen: screen)
        switch family {
        case .systemSmall:
            return sizes.small
        case .systemMedium:
            return sizes.medium
        case .systemLarge:
            return sizes.large
        default:
            return sizes.small
        }
    }

    @MainActor
    static func sizesForDevice(screen: UIScreen) -> Sizes {
        let idiom = UIDevice.current.userInterfaceIdiom
        let portraitWidth = min(screen.bounds.width, screen.bounds.height)
        return sizesForDevice(idiom: idiom, portraitWidth: portraitWidth, displayScale: screen.scale)
    }

    static func sizesForDevice(idiom: UIUserInterfaceIdiom, portraitWidth: CGFloat, displayScale: CGFloat) -> Sizes {
        let w = max(1, portraitWidth)
        let scale = max(1, displayScale)

        if idiom == .pad {
            // iPad widgets generally behave like a 2-column layout inside a narrower widget region.
            // This is intentionally not keyed on device model strings.
            let mediumWidth = roundToPixel(clamp(w * 0.41, min: 306, max: 379), scale: scale)
            let spacing = roundToPixel(clamp(w * 0.038, min: 24, max: 40), scale: scale)

            let smallSide = roundToPixel((mediumWidth - spacing) / 2, scale: scale)

            let small = CGSize(width: smallSide, height: smallSide)
            let medium = CGSize(width: mediumWidth, height: smallSide)
            let large = CGSize(width: mediumWidth, height: mediumWidth)

            return Sizes(small: small, medium: medium, large: large)
        } else {
            // iPhone portrait assumption.
            // The side inset and spacing are derived from screen width, avoiding per-device tables.
            let sidePadding = roundToPixel(clamp(w * 0.20 - 52, min: 16, max: 36), scale: scale)
            let spacing = roundToPixel(clamp(w * 0.058, min: 18, max: 26), scale: scale)
            let availableWidth = max(1, w - (2 * sidePadding))

            let smallSide = roundToPixel((availableWidth - spacing) / 2, scale: scale)
            let mediumWidth = roundToPixel(availableWidth, scale: scale)

            // Large widgets are slightly taller than a perfect 2x2 grid on iPhone.
            let largeExtraHeight = roundToPixel(clamp(w * 0.040, min: 10, max: 18), scale: scale)
            let largeHeight = roundToPixel((smallSide * 2) + spacing + largeExtraHeight, scale: scale)

            let small = CGSize(width: smallSide, height: smallSide)
            let medium = CGSize(width: mediumWidth, height: smallSide)
            let large = CGSize(width: mediumWidth, height: largeHeight)

            return Sizes(small: small, medium: medium, large: large)
        }
    }

    static func fitScale(contentSize: CGSize, containerSize: CGSize, allowUpscale: Bool) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        guard containerSize.width > 0, containerSize.height > 0 else { return 1 }

        let sx = containerSize.width / contentSize.width
        let sy = containerSize.height / contentSize.height
        let s = min(sx, sy)

        return allowUpscale ? s : min(1, s)
    }

    static func thumbnailScale(nativeSize: CGSize, targetHeight: CGFloat, targetWidth: CGFloat? = nil, allowUpscale: Bool = false) -> CGFloat {
        guard nativeSize.width > 0, nativeSize.height > 0 else { return 1 }

        var s = targetHeight / nativeSize.height
        if let w = targetWidth {
            s = min(s, w / nativeSize.width)
        }
        return allowUpscale ? s : min(1, s)
    }

    static func scaledSize(baseSize: CGSize, scale: CGFloat, displayScale: CGFloat) -> CGSize {
        let s = max(0, scale)
        let pxScale = max(1, displayScale)
        return CGSize(
            width: floorToPixel(baseSize.width * s, scale: pxScale),
            height: floorToPixel(baseSize.height * s, scale: pxScale)
        )
    }

    static func roundToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    static func floorToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        floor(value * scale) / scale
    }

    static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

    @MainActor
    static func currentScreen() -> UIScreen {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let screen = screenFromWindowScenes(windowScenes, preferForegroundActive: true) {
            return screen
        }
        if let screen = screenFromWindowScenes(windowScenes, preferForegroundActive: false) {
            return screen
        }
        if let screen = windowScenes.first?.screen {
            return screen
        }

        preconditionFailure("WidgetPreviewMetrics.currentScreen(): no UIWindowScene available")
    }

    @MainActor
    private static func screenFromWindowScenes(_ scenes: [UIWindowScene], preferForegroundActive: Bool) -> UIScreen? {
        let orderedScenes: [UIWindowScene]
        if preferForegroundActive {
            let active = scenes.filter { $0.activationState == .foregroundActive }
            orderedScenes = active.isEmpty ? scenes : active
        } else {
            orderedScenes = scenes
        }

        for scene in orderedScenes {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) {
                return key.screen
            }
            if let any = scene.windows.first {
                return any.screen
            }
        }

        return nil
    }
}
