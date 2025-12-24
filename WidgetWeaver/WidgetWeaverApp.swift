//
//  WidgetWeaverApp.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit

@main
struct WidgetWeaverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color("AccentColor"))
                .task {
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenClock)
                }
        }
    }
}
