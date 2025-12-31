//
//  RainSurfaceDissipationNoise.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//

import SwiftUI

/// Noise-based “dissipation” for the rain surface.
/// This removes opacity from the filled body near its contour, rather than adding a coloured fuzz layer.
enum RainSurfaceDissipationNoise {

    struct Settings: Sendable {
        /// Width (in points) of the erosion band around the contour.
        var fadeWidth: CGFloat

        /// Number of erosion passes. 3 is usually enough.
        var steps: Int

        /// Tiled image scale for `GraphicsContext.Shading.tiledImage`.
        /// Smaller values make the speckle tighter; larger values make it chunkier.
        var tileScale: CGFloat

        /// Overall removal strength (0...1).
        var intensity: CGFloat

        /// Seed used to vary tile origin deterministically.
        var seed: UInt64

        /// Origin jitter amplitude in points. Higher values reduce visible repetition.
        var originJitter: CGFloat

        /// Optional extra clip rect (for example, to avoid eroding the bottom baseline).
        var clipRect: CGRect?

        init(
            fadeWidth: CGFloat,
            steps: Int = 3,
            tileScale: CGFloat = 0.75,
            intensity: CGFloat = 0.92,
            seed: UInt64 = 0,
            originJitter: CGFloat = 256,
            clipRect: CGRect? = nil
        ) {
            self.fadeWidth = fadeWidth
            self.steps = max(1, steps)
            self.tileScale = max(0.05, tileScale)
            self.intensity = Self.clamp01(intensity)
            self.seed = seed
            self.originJitter = max(0, originJitter)
            self.clipRect = clipRect
        }

        private static func clamp01(_ x: CGFloat) -> CGFloat {
            min(1, max(0, x))
        }
    }

    /// Applies dissipating erosion to `filledShape`, constrained to a stroked band around `contour` (or the shape itself if nil).
    ///
    /// - Parameters:
    ///   - bounds: The drawing bounds for filling the tiled image (typically your plot rect).
    ///   - filledShape: The full closed rain body path that was already filled.
    ///   - contour: A contour path (top curve + side slopes). If unavailable, pass nil and the whole outline of `filledShape` is used.
    static func apply(
        in context: inout GraphicsContext,
        bounds: CGRect,
        filledShape: Path,
        contour: Path? = nil,
        settings: Settings
    ) {
        guard settings.intensity > 0 else { return }
        guard settings.fadeWidth > 0 else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }

        let basePath = contour ?? filledShape
        let weights = normalisedWeights(count: settings.steps)

        for i in 0..<settings.steps {
            let t = CGFloat(i + 1) / CGFloat(settings.steps)

            // Band grows outward with each step.
            let bandWidth = settings.fadeWidth * (0.35 + 0.65 * t)

            // Weight controls how much alpha is removed per pass.
            let passAlpha = settings.intensity * weights[i]

            let bandPath = basePath.strokedPath(
                StrokeStyle(
                    lineWidth: bandWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    miterLimit: 2
                )
            )

            let shading = tiledNoiseShading(
                bounds: bounds,
                seed: settings.seed &+ UInt64(i) &* 0x9E3779B97F4A7C15,
                jitter: settings.originJitter,
                scale: settings.tileScale
            )

            context.drawLayer { layer in
                if let clipRect = settings.clipRect {
                    layer.clip(to: Path(clipRect))
                }

                // Only erode within the already-filled body.
                layer.clip(to: filledShape)

                // Only erode near the contour (band region).
                layer.clip(to: bandPath)

                // Remove opacity (no colour added).
                layer.blendMode = .destinationOut
                layer.opacity = passAlpha

                layer.fill(Path(bounds), with: shading)
            }
        }
    }

    // MARK: - Internals

    private static func normalisedWeights(count: Int) -> [CGFloat] {
        if count <= 1 { return [1] }
        // Bias towards stronger erosion at the outermost pass.
        let raw: [CGFloat] = (1...count).map { i in
            let t = CGFloat(i) / CGFloat(count)
            return pow(t, 2.2)
        }
        let s = raw.reduce(0, +)
        if s <= 0 { return Array(repeating: 1 / CGFloat(count), count: count) }
        return raw.map { $0 / s }
    }

    private static func tiledNoiseShading(
        bounds: CGRect,
        seed: UInt64,
        jitter: CGFloat,
        scale: CGFloat
    ) -> GraphicsContext.Shading {
        // White image with alpha is ideal; colour is irrelevant for destinationOut.
        let image = Image("RainFuzzNoise")

        var state = seed
        let ox = (rand01(&state) - 0.5) * 2 * jitter
        let oy = (rand01(&state) - 0.5) * 2 * jitter

        let origin = CGPoint(x: bounds.minX + ox, y: bounds.minY + oy)

        // Uses SwiftUI’s built-in tiled image shading.
        return .tiledImage(image, origin: origin, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: scale)
    }

    /// SplitMix64-derived deterministic random in [0, 1).
    private static func rand01(_ state: inout UInt64) -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)

        // Use top 53 bits to build a Double in [0, 1).
        let v = Double(z >> 11) / Double(1 << 53)
        return CGFloat(v)
    }
}
