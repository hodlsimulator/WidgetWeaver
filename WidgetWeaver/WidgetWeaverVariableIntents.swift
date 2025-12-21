//
//  WidgetWeaverVariableIntents.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//
//  Variables + Shortcuts (Milestone 6)
//  Milestone 8: Variables are Pro-only.
//

import AppIntents
import Foundation
import WidgetKit

struct WidgetWeaverSetVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Set WidgetWeaver Variable" }
    static var description: IntentDescription {
        IntentDescription(
            "Sets a variable used by WidgetWeaver designs.\nReference variables in text using {{key}} or {{key|fallback}}.\nFilters are supported: {{key|fallback|upper}}, {{amount|0|number:0}}, {{last_done|Never|relative}}."
        )
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: streak (used as {{streak}})")
    var key: String

    @Parameter(title: "Value")
    var value: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$key) to \(\.$value)")
    }

    init() {}

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else {
            return .result(dialog: "Key was empty.")
        }

        WidgetWeaverVariableStore.shared.setValue(value, for: canonical)
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Set \(canonical) to \(value).")
    }
}

struct WidgetWeaverGetVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Get WidgetWeaver Variable" }
    static var description: IntentDescription { IntentDescription("Gets a WidgetWeaver variable value.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: streak (used as {{streak}})")
    var key: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$key)")
    }

    init() {}

    init(key: String) {
        self.key = key
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(value: "", dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else {
            return .result(value: "", dialog: "Key was empty.")
        }

        let value = WidgetWeaverVariableStore.shared.value(for: canonical) ?? ""
        return .result(value: value, dialog: "Value for \(canonical): \(value)")
    }
}

struct WidgetWeaverRemoveVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Remove WidgetWeaver Variable" }
    static var description: IntentDescription { IntentDescription("Removes a WidgetWeaver variable.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: streak (used as {{streak}})")
    var key: String

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$key)")
    }

    init() {}

    init(key: String) {
        self.key = key
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else {
            return .result(dialog: "Key was empty.")
        }

        WidgetWeaverVariableStore.shared.removeValue(for: canonical)
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Removed \(canonical).")
    }
}

struct WidgetWeaverIncrementVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Increment WidgetWeaver Variable" }
    static var description: IntentDescription {
        IntentDescription("Treats the variable as an integer, increments it, and saves the new value.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: counter (used as {{counter}})")
    var key: String

    @Parameter(title: "Amount", default: 1)
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Increment \(\.$key) by \(\.$amount)")
    }

    init() {}

    init(key: String, amount: Int) {
        self.key = key
        self.amount = amount
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(value: "0", dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else {
            return .result(value: "0", dialog: "Key was empty.")
        }

        let store = WidgetWeaverVariableStore.shared
        let existingRaw = store.value(for: canonical) ?? "0"
        let existing = Int(existingRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let newValue = existing + amount

        store.setValue(String(newValue), for: canonical)
        WidgetCenter.shared.reloadAllTimelines()

        return .result(value: String(newValue), dialog: "Updated \(canonical) to \(newValue).")
    }
}

// MARK: - Set variable to Now (pairs with |relative and |date:...)

enum WidgetWeaverNowValueFormat: String, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Now Value Format")
    }

    static var caseDisplayRepresentations: [WidgetWeaverNowValueFormat: DisplayRepresentation] {
        [
            .iso8601: DisplayRepresentation(title: "ISO8601 (UTC)"),
            .unixSeconds: DisplayRepresentation(title: "Unix seconds"),
            .dateOnly: DisplayRepresentation(title: "Date (yyyy-MM-dd)"),
            .timeOnly: DisplayRepresentation(title: "Time (HH:mm)"),
        ]
    }

    case iso8601
    case unixSeconds
    case dateOnly
    case timeOnly
}

struct WidgetWeaverSetVariableToNowIntent: AppIntent {
    static var title: LocalizedStringResource { "Set WidgetWeaver Variable to Now" }
    static var description: IntentDescription {
        IntentDescription(
            "Sets a variable to the current date/time.\nBest paired with {{key|fallback|relative}} or {{key|fallback|date:FORMAT}}."
        )
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: last_done (used as {{last_done|Never|relative}})")
    var key: String

    @Parameter(title: "Format", default: .iso8601)
    var format: WidgetWeaverNowValueFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$key) to Now (\(\.$format))")
    }

    init() {}

    init(key: String, format: WidgetWeaverNowValueFormat) {
        self.key = key
        self.format = format
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(value: "", dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else {
            return .result(value: "", dialog: "Key was empty.")
        }

        let now = Date()
        let value: String = {
            switch format {
            case .iso8601:
                return WidgetWeaverVariableTemplate.iso8601String(now)

            case .unixSeconds:
                return String(Int64(now.timeIntervalSince1970))

            case .dateOnly:
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = Calendar.autoupdatingCurrent.timeZone
                df.dateFormat = "yyyy-MM-dd"
                return df.string(from: now)

            case .timeOnly:
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = Calendar.autoupdatingCurrent.timeZone
                df.dateFormat = "HH:mm"
                return df.string(from: now)
            }
        }()

        WidgetWeaverVariableStore.shared.setValue(value, for: canonical)
        WidgetCenter.shared.reloadAllTimelines()

        return .result(value: value, dialog: "Set \(canonical) to \(value).")
    }
}
