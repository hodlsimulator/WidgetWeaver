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

/// Registers a Darwin notification observer and automatically unregisters on deinit.
///
/// This intentionally registers with `name: nil` to avoid SDK overlay type mismatches
/// (CFString vs CFNotificationName) and filters in the callback instead.
public final class DarwinNotificationToken: @unchecked Sendable {
    private let expectedName: CFNotificationName
    private let handler: @MainActor () -> Void

    public init(name: String, handler: @MainActor @escaping () -> Void) {
        self.expectedName = CFNotificationName(rawValue: name as CFString)
        self.handler = handler

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            DarwinNotificationToken.callback,
            nil,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }

    private static let callback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer else { return }
        guard let name else { return }

        let token = Unmanaged<DarwinNotificationToken>.fromOpaque(observer).takeUnretainedValue()
        guard name == token.expectedName else { return }

        Task { @MainActor in
            token.handler()
        }
    }
}
