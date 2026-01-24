//
//  WidgetWeaverWidgetVariableIntents.swift
//  WidgetWeaverWidgetExtension
//
//  Created by . . on 12/21/25.
//

import AppIntents
import Foundation
import WidgetKit

// Widget-only copies of the variable intents.
// The app target has its own intents file; the widget target needs these too for Button(intent:).

struct WidgetWeaverIncrementVariableIntent: AppIntent {
    static var title: LocalizedStringResource { "Increment WidgetWeaver Variable" }
    static var description: IntentDescription {
        IntentDescription("Treats the variable as an integer, increments it, and saves the new value.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Key", description: "Example: coffee (used as {{coffee}})")
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

    func perform() async throws -> some IntentResult {
        guard WidgetWeaverEntitlements.isProUnlocked else { return .result() }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result() }

        let store = WidgetWeaverVariableStore.shared
        let existingRaw = store.value(for: canonical) ?? "0"
        let existing = Int(existingRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let newValue = existing + amount

        store.setValue(String(newValue), for: canonical)
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

enum WidgetWeaverNowValueFormat: String, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Now Value Format")
    }

    static var caseDisplayRepresentations: [WidgetWeaverNowValueFormat: DisplayRepresentation] {
        [
            .iso8601: DisplayRepresentation(title: "ISO8601 (UTC)"),
            .unixSeconds: DisplayRepresentation(title: "Unix seconds"),
            .unixMilliseconds: DisplayRepresentation(title: "Unix milliseconds"),
            .dateOnly: DisplayRepresentation(title: "Date (yyyy-MM-dd)"),
            .timeOnly: DisplayRepresentation(title: "Time (HH:mm)"),
        ]
    }

    case iso8601
    case unixSeconds
    case unixMilliseconds
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

    func perform() async throws -> some IntentResult {
        guard WidgetWeaverEntitlements.isProUnlocked else { return .result() }

        let canonical = WidgetWeaverVariableStore.canonicalKey(key)
        guard !canonical.isEmpty else { return .result() }

        let now = Date()
        let value: String = {
            switch format {
            case .iso8601:
                return WidgetWeaverVariableTemplate.iso8601String(now)

            case .unixSeconds:
                return String(Int64(now.timeIntervalSince1970))

            case .unixMilliseconds:
                return String(Int64((now.timeIntervalSince1970 * 1000.0).rounded(.down)))

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

        return .result()
    }
}
