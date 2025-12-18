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

struct WidgetWeaverSetVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Set WidgetWeaver Variable" }
    static var description: IntentDescription {
        IntentDescription("Sets a variable used by WidgetWeaver designs.\nReference variables in text using {{key}} or {{key|fallback}}.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: streak (used as {{streak}})")
    var key: String

    @Parameter(title: "Value")
    var value: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$key) to \(\.$value)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result(dialog: "Key was empty.") }

        WidgetWeaverVariableStore.shared.setValue(value, for: canonical)
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

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(value: "", dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result(value: "", dialog: "Key was empty.") }

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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result(dialog: "Key was empty.") }

        WidgetWeaverVariableStore.shared.removeValue(for: canonical)
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

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard WidgetWeaverEntitlements.isProUnlocked else {
            return .result(value: "0", dialog: "WidgetWeaver Pro is required for variables.")
        }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result(value: "0", dialog: "Key was empty.") }

        let store = WidgetWeaverVariableStore.shared
        let existingRaw = store.value(for: canonical) ?? "0"
        let existing = Int(existingRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let newValue = existing + amount

        store.setValue(String(newValue), for: canonical)
        return .result(value: String(newValue), dialog: "Updated \(canonical) to \(newValue).")
    }
}
