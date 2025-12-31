//
//  WidgetWeaverStepsUIComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Extracted from WidgetWeaverStepsSettingsView.swift to share UI primitives + formatting helpers.
//

import SwiftUI

// MARK: - Today card + ring

struct StepsTodayCard: View {
    let steps: Int
    let goal: Int
    let fraction: Double
    let percent: Int
    let access: WidgetWeaverStepsAccess
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StepsRing(fraction: fraction, lineWidth: 10)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .bold()

                    Text(primary)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()

                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let fetchedAt {
                Text("Updated \(wwTimeShort(fetchedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch access {
        case .authorised: return "Steps today"
        case .denied: return "Steps (Denied)"
        case .notAvailable: return "Steps (Unavailable)"
        case .notDetermined: return "Steps (Not enabled)"
        case .unknown: return "Steps"
        }
    }

    private var primary: String {
        switch access {
        case .authorised, .unknown:
            return wwFormatSteps(steps)
        case .denied, .notAvailable, .notDetermined:
            return "—"
        }
    }

    private var secondary: String {
        switch access {
        case .denied, .notDetermined:
            return "Tap Request Steps Access."
        case .notAvailable:
            return "HealthKit isn’t available on this device."
        case .unknown, .authorised:
            if goal > 0 { return "Goal \(wwFormatSteps(goal)) • \(percent)%" }
            return "No goal set"
        }
    }
}

struct StepsRing: View {
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        let clamped = min(1.0, max(0.0, fraction))
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Formatting helpers

func wwFormatSteps(_ n: Int) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesGroupingSeparator = true
    return nf.string(from: NSNumber(value: n)) ?? "\(n)"
}

func wwDateMedium(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: d)
}

func wwMonthTitle(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateFormat = "LLLL yyyy"
    return df.string(from: d)
}

func wwTimeShort(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateStyle = .none
    df.timeStyle = .short
    return df.string(from: d)
}
