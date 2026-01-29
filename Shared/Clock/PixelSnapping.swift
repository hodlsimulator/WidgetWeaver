//
//  PixelSnapping.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import CoreGraphics

/// Utilities for snapping geometry to physical pixels.
///
/// Notes:
/// - Snapping is applied using the provided display scale.
/// - The helpers avoid importing SwiftUI so they are usable from CoreGraphics renderers.
enum PixelSnapping {

    @inline(__always)
    static func px(scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return 1.0 }
        return 1.0 / scale
    }

    /// Snaps a scalar to the nearest physical pixel.
    @inline(__always)
    static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// Snaps a scalar down to the nearest physical pixel.
    @inline(__always)
    static func floorToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return floor(value * scale) / scale
    }

    /// Snaps a scalar up to the nearest physical pixel.
    @inline(__always)
    static func ceilToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return ceil(value * scale) / scale
    }

    /// Snaps a point to the nearest physical pixel.
    @inline(__always)
    static func snap(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: snap(point.x, scale: scale), y: snap(point.y, scale: scale))
    }

    /// Snaps a size to the nearest physical pixel.
    @inline(__always)
    static func snap(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: snap(size.width, scale: scale), height: snap(size.height, scale: scale))
    }

    /// Returns a line width that is at least one physical pixel.
    @inline(__always)
    static func minLineWidth(_ requested: CGFloat, scale: CGFloat) -> CGFloat {
        let one = px(scale: scale)
        return max(one, snap(requested, scale: scale))
    }
}
