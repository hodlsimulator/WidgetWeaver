//
//  WidgetWeaverClockCoreAnimationHandsOverlayView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI

/// Kept to avoid build breaks from earlier experiments.
///
/// The budget-safe ticking implementation uses `TimelineView` in pure SwiftUI, so this overlay is
/// intentionally a no-op.
struct WidgetWeaverClockCoreAnimationHandsOverlayView: View {
    let palette: WidgetWeaverClockPalette
    let date: Date
    let showSecondHand: Bool
    let scale: CGFloat

    init(
        palette: WidgetWeaverClockPalette,
        date: Date,
        showSecondHand: Bool,
        scale: CGFloat = 1.0
    ) {
        self.palette = palette
        self.date = date
        self.showSecondHand = showSecondHand
        self.scale = scale
    }

    var body: some View {
        EmptyView()
    }
}
