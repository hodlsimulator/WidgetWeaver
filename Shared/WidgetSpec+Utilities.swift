//
//  WidgetSpec+Utilities.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

// MARK: - Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}

extension Double {
    func normalised() -> Double { self.isFinite ? self : 0 }
}
