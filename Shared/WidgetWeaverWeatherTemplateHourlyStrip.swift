//
//  WidgetWeaverWeatherTemplateHourlyStrip.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Modularised out of WidgetWeaverWeatherTemplateComponents.swift
//

import Foundation
import SwiftUI

struct WeatherHourlyRainStrip: View {
    let points: [WidgetWeaverWeatherHourlyPoint]
    let unit: UnitTemperature
    let accent: Color
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(points.prefix(8)) { p in
                VStack(spacing: 4) {
                    Text(wwHourString(p.date))
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(precipText(p.precipitationChance01))
                        .font(.system(size: fontSize + 1, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(wwTempString(p.temperatureC, unit: unit))
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            WeatherGlassBackground(cornerRadius: 14)
        }
    }

    private func precipText(_ chance01: Double?) -> String {
        guard let chance01 else { return "—" }
        let pct = Int((chance01 * 100).rounded())
        return "\(pct)%"
    }
}
