//
//  AppGroupDarwinNotifications.swift
//  WidgetWeaver
//
//  Created by . . on 01/04/26.
//

import CoreFoundation
import Foundation

public enum AppGroupDarwinNotifications {
    public static let noiseMachineStateDidChange = "\(AppGroup.identifier).NoiseMachine.StateDidChange.v1"
}

public enum AppGroupDarwinNotificationCenter {
    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true
        )
    }
}

public final class DarwinNotificationToken: @unchecked Sendable {
    private let name: String
    private let handler: @MainActor () -> Void

    public init(name: String, handler: @MainActor @escaping () -> Void) {
        self.name = name
        self.handler = handler

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            DarwinNotificationToken.callback,
            name as CFString, // <- CFString on this SDK
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            name as CFString, // <- CFString on this SDK
            nil
        )
    }

    private static let callback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let token = Unmanaged<DarwinNotificationToken>.fromOpaque(observer).takeUnretainedValue()

        Task { @MainActor in
            token.handler()
        }
    }
}
