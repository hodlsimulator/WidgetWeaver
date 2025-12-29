//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import Foundation

/// Widget-facing wrapper.
///
/// Home Screen widgets commonly ignore `TimelineView(.periodic)` schedules.
/// This wrapper uses the CoreAnimation-backed continuous sweep clock, which
/// does not require timeline entries per second.
struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// The active timeline entry date (used as a deterministic render anchor).
    let date: Date

    /// Kept for API compatibility with the widget entry, but not required for the continuous sweep approach.
    let anchorDate: Date

    /// Kept for API compatibility with the widget entry, but not required for the continuous sweep approach.
    let tickSeconds: TimeInterval

    var body: some View {
        WidgetWeaverClockLiveView(
            palette: palette,
            startDate: date
        )
    }
}
