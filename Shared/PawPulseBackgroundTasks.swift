//
//  PawPulseBackgroundTasks.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
@preconcurrency import BackgroundTasks

public enum PawPulseBackgroundTasks {
    public static let refreshTaskIdentifier: String = "com.conornolan.widgetweaver.pawpulse.refresh"

    public static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
    }

    public static func scheduleNextEarliest(minutesFromNow: Int = 30) {
        guard PawPulseSettingsStore.resolvedBaseURL() != nil else { return }

        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(max(15, minutesFromNow)) * 60.0)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Intentionally ignored. iOS can reject requests and will manage execution timing.
        }
    }

    private static func handle(_ bgTask: BGAppRefreshTask) {
        scheduleNextEarliest(minutesFromNow: 30)

        let completer = BGTaskCompleter(bgTask)

        let work = Task(priority: .utility) {
            defer {
                completer.complete(success: !Task.isCancelled)
            }
            _ = await PawPulseEngine.shared.updateIfNeeded(force: false)
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
