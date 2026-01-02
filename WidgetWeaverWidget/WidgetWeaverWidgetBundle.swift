//
//  WidgetWeaverWidgetBundle.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/17/25.
//

//
//  WidgetWeaverWidgetBundle.swift
//  WidgetWeaverWidgetExtension
//
//  Created by Conor Nolan on 19/11/2024.
//

import WidgetKit
import SwiftUI

@main
struct WidgetWeaverWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidgetWeaverWidget()
        WidgetWeaverNoiseMachineWidget()
        WidgetWeaverHomeScreenClockWidget()
        WidgetWeaverLockScreenWeatherWidget()
        WidgetWeaverLockScreenNextUpWidget()
        WidgetWeaverLockScreenStepsWidget()
    }
}
