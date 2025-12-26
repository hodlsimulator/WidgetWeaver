//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Deterministic anchor provided by WidgetKit (timeline entry date).
    /// Used as a fallback base for pre-rendering; the live driver re-syncs on-screen.
    let anchorDate: Date

    var body: some View {
        WidgetWeaverClockLiveView(palette: palette, startDate: anchorDate)
    }
}
