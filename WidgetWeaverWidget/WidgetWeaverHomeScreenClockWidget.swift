//
//  WidgetWeaverHomeScreenClockWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/23/25.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

public struct WidgetWeaverHomeScreenClockConfigurationIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Clock" }
    public static var description: IntentDescription { IntentDescription("Configure the clock widget.") }

    @Parameter(title: "Colour Scheme", default: .classic)
    public var colourScheme: WidgetWeaverClockWidgetColourScheme

    public static var parameterSummary: some ParameterSummary {
        Summary("Colour Scheme: \(\.$colourScheme)")
    }

    public init() {}
}

enum WidgetWeaverClockTickMode: Int {
    case minuteOnly = 0
    case secondsSweep = 1
}

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let colourScheme: WidgetWeaverClockColourScheme
    let isWidgetKitPreview: Bool
}

private enum WWClockTimelineConfig {
    // Keep this short so configuration changes cannot remain “stuck” behind a long cached timeline.
    // This stays minute-based (budget-safe) and ensures the provider is re-queried frequently.
    static let maxEntriesPerTimeline: Int = 2 // now + next minute boundary
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            tickMode: .minuteOnly,
            tickSeconds: 60.0,
            colourScheme: .classic,
            isWidgetKitPreview: true
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        return Entry(
            date: now,
            tickMode: .minuteOnly,
            tickSeconds: 60.0,
            colourScheme: scheme,
            isWidgetKitPreview: true
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        WWClockInstrumentation.recordTimelineBuild(now: now, scheme: scheme)

        return makeMinuteTimeline(now: now, colourScheme: scheme, isWidgetKitPreview: context.isPreview)
    }

    private func makeMinuteTimeline(
        now: Date,
        colourScheme: WidgetWeaverClockColourScheme,
        isWidgetKitPreview: Bool
    ) -> Timeline<Entry> {
        let minuteAnchorNow = Self.floorToMinute(now)
        let nextMinuteBoundary = minuteAnchorNow.addingTimeInterval(60.0)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        // Immediate entry uses `now` so edits mid-minute have a chance to render quickly.
        entries.append(
            Entry(
                date: now,
                tickMode: .secondsSweep,
                tickSeconds: 0.0,
                colourScheme: colourScheme,
                isWidgetKitPreview: isWidgetKitPreview
            )
        )

        // Single future entry ends the timeline at the next minute boundary, so WidgetKit re-requests
        // the timeline regularly and picks up configuration changes without explicit reload calls.
        if entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: nextMinuteBoundary,
                    tickMode: .secondsSweep,
                    tickSeconds: 0.0,
                    colourScheme: colourScheme,
                    isWidgetKitPreview: isWidgetKitPreview
                )
            )
        }

        WWClockDebugLog.appendLazy(
            category: "clock",
            throttleID: "clockWidget.provider.timeline",
            minInterval: 60.0,
            now: now
        ) {
            let nowRef = Int(now.timeIntervalSinceReferenceDate.rounded())
            let anchorRef = Int(minuteAnchorNow.timeIntervalSinceReferenceDate.rounded())
            let nextRef = Int(nextMinuteBoundary.timeIntervalSinceReferenceDate.rounded())

            let firstRef = Int((entries.first?.date ?? now).timeIntervalSinceReferenceDate.rounded())
            let lastRef = Int((entries.last?.date ?? now).timeIntervalSinceReferenceDate.rounded())

            return "provider.timeline scheme=\(colourScheme.rawValue) nowRef=\(nowRef) anchorRef=\(anchorRef) nextRef=\(nextRef) entries=\(entries.count) firstRef=\(firstRef) lastRef=\(lastRef) policy=atEnd"
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Instrumentation (App Group)

private enum WWClockInstrumentation {
    private static let lastKey = "widgetweaver.clock.timelineBuild.last"
    private static let schemeKey = "widgetweaver.clock.timelineBuild.scheme"
    private static let countPrefix = "widgetweaver.clock.timelineBuild.count."

    static func recordTimelineBuild(now: Date, scheme: WidgetWeaverClockColourScheme) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: lastKey)
        defaults.set(scheme.rawValue, forKey: schemeKey)

        let dayKey = Self.dayKey(for: now)
        let countKey = countPrefix + dayKey
        let c = defaults.integer(forKey: countKey)
        defaults.set(c + 1, forKey: countKey)
    }

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d%02d%02d", y, m, d)
    }
}

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverHomeScreenClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            // Keep keyed by the entry date to avoid stale/black snapshots on Home Screen.
            WidgetWeaverHomeScreenClockView(entry: entry)
                .id(entry.date)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: colorScheme
        )

        Group {
            if entry.isWidgetKitPreview {
                WidgetWeaverClockWidgetStaticPreviewFace(
                    palette: palette,
                    date: entry.date
                )
            } else {
                WidgetWeaverClockWidgetLiveView(
                    palette: palette,
                    entryDate: entry.date,
                    tickMode: entry.tickMode,
                    tickSeconds: entry.tickSeconds
                )
            }
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
        .clipShape(ContainerRelativeShape())
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text("scheme=\(entry.colourScheme.rawValue)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.65))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }
}

private struct WidgetWeaverClockWidgetStaticPreviewFace: View {
    let palette: WidgetWeaverClockPalette
    let date: Date

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let dialSize = side * 0.86
            let radius = dialSize * 0.5
            let px = WWClock.px(scale: displayScale)

            let angles = clockAngles(for: date)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [palette.dialCenter, palette.dialEdge]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )

                // Subtle edge to keep the dial readable against bright schemes.
                Circle()
                    .strokeBorder(palette.separatorRing.opacity(0.45), lineWidth: max(px, 0.8))

                // Hour hand
                hand(
                    width: dialSize * 0.085,
                    length: dialSize * 0.26,
                    angleDegrees: angles.hour,
                    baseOffset: dialSize * 0.13
                )

                // Minute hand
                hand(
                    width: dialSize * 0.065,
                    length: dialSize * 0.36,
                    angleDegrees: angles.minute,
                    baseOffset: dialSize * 0.18
                )

                // Second hand (thin, high-contrast)
                RoundedRectangle(cornerRadius: dialSize * 0.01, style: .continuous)
                    .fill(palette.accent)
                    .frame(width: max(px, dialSize * 0.018), height: dialSize * 0.42)
                    .offset(y: -dialSize * 0.21)
                    .rotationEffect(.degrees(angles.second))

                // Hub
                Circle()
                    .fill(palette.hubBase)
                    .frame(width: dialSize * 0.10, height: dialSize * 0.10)

                Circle()
                    .fill(palette.accent)
                    .frame(width: dialSize * 0.034, height: dialSize * 0.034)
            }
            .frame(width: dialSize, height: dialSize)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
        }
    }

    private func hand(width: CGFloat, length: CGFloat, angleDegrees: Double, baseOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.5, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [palette.handLight, palette.handMid, palette.handDark]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.5, style: .continuous)
                    .strokeBorder(palette.handEdge.opacity(0.35), lineWidth: max(WWClock.px(scale: displayScale), 0.7))
            }
            .frame(width: width, height: length)
            .offset(y: -baseOffset)
            .rotationEffect(.degrees(angleDegrees))
    }

    private struct Angles {
        let hour: Double
        let minute: Double
        let second: Double
    }

    private func clockAngles(for date: Date) -> Angles {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)
        let h = Double((comps.hour ?? 0) % 12)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0)

        let hour = (h + (m / 60.0)) / 12.0 * 360.0
        let minute = (m / 60.0) * 360.0
        let second = (s / 60.0) * 360.0

        return Angles(hour: hour, minute: minute, second: second)
    }
}
