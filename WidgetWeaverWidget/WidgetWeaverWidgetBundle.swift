//
//  WidgetWeaverWidgetBundle.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/17/25.
//

import WidgetKit
import SwiftUI

@main
struct WidgetWeaverWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        WidgetWeaverWidget()
        WidgetWeaverHomeScreenClockWidget()
        WidgetWeaverHomeScreenStepsWidget()
        WidgetWeaverHomeScreenActivityWidget()
        WidgetWeaverLockScreenWeatherWidget()
        WidgetWeaverLockScreenStepsWidget()
        WidgetWeaverLockScreenActivityWidget()

        #if PAWPULSE
        WidgetWeaverPawPulseLatestCatWidget()
        #endif

        WidgetWeaverNoiseMachineWidget()
        WidgetWeaverClipboardActionsWidget()

        #if DEBUG
        WidgetWeaverRemindersDebugSpikeWidget()
        #endif
    }
}
