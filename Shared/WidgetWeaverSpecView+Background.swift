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
            if layout.template == .weather {
                weatherBackdrop(style: style, accent: accent)
            } else if layout.template == .poster,
                      let image = spec.image,
                      let uiImage = image.loadUIImageForRender(
                          family: family,
                          debugContext: WWPhotoLogContext(
                              renderContext: context.rawValue,
                              family: String(describing: family),
                              template: "poster",
                              specID: String(spec.id.uuidString.prefix(8)),
                              specName: spec.name
                          )
                      ) {
                Color(uiColor: .systemBackground)

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)
            } else if layout.template == .poster,
                      let image = spec.image,
                      let manifestFile = image.smartPhoto?.shuffleManifestFileName,
                      !manifestFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ctx = WWPhotoLogContext(
                    renderContext: context.rawValue,
                    family: String(describing: family),
                    template: "poster",
                    specID: String(spec.id.uuidString.prefix(8)),
                    specName: spec.name
                )
                let _ = WWPhotoDebugLog.appendLazy(
                    category: "photo.render",
                    throttleID: "poster.placeholder.\(spec.id.uuidString.prefix(8)).\(family)",
                    minInterval: 20.0,
                    context: ctx
                ) {
                    "poster: showing placeholder (image load returned nil) manifest=\(manifestFile)"
                }

                Color(uiColor: .systemBackground)

                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("No photo configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            } else {
                Color(uiColor: .systemBackground)

                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            }
        }
        .ignoresSafeArea()
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
        // to change the widget’s outer corners.
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
