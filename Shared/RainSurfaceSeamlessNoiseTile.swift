//
//  RainSurfaceSeamlessNoiseTile.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//
//  Seamless (wrap-around) noise tiles used for the nowcast “dissipated” rain surface.
//  These must be exactly seamless because GraphicsContext.Shading.tiledImage repeats them with filtering.
//  If the first/last row or column differs, the repeat boundary becomes visible.
//

import Foundation
import SwiftUI
import CoreGraphics

enum RainSurfaceSeamlessNoiseTile {

    enum Kind {
        case fine
        case coarse
    }

    // Smaller tile reduces cold-start cost in WidgetKit.
    static let tileSizePixels: Int = 64

    static func image(_ kind: Kind) -> Image {
        switch kind {
        case .fine:
            return Image(decorative: fineCGImage, scale: 1.0, orientation: .up)
        case .coarse:
            return Image(decorative: coarseCGImage, scale: 1.0, orientation: .up)
        }
    }

    static func cgImage(_ kind: Kind) -> CGImage {
        switch kind {
        case .fine: return fineCGImage
        case .coarse: return coarseCGImage
        }
    }

    // MARK: - Cached tiles

    private static let fineCGImage: CGImage = {
        // Fine grain: mostly transparent highlights.
        makeTile(
            size: tileSizePixels,
            seed: 0xA1B2_C3D4_E5F6_1020,
            basePeriod: 38,
            octaves: 3,
            lacunarity: 2.0,
            gain: 0.55,
            cutoff: 0.50,
            power: 1.65,
            baseAlpha: 0.030
        )
    }()

    private static let coarseCGImage: CGImage = {
        // Coarse wisps: chunkier alpha shapes.
        makeTile(
            size: tileSizePixels,
            seed: 0x0F1E_2D3C_4B5A_6978,
            basePeriod: 14,
            octaves: 3,
            lacunarity: 2.0,
            gain: 0.62,
            cutoff: 0.46,
            power: 1.35,
            baseAlpha: 0.022
        )
    }()

    // MARK: - Generation

    private static func makeTile(
        size: Int,
        seed: UInt64,
        basePeriod: Int,
        octaves: Int,
        lacunarity: Double,
        gain: Double,
        cutoff: Double,
        power: Double,
        baseAlpha: Double
    ) -> CGImage {
        let w = max(2, size)
        let h = max(2, size)

        // Precompute octave grids (periodic).
        var grids: [(period: Int, values: [Double], amp: Double)] = []
        grids.reserveCapacity(max(1, octaves))

        var prng = RainSurfacePRNG(seed: seed)
        var period = max(2, basePeriod)
        var amp = 1.0

        for _ in 0..<max(1, octaves) {
            let values = makeGrid(period: period, prng: &prng)
            grids.append((period: period, values: values, amp: amp))
            amp *= gain
            period = max(2, Int(Double(period) * lacunarity))
        }

        let ampSum = max(0.000001, grids.reduce(0.0) { $0 + $1.amp })

        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        // Seam-free tiling requires the last pixel row/column to equal the first.
        // Sampling u/v in [0, 1] inclusive (denominator = size - 1) guarantees exact edge matches.
        let denomX = Double(max(1, w - 1))
        let denomY = Double(max(1, h - 1))

        for y in 0..<h {
            let v = Double(y) / denomY
            for x in 0..<w {
                let u = Double(x) / denomX

                var value = 0.0
                for g in grids {
                    value += samplePeriodicValueNoise(u: u, v: v, period: g.period, grid: g.values) * g.amp
                }
                value /= ampSum

                // Alpha shaping (sparse).
                var a = (value - cutoff) / max(0.000001, (1.0 - cutoff))
                a = clamp01(a)
                a = pow(a, max(0.05, power))
                a = baseAlpha + (1.0 - baseAlpha) * a

                let alpha = UInt8(max(0, min(255, Int((a * 255.0).rounded()))))

                let i = (y * w + x) * 4
                rgba[i + 0] = 255
                rgba[i + 1] = 255
                rgba[i + 2] = 255
                rgba[i + 3] = alpha
            }
        }

        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    private static func makeGrid(period: Int, prng: inout RainSurfacePRNG) -> [Double] {
        let p = max(2, period)
        var out = [Double](repeating: 0.0, count: p * p)
        for i in 0..<out.count {
            out[i] = prng.nextFloat01()
        }
        return out
    }

    private static func samplePeriodicValueNoise(u: Double, v: Double, period: Int, grid: [Double]) -> Double {
        let p = max(2, period)

        let x = u * Double(p)
        let y = v * Double(p)

        let x0i = Int(floor(x))
        let y0i = Int(floor(y))
        let x1i = x0i + 1
        let y1i = y0i + 1

        let tx = x - Double(x0i)
        let ty = y - Double(y0i)

        let sx = smoothstep(tx)
        let sy = smoothstep(ty)

        let x0 = positiveMod(x0i, p)
        let y0 = positiveMod(y0i, p)
        let x1 = positiveMod(x1i, p)
        let y1 = positiveMod(y1i, p)

        let v00 = grid[y0 * p + x0]
        let v10 = grid[y0 * p + x1]
        let v01 = grid[y1 * p + x0]
        let v11 = grid[y1 * p + x1]

        let a = lerp(v00, v10, sx)
        let b = lerp(v01, v11, sx)
        return lerp(a, b, sy)
    }

    private static func positiveMod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return (r < 0) ? (r + m) : r
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = clamp01(t)
        return x * x * (3.0 - 2.0 * x)
    }

    private static func clamp01(_ x: Double) -> Double {
        max(0.0, min(1.0, x.isFinite ? x : 0.0))
    }
}
