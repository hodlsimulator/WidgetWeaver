//
//  EditorToolFocusGating.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

enum EditorToolFocusGating {
    /// Applies focus-group-specific "safety rails" to avoid showing irrelevant tools during deep edits.
    ///
    /// Principles:
    /// - Do not unexpectedly remove primary editing affordances unless we are certain the user is in a focused sub-flow.
    /// - Always preserve Style (and other global tools) when in doubt.
    static func editorToolIDsApplyingFocusGate(
        eligibleToolIDs: [EditorToolID],
        focusGroup: EditorToolFocusGroup
    ) -> [EditorToolID] {
        switch focusGroup {
        case .smartPhotos:
            return gateForSmartPhotos(eligibleToolIDs: eligibleToolIDs)
        default:
            return eligibleToolIDs
        }
    }

    private static func gateForSmartPhotos(eligibleToolIDs: [EditorToolID]) -> [EditorToolID] {
        // Only apply gating when the Smart Photo tool suite is actually present.
        let primarySmartPhotoTools: Set<EditorToolID> = [.albumShuffle, .smartPhotoCrop, .smartRules, .smartPhoto, .image]
        if eligibleToolIDs.first(where: { primarySmartPhotoTools.contains($0) }) == nil {
            return eligibleToolIDs
        }

        // Allowlist to keep visible during Smart Photo-focused flows.
        let allowlist: [EditorToolID] = [
        .albumShuffle,
        .smartPhotoCrop,
        .smartRules,
        .smartPhoto,
        .image,
        .style,
    ]

        // Keep the relative order of eligible tools, but only for allowlisted tools.
        var out: [EditorToolID] = []
        out.reserveCapacity(eligibleToolIDs.count)
        for id in eligibleToolIDs where allowlist.contains(id) {
            out.append(id)
        }

        // If we somehow filtered everything out, fall back to eligible list.
        if out.isEmpty {
            return eligibleToolIDs
        }

        return out
    }
}
