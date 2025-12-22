//
//  WidgetWeaverWeatherTemplateComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Card + rain chart components.
//  Chart redesign goals:
//  - Intensity uses an absolute mm/h scale (drizzle never renders as “full height”).
//  - Certainty uses bar solidity (opacity).
//  - Uncertainty uses a static Dark Sky-style wiggle + halo.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Metrics

struct WeatherMetrics: Sendable {
    let style: StyleSpec
    let family: WidgetFamily

    let scale: CGFloat

    init(style: StyleSpec, family: WidgetFamily) {
        self.style = style
        self.family = family
        self.scale = CGFloat(style.weatherScale)
    }

    var outerPadding: CGFloat {
        CGFloat(style.padding)
    }

    var innerPadding: CGFloat {
        max(10, CGFloat(style.padding) * 0.75)
    }

    var cornerRadius: CGFloat {
        CGFloat(style.cornerRadius)
    }

    var smallGraphHeight: CGFloat { 26 * scale }
    var mediumGraphHeight: CGFloat { 96 * scale }
    var largeGraphHeight: CGFloat { 120 * scale }

    func temperatureText(fromCelsius c: Double) -> String {
        let unit = WidgetWeaverWeatherStore.shared.resolvedUnitTemperature()
        let value = Measurement(value: c, unit: UnitTemperature.celsius).converted(to: unit).value
        let rounded = Int(value.rounded())
        return "\(rounded)°"
    }
}

// MARK: - Card Container

struct WeatherCardContainer<Content: View>: View {
    let metrics: WeatherMetrics
    let style: StyleSpec
    let accent: Color

    // nil for empty state
    let nowcast: WeatherNowcast?

    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            WeatherCardBackground(
                metrics: metrics,
                style: style,
                accent: accent,
                nowcast: nowcast
            )

            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct WeatherCardBackground: View {
    let metrics: WeatherMetrics
    let style: StyleSpec
    let accent: Color
    let nowcast: WeatherNowcast?

    var body: some View {
        let raininess01 = nowcast?.raininess01 ?? 0.0

        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(style.background.shapeStyle(accent: accent))

            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18 + 0.16 * raininess01),
                            Color.clear,
                            accent.opacity(0.10 + 0.10 * raininess01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WeatherCloudOverlay(style: style, accent: accent)
                .opacity(cloudOpacity(for: style, raininess01: raininess01))
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))

            if style.backgroundGlowEnabled {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.20 + 0.25 * raininess01),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: 240
                        )
                    )
                    .blur(radius: 18)
            }
        }
    }

    private func cloudOpacity(for style: StyleSpec, raininess01: Double) -> Double {
        let base = max(0.0, min(1.0, style.backgroundOverlayOpacity))
        return min(1.0, base * (0.85 + 0.35 * raininess01))
    }
}

private struct WeatherCloudOverlay: View {
    let style: StyleSpec
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let amount = max(0.0, min(1.0, style.backgroundOverlayOpacity))

            Canvas { ctx, _ in
                guard amount > 0.01 else { return }

                let mode = cloudMode(from: style.backgroundOverlay)

                switch mode {
                case .none:
                    break
                case .soft:
                    drawSoftClouds(in: &ctx, size: size, amount: amount)
                case .storm:
                    drawStormClouds(in: &ctx, size: size, amount: amount)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private enum CloudMode {
        case none
        case soft
        case storm
    }

    private func cloudMode(from token: BackgroundToken) -> CloudMode {
        switch token {
        case .plain:
            return .none
        case .solidAccent:
            return .storm
        default:
            return .soft
        }
    }

    private func drawSoftClouds(in ctx: inout GraphicsContext, size: CGSize, amount: Double) {
        ctx.addFilter(.blur(radius: 18 + 10 * amount))
        ctx.blendMode = .overlay

        let opacity = 0.10 + 0.18 * amount
        let color = Color.white.opacity(opacity)

        let blobs: [CGRect] = [
            CGRect(x: size.width * 0.02, y: size.height * 0.10, width: size.width * 0.70, height: size.height * 0.30),
            CGRect(x: size.width * 0.35, y: size.height * 0.06, width: size.width * 0.70, height: size.height * 0.32),
            CGRect(x: size.width * 0.10, y: size.height * 0.22, width: size.width * 0.55, height: size.height * 0.26),
            CGRect(x: size.width * 0.48, y: size.height * 0.22, width: size.width * 0.50, height: size.height * 0.28)
        ]

        for rect in blobs {
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func drawStormClouds(in ctx: inout GraphicsContext, size: CGSize, amount: Double) {
        ctx.addFilter(.blur(radius: 22 + 14 * amount))
        ctx.blendMode = .multiply

        let opacity = 0.14 + 0.24 * amount
        let color = Color.black.opacity(opacity)

        let blobs: [CGRect] = [
            CGRect(x: size.width * -0.05, y: size.height * 0.08, width: size.width * 0.85, height: size.height * 0.36),
            CGRect(x: size.width * 0.25, y: size.height * 0.04, width: size.width * 0.90, height: size.height * 0.40),
            CGRect(x: size.width * 0.05, y: size.height * 0.24, width: size.width * 0.75, height: size.height * 0.34),
            CGRect(x: size.width * 0.45, y: size.height * 0.26, width: size.width * 0.70, height: size.height * 0.36)
        ]

        for rect in blobs {
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
        }

        // FIX: Path initialiser has no `rect:` label.
        ctx.blendMode = .overlay
        let haze = accent.opacity(0.06 + 0.10 * amount)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(haze))
    }
}

// MARK: - Icons + Attribution

struct WeatherConditionIcon: View {
    let symbolName: String
    let accent: Color

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accent.opacity(0.92))
    }
}

struct WeatherAttributionBadge: View {
    let attributionURL: URL?

    var body: some View {
        if let url = attributionURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("Weather")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "applelogo")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("Weather")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Nowcast Chart

struct WeatherNowcastChart: View {
    enum Axis {
        case none
        case nowTo60m
    }

    let buckets: [WeatherNowcastBucket]
    let accent: Color
    let metrics: WeatherMetrics
    let axis: Axis

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let corner: CGFloat = 12 * metrics.scale
            let inset: CGFloat = 10 * metrics.scale
            let axisHeight: CGFloat = (axis == .none) ? 0 : (14 * metrics.scale)

            let plotSize = CGSize(
                width: max(1, size.width - inset * 2),
                height: max(1, size.height - inset * 2 - axisHeight)
            )

            let bars = makeBars(plotSize: plotSize)
            let wigglePoints = makeWigglePoints(bars: bars, plotSize: plotSize)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }

                if buckets.isEmpty {
                    Text("—")
                        .font(.system(size: 13 * metrics.scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, axisHeight)
                } else {
                    ZStack(alignment: .bottomLeading) {
                        WeatherGraphGuides()
                            .opacity(0.22)

                        HStack(alignment: .bottom, spacing: bars.spacing) {
                            ForEach(bars.items) { bar in
                                WeatherRainBar(bar: bar, accent: accent)
                            }
                        }
                        .frame(width: plotSize.width, height: plotSize.height, alignment: .bottomLeading)

                        if wigglePoints.count > 1 {
                            let avgUncertainty = wigglePoints.map(\.uncertainty01).reduce(0.0, +) / Double(wigglePoints.count)

                            WeatherNowcastWiggleLine(points: wigglePoints, maxAmplitude: 8 * metrics.scale)
                                .stroke(accent.opacity(0.16 + 0.18 * avgUncertainty), style: StrokeStyle(lineWidth: 10 * metrics.scale, lineCap: .round, lineJoin: .round))
                                .blur(radius: 10 * metrics.scale)

                            WeatherNowcastWiggleLine(points: wigglePoints, maxAmplitude: 8 * metrics.scale)
                                .stroke(accent.opacity(0.55 + 0.25 * (1.0 - avgUncertainty)), style: StrokeStyle(lineWidth: 2.2 * metrics.scale, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .padding(.top, inset)
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset + axisHeight)
                }

                if axis != .none {
                    HStack {
                        Text("Now")
                        Spacer()
                        Text("60m")
                    }
                    .font(.system(size: 11 * metrics.scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset - 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    // Absolute intensity scale (mm/h) so drizzle does not look like heavy rain.
    private let displayMaxIntensityMMPerHour: Double = 8.0

    private struct Bars {
        let items: [WeatherRainBar.Bar]
        let spacing: CGFloat
    }

    private func makeBars(plotSize: CGSize) -> Bars {
        let count = buckets.count
        guard count > 0 else {
            return Bars(items: [], spacing: 0)
        }

        let spacing: CGFloat = (count <= 16) ? (3 * metrics.scale) : (2 * metrics.scale)

        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let barWidth = max(1, (plotSize.width - totalSpacing) / CGFloat(count))
        let barCorner = max(1, min(barWidth * 0.45, 4 * metrics.scale))

        var items: [WeatherRainBar.Bar] = []
        items.reserveCapacity(count)

        for i in 0..<count {
            let b = buckets[i]

            let intensity = max(0.0, b.intensityMMPerHour)
            let chance = clamp01(b.chance01)

            let clampedIntensity = min(displayMaxIntensityMMPerHour, intensity)
            let intensity01 = (displayMaxIntensityMMPerHour <= 0) ? 0.0 : (clampedIntensity / displayMaxIntensityMMPerHour)
            let height01 = sqrt(clamp01(intensity01))

            let minVisible: CGFloat = 1.5 * metrics.scale
            let height = max(minVisible, plotSize.height * CGFloat(height01))

            let uncertainty = clamp01(0.65 * (1.0 - chance) + 0.35 * clamp01(b.rainUncertainty01))

            let bar = WeatherRainBar.Bar(
                id: i,
                width: barWidth,
                height: height,
                cornerRadius: barCorner,
                chance01: chance,
                uncertainty01: uncertainty
            )
            items.append(bar)
        }

        return Bars(items: items, spacing: spacing)
    }

    private func makeWigglePoints(bars: Bars, plotSize: CGSize) -> [WeatherNowcastWiggleLine.Point] {
        guard bars.items.count > 1 else { return [] }

        var pts: [WeatherNowcastWiggleLine.Point] = []
        pts.reserveCapacity(bars.items.count)

        var x: CGFloat = 0
        for (idx, bar) in bars.items.enumerated() {
            let xCenter = x + bar.width / 2.0
            x += bar.width + bars.spacing

            let yTop = plotSize.height - bar.height

            let x01 = Double(xCenter / max(1, plotSize.width))
            let y01 = Double(yTop / max(1, plotSize.height))

            pts.append(
                WeatherNowcastWiggleLine.Point(
                    index: idx,
                    x01: clamp01(x01),
                    y01: clamp01(y01),
                    uncertainty01: clamp01(bar.uncertainty01)
                )
            )
        }

        return pts
    }
}

private struct WeatherGraphGuides: View {
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let y1 = h * 0.25
            let y2 = h * 0.50
            let y3 = h * 0.75

            Path { p in
                p.move(to: CGPoint(x: 0, y: y1))
                p.addLine(to: CGPoint(x: geo.size.width, y: y1))
                p.move(to: CGPoint(x: 0, y: y2))
                p.addLine(to: CGPoint(x: geo.size.width, y: y2))
                p.move(to: CGPoint(x: 0, y: y3))
                p.addLine(to: CGPoint(x: geo.size.width, y: y3))
            }
            .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
        .allowsHitTesting(false)
    }
}

struct WeatherRainBar: View {
    struct Bar: Identifiable {
        let id: Int
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let chance01: Double
        let uncertainty01: Double
    }

    let bar: Bar
    let accent: Color

    var body: some View {
        let solidity = 0.18 + 0.82 * clamp01(bar.chance01)
        let haze = 0.08 + 0.18 * clamp01(bar.uncertainty01)

        RoundedRectangle(cornerRadius: bar.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(solidity * 0.65),
                        accent.opacity(solidity),
                        accent.opacity(solidity * 0.92)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: bar.cornerRadius, style: .continuous)
                    .stroke(accent.opacity(haze), lineWidth: 3)
                    .blur(radius: 4)
            }
            .frame(width: bar.width, height: bar.height)
            .accessibilityLabel(Text("Rain bar"))
    }
}

// MARK: - Wiggle Shape

struct WeatherNowcastWiggleLine: Shape {
    struct Point: Hashable {
        let index: Int
        let x01: Double
        let y01: Double
        let uncertainty01: Double
    }

    let points: [Point]
    let maxAmplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }

        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

        let cgPoints: [CGPoint] = points.map {
            CGPoint(
                x: rect.minX + CGFloat($0.x01) * rect.width,
                y: rect.minY + CGFloat($0.y01) * rect.height
            )
        }

        var path = Path()
        path.move(to: cgPoints[0])

        let segmentsPerEdge = 6

        for i in 0..<(cgPoints.count - 1) {
            let p0 = cgPoints[i]
            let p1 = cgPoints[i + 1]

            let u0 = clamp01(points[i].uncertainty01)
            let u1 = clamp01(points[i + 1].uncertainty01)

            for s in 1...segmentsPerEdge {
                let t = CGFloat(s) / CGFloat(segmentsPerEdge)

                let x = lerp(p0.x, p1.x, t)
                let yBase = lerp(p0.y, p1.y, t)

                let u = lerpD(u0, u1, Double(t))
                let amp = CGFloat(u) * maxAmplitude

                // Deterministic phase: stable per bucket index (static uncertainty look).
                let phase = (Double(i) * 1.25) + (Double(t) * Double.pi * 2.6)
                let wiggle = sin(phase) * Double(amp)

                let y = yBase + CGFloat(wiggle)

                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

// MARK: - Utilities

private func clamp01(_ v: Double) -> Double {
    max(0.0, min(1.0, v))
}
