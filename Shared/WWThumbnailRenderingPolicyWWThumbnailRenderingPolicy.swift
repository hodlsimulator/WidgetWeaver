//
//  WWThumbnailRenderingPolicyWWThumbnailRenderingPolicy.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//

import SwiftUI

private struct WWThumbnailRenderingEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var wwThumbnailRenderingEnabled: Bool {
        get { self[WWThumbnailRenderingEnabledKey.self] }
        set { self[WWThumbnailRenderingEnabledKey.self] = newValue }
    }
}
