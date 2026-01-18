//
//  WidgetWeaverSpecView+Background.swift
//  WidgetWeaver
//
//  Created by . . on 1/16/26.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import AppIntents

extension WidgetWeaverSpecView {
    // MARK: - Background

    func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            switch layout.template {
            case .weather:
                weatherBackdrop(style: style, accent: accent)

            case .poster:
                posterBackdrop(spec: spec, layout: layout, style: style, accent: accent)

            default:
                defaultBackdrop(style: style, accent: accent)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func posterBackdrop(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let isAppExtension: Bool = {
            let url = Bundle.main.bundleURL
            if url.pathExtension == "appex" { return true }
            return url.path.contains(".appex/")
        }()

        let debugContext: WWPhotoLogContext? = {
            guard WWPhotoDebugLog.isEnabled() else { return nil }
            return WWPhotoLogContext(
                renderContext: context.rawValue,
                family: String(describing: family),
                template: "poster",
                specID: String(spec.id.uuidString.prefix(8)),
                specName: spec.name,
                isAppExtension: isAppExtension
            )
        }()

        let loadedPosterImage: UIImage? = {
            guard let image = spec.image else { return nil }
            return image.loadUIImageForRender(family: family, debugContext: debugContext)
        }()

        if let uiImage = loadedPosterImage {
            Color(uiColor: .systemBackground)

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipped()

            Rectangle()
                .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                .opacity(style.backgroundOverlayOpacity)
        } else if shouldShowPosterPhotoEmptyState(spec: spec, layout: layout) {
            if let debugContext, spec.image != nil {
                let manifest = (spec.image?.smartPhoto?.shuffleManifestFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let manifestLabel = manifest.isEmpty ? "none" : manifest
                let _ = WWPhotoDebugLog.appendLazy(
                    category: "photo.render",
                    throttleID: "poster.photoPlaceholder.\(spec.id.uuidString.prefix(8)).\(family)",
                    minInterval: 25.0,
                    context: debugContext
                ) {
                    "poster: photo placeholder (image load returned nil) baseFile=\(spec.image?.fileName ?? "") manifest=\(manifestLabel)"
                }
            }

            defaultBackdrop(style: style, accent: accent)
            photoEmptyStateContent(message: "Choose a photo in Editor")
        } else {
            defaultBackdrop(style: style, accent: accent)
        }
    }

    private func shouldShowPosterPhotoEmptyState(spec: WidgetSpec, layout: LayoutSpec) -> Bool {
        guard layout.template == .poster else { return false }

        // Poster templates are photo-backed.
        // If no usable image is available (not chosen, missing file, decode failure), show a
        // deliberate placeholder instead of silently falling back to a random gradient.
        return true
    }

    @ViewBuilder
    private func defaultBackdrop(style: StyleSpec, accent: Color) -> some View {
        Color(uiColor: .systemBackground)

        Rectangle()
            .fill(style.background.shapeStyle(accent: accent))

        Rectangle()
            .fill(style.backgroundOverlay.shapeStyle(accent: accent))
            .opacity(style.backgroundOverlayOpacity)

        backgroundEffects(style: style, accent: accent)
    }

    @ViewBuilder
    private func photoEmptyStateContent(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
    }

    /// Weather uses a lot of `.ultraThinMaterial`. In WidgetKit, materials take their blur source from the
    /// widget container background. If the container background is clear, materials render as black.
    /// This backdrop is used as the widget container background so the weather glass has a real source.
    private func weatherBackdrop(style: StyleSpec, accent: Color) -> some View {
        let store = WidgetWeaverWeatherStore.shared
        let now = WidgetWeaverRenderClock.now
        let snapshot = store.snapshotForRender(context: context)

        let palette: WeatherPalette = {
            if let snapshot {
                return WeatherPalette.forSnapshot(snapshot, now: now, accent: accent)
            }
            return WeatherPalette.fallback(accent: accent)
        }()

        return ZStack {
            if style.background == .subtleMaterial {
                WeatherBackdropView(palette: palette, family: family)
            } else {
                Color(uiColor: .systemBackground)
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))
            }

            Rectangle()
                .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                .opacity(style.backgroundOverlayOpacity)

            backgroundEffects(style: style, accent: accent)
        }
        .ignoresSafeArea()
    }

    private func backgroundEffects(style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if style.backgroundGlowEnabled {
                Circle()
                    .fill(accent)
                    .blur(radius: 70)
                    .opacity(0.18)
                    .offset(x: -120, y: -120)

                Circle()
                    .fill(accent)
                    .blur(radius: 90)
                    .opacity(0.12)
                    .offset(x: 140, y: 160)
            }
        }
    }
}

// MARK: - Background Modifier

struct WidgetWeaverBackgroundModifier<Background: View>: ViewModifier {
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let background: Background

    func body(content: Content) -> some View {
        // iOS controls the outer widget mask.
        // Widget designs cannot change the widget’s shape.
        // The preview uses a stable approximation for the outer mask so sliders do not appear
        // to change widget’s outer corners.
        let outerCornerRadius = Self.systemWidgetCornerRadius()

        switch context {
        case .widget:
            content
                .containerBackground(for: .widget) { background }
                .clipShape(ContainerRelativeShape())

        case .preview, .simulator:
            content
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        }
    }

    private static func systemWidgetCornerRadius() -> CGFloat {
        // The system widget corner radius is not exposed publicly.
        // Values are tuned to look close to iOS on iPhone and iPad.
        if UIDevice.current.userInterfaceIdiom == .pad { return 24 }
        return 22
    }
}
