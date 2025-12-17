//
//  WidgetSpecStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public final class WidgetSpecStore: @unchecked Sendable {
    public static let shared = WidgetSpecStore()

    private let defaults: UserDefaults

    // v1 multi-spec storage
    private let specsKey = "widgetweaver.specs.v1"
    private let defaultIDKey = "widgetweaver.specs.v1.default_id"

    // Legacy (v0.9.x) single-spec storage
    private let legacySingleSpecKey = "widgetweaver.spec.v1.default"

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        migrateLegacySingleSpecIfNeeded()
        seedIfNeeded()
    }

    // MARK: - Compatibility (v0.9.x API)

    /// Legacy API: returns the current default spec.
    public func load() -> WidgetSpec {
        loadDefault()
    }

    /// Legacy API: saves without changing default.
    public func save(_ spec: WidgetSpec) {
        save(spec, makeDefault: false)
    }

    /// Legacy API: clears storage (keeps at least one seeded spec afterwards).
    public func clear() {
        defaults.removeObject(forKey: specsKey)
        defaults.removeObject(forKey: defaultIDKey)
        defaults.removeObject(forKey: legacySingleSpecKey)
        seedIfNeeded()
    }

    // MARK: - Multi-spec API

    public func loadAll() -> [WidgetSpec] {
        loadAllInternal()
    }

    public func load(id: UUID) -> WidgetSpec? {
        loadAllInternal().first(where: { $0.id == id })?.normalised()
    }

    public func defaultSpecID() -> UUID? {
        guard let raw = defaults.string(forKey: defaultIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public func setDefault(id: UUID) {
        defaults.set(id.uuidString, forKey: defaultIDKey)
    }

    public func loadDefault() -> WidgetSpec {
        let specs = loadAllInternal()

        if let id = defaultSpecID(), let match = specs.first(where: { $0.id == id }) {
            return match.normalised()
        }

        if let first = specs.first {
            return first.normalised()
        }

        return WidgetSpec.defaultSpec().normalised()
    }

    public func save(_ spec: WidgetSpec, makeDefault: Bool) {
        var specs = loadAllInternal()
        let normalised = spec.normalised()

        if let idx = specs.firstIndex(where: { $0.id == normalised.id }) {
            specs[idx] = normalised
        } else {
            specs.append(normalised)
        }

        saveAllInternal(specs)

        if makeDefault || defaultSpecID() == nil {
            setDefault(id: normalised.id)
        }
    }

    public func delete(id: UUID) {
        var specs = loadAllInternal()
        specs.removeAll { $0.id == id }

        if specs.isEmpty {
            let seeded = WidgetSpec.defaultSpec().normalised()
            saveAllInternal([seeded])
            setDefault(id: seeded.id)
            return
        }

        saveAllInternal(specs)

        if defaultSpecID() == id {
            setDefault(id: specs[0].id)
        }
    }

    // MARK: - Internals

    private func loadAllInternal() -> [WidgetSpec] {
        guard let data = defaults.data(forKey: specsKey) else { return [] }
        do {
            let specs = try JSONDecoder().decode([WidgetSpec].self, from: data)
            return specs.map { $0.normalised() }
        } catch {
            return []
        }
    }

    private func saveAllInternal(_ specs: [WidgetSpec]) {
        do {
            let data = try JSONEncoder().encode(specs.map { $0.normalised() })
            defaults.set(data, forKey: specsKey)
        } catch {
            // Intentionally ignored
        }
    }

    private func migrateLegacySingleSpecIfNeeded() {
        guard defaults.data(forKey: specsKey) == nil else { return }
        guard let legacyData = defaults.data(forKey: legacySingleSpecKey) else { return }

        defer {
            defaults.removeObject(forKey: legacySingleSpecKey)
        }

        do {
            let legacySpec = try JSONDecoder().decode(WidgetSpec.self, from: legacyData).normalised()
            saveAllInternal([legacySpec])
            setDefault(id: legacySpec.id)
        } catch {
            // Intentionally ignored
        }
    }

    private func seedIfNeeded() {
        let specs = loadAllInternal()

        if specs.isEmpty {
            let seeded = WidgetSpec.defaultSpec().normalised()
            saveAllInternal([seeded])
            setDefault(id: seeded.id)
            return
        }

        if defaultSpecID() == nil, let first = specs.first {
            setDefault(id: first.id)
        }
    }
}
