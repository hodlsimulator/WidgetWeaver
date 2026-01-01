//
//  WidgetWeaverRemixEngine+RNG.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Deterministic RNG

    struct SeededRNG {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed
        }

        mutating func nextUInt64() -> UInt64 {
            // LCG (Numerical Recipes). Simple and fine for UI variety.
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            let value = nextUInt64() % max(1, span)
            return range.lowerBound + Int(value)
        }

        mutating func bool(probability: Double) -> Bool {
            let p = max(0.0, min(1.0, probability))
            let x = Double(nextUInt64() % 10_000) / 10_000.0
            return x < p
        }

        mutating func pick<T>(from array: [T]) -> T {
            if array.isEmpty {
                fatalError("SeededRNG.pick called with empty array")
            }
            let idx = int(in: 0...(array.count - 1))
            return array[idx]
        }
    }
}
