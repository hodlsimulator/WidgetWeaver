//
//  WidgetWeaverApp.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI

@main
struct WidgetWeaverApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color("AccentColor"))
                .task {
                    await MainActor.run {
                        WidgetWeaverWidgetRefresh.forceKick()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        WidgetWeaverWidgetRefresh.kickIfNeeded()
                    }
                }
        }
    }
}
