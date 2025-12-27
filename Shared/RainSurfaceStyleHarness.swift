//
//  RainSurfaceStyleHarness.swift
//  WidgetWeaver
//
//  Created by . . on 12/26/25.
//

import SwiftUI

struct RainSurfaceStyleHarness: View {
    var body: some View {
        let intensities: [Double] = [
            0, 0, 0.1, 0.6, 1.2, 1.5, 1.2, 0.9, 0.7, 0.3, 0.1, 0, 0, 0.2, 0.8, 0.4, 0, 0
        ]
        let certainties: [Double] = intensities.map { $0 <= 0.0001 ? 0.15 : 0.85 }

        var cfg = RainForecastSurfaceConfiguration()
        cfg.noiseSeed = 12345

        cfg.coreTopMix = 0.0
        cfg.glossEnabled = false
        cfg.glintEnabled = false

        cfg.fuzzEnabled = true
        cfg.fuzzChanceThreshold = 0.60
        cfg.fuzzChanceTransition = 0.24
        cfg.fuzzChanceFloor = 0.22
        cfg.fuzzMaxOpacity = 0.34
        cfg.fuzzWidthFraction = 0.22
        cfg.fuzzErodeStrength = 0.95

        return VStack(spacing: 16) {
            RainForecastSurfaceView(intensities: intensities, certainties: certainties, configuration: cfg)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding()
        }
        .background(Color.black)
    }
}
