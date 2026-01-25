//
//  WidgetWeaverWeatherDeepLinkHost.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import Foundation
import SwiftUI

enum WidgetWeaverWeatherDeepLink: String, Identifiable {
    case settings

    var id: String { rawValue }

    static func from(url: URL) -> WidgetWeaverWeatherDeepLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "widgetweaver" else { return nil }

        let host = (url.host ?? "").lowercased()
        let pathSegments = url.pathComponents.dropFirst().map { $0.lowercased() }
        let first = pathSegments.first ?? ""

        // Host-based variants:
        // - widgetweaver://weather
        // - widgetweaver://weather/settings
        // - widgetweaver://weather/location
        if host == "weather" || host == "weather-settings" || host == "weathersettings" || host == "weather-location" || host == "weatherlocation" {
            return .settings
        }

        // Path-based variants:
        // - widgetweaver://open/weather
        // - widgetweaver://open/weather/settings
        if host == "open" {
            if first == "weather" || first == "weather-settings" || first == "weathersettings" || first == "weather-location" || first == "weatherlocation" {
                return .settings
            }
        }

        return nil
    }
}

struct WidgetWeaverWeatherDeepLinkHost<Content: View>: View {
    @State private var activeDeepLink: WidgetWeaverWeatherDeepLink?

    let content: () -> Content

    var body: some View {
        content()
            .onOpenURL { url in
                if let deepLink = WidgetWeaverWeatherDeepLink.from(url: url) {
                    activeDeepLink = deepLink
                }
            }
            .sheet(item: $activeDeepLink) { deepLink in
                switch deepLink {
                case .settings:
                    WidgetWeaverWeatherSettingsView(onClose: { activeDeepLink = nil })
                }
            }
    }
}
