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
    var body: some Widget {
        WidgetWeaverWidget()
        WidgetWeaverHomeScreenClockWidget()
        WidgetWeaverHomeScreenStepsWidget()
        WidgetWeaverHomeScreenActivityWidget()
        WidgetWeaverLockScreenWeatherWidget()
        WidgetWeaverLockScreenStepsWidget()
        WidgetWeaverLockScreenActivityWidget()
        WidgetWeaverPawPulseLatestCatWidget()
        WidgetWeaverNoiseMachineWidget()
    }
}
