//
//  WidgetWeaverRemixEngine+Context.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Remix Context

    struct RemixContext {
        let base: WidgetSpec

        let baseTemplate: LayoutTemplateToken
        let baseAccent: AccentToken

        let hasImage: Bool
        let hasSymbol: Bool
        let hasSecondaryText: Bool

        let isWeatherTemplate: Bool
        let isNextUpTemplate: Bool

        init(base: WidgetSpec) {
            self.base = base
            self.baseTemplate = base.layout.template
            self.baseAccent = base.style.accent

            self.hasImage = base.image != nil
            self.hasSymbol = base.symbol != nil
            self.hasSecondaryText = (base.secondaryText != nil) && !(base.secondaryText?.isEmpty ?? true)

            self.isWeatherTemplate = base.layout.template == .weather
            self.isNextUpTemplate = base.layout.template == .nextUpCalendar
        }

        var isSpecialTemplate: Bool {
            isWeatherTemplate || isNextUpTemplate
        }

        var allowedTemplates: [LayoutTemplateToken] {
            if isWeatherTemplate { return [.weather] }
            if isNextUpTemplate { return [.nextUpCalendar] }

            // Keep remix within the "content templates". Weather/NextUp can be selected explicitly elsewhere.
            if hasImage {
                return [.poster, .classic, .hero]
            }
            return [.classic, .hero, .poster]
        }

        func nearAccents() -> [AccentToken] {
            switch baseAccent {
            case .blue:
                return [.blue, .teal, .indigo, .purple]
            case .teal:
                return [.teal, .blue, .green, .indigo]
            case .green:
                return [.green, .teal, .yellow, .blue]
            case .orange:
                return [.orange, .yellow, .red, .pink]
            case .pink:
                return [.pink, .purple, .red, .orange]
            case .purple:
                return [.purple, .indigo, .pink, .blue]
            case .red:
                return [.red, .orange, .pink, .yellow]
            case .yellow:
                return [.yellow, .orange, .green]
            case .gray:
                return [.gray, .indigo, .blue]
            case .indigo:
                return [.indigo, .blue, .purple, .teal]
            }
        }
    }
}
