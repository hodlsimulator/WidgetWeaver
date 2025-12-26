//
//  RainSurfaceStyleHarness.swift
//  WidgetWeaver
//
//  Created by . . on 12/26/25.
//
//  DEBUG-only harness to validate nowcast surface styling across sizes and synthetic series.
//

import Foundation
import SwiftUI

#if DEBUG

struct RainSurfaceStyleHarnessView: View {
    private struct Case: Identifiable {
        let id = UUID()
        let name: String
        let intensities: [Double]
        let certainties: [Double]
        let seed: UInt64
    }

    private struct SizeCase: Identifiable {
        let id = UUID()
        let name: String
        let size: CGSize
        let familySalt: UInt64
    }

    private let sizes: [SizeCase] = [
        // Typical iPhone widget sizes (approx; intended for comparative validation).
        .init(name: "Small", size: CGSize(width: 155, height: 155), familySalt: 1),
        .init(name: "Medium", size: CGSize(width: 329, height: 155), familySalt: 2),
        .init(name: "Large", size: CGSize(width: 329, height: 345), familySalt: 3)
    ]

    private var cases: [Case] {
        [
            Case(
                name: "Single mound",
                intensities: makeSingleMound(),
                certainties: makeCertainties(flat: 0.90),
                seed: 0xC0FFEE01
            ),
            Case(
                name: "Monotone decline",
                intensities: makeMonotoneDecline(),
                certainties: makeCertainties(flat: 0.85),
                seed: 0xC0FFEE02
            ),
            Case(
                name: "Two peaks",
                intensities: makeTwoPeaks(),
                certainties: makeCertainties(horizon: true),
                seed: 0xC0FFEE03
            ),
            Case(
                name: "Drizzle bump",
                intensities: makeDrizzleBump(),
                certainties: makeCertainties(flat: 0.78),
                seed: 0xC0FFEE04
            ),
            Case(
                name: "Hard start/end (non-zero ends)",
                intensities: makeHardStartEnd(),
                certainties: makeCertainties(flat: 0.70),
                seed: 0xC0FFEE05
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sizes) { s in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Widget size: \(s.name)")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))

                        ForEach(cases) { c in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(c.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))

                                let cfg = harnessConfig(seed: RainSurfacePRNG.combine(c.seed, s.familySalt))

                                RainForecastSurfaceView(
                                    intensities: c.intensities,
                                    certainties: c.certainties,
                                    configuration: cfg
                                )
                                .frame(width: s.size.width, height: s.size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.10), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.black)
    }

    // MARK: - Config

    private func harnessConfig(seed: UInt64) -> RainForecastSurfaceConfiguration {
        var c = RainForecastSurfaceConfiguration()
        c.noiseSeed = seed

        c.maxDenseSamples = 1024
        c.silhouetteSmoothingPasses = 3
        c.tailEasingFraction = 0.10

        c.baselineFractionFromTop = 0.596
        c.topHeadroomFraction = 0.30
        c.typicalPeakFraction = 0.195
        c.robustMaxPercentile = 0.93
        c.intensityGamma = 0.65

        c.coreBodyColor = Color(red: 0.00, green: 0.10, blue: 0.42)
        c.coreTopColor = Color(red: 0.20, green: 0.55, blue: 1.00)

        c.rimEnabled = true
        c.rimColor = Color(red: 0.62, green: 0.88, blue: 1.00)
        c.rimOuterOpacity = 0.06
        c.rimOuterWidthPixels = 14.0
        c.rimInnerOpacity = 0.0
        c.rimInnerWidthPixels = 0.0

        c.glossEnabled = true
        c.glossMaxOpacity = 0.12
        c.glossDepthPixels = 10.0...16.0
        c.insideLightMinHeightPixels = 3.0

        c.glintEnabled = false

        c.fuzzEnabled = true
        c.fuzzColor = Color(red: 0.62, green: 0.88, blue: 1.00)
        c.fuzzMaxOpacity = 0.14
        c.fuzzWidthFraction = 0.20
        c.fuzzBaseDensity = 0.62
        c.fuzzLowHeightPower = 2.6
        c.fuzzUncertaintyFloor = 0.12
        c.fuzzSpeckleBudget = 14_000

        c.baselineColor = Color(red: 0.46, green: 0.62, blue: 0.80)
        c.baselineLineOpacity = 0.18
        c.baselineEndFadeFraction = 0.035

        c.rasterMaxWidthPixels = 1200
        c.rasterMaxHeightPixels = 800
        c.rasterMaxTotalPixels = 800_000

        return c
    }

    // MARK: - Synthetic series

    private func makeSingleMound() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x = (t - 0.45) / 0.18
            let g = exp(-x * x)
            return 4.0 * g
        }
    }

    private func makeMonotoneDecline() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let v = 3.5 * (1.0 - t)
            return max(0.0, v)
        }
    }

    private func makeTwoPeaks() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x1 = (t - 0.30) / 0.12
            let x2 = (t - 0.68) / 0.10
            let g1 = exp(-x1 * x1)
            let g2 = exp(-x2 * x2)
            return 2.2 * g1 + 3.0 * g2
        }
    }

    private func makeDrizzleBump() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let base = 0.25
            let x = (t - 0.55) / 0.10
            let g = exp(-x * x)
            return base + 0.85 * g
        }
    }

    private func makeHardStartEnd() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            // Flat-ish rain with non-zero endpoints and a mid bump.
            let mid = exp(-pow((t - 0.50) / 0.18, 2.0))
            return 1.2 + 2.0 * mid
        }
    }

    private func makeCertainties(flat v: Double) -> [Double] {
        Array(repeating: RainSurfaceMath.clamp01(v), count: 60)
    }

    private func makeCertainties(horizon: Bool) -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            if !horizon { return 0.85 }
            let u = RainSurfaceMath.clamp01((t - 0.65) / 0.35)
            let hs = RainSurfaceMath.smoothstep01(u)
            return RainSurfaceMath.lerp(0.92, 0.70, hs)
        }
    }
}

struct RainSurfaceStyleHarnessView_Previews: PreviewProvider {
    static var previews: some View {
        RainSurfaceStyleHarnessView()
            .preferredColorScheme(.dark)
    }
}

#endif
