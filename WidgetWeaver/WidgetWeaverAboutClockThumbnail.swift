//
//  WidgetWeaverAboutClockThumbnail.swift
//  WidgetWeaver
//
//  Created by . . on 1/22/26.
//

import Foundation
import SwiftUI

/// Small, fast-rendering clock thumbnail used in the in-app catalog.
///
/// Rendering is routed through `WidgetWeaverClockFaceView` so thumbnails match the
/// widget/editor composition for the same face + palette.
struct WidgetWeaverAboutClockThumbnail: View {
    enum Variant: String, CaseIterable {
        case classic
        case ocean
        case graphite
    }

    let variant: Variant

    /// Defaults to `.icon` to match the current Clock defaults (Quick and new Designer).
    var face: WidgetWeaverClockFaceToken = .icon

    @Environment(\.wwThumbnailRenderingEnabled) private var thumbnailRenderingEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if thumbnailRenderingEnabled {
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    clockBody(date: context.date)
                }
            } else {
                clockBody(date: Date())
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func clockBody(date: Date) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            let angles = Self.handAngles(for: date)
            let palette = Self.palette(for: variant, colorScheme: colorScheme)

            ZStack {
                WidgetWeaverClockBackgroundView(palette: palette)

                WidgetWeaverClockFaceView(
                    face: face,
                    palette: palette,
                    hourAngle: .degrees(angles.hour),
                    minuteAngle: .degrees(angles.minute),
                    secondAngle: .degrees(angles.second),
                    showsSecondHand: true,
                    showsMinuteHand: true,
                    showsHandShadows: false,
                    showsGlows: false,
                    showsCentreHub: true,
                    handsOpacity: 1.0
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private struct Angles {
        let hour: Double
        let minute: Double
        let second: Double
    }

    private static func handAngles(for date: Date) -> Angles {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        let hourDeg = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
        let minuteDeg = (minuteInt + sec / 60.0) * 6.0
        let secondDeg = sec * 6.0

        return Angles(hour: hourDeg, minute: minuteDeg, second: secondDeg)
    }

    private static func palette(for variant: Variant, colorScheme: ColorScheme) -> WidgetWeaverClockPalette {
        let scheme: WidgetWeaverClockColourScheme = {
            switch variant {
            case .classic:
                return .classic
            case .ocean:
                return .ocean
            case .graphite:
                return .graphite
            }
        }()

        return WidgetWeaverClockPalette.resolve(scheme: scheme, mode: colorScheme)
    }
}
