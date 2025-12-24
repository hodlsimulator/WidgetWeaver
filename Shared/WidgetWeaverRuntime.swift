//
//  WidgetWeaverRuntime.swift
//  WidgetWeaver
//
//  Created by . . on 12/24/25.
//

import Foundation

public enum WidgetWeaverRuntime {
    public static var isRunningInAppExtension: Bool {
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".appex") { return true }
        if path.contains(".appex/") { return true }
        return false
    }
}
