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
                    #if !DEBUG
                    await MainActor.run {
                        WidgetWeaverWidgetRefresh.forceKick()
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        #if !DEBUG
                        WidgetWeaverWidgetRefresh.kickIfNeeded()
                        #endif
                    }
                }
        }
    }
}
