//
//  WidgetWeaverWidgetKinds.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

//
//  WidgetWeaverWidgetKinds.swift
//  WidgetWeaver
//
//  Created by Conor Nolan on 20/11/2024.
//

public enum WidgetWeaverWidgetKinds {
    public static let main = "WidgetWeaverWidget"
    public static let lockScreenWeather = "WidgetWeaverLockScreenWeatherWidget"
    public static let lockScreenNextUp = "WidgetWeaverLockScreenNextUpWidget"
    public static let lockScreenSteps = "WidgetWeaverLockScreenStepsWidget"
    
    // V110: because this widget kind had an archived snapshot that
    // was crashing and blocking all widget gallery rendering.
    public static let homeScreenClock = "WidgetWeaverHomeScreenClockWidgetV110"
    
    public static let noiseMachine = "WidgetWeaverNoiseMachineWidget"
}
