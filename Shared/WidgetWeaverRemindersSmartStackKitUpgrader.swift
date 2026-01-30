//
//  WidgetWeaverRemindersSmartStackKitUpgrader.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import Foundation

public enum WidgetWeaverRemindersSmartStackKitUpgrader {

    public enum Slot: String, CaseIterable, Hashable, Identifiable, Sendable {
        case today
        case overdue
        case upcoming
        case highPriority
        case anytime
        case lists

        public var id: String { rawValue }

        public var mode: WidgetWeaverRemindersMode {
            switch self {
            case .today: return .today
            case .overdue: return .overdue
            case .upcoming: return .soon
            case .highPriority: return .flagged
            case .anytime: return .focus
            case .lists: return .list
            }
        }

        public var sortIndex: Int {
            switch self {
            case .today: return 1
            case .overdue: return 2
            case .upcoming: return 3
            case .highPriority: return 4
            case .anytime: return 5
            case .lists: return 6
            }
        }

        public var v1DefaultDesignName: String {
            switch self {
            case .today: return "Reminders 1 — Today"
            case .overdue: return "Reminders 2 — Overdue"
            case .upcoming: return "Reminders 3 — Soon"
            case .highPriority: return "Reminders 4 — Priority"
            case .anytime: return "Reminders 5 — Focus"
            case .lists: return "Reminders 6 — Lists"
            }
        }

        public var v2DefaultDesignName: String {
            switch self {
            case .today: return "Reminders 1 — Today"
            case .overdue: return "Reminders 2 — Overdue"
            case .upcoming: return "Reminders 3 — Upcoming"
            case .highPriority: return "Reminders 4 — High priority"
            case .anytime: return "Reminders 5 — Anytime"
            case .lists: return "Reminders 6 — Lists"
            }
        }
    }

    public struct Result: Hashable {
        public var spec: WidgetSpec
        public var didChange: Bool

        public init(spec: WidgetSpec, didChange: Bool) {
            self.spec = spec
            self.didChange = didChange
        }
    }

    /// Upgrades an existing Smart Stack kit design from v1 to v2 in a deterministic, idempotent way.
    ///
    /// Behaviour:
    /// - Only Reminders template specs are eligible.
    /// - Only specs whose Reminders mode matches the provided slot are eligible.
    /// - The default v1 kit design name is renamed to the v2 kit design name.
    /// - Custom design names are preserved.
    /// - The spec's `updatedAt` timestamp is preserved to avoid unintended library reordering.
    public static func upgradeV1ToV2IfNeeded(spec: WidgetSpec, slot: Slot) -> Result {
        guard spec.layout.template == .reminders else {
            return Result(spec: spec, didChange: false)
        }
        guard var config = spec.remindersConfig else {
            return Result(spec: spec, didChange: false)
        }
        guard config.mode == slot.mode else {
            return Result(spec: spec, didChange: false)
        }

        var out = spec
        var changed = false

        if config.smartStackKitVersion < 2 {
            config.smartStackKitVersion = 2
            changed = true
        }

        if out.name == slot.v1DefaultDesignName {
            out.name = slot.v2DefaultDesignName
            changed = true
        }

        out.remindersConfig = config
        return Result(spec: out, didChange: changed)
    }
}
