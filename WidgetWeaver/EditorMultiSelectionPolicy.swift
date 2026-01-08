//
//  EditorMultiSelectionPolicy.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

/// Policy for determining which tools remain visible during multi-selection.
///
/// `.intersection` means a tool must explicitly opt into multi-selection support; otherwise it is hidden.
enum EditorMultiSelectionPolicy: String, CaseIterable, Hashable, Sendable {
    case intersection
}
