//
//  WidgetSpec+Utilities.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}

extension Double {
    func normalised() -> Double {
        isFinite ? self : 0
    }
}

// MARK: - Variables (App Group)
//
// Variable references inside text fields:
//
// - "{{key}}" -> replaced with the current value for "key"
// - "{{key|fallback}}" -> fallback used when key is missing/empty
//
// Keys are canonicalised as:
// - trimmed
// - lowercased
// - internal whitespace collapsed to single spaces

public final class WidgetWeaverVariableStore: @unchecked Sendable {
    public static let shared = WidgetWeaverVariableStore()

    private let defaults: UserDefaults
    private let variablesKey = "widgetweaver.variables.v1"

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    public func loadAll() -> [String: String] {
        guard WidgetWeaverEntitlements.isProUnlocked else { return [:] }
        return loadAllInternal()
    }

    public func value(for rawKey: String) -> String? {
        guard WidgetWeaverEntitlements.isProUnlocked else { return nil }

        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return nil }

        let vars = loadAllInternal()
        return vars[key]
    }

    public func setValue(_ value: String, for rawKey: String) {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }

        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return }

        var vars = loadAllInternal()
        vars[key] = value
        saveAllInternal(vars)
        flushAndNotifyWidgets()
    }

    public func removeValue(for rawKey: String) {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }

        let key = Self.canonicalKey(rawKey)
        guard !key.isEmpty else { return }

        var vars = loadAllInternal()
        vars.removeValue(forKey: key)
        saveAllInternal(vars)
        flushAndNotifyWidgets()
    }

    public func clearAll() {
        guard WidgetWeaverEntitlements.isProUnlocked else { return }
        defaults.removeObject(forKey: variablesKey)
        flushAndNotifyWidgets()
    }

    public static func canonicalKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var out = ""
        out.reserveCapacity(min(trimmed.count, 64))

        var lastWasSpace = false
        for ch in trimmed.lowercased() {
            if ch.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }

            if out.count >= 64 { break }
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadAllInternal() -> [String: String] {
        guard let data = defaults.data(forKey: variablesKey) else { return [:] }
        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            return decoded
        } catch {
            return [:]
        }
    }

    private func saveAllInternal(_ vars: [String: String]) {
        do {
            let data = try JSONEncoder().encode(vars)
            defaults.set(data, forKey: variablesKey)
        } catch {
            // Intentionally ignored.
        }
    }

    private func flushAndNotifyWidgets() {
        defaults.synchronize()

        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }
}

// MARK: - Variable template rendering

public enum WidgetWeaverVariableTemplate {
    public static func render(_ template: String, variables: [String: String]) -> String {
        guard template.contains("{{") else { return template }

        var cursor = template.startIndex
        let end = template.endIndex
        var out = ""

        while cursor < end {
            guard let open = template.range(of: "{{", range: cursor..<end) else {
                out.append(contentsOf: template[cursor..<end])
                break
            }

            if open.lowerBound > cursor {
                out.append(contentsOf: template[cursor..<open.lowerBound])
            }

            let afterOpen = open.upperBound
            guard let close = template.range(of: "}}", range: afterOpen..<end) else {
                out.append(contentsOf: template[open.lowerBound..<end])
                break
            }

            let token = template[afterOpen..<close.lowerBound]
            out.append(resolveToken(token, variables: variables))

            cursor = close.upperBound
        }

        return out
    }

    private static func resolveToken(_ token: Substring, variables: [String: String]) -> String {
        let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let rawKey = parts.first.map(String.init) ?? ""
        let fallback = parts.count > 1 ? String(parts[1]) : ""

        let key = WidgetWeaverVariableStore.canonicalKey(rawKey)
        guard !key.isEmpty else { return fallback }

        if let value = variables[key], !value.isEmpty {
            return value
        }
        return fallback
    }
}

// MARK: - Apply variables to a spec at render time

public extension WidgetSpec {
    func resolvingVariables(using store: WidgetWeaverVariableStore = .shared) -> WidgetSpec {
        let vars = WidgetWeaverEntitlements.isProUnlocked ? store.loadAll() : [:]
        return resolvingVariables(using: vars)
    }

    func resolvingVariables(using variables: [String: String]) -> WidgetSpec {
        var s = self

        s.name = WidgetWeaverVariableTemplate.render(s.name, variables: variables)
        s.primaryText = WidgetWeaverVariableTemplate.render(s.primaryText, variables: variables)

        if let secondary = s.secondaryText {
            let rendered = WidgetWeaverVariableTemplate.render(secondary, variables: variables)
            let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            s.secondaryText = trimmed.isEmpty ? nil : rendered
        }

        if let matched = s.matchedSet {
            var m = matched

            if var v = m.small {
                v.primaryText = WidgetWeaverVariableTemplate.render(v.primaryText, variables: variables)
                if let sec = v.secondaryText {
                    let rendered = WidgetWeaverVariableTemplate.render(sec, variables: variables)
                    let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
                    v.secondaryText = trimmed.isEmpty ? nil : rendered
                }
                m.small = v
            }

            if var v = m.medium {
                v.primaryText = WidgetWeaverVariableTemplate.render(v.primaryText, variables: variables)
                if let sec = v.secondaryText {
                    let rendered = WidgetWeaverVariableTemplate.render(sec, variables: variables)
                    let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
                    v.secondaryText = trimmed.isEmpty ? nil : rendered
                }
                m.medium = v
            }

            if var v = m.large {
                v.primaryText = WidgetWeaverVariableTemplate.render(v.primaryText, variables: variables)
                if let sec = v.secondaryText {
                    let rendered = WidgetWeaverVariableTemplate.render(sec, variables: variables)
                    let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
                    v.secondaryText = trimmed.isEmpty ? nil : rendered
                }
                m.large = v
            }

            s.matchedSet = m
        }

        return s.normalised()
    }
}
