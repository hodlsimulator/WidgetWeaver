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
    
    init() {
        AppGroup.ensureExistence()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color("AccentColor"))
                .task {
                    await NoiseMachineController.shared.bootstrapOnLaunch()

                    #if !DEBUG
                    await MainActor.run {
                        WidgetWeaverWidgetRefresh.forceKickWidgetCacheWarmUp()
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await NoiseMachineController.shared.flushPersistence() }
                    }

                    #if !DEBUG
                    if phase == .background {
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            await MainActor.run {
                                WidgetWeaverWidgetRefresh.forceKickWidgetsFromBackground()
                            }
                        }
                    }
                    #endif
                }
        }
    }
}
