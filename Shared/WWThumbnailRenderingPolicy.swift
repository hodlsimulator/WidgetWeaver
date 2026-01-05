//
//  WWThumbnailRenderingPolicy.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//

import SwiftUI

private struct WWThumbnailRenderingEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

// When true, views should avoid expensive rendering paths.
// Intended for WidgetKit placeholder / preview rendering where budgets are tight.
private struct WWLowGraphicsBudgetKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var wwThumbnailRenderingEnabled: Bool {
        get { self[WWThumbnailRenderingEnabledKey.self] }
        set { self[WWThumbnailRenderingEnabledKey.self] = newValue }
    }

    var wwLowGraphicsBudget: Bool {
        get { self[WWLowGraphicsBudgetKey.self] }
        set { self[WWLowGraphicsBudgetKey.self] = newValue }
    }
}
