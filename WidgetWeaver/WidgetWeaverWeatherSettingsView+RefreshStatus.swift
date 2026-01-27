//
//  WidgetWeaverWeatherSettingsView+RefreshStatus.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import Foundation
import UIKit

extension WidgetWeaverWeatherSettingsView {

    var backgroundRefreshStatusLabel: String {
        switch backgroundRefreshStatus {
        case .available:
            return "On"
        case .denied:
            return "Off"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    var autoRefreshFooterText: String {
        var lines: [String] = [
            "Weather refreshes when the app becomes active and during iOS background fetch windows."
        ]

        switch backgroundRefreshStatus {
        case .denied:
            lines.append("Background App Refresh is off. Enable it in Settings → General → Background App Refresh.")
        case .restricted:
            lines.append("Background App Refresh is restricted by device policy. Background updates may be unavailable.")
        default:
            break
        }

        if lowPowerModeEnabled {
            lines.append("Low Power Mode can delay background refresh. Consider turning it off in Settings → Battery.")
        }

        return lines.joined(separator: "\n")
    }

    func refreshSystemRefreshStatus() {
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
