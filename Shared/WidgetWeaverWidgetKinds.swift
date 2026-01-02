//
//  WidgetWeaverWidgetKinds.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public enum WidgetWeaverWidgetKinds {
    public static let main = "WidgetWeaverWidget"
    public static let lockScreenWeather = "WidgetWeaverLockScreenWeatherWidget"
    public static let lockScreenNextUp = "WidgetWeaverLockScreenNextUpWidget"
    public static let lockScreenSteps = "WidgetWeaverLockScreenStepsWidget"
    public static let homeScreenSteps = "WidgetWeaverHomeScreenStepsWidget"

    // Bump to flush archived WidgetKit snapshots while iterating.
    public static let homeScreenClock = "WidgetWeaverHomeScreenClockWidgetV101"
}
