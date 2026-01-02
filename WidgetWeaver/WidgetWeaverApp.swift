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
        AppGroup.ensureImagesDirectoryExists()

        Task {
            await NoiseMachineController.shared.bootstrapOnLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            WidgetWeaverDeepLinkHost {
                ContentView()
            }
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
                    Task { await NoiseMachineController.shared.flushPersistence() }
                }

#if !DEBUG
                if phase == .background {
                    WidgetWeaverWidgetRefresh.kickIfNeeded()
                }
#endif
            }
        }
    }
}
