//
//  WidgetSpecStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public final class WidgetSpecStore {
    public static let shared = WidgetSpecStore()

    private let defaults: UserDefaults
    private let key = "widgetweaver.spec.v1.default"

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    public func load() -> WidgetSpec {
        guard let data = defaults.data(forKey: key) else {
            return WidgetSpec.defaultSpec()
        }

        do {
            let spec = try JSONDecoder().decode(WidgetSpec.self, from: data)
            return spec.normalised()
        } catch {
            return WidgetSpec.defaultSpec()
        }
    }

    public func save(_ spec: WidgetSpec) {
        let normalised = spec.normalised()
        do {
            let data = try JSONEncoder().encode(normalised)
            defaults.set(data, forKey: key)
        } catch {
            // Intentionally ignored
        }
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
