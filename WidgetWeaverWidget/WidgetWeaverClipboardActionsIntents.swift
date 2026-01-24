//
//  WidgetWeaverClipboardActionsIntents.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

#if CLIPBOARD_ACTIONS
import AppIntents
import Foundation

struct WidgetWeaverClipboardClearInboxIntent: AppIntent {
    static var title: LocalizedStringResource { "Clear Action Inbox" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetWeaverClipboardInboxStore.clearAll()
        WidgetWeaverClipboardInboxStore.setLastAction(kind: "clear", message: "Inbox cleared.")
        return .result()
    }
}
#endif
