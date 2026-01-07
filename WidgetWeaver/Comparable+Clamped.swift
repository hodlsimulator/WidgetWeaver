//
//  Comparable+Clamped.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

extension Comparable {
    @inlinable
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
