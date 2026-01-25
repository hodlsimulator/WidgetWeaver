//
//  WidgetWeaverApp.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import UIKit
import Foundation
@preconcurrency import BackgroundTasks

@MainActor
final class WidgetWeaverAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        WidgetWeaverInterfaceOrientationLock.currentMask
    }
}

@main
struct WidgetWeaverApp: App {
    @UIApplicationDelegateAdaptor(WidgetWeaverAppDelegate.self)
    private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppGroup.ensureImagesDirectoryExists()

        FeatureFlags.seedPosterSuiteOnForAquariumTestFlightIfNeeded()

        if WidgetWeaverFeatureFlags.pawPulseEnabled {
            PawPulseCache.ensureDirectoryExists()
        }

        PawPulseBackgroundTasks.register()
        if WidgetWeaverFeatureFlags.pawPulseEnabled {
            PawPulseBackgroundTasks.scheduleNextEarliest(minutesFromNow: 30)
        }

        WidgetWeaverWeatherBackgroundRefresh.register()
        WidgetWeaverWeatherBackgroundRefresh.scheduleNextEarliest(minutesFromNow: 30)
        WidgetWeaverWeatherBackgroundRefresh.kickIfLocationConfigured()

        Task {
            await NoiseMachineController.shared.bootstrapOnLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            WidgetWeaverWeatherDeepLinkHost {
                WidgetWeaverDeepLinkHost {
                    ContentView()
                }
            }
#if DEBUG
            .modifier(WidgetWeaverUITestEnvironmentModifier())
#endif
            .tint(Color("AccentColor"))
            .task {
#if !DEBUG
                await MainActor.run {
                    WidgetWeaverWidgetRefresh.forceKick()
                }
#endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    WidgetWeaverWeatherBackgroundRefresh.scheduleNextEarliest(minutesFromNow: 30)
                    WidgetWeaverWeatherBackgroundRefresh.kickIfLocationConfigured()
                }

                if phase == .background {
                    Task { await NoiseMachineController.shared.flushPersistence() }
                    PawPulseBackgroundTasks.scheduleNextEarliest(minutesFromNow: 30)
                    WidgetWeaverWeatherBackgroundRefresh.scheduleNextEarliest(minutesFromNow: 30)
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

private enum WidgetWeaverWeatherBackgroundRefresh {
    static let refreshTaskIdentifier: String = "com.conornolan.widgetweaver.weather.refresh"

    private static let registrationToken: Bool = {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
    }()

    @discardableResult
    static func register() -> Bool {
        registrationToken
    }

    static func cancelPending() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskIdentifier)
    }

    static func scheduleNextEarliest(minutesFromNow: Int = 30) {
        guard register() else { return }

        guard WidgetWeaverWeatherStore.shared.loadLocation() != nil else {
            cancelPending()
            return
        }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(max(15, minutesFromNow)) * 60.0)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Intentionally ignored. iOS can reject requests and will manage execution timing.
        }
    }

    static func kickIfLocationConfigured() {
        Task(priority: .utility) {
            guard WidgetWeaverWeatherStore.shared.loadLocation() != nil else { return }
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
        }
    }

    private static func handle(_ bgTask: BGAppRefreshTask) {
        guard WidgetWeaverWeatherStore.shared.loadLocation() != nil else {
            bgTask.setTaskCompleted(success: true)
            return
        }

        scheduleNextEarliest(minutesFromNow: 30)

        let completer = BGTaskCompleter(bgTask)

        let work = Task(priority: .utility) {
            var success = true
            defer { completer.complete(success: success && !Task.isCancelled) }

            let result = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
            success = (result.errorDescription == nil)
        }

        bgTask.expirationHandler = {
            work.cancel()
        }
    }

    private final class BGTaskCompleter: @unchecked Sendable {
        private let bgTask: BGAppRefreshTask

        init(_ bgTask: BGAppRefreshTask) {
            self.bgTask = bgTask
        }

        func complete(success: Bool) {
            bgTask.setTaskCompleted(success: success)
        }
    }
}

#if DEBUG
private struct WidgetWeaverUITestEnvironmentModifier: ViewModifier {
    private enum LaunchKeys {
        static let dynamicType = "-widgetweaver.uiTest.dynamicType"
        static let reduceMotion = "-widgetweaver.uiTest.reduceMotion"
    }

    func body(content: Content) -> some View {
        let args = ProcessInfo.processInfo.arguments

        let dynamicTypeSize: DynamicTypeSize? = {
            guard let idx = args.firstIndex(of: LaunchKeys.dynamicType) else { return nil }
            let next = args.index(after: idx)
            guard args.indices.contains(next) else { return nil }
            return DynamicTypeSize.fromLaunchValue(args[next])
        }()

        let reduceMotion: Bool? = {
            guard let idx = args.firstIndex(of: LaunchKeys.reduceMotion) else { return nil }
            let next = args.index(after: idx)
            guard args.indices.contains(next) else { return true }
            return args[next] != "0"
        }()

        switch (dynamicTypeSize, reduceMotion) {
        case (nil, nil):
            content
        case (let d?, nil):
            content.environment(\.dynamicTypeSize, d)
        case (nil, let r?):
            content.transaction { t in
                if r { t.disablesAnimations = true }
            }
        case (let d?, let r?):
            content
                .environment(\.dynamicTypeSize, d)
                .transaction { t in
                    if r { t.disablesAnimations = true }
                }
        }
    }
}

private extension DynamicTypeSize {
    static func fromLaunchValue(_ raw: String) -> DynamicTypeSize? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "xsmall":
            return .xSmall
        case "small":
            return .small
        case "medium":
            return .medium
        case "large":
            return .large
        case "xlarge":
            return .xLarge
        case "xxlarge":
            return .xxLarge
        case "xxxlarge", "xxxl":
            return .xxxLarge
        case "accessibility1", "a1":
            return .accessibility1
        case "accessibility2", "a2":
            return .accessibility2
        case "accessibility3", "a3":
            return .accessibility3
        case "accessibility4", "a4":
            return .accessibility4
        case "accessibility5", "a5":
            return .accessibility5
        default:
            return nil
        }
    }
}
#endif
