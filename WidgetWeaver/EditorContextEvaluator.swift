//
//  EditorContextEvaluator.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Pure logic helpers used to derive context/capabilities from editor state.
///
/// This file deliberately avoids SwiftUI and any I/O to keep evaluation cheap and testable.
enum EditorContextEvaluator {
    static func selectionKind(selectionCount: Int) -> EditorSelectionKind {
        if selectionCount <= 0 { return .none }
        if selectionCount == 1 { return .single }
        return .multi
    }
}
