//
//  WidgetActionDraft+Defaults.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

extension WidgetActionDraft {
    static func defaultIncrement() -> WidgetActionDraft {
        WidgetActionDraft(
            title: "+1",
            systemImage: "plus.circle.fill",
            kind: .incrementVariable,
            variableKey: "count",
            incrementAmount: 1,
            nowFormat: .iso8601
        )
    }

    static func defaultDone() -> WidgetActionDraft {
        WidgetActionDraft(
            title: "Done",
            systemImage: "checkmark.circle.fill",
            kind: .incrementVariable,
            variableKey: "done",
            incrementAmount: 1,
            nowFormat: .iso8601
        )
    }
}
