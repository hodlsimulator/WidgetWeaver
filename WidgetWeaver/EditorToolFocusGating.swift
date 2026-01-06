//
//  EditorToolFocusGating.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Coarse focus buckets used to gate tool visibility.
///
/// Only `.smartPhotos` is currently used for gating; other cases exist so future
/// expansion stays local to this file.
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
    guard focusGroup == .smartPhotos else {
        return eligible
    }

    // Curated allowlist: keep this tight in the first slice to avoid unexpected UI changes.
    let allowlist: [EditorToolID] = [
        .albumShuffle,
        .smartPhotoCrop,
        .smartRules,
        .smartPhoto,
        .image,
        .style,
    ]

    let filtered = eligible.filter { allowlist.contains($0) }

    // Safety: avoid showing an empty tool list if IDs drift.
    if filtered.isEmpty {
        return eligible
    }

    // Safety: if none of the primary Smart Photo tools are present, do not gate.
    // This prevents an odd state (e.g. template switch) from collapsing the UI down
    // to only generic tools such as Style.
    let primarySmartPhotoTools: Set<EditorToolID> = [.albumShuffle, .smartPhotoCrop, .smartRules, .smartPhoto, .image]
    let containsPrimary = filtered.contains(where: { primarySmartPhotoTools.contains($0) })
    if !containsPrimary {
        return eligible
    }

    return filtered
}
