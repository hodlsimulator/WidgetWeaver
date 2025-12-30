//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Procedural "rain surface" renderer.
//  Goal: pure black background, smooth core mound, and a speckled fuzzy uncertainty band
//  that resembles the mockup (without heavy blurs or per-pixel work).
//

import SwiftUI
import Foundation

struct RainForecastSurfaceRenderer {
    private let intensities: [Double]
    private let certainties: [Double]
    private let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    init(
        intensities: [Double],
        certainties: [Double?],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties.map { $0 ?? 0.0 }
        self.configuration = configuration
    }

    func render(in context: inout GraphicsContext, rect: CGRect, displayScale: CGFloat) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        guard !rect.isEmpty else { return }

        // Ensure the configuration knows the source count (used for tail minutes mapping).
        var cfg = configuration
        cfg.sourceMinuteCount = max(1, intensities.count)

        // Layout
        let chartRect = rect
        let baselineY = chartRect.minY + chartRect.height * CGFloat(cfg.baselineFractionFromTop)

        // Convert intensities to heights, resample, smooth, then build curve points.
        let source = Self.fillMissingLinearHoldEnds(intensities)
        let (denseHeights, denseCertainties) = Self.makeDenseSignals(
            sourceIntensities: source,
            sourceCertainties: certainties,
            rect: chartRect,
            baselineY: baselineY,
            displayScale: ds,
            cfg: cfg
        )

        let curvePoints = Self.makeCurvePoints(
            rect: chartRect,
            baselineY: baselineY,
            heights: denseHeights
        )

        // Core fill (mound).
        let corePath = Self.makeCoreFillPath(rect: chartRect, baselineY: baselineY, curve: curvePoints)
        Self.drawCore(in: &context, rect: chartRect, baselineY: baselineY, corePath: corePath, cfg: cfg)

        // Rim (optional)
        if cfg.rimEnabled, curvePoints.count >= 2 {
            let strokePath = Self.makeCurveStrokePath(curve: curvePoints)
            Self.drawRim(in: &context, strokePath: strokePath, displayScale: ds, cfg: cfg)
        }

        // Fuzz (uncertainty). Hard requirement: avoid expensive work in WidgetKit placeholder contexts.
        if cfg.fuzzEnabled, cfg.canEnableFuzz, curvePoints.count >= 2 {
            Self.drawFuzz(
                in: &context,
                rect: chartRect,
                baselineY: baselineY,
                curve: curvePoints,
                heights: denseHeights,
                certainties: denseCertainties,
                displayScale: ds,
                cfg: cfg
            )
        }

        // Baseline line.
        if cfg.baselineEnabled {
            Self.drawBaseline(in: &context, rect: chartRect, baselineY: baselineY, displayScale: ds, cfg: cfg)
        }
    }
}

// MARK: - Core

private extension RainForecastSurfaceRenderer {
    static func drawCore(in context: inout GraphicsContext, rect: CGRect, baselineY: CGFloat, corePath: Path, cfg: RainForecastSurfaceConfiguration) {
        // Vertical core gradient: lighter near the top, deeper toward the baseline.
        let topY = rect.minY + rect.height * CGFloat(cfg.topHeadroomFraction)
        let start = CGPoint(x: rect.midX, y: topY)
        let end = CGPoint(x: rect.midX, y: baselineY)

        let gradient = Gradient(stops: [
            .init(color: cfg.coreTopColor, location: 0.0),
            .init(color: cfg.coreBodyColor, location: 1.0)
        ])

        context.fill(corePath, with: .linearGradient(gradient, startPoint: start, endPoint: end))

        // Optional gloss: cheap (no blur), clipped by core shape.
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0 {
            let glossOpacity = max(0.0, min(cfg.glossMaxOpacity, 1.0))
            if glossOpacity > 0.0001 {
                context.drawLayer { layer in
                    layer.clip(to: corePath)

                    let glossHeight = max(1.0, (baselineY - topY) * 0.32)
                    let glossRect = CGRect(
                        x: rect.minX,
                        y: topY,
                        width: rect.width,
                        height: glossHeight
                    )

                    let g = Gradient(stops: [
                        .init(color: Color.white.opacity(glossOpacity), location: 0.0),
                        .init(color: Color.white.opacity(0.0), location: 1.0)
                    ])
                    layer.blendMode = .screen
                    layer.fill(Path(glossRect), with: .linearGradient(g, startPoint: glossRect.origin, endPoint: CGPoint(x: glossRect.minX, y: glossRect.maxY)))
                }
            }
        }

        // Fade ends into black a bit (matches the mockup's “tails” that disappear).
        let fade = max(0.0, min(cfg.coreFadeFraction, 0.48))
        if fade > 0.0001 {
            let leftFadeW = rect.width * CGFloat(fade)
            let rightFadeW = rect.width * CGFloat(fade)

            context.drawLayer { layer in
                layer.clip(to: corePath)

                // Left fade
                let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftFadeW, height: rect.height)
                let gl = Gradient(stops: [
                    .init(color: Color.black.opacity(1.0), location: 0.0),
                    .init(color: Color.black.opacity(0.0), location: 1.0)
                ])
                layer.blendMode = .multiply
                layer.fill(Path(leftRect), with: .linearGradient(gl, startPoint: leftRect.origin, endPoint: CGPoint(x: leftRect.maxX, y: leftRect.minY)))

                // Right fade
                let rightRect = CGRect(x: rect.maxX - rightFadeW, y: rect.minY, width: rightFadeW, height: rect.height)
                let gr = Gradient(stops: [
                    .init(color: Color.black.opacity(0.0), location: 0.0),
                    .init(color: Color.black.opacity(1.0), location: 1.0)
                ])
                layer.fill(Path(rightRect), with: .linearGradient(gr, startPoint: CGPoint(x: rightRect.minX, y: rightRect.minY), endPoint: CGPoint(x: rightRect.maxX, y: rightRect.minY)))
            }
        }
    }

    static func drawRim(in context: inout GraphicsContext, strokePath: Path, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        // Outer rim
        let outerOpacity = max(0.0, min(cfg.rimOuterOpacity, 1.0))
        let outerW = max(0.25, cfg.rimOuterWidthPixels / ds)
        if outerOpacity > 0.0001, outerW > 0 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(strokePath, with: .color(cfg.rimColor.opacity(outerOpacity)), lineWidth: outerW)
            }
        }

        // Inner rim
        let innerOpacity = max(0.0, min(cfg.rimInnerOpacity, 1.0))
        let innerW = max(0.25, cfg.rimInnerWidthPixels / ds)
        if innerOpacity > 0.0001, innerW > 0 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(strokePath, with: .color(cfg.rimColor.opacity(innerOpacity)), lineWidth: innerW)
            }
        }
    }
}

// MARK: - Fuzz / Uncertainty

private extension RainForecastSurfaceRenderer {
    static func drawFuzz(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        curve: [CGPoint],
        heights: [CGFloat],
        certainties: [Double],
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        // Band width in points (clamped from config's pixel clamp).
        let bandWidth = computeBandWidth(rect: rect, displayScale: ds, cfg: cfg)
        if bandWidth <= 0.5 { return }

        // Strength per point: driven by chance/uncertainty + extra at low heights + tail emphasis.
        var strength = computeFuzzStrength(heights: heights, certainties: certainties, cfg: cfg)

        // Suppress fuzz far away from any rain "mass" to avoid peppering long dry baseline.
        let wetEps: CGFloat = max(1.0, (rect.height * 0.004))
        let wetMask = heights.map { $0 > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)

        let samplesPerPx = max(0.0001, Double(curve.count - 1) / Double(max(1.0, rect.width * ds)))
        let edgeWindowSamples = max(1, Int(round(cfg.fuzzEdgeWindowPx * samplesPerPx)))

        for i in 0..<strength.count {
            if distToWet[i] > edgeWindowSamples {
                strength[i] = 0
            }
        }

        // Emphasise around transitions (wet <-> dry), within a tail window in minutes.
        applyTailBoost(strength: &strength, wetMask: wetMask, cfg: cfg)

        // Particle budget: clamp hard + width-scaled cap to avoid accidental blowups.
        var budget = Int(round(Double(cfg.fuzzSpeckleBudget) * max(0.0, cfg.fuzzDensity)))
        budget = max(0, min(budget, 9000))

        // Extra safety cap in app extensions (WidgetKit is tight).
        let runtimeCap = WidgetWeaverRuntime.isRunningInAppExtension ? 2000 : 4200
        budget = min(budget, runtimeCap)

        // Width-scaled cap (prevents tying speckles to area).
        let wPx = Double(rect.width * ds)
        let widthCap = Int(max(250, min(4200, wPx * 5.0)))
        budget = min(budget, widthCap)

        if budget <= 0 { return }

        // Convert per-point strength into weights (also discourage speckles when strength is tiny).
        var weights = [Double](repeating: 0, count: curve.count)
        var totalW: Double = 0
        for i in 0..<curve.count {
            let s = Double(strength[i])
            if s <= 0.0005 { continue }
            // Slight curve-length preference (avoids concentrating only at the peak).
            let w = s
            weights[i] = w
            totalW += w
        }

        if totalW <= 0.0000001 { return }

        let counts = allocateCounts(budget: budget, weights: weights, totalWeight: totalW)

        // Tangents/normals along the curve.
        let (tangents, normals) = computeTangentsAndNormals(curve)

        // Particle parameters
        let baseOpacity = max(0.0, min(cfg.fuzzMaxOpacity, 1.0)) * max(0.0, cfg.fuzzSpeckStrength)
        let insideFrac = max(0.0, min(cfg.fuzzInsideSpeckleFraction, 1.0))

        let minR = max(0.10, cfg.fuzzSpeckleRadiusPixels.lowerBound / ds)
        let maxR = max(minR, cfg.fuzzSpeckleRadiusPixels.upperBound / ds)

        let outsidePow = max(0.05, cfg.fuzzDistancePowerOutside)
        let insidePow = max(0.05, cfg.fuzzDistancePowerInside)

        let tanJitter = max(0.0, cfg.fuzzAlongTangentJitter) * Double(bandWidth)

        let insideWidth = Double(bandWidth) * max(0.0, cfg.fuzzInsideWidthFactor)
        let insideOpacityFactor = max(0.0, min(cfg.fuzzInsideOpacityFactor, 1.0))

        // Deterministic RNG.
        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, UInt64(curve.count) &* 0x9E37_79B9_7F4A_7C15)
        var rng = RainSurfacePRNG(seed: seed)

        // Bin by alpha to keep draw calls low (few fills) without losing contrast.
        let binCount = 9
        var binPaths = Array(repeating: Path(), count: binCount)
        var binAlphaSum = Array(repeating: 0.0, count: binCount)
        var binDotCount = Array(repeating: 0, count: binCount)

        // Draw in a single clipped layer; blend adds the luminous speck look.
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            layer.blendMode = .plusLighter

            for i in 0..<curve.count {
                let c = counts[i]
                if c <= 0 { continue }

                let p0 = curve[i]
                let t = tangents[i]
                let n = normals[i]

                let s = Double(strength[i])
                if s <= 0.0005 { continue }

                for _ in 0..<c {
                    let isInside = (rng.nextFloat01() < insideFrac)

                    // Distance from the curve along the normal (outside vs inside have different powers/width).
                    let u = rng.nextFloat01()
                    let distUnit = pow(u, isInside ? insidePow : outsidePow)

                    let maxDist = isInside ? insideWidth : Double(bandWidth)
                    let signedDist = (isInside ? -1.0 : 1.0) * distUnit * maxDist

                    // Tangent jitter keeps it "cloudy" rather than a clean stroke.
                    let tanJ = rng.nextSignedFloat() * tanJitter

                    var x = Double(p0.x) + Double(n.x) * signedDist + Double(t.x) * tanJ
                    var y = Double(p0.y) + Double(n.y) * signedDist + Double(t.y) * tanJ

                    // Keep fuzz above baseline.
                    y = min(y, Double(baselineY) - 0.25)

                    // Random radius, skewed toward small.
                    let rr = pow(rng.nextFloat01(), 1.85)
                    let r = minR + (maxR - minR) * CGFloat(rr)

                    // Opacity: strength * distance falloff * random jitter.
                    let distAbs = abs(signedDist)
                    let falloff = pow(max(0.0, 1.0 - distAbs / max(0.0001, maxDist)), 2.2)

                    var a = baseOpacity * s * falloff
                    if isInside {
                        a *= insideOpacityFactor
                    }

                    // Small jitter for grain feel.
                    a *= (0.80 + 0.40 * rng.nextFloat01())
                    a = max(0.0, min(a, 0.85))

                    if a <= 0.0003 { continue }

                    // Bin selection by relative alpha.
                    let rel = max(0.0, min(1.0, a / max(0.0001, baseOpacity)))
                    let b = min(binCount - 1, max(0, Int(rel * Double(binCount - 1))))

                    let ellipse = CGRect(
                        x: CGFloat(x) - r,
                        y: CGFloat(y) - r,
                        width: r * 2.0,
                        height: r * 2.0
                    )
                    binPaths[b].addEllipse(in: ellipse)
                    binAlphaSum[b] += a
                    binDotCount[b] += 1
                }
            }

            // Fill bins
            for b in 0..<binCount {
                let nDots = binDotCount[b]
                if nDots == 0 { continue }
                let avgA = binAlphaSum[b] / Double(nDots)
                if avgA <= 0.0002 { continue }
                layer.fill(binPaths[b], with: .color(cfg.fuzzColor.opacity(avgA)))
            }

            // Optional haze stroke (no blur): one cheap stroke adds coherence.
            let hazeStrength = max(0.0, min(cfg.fuzzHazeStrength, 1.0))
            if hazeStrength > 0.0001 {
                let hazePath = makeCurveStrokePath(curve: curve)

                let lw = max(0.25, (Double(bandWidth) * cfg.fuzzHazeStrokeWidthFactor))
                layer.stroke(hazePath, with: .color(cfg.fuzzColor.opacity(hazeStrength * 0.20)), lineWidth: lw)

                let insideLW = max(0.25, (Double(bandWidth) * cfg.fuzzInsideHazeStrokeWidthFactor))
                layer.stroke(hazePath, with: .color(cfg.fuzzColor.opacity(hazeStrength * 0.12)), lineWidth: insideLW)
            }
        }
    }

    static func computeBandWidth(rect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        let fractionWidth = rect.width * CGFloat(max(0.0, cfg.fuzzWidthFraction))

        let minPx = max(0.0, cfg.fuzzWidthPixelsClamp.lowerBound)
        let maxPx = max(minPx, cfg.fuzzWidthPixelsClamp.upperBound)

        let minPt = CGFloat(minPx) / ds
        let maxPt = CGFloat(maxPx) / ds

        return min(max(fractionWidth, minPt), maxPt)
    }

    static func computeFuzzStrength(heights: [CGFloat], certainties: [Double], cfg: RainForecastSurfaceConfiguration) -> [CGFloat] {
        let n = min(heights.count, certainties.count)
        if n <= 0 { return [] }

        let smoothCert = smoothDoubles(Array(certainties.prefix(n)), radius: 2, passes: 1)

        let maxH = max(heights.prefix(n).max() ?? 0.0, 0.0001)
        let invMaxH = 1.0 / Double(maxH)

        let thr = cfg.fuzzChanceThreshold
        let trans = max(0.0001, cfg.fuzzChanceTransition)
        let exp = max(0.01, cfg.fuzzChanceExponent)
        let floor = max(0.0, min(cfg.fuzzChanceFloor, 1.0))
        let minStrength = max(0.0, min(cfg.fuzzChanceMinStrength, 1.0))

        let lowPow = max(0.01, cfg.fuzzLowHeightPower)
        let lowBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var out = [CGFloat](repeating: 0, count: n)

        for i in 0..<n {
            let c = clamp01(smoothCert[i])

            // Lower chance => higher fuzz strength.
            var s = clamp01((thr - c) / trans)
            s = pow(s, exp)

            // Floor and min strength.
            s = max(s, floor)

            // Low-height emphasis (edges and base get more fuzz).
            let hNorm = clamp01(Double(heights[i]) * invMaxH)
            let low = pow(1.0 - hNorm, lowPow)
            s *= (1.0 + lowBoost * low)

            s = max(s, minStrength)
            out[i] = CGFloat(clamp01(s))
        }

        return out
    }

    static func applyTailBoost(strength: inout [CGFloat], wetMask: [Bool], cfg: RainForecastSurfaceConfiguration) {
        guard strength.count == wetMask.count, strength.count > 2 else { return }

        let n = strength.count
        let minutes = max(0.0, cfg.fuzzTailMinutes)
        let sourceCount = max(1, cfg.sourceMinuteCount)

        let tailSamples = Int(round(Double(n) * minutes / Double(sourceCount)))
        if tailSamples <= 0 { return }

        // Find transitions (wet <-> dry).
        var transitions: [Int] = []
        for i in 1..<n {
            if wetMask[i] != wetMask[i - 1] {
                transitions.append(i)
            }
        }
        if transitions.isEmpty { return }

        for tIdx in transitions {
            let lo = max(0, tIdx - tailSamples)
            let hi = min(n - 1, tIdx + tailSamples)

            for j in lo...hi {
                let d = abs(j - tIdx)
                let u = 1.0 - (Double(d) / Double(max(1, tailSamples)))
                let boost = pow(max(0.0, u), 1.8) // more concentrated at the edge
                let s = Double(strength[j])

                // Pull towards 1.0 near edges, but never exceeds 1.0.
                let bumped = s + (1.0 - s) * (0.65 * boost)
                strength[j] = CGFloat(min(1.0, max(0.0, bumped)))
            }
        }
    }
}

// MARK: - Baseline

private extension RainForecastSurfaceRenderer {
    static func drawBaseline(in context: inout GraphicsContext, rect: CGRect, baselineY: CGFloat, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        let lineOpacity = max(0.0, min(cfg.baselineLineOpacity, 1.0))
        if lineOpacity <= 0.0001 { return }

        let y = baselineY + CGFloat(cfg.baselineOffsetPixels) / ds
        let w = max(0.25, CGFloat(cfg.baselineWidthPixels) / ds)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))

        let fade = max(0.0, min(cfg.baselineEndFadeFraction, 0.49))
        if fade > 0.0001 {
            let g = Gradient(stops: [
                .init(color: cfg.baselineColor.opacity(0.0), location: 0.0),
                .init(color: cfg.baselineColor.opacity(lineOpacity), location: fade),
                .init(color: cfg.baselineColor.opacity(lineOpacity), location: 1.0 - fade),
                .init(color: cfg.baselineColor.opacity(0.0), location: 1.0)
            ])
            context.stroke(
                p,
                with: .linearGradient(g, startPoint: CGPoint(x: rect.minX, y: y), endPoint: CGPoint(x: rect.maxX, y: y)),
                lineWidth: w
            )
        } else {
            context.stroke(p, with: .color(cfg.baselineColor.opacity(lineOpacity)), lineWidth: w)
        }
    }
}

// MARK: - Dense signals and geometry

private extension RainForecastSurfaceRenderer {
    static func makeDenseSignals(
        sourceIntensities: [Double],
        sourceCertainties: [Double],
        rect: CGRect,
        baselineY: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) -> (heights: [CGFloat], certainties: [Double]) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0
        let nSrc = max(1, sourceIntensities.count)

        // Determine a robust max for scaling.
        let robustMax = robustReferenceMax(
            values: sourceIntensities,
            fallback: cfg.intensityReferenceMaxMMPerHour,
            percentile: cfg.robustMaxPercentile
        )

        let availableHeight = max(2.0, (baselineY - rect.minY) - rect.height * CGFloat(cfg.topHeadroomFraction))
        let peakTarget = CGFloat(max(0.05, min(cfg.typicalPeakFraction, 1.0))) * availableHeight

        let gamma = max(0.01, cfg.intensityGamma)

        // Convert to source heights.
        var srcHeights = [CGFloat](repeating: 0, count: nSrc)
        for i in 0..<nSrc {
            let v = max(0.0, sourceIntensities[i])
            let norm = clamp01(v / max(0.0001, robustMax))
            let shaped = pow(norm, gamma)
            srcHeights[i] = peakTarget * CGFloat(shaped)
        }

        // Edge easing (soft tails).
        applyEdgeEasing(&srcHeights, fraction: cfg.edgeEasingFraction, power: cfg.edgeEasingPower)

        // Make a certainty array of matching length (if missing, treat as 0).
        var srcCert = [Double](repeating: 0.0, count: nSrc)
        if sourceCertainties.count == nSrc {
            for i in 0..<nSrc { srcCert[i] = clamp01(sourceCertainties[i]) }
        } else if !sourceCertainties.isEmpty {
            let r = resampleLinear(sourceCertainties.map(clamp01), targetCount: nSrc)
            for i in 0..<nSrc { srcCert[i] = r[i] }
        }

        // Dense sample count: proportional to width, but clamped.
        let wPx = Double(rect.width * ds)
        let desired = max(nSrc, Int(round(wPx * 1.85)))
        let nDense = max(120, min(desired, max(120, cfg.maxDenseSamples)))

        let denseHeights = smoothCGFloats(
            resampleLinear(srcHeights, targetCount: nDense),
            radius: 2,
            passes: 2
        )

        let denseCert = smoothDoubles(
            resampleLinear(srcCert, targetCount: nDense),
            radius: 2,
            passes: 1
        )

        return (denseHeights, denseCert)
    }

    static func makeCurvePoints(rect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> [CGPoint] {
        let n = max(2, heights.count)
        if heights.count < 2 {
            return [
                CGPoint(x: rect.minX, y: baselineY),
                CGPoint(x: rect.maxX, y: baselineY)
            ]
        }

        var pts: [CGPoint] = []
        pts.reserveCapacity(heights.count)

        for i in 0..<heights.count {
            let t = CGFloat(i) / CGFloat(max(1, heights.count - 1))
            let x = rect.minX + rect.width * t
            let y = max(rect.minY, min(baselineY, baselineY - heights[i]))
            pts.append(CGPoint(x: x, y: y))
        }

        return pts
    }

    static func makeCoreFillPath(rect: CGRect, baselineY: CGFloat, curve: [CGPoint]) -> Path {
        guard let first = curve.first, let last = curve.last else { return Path() }

        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: baselineY))
            p.addLine(to: first)

            if curve.count == 2 {
                p.addLine(to: last)
            } else {
                var prev = first
                for i in 1..<curve.count {
                    let cur = curve[i]
                    let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
                    p.addQuadCurve(to: mid, control: prev)
                    prev = cur
                }
                p.addLine(to: last)
            }

            p.addLine(to: CGPoint(x: rect.maxX, y: baselineY))
            p.closeSubpath()
        }
    }

    static func makeCurveStrokePath(curve: [CGPoint]) -> Path {
        guard let first = curve.first, let last = curve.last else { return Path() }

        return Path { p in
            p.move(to: first)

            if curve.count == 2 {
                p.addLine(to: last)
                return
            }

            var prev = first
            for i in 1..<curve.count {
                let cur = curve[i]
                let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
                p.addQuadCurve(to: mid, control: prev)
                prev = cur
            }

            p.addLine(to: last)
        }
    }

    static func computeTangentsAndNormals(_ pts: [CGPoint]) -> (tangents: [CGPoint], normals: [CGPoint]) {
        let n = pts.count
        var tangents = Array(repeating: CGPoint(x: 1, y: 0), count: n)
        var normals = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        guard n >= 2 else { return (tangents, normals) }

        for i in 0..<n {
            let pPrev = pts[max(0, i - 1)]
            let pNext = pts[min(n - 1, i + 1)]
            let dx = pNext.x - pPrev.x
            let dy = pNext.y - pPrev.y

            let len = max(0.0001, sqrt(dx * dx + dy * dy))
            let tx = dx / len
            let ty = dy / len

            var nx = -ty
            var ny = tx

            // Ensure "outside" normal generally points upward (negative y).
            if ny > 0 {
                nx = -nx
                ny = -ny
            }

            tangents[i] = CGPoint(x: tx, y: ty)
            normals[i] = CGPoint(x: nx, y: ny)
        }

        return (tangents, normals)
    }
}

// MARK: - Utilities (no per-pixel loops, bounded work)

private extension RainForecastSurfaceRenderer {
    static func clamp01(_ x: Double) -> Double {
        if x.isNaN { return 0.0 }
        if x < 0 { return 0.0 }
        if x > 1 { return 1.0 }
        return x
    }

    static func robustReferenceMax(values: [Double], fallback: Double, percentile: Double) -> Double {
        let finite = values.filter { $0.isFinite && $0 >= 0.0 }
        if finite.isEmpty {
            return max(0.0001, fallback.isFinite ? max(0.0001, fallback) : 1.0)
        }

        let p = clamp01(percentile)
        let sorted = finite.sorted()
        let idx = min(sorted.count - 1, max(0, Int(round(Double(sorted.count - 1) * p))))
        let v = sorted[idx]
        return max(0.0001, v)
    }

    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        if values.isEmpty { return [] }

        var out = values
        var finiteIdx: [Int] = []
        finiteIdx.reserveCapacity(values.count)

        for i in values.indices {
            if values[i].isFinite {
                finiteIdx.append(i)
            } else {
                out[i] = .nan
            }
        }

        if finiteIdx.isEmpty {
            return Array(repeating: 0.0, count: values.count)
        }

        // Leading
        let first = finiteIdx[0]
        let firstV = max(0.0, values[first])
        if first > 0 {
            for i in 0..<first { out[i] = firstV }
        }

        // Gaps
        for k in 0..<(finiteIdx.count - 1) {
            let a = finiteIdx[k]
            let b = finiteIdx[k + 1]
            let va = max(0.0, values[a])
            let vb = max(0.0, values[b])

            out[a] = va
            out[b] = vb

            let gap = b - a
            if gap > 1 {
                for i in (a + 1)..<b {
                    let t = Double(i - a) / Double(gap)
                    out[i] = va + (vb - va) * t
                }
            }
        }

        // Trailing
        let last = finiteIdx.last!
        let lastV = max(0.0, values[last])
        if last < values.count - 1 {
            for i in (last + 1)..<values.count { out[i] = lastV }
        }

        // Final clamp
        for i in out.indices {
            if !out[i].isFinite { out[i] = 0.0 }
            out[i] = max(0.0, out[i])
        }

        return out
    }

    static func resampleLinear(_ values: [Double], targetCount: Int) -> [Double] {
        let n = values.count
        if targetCount <= 0 { return [] }
        if n == 0 { return Array(repeating: 0.0, count: targetCount) }
        if n == 1 { return Array(repeating: values[0], count: targetCount) }
        if targetCount == n { return values }

        var out = [Double](repeating: 0.0, count: targetCount)
        for i in 0..<targetCount {
            let t = Double(i) / Double(max(1, targetCount - 1))
            let pos = t * Double(n - 1)
            let j0 = Int(floor(pos))
            let j1 = min(n - 1, j0 + 1)
            let u = pos - Double(j0)
            out[i] = values[j0] + (values[j1] - values[j0]) * u
        }
        return out
    }

    static func resampleLinear(_ values: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = values.count
        if targetCount <= 0 { return [] }
        if n == 0 { return Array(repeating: 0.0, count: targetCount) }
        if n == 1 { return Array(repeating: values[0], count: targetCount) }
        if targetCount == n { return values }

        var out = [CGFloat](repeating: 0.0, count: targetCount)
        for i in 0..<targetCount {
            let t = CGFloat(i) / CGFloat(max(1, targetCount - 1))
            let pos = t * CGFloat(n - 1)
            let j0 = Int(floor(pos))
            let j1 = min(n - 1, j0 + 1)
            let u = pos - CGFloat(j0)
            out[i] = values[j0] + (values[j1] - values[j0]) * u
        }
        return out
    }

    static func applyEdgeEasing(_ heights: inout [CGFloat], fraction: Double, power: Double) {
        let n = heights.count
        if n < 2 { return }

        let f = max(0.0, min(0.49, fraction))
        let m = Int(round(Double(n) * f))
        if m <= 0 { return }

        let p = max(0.05, power)

        for i in 0..<m {
            let t = Double(i) / Double(max(1, m - 1))
            let e = pow(t, p)
            heights[i] *= CGFloat(e)
            heights[n - 1 - i] *= CGFloat(e)
        }
    }

    static func smoothDoubles(_ values: [Double], radius: Int, passes: Int) -> [Double] {
        if values.count < 3 { return values }
        let r = max(0, radius)
        let p = max(0, passes)
        if r == 0 || p == 0 { return values }

        var out = values
        var tmp = values

        for _ in 0..<p {
            for i in 0..<out.count {
                let lo = max(0, i - r)
                let hi = min(out.count - 1, i + r)
                var s = 0.0
                var c = 0.0
                for j in lo...hi {
                    s += out[j]
                    c += 1.0
                }
                tmp[i] = (c > 0) ? (s / c) : out[i]
            }
            out = tmp
        }

        return out
    }

    static func smoothCGFloats(_ values: [CGFloat], radius: Int, passes: Int) -> [CGFloat] {
        if values.count < 3 { return values }
        let r = max(0, radius)
        let p = max(0, passes)
        if r == 0 || p == 0 { return values }

        var out = values
        var tmp = values

        for _ in 0..<p {
            for i in 0..<out.count {
                let lo = max(0, i - r)
                let hi = min(out.count - 1, i + r)
                var s: CGFloat = 0
                var c: CGFloat = 0
                for j in lo...hi {
                    s += out[j]
                    c += 1
                }
                tmp[i] = (c > 0) ? (s / c) : out[i]
            }
            out = tmp
        }

        return out
    }

    static func distanceToNearestTrue(_ mask: [Bool]) -> [Int] {
        let n = mask.count
        if n == 0 { return [] }

        let inf = 1_000_000
        var dist = Array(repeating: inf, count: n)

        var lastTrue = -inf
        for i in 0..<n {
            if mask[i] { lastTrue = i }
            dist[i] = i - lastTrue
        }

        lastTrue = inf
        for i in stride(from: n - 1, through: 0, by: -1) {
            if mask[i] { lastTrue = i }
            dist[i] = min(dist[i], lastTrue - i)
        }

        return dist
    }

    static func allocateCounts(budget: Int, weights: [Double], totalWeight: Double) -> [Int] {
        let n = weights.count
        if n == 0 || budget <= 0 || totalWeight <= 0 {
            return Array(repeating: 0, count: n)
        }

        var counts = Array(repeating: 0, count: n)
        var fracs: [(idx: Int, frac: Double)] = []
        fracs.reserveCapacity(n)

        var assigned = 0
        let invTotal = 1.0 / totalWeight

        for i in 0..<n {
            let raw = Double(budget) * weights[i] * invTotal
            let base = Int(floor(raw))
            counts[i] = max(0, base)
            assigned += counts[i]
            fracs.append((i, raw - Double(base)))
        }

        var remaining = budget - assigned
        if remaining <= 0 { return counts }

        fracs.sort { $0.frac > $1.frac }

        var k = 0
        while remaining > 0 && k < fracs.count {
            counts[fracs[k].idx] += 1
            remaining -= 1
            k += 1
            if k == fracs.count { k = 0 }
        }

        return counts
    }
}
