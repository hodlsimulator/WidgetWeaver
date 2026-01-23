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



// MARK: - Activity today card (multi-metric)

struct ActivityTodayCard: View {
    let snapshot: WidgetWeaverActivitySnapshot?
    let access: WidgetWeaverActivityAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.circle")
                    .font(.title2)
                    .foregroundStyle(.accent)

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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if let fetchedAt = snapshot?.fetchedAt {
                Text("Updated \(wwTimeShort(fetchedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch access {
        case .authorised, .partial: return "Activity today"
        case .denied: return "Activity (Denied)"
        case .notAvailable: return "Activity (Unavailable)"
        case .notDetermined: return "Activity (Not enabled)"
        case .unknown: return "Activity"
        }
    }

    private var primary: String {
        switch access {
        case .authorised, .partial, .unknown:
            if let steps = snapshot?.steps {
                return "\(wwFormatSteps(steps)) steps"
            }
            return "—"
        case .denied, .notAvailable, .notDetermined:
            return "—"
        }
    }

    private var secondary: String {
        switch access {
        case .denied, .notDetermined:
            return "Tap Request Activity Access."
        case .notAvailable:
            return "HealthKit isn’t available on this device."
        case .unknown:
            return "Refresh to load today’s snapshot."
        case .authorised, .partial:
            let flightsText: String? = snapshot?.flightsClimbed.map { "\($0) flights" }
            let distanceText: String? = snapshot?.distanceWalkingRunningMeters.map(wwFormatDistanceKM)
            let energyText: String? = snapshot?.activeEnergyBurnedKilocalories.map(wwFormatKcal)

            let parts = [flightsText, distanceText, energyText].compactMap { $0 }
            if parts.isEmpty { return "Today" }
            return parts.joined(separator: " • ")
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



// MARK: - Insights

struct StepsInsightsBarCompact: View {
    let analytics: WidgetWeaverStepsAnalytics

    var body: some View {
        HStack(spacing: 10) {
            StepsInsightPill(title: "Streak", value: "\(analytics.currentStreakDays)d")
            StepsInsightPill(title: "Avg 7", value: wwFormatSteps(Int(analytics.averageSteps(days: 7).rounded())))
            StepsInsightPill(title: "Avg 30", value: wwFormatSteps(Int(analytics.averageSteps(days: 30).rounded())))
        }
    }
}

struct StepsInsightPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Formatting helpers

func wwFormatSteps(_ n: Int) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesGroupingSeparator = true
    return nf.string(from: NSNumber(value: n)) ?? "\(n)"
}


func wwFormatDistanceKM(_ meters: Double) -> String {
    let km = max(0, meters) / 1000.0

    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesGroupingSeparator = true
    nf.minimumFractionDigits = 0
    nf.maximumFractionDigits = 1

    let s = nf.string(from: NSNumber(value: km)) ?? String(format: "%.1f", km)
    return "\(s) km"
}

func wwFormatKcal(_ kcal: Double) -> String {
    let v = Int(max(0, kcal).rounded())
    return "\(wwFormatSteps(v)) kcal"
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
