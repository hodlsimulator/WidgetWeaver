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
        .init(name: "Small", size: CGSize(width: 155, height: 155), familySalt: 1),
        .init(name: "Medium", size: CGSize(width: 329, height: 155), familySalt: 2),
        .init(name: "Large", size: CGSize(width: 329, height: 345), familySalt: 3)
    ]

    private var cases: [Case] {
        [
            Case(
                name: "Single mound (high certainty)",
                intensities: makeSingleMound(),
                certainties: makeCertainties(flat: 0.92),
                seed: 0xC0FFEE01
            ),
            Case(
                name: "Single mound (low certainty)",
                intensities: makeSingleMound(),
                certainties: makeCertainties(flat: 0.35),
                seed: 0xC0FFEE11
            ),
            Case(
                name: "Monotone decline (certainty fades)",
                intensities: makeMonotoneDecline(),
                certainties: makeCertainties(horizonFadeFrom: 0.90, to: 0.55),
                seed: 0xC0FFEE02
            ),
            Case(
                name: "Two peaks (mixed certainty)",
                intensities: makeTwoPeaks(),
                certainties: makeCertainties(twoZone: true),
                seed: 0xC0FFEE03
            ),
            Case(
                name: "Drizzle bump (low certainty tail)",
                intensities: makeDrizzleBump(),
                certainties: makeCertainties(horizonFadeFrom: 0.78, to: 0.42),
                seed: 0xC0FFEE04
            ),
            Case(
                name: "Hard start/end",
                intensities: makeHardStartEnd(),
                certainties: makeCertainties(flat: 0.60),
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

        c.glintEnabled = false

        c.fuzzRasterMaxPixels = 800_000
        c.fuzzInsideThreshold = 14
        c.fuzzClumpCellPixels = 12.0
        c.fuzzEdgePower = 0.65
        c.fuzzHazeStrength = 0.95
        c.fuzzSpeckStrength = 0.70

        c.fuzzEnabled = true
        c.fuzzColor = Color(red: 0.62, green: 0.88, blue: 1.00)
        c.fuzzMaxOpacity = 0.14
        c.fuzzWidthFraction = 0.20
        c.fuzzBaseDensity = 0.62
        c.fuzzLowHeightPower = 2.6
        c.fuzzUncertaintyFloor = 0.12
        c.fuzzUncertaintyExponent = 2.2
        c.fuzzSpeckleBudget = 14_000

        c.baselineColor = Color(red: 0.46, green: 0.62, blue: 0.80)
        c.baselineLineOpacity = 0.18
        c.baselineEndFadeFraction = 0.035

        return c
    }

    // MARK: - Synthetic series

    private func makeSingleMound() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x = (t - 0.55) / 0.22
            let g = exp(-(x * x))
            let v = pow(g, 1.15)
            return RainSurfaceMath.clamp01(v)
        }
    }

    private func makeMonotoneDecline() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let v = pow(max(0.0, 1.0 - t), 0.85)
            return RainSurfaceMath.clamp01(v)
        }
    }

    private func makeTwoPeaks() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)

            let x1 = (t - 0.38) / 0.12
            let x2 = (t - 0.68) / 0.16

            let g1 = exp(-(x1 * x1))
            let g2 = exp(-(x2 * x2))

            let v = min(1.0, 0.75 * g1 + 0.95 * g2)
            return RainSurfaceMath.clamp01(pow(v, 1.10))
        }
    }

    private func makeDrizzleBump() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x = (t - 0.62) / 0.10
            let g = exp(-(x * x))
            let base = 0.06
            let v = base + 0.22 * g
            return RainSurfaceMath.clamp01(v)
        }
    }

    private func makeHardStartEnd() -> [Double] {
        let n = 60
        return (0..<n).map { i in
            if i < 6 { return 0.0 }
            if i > 54 { return 0.0 }
            if i < 12 { return 0.85 }
            if i > 44 { return 0.55 }
            return 0.70
        }
    }

    private func makeCertainties(flat: Double) -> [Double] {
        let v = RainSurfaceMath.clamp01(flat)
        return Array(repeating: v, count: 60)
    }

    private func makeCertainties(horizonFadeFrom a: Double, to b: Double) -> [Double] {
        let n = 60
        let aa = RainSurfaceMath.clamp01(a)
        let bb = RainSurfaceMath.clamp01(b)
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let u = RainSurfaceMath.smoothstep01(t)
            return RainSurfaceMath.clamp01(RainSurfaceMath.lerp(aa, bb, u))
        }
    }

    private func makeCertainties(twoZone: Bool) -> [Double] {
        guard twoZone else { return makeCertainties(flat: 0.80) }
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            if t < 0.48 { return 0.88 }
            if t < 0.70 { return 0.40 }
            return 0.62
        }
    }
}
#endif
