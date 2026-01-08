//
//  EditorToolFocusGating.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Coarse focus buckets used to gate tool visibility.
///
/// Gating is a last-mile filter applied after capabilities + eligibility constraints.
/// It is used to keep “sub-flow” editing predictable (e.g. Smart Photos, Clock adjustments).
enum EditorToolFocusGroup: String, CaseIterable, Hashable, Sendable {
    case widget
    case smartPhotos
    case clock
    case other
}

func editorToolFocusGroup(for focus: EditorFocusTarget) -> EditorToolFocusGroup {
    switch focus {
    case .widget:
        return .widget

    case .clock:
        return .clock

    case .albumContainer(_, let subtype) where subtype == .smart:
        return .smartPhotos

    case .albumPhoto(_, _, let subtype) where subtype == .smart:
        return .smartPhotos

    case .smartRuleEditor:
        return .smartPhotos

    case .element(let id) where id.hasPrefix("smartPhoto"):
        // Smart Photo sub-flows that model focus as a generic element target.
        return .smartPhotos

    case .element:
        return .other

    case .albumContainer:
        return .other

    case .albumPhoto:
        return .other
    }
}

func editorToolIDsApplyingFocusGate(
    eligible: [EditorToolID],
    focusGroup: EditorToolFocusGroup
) -> [EditorToolID] {
    switch focusGroup {
    case .smartPhotos:
        // Curated allowlist: keep this tight to avoid unexpected UI changes.
        let allowlist: [EditorToolID] = [
            .albumShuffle,
            .smartPhotoCrop,
            .smartPhoto,
            .image,
            .smartRules,
            .style,
        ]

        // Preserve curated ordering rather than recomputing from global tool order.
        let filtered = allowlist.filter { eligible.contains($0) }

        // Safety: avoid showing an empty tool list if IDs drift.
        if filtered.isEmpty {
            return eligible
        }

        // Safety: if none of the primary Smart Photo tools are present, do not gate.
        // This prevents an odd state (e.g. template switch) from collapsing the UI down
        // to only generic tools such as Style.
        let primarySmartPhotoTools: Set<EditorToolID> = [
            .albumShuffle,
            .smartPhotoCrop,
            .smartRules,
            .smartPhoto,
            .image,
        ]
        let containsPrimary = filtered.contains(where: { primarySmartPhotoTools.contains($0) })
        if !containsPrimary {
            return eligible
        }

        return filtered

    case .clock:
        // Clock edits should not surface unrelated media tools (Smart Photos, Albums, etc).
        //
        // This is intentionally broader than the Smart Photos allowlist: clock adjustments can be
        // made while still needing access to general widget controls.
        let allowlist: [EditorToolID] = [
            .status,
            .designs,
            .widgets,
            .layout,
            .style,
            .matchedSet,
            .variables,
            .sharing,
            .ai,
            .pro,
        ]

        // Preserve curated ordering rather than recomputing from global tool order.
        let filtered = allowlist.filter { eligible.contains($0) }

        // Safety: avoid showing an empty tool list if IDs drift.
        if filtered.isEmpty {
            return eligible
        }

        // Safety: keep at least one primary tool for a usable editing surface.
        let primaryClockTools: Set<EditorToolID> = [.widgets, .layout, .style]
        let containsPrimary = filtered.contains(where: { primaryClockTools.contains($0) })
        if !containsPrimary {
            return eligible
        }

        return filtered

    case .widget, .other:
        return eligible
    }
}
