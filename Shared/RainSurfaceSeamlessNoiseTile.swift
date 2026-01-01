//
//  RainSurfaceSeamlessNoiseTile.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//
//  Seamless (wrap-around) noise tiles used for the nowcast “dissipated” rain surface.
//  These are generated deterministically in code to avoid visible seams/banding when tiled.
//

import Foundation
import SwiftUI
import CoreGraphics

enum RainSurfaceSeamlessNoiseTile {

    enum Kind {
        case fine
        case coarse
    }

    // Tile size in pixels for both variants.
    // A fixed size keeps caching simple; scaling is handled at draw time.
    static let tileSizePixels: Int = 128

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
        // Fine grain: higher frequency + higher cutoff (mostly transparent).
        makeTile(
            size: tileSizePixels,
            seed: 0xA1B2_C3D4_E5F6_1020,
            basePeriod: 26,
            octaves: 4,
            lacunarity: 2.0,
            gain: 0.55,
            cutoff: 0.58,
            power: 2.35,
            baseAlpha: 0.015
        )
    }()

    private static let coarseCGImage: CGImage = {
        // Coarse wisps: lower frequency + lower cutoff (more connected shapes).
        makeTile(
            size: tileSizePixels,
            seed: 0x0F1E_2D3C_4B5A_6978,
            basePeriod: 12,
            octaves: 3,
            lacunarity: 2.0,
            gain: 0.60,
            cutoff: 0.50,
            power: 1.65,
            baseAlpha: 0.010
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

        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        let denomX = Double(w - 1)
        let denomY = Double(h - 1)

        for y in 0..<h {
            let v = Double(y) / denomY
            for x in 0..<w {
                let u = Double(x) / denomX

                var value = 0.0
                var amp = 1.0
                var sum = 0.0

                var period = max(2, basePeriod)
                var s = seed

                for _ in 0..<max(1, octaves) {
                    value += valueNoise(u: u, v: v, period: period, seed: s) * amp
                    sum += amp
                    amp *= gain
                    period = max(2, Int(Double(period) * lacunarity))
                    s = mixSeed(s, 0x9E37_79B9_7F4A_7C15)
                }

                value /= max(0.000001, sum)

                // Map to sparse alpha with a soft knee.
                var a = (value - cutoff) / max(0.000001, (1.0 - cutoff))
                if a < 0 { a = 0 }
                if a > 1 { a = 1 }

                a = pow(a, power)
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

    private static func valueNoise(u: Double, v: Double, period: Int, seed: UInt64) -> Double {
        // Periodic lattice in [0, period), sampled over a torus.
        let x = u * Double(period)
        let y = v * Double(period)

        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1

        let tx = x - Double(x0)
        let ty = y - Double(y0)

        let sx = smoothstep(tx)
        let sy = smoothstep(ty)

        let v00 = lattice(x: x0, y: y0, period: period, seed: seed)
        let v10 = lattice(x: x1, y: y0, period: period, seed: seed)
        let v01 = lattice(x: x0, y: y1, period: period, seed: seed)
        let v11 = lattice(x: x1, y: y1, period: period, seed: seed)

        let a = lerp(v00, v10, sx)
        let b = lerp(v01, v11, sx)
        return lerp(a, b, sy)
    }

    private static func lattice(x: Int, y: Int, period: Int, seed: UInt64) -> Double {
        let p = max(1, period)
        let xi = positiveMod(x, p)
        let yi = positiveMod(y, p)

        // 2D hash -> [0, 1).
        let key = (UInt64(UInt32(xi)) << 32) | UInt64(UInt32(yi))
        let h = mixSeed(seed, key)
        return toUnit01(h)
    }

    private static func positiveMod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return (r < 0) ? (r + m) : r
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = max(0.0, min(1.0, t))
        return x * x * (3.0 - 2.0 * x)
    }

    // MARK: - Hashing

    private static func mixSeed(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var x = a &+ 0x9E37_79B9_7F4A_7C15
        x ^= b &+ 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    private static func toUnit01(_ x: UInt64) -> Double {
        // Use top 53 bits to build a Double in [0, 1).
        let y = x >> 11
        return Double(y) * (1.0 / 9007199254740992.0)
    }
}
