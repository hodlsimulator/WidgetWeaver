//
//  ContentView+Sheets.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import SwiftUI

extension ContentView {
    enum ActiveSheet: Identifiable {
        case widgetHelp
        case pro
        case variables
        case inspector
        case remix
        case weather
        case steps
        case activity
        case reminders
        case remindersSmartStackGuide
        case importReview

        var id: Int {
            switch self {
            case .widgetHelp: return 1
            case .pro: return 2
            case .variables: return 3
            case .weather: return 4
            case .inspector: return 5
            case .remix: return 6
            case .steps: return 7
            case .activity: return 8
            case .reminders: return 10
            case .remindersSmartStackGuide: return 11
            case .importReview: return 9
            }
        }
    }

    func sheetContent(_ sheet: ActiveSheet) -> AnyView {
        switch sheet {
        case .widgetHelp:
            return AnyView(WidgetWorkflowHelpView())

        case .pro:
            return AnyView(WidgetWeaverProView(manager: proManager))

        case .variables:
            return AnyView(
                WidgetWeaverVariablesView(
                    proManager: proManager,
                    onShowPro: { activeSheet = .pro }
                )
            )

        case .inspector:
            return AnyView(
                WidgetWeaverDesignInspectorView(
                    spec: draftSpec(id: selectedSpecID),
                    initialFamily: previewFamily
                )
            )

        case .remix:
            return AnyView(
                WidgetWeaverRemixSheet(
                    variants: remixVariants,
                    family: previewFamily,
                    onApply: { spec in applyRemixVariant(spec) },
                    onAgain: { remixAgain() },
                    onClose: { activeSheet = nil }
                )
            )

        case .weather:
            return AnyView(
                NavigationStack {
                    WidgetWeaverWeatherSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .steps:
            return AnyView(
                NavigationStack {
                    WidgetWeaverStepsSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .activity:
            return AnyView(
                NavigationStack {
                    WidgetWeaverActivitySettingsView(onClose: { activeSheet = nil })
                }
            )

        case .reminders:
            return AnyView(
                NavigationStack {
                    WidgetWeaverRemindersSettingsView(onClose: { activeSheet = nil })
                }
            )

        case .remindersSmartStackGuide:
            return AnyView(
                NavigationStack {
                    WidgetWeaverRemindersSmartStackGuideView(onClose: { activeSheet = nil })
                }
            )

        case .importReview:
            return importReviewSheetAnyView()
        }
    }
}
