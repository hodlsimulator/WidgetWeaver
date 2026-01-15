//
//  WWClockWidgetDebugBadge.swift
//  WidgetWeaverWidget
//
//  Created by . . on 01/02/26.
//

import Foundation
import StoreKit
import SwiftUI
import WidgetKit

actor WWClockWidgetDebugGate {
    static let shared = WWClockWidgetDebugGate()
    private var cached: Bool?

    func isEnabled() async -> Bool {
        #if DEBUG
        return true
        #else
        if let v = cached { return v }
        let v = await compute()
        cached = v
        return v
        #endif
    }

    private func compute() async -> Bool {
        do {
            let verificationResult = try await AppTransaction.shared

            let envRaw: String
            switch verificationResult {
            case .verified(let appTransaction):
                envRaw = appTransaction.environment.rawValue
            case .unverified(let appTransaction, _):
                envRaw = appTransaction.environment.rawValue
            }

            return envRaw.lowercased() == "sandbox"
        } catch {
            return false
        }
    }
}

struct WWClockWidgetDebugBadge: View {
    let entryDate: Date
    let minuteAnchor: Date
    let timerRange: ClosedRange<Date>
    let showSeconds: Bool
    let tickModeLabel: String

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.widgetFamily) private var widgetFamily

    #if DEBUG
    @State private var enabled: Bool = true
    #else
    @State private var enabled: Bool = false
    #endif

    @State private var didCheckGate: Bool = false

    var body: some View {
        Group {
            if enabled {
                content
            }
        }
        .task {
            if didCheckGate { return }
            didCheckGate = true
            enabled = await WWClockWidgetDebugGate.shared.isEnabled()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WWClock dbg")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))

            Text("fam=\(familyLabel(widgetFamily)) sec=\(showSeconds ? "1" : "0") mode=\(tickModeLabel)")
                .font(.system(size: 9, weight: .regular, design: .monospaced))

            Text("redact=\(redactionLabel(redactionReasons)) dt=\(dtLabel(dynamicTypeSize)) rm=\(reduceMotion ? "1" : "0")")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .opacity(0.9)

            Text("font=\(WWClockSecondHandFont.isAvailable() ? "1" : "0") entryΔ=\(entryDeltaSeconds(entryDate, minuteAnchor))s")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .opacity(0.9)
            Text("bid=\(bundleShortLabel())")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .opacity(0.9)

            Text("agUD=\(appGroupDefaultsOK() ? "1" : "0") agURL=\(appGroupURLOK() ? "1" : "0") bal=\(WWClockDebugLog.isBallooningEnabled() ? "1" : "0")")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .opacity(0.9)


            HStack(spacing: 6) {
                Text("sys:")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                Text(timerInterval: timerRange, countsDown: false)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text("test:")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                Text("0:00")
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .font(WWClockSecondHandFont.font(size: 22))
                    .frame(width: 22, height: 22, alignment: .center)
                    .clipped()
            }

            HStack(spacing: 6) {
                Text("hand:")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                Text(timerInterval: timerRange, countsDown: false)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .font(WWClockSecondHandFont.font(size: 22))
                    .frame(width: 22, height: 22, alignment: .center)
                    .clipped()
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.55))
        .foregroundStyle(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func familyLabel(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "S"
        case .systemMedium: return "M"
        case .systemLarge: return "L"
        case .systemExtraLarge: return "XL"
        case .accessoryCircular: return "AC"
        case .accessoryRectangular: return "AR"
        case .accessoryInline: return "AI"
        case .accessoryCorner: return "AK"
        @unknown default: return "?"
        }
    }

    private func redactionLabel(_ reasons: RedactionReasons) -> String {
        var parts: [String] = []
        if reasons.contains(.placeholder) { parts.append("placeholder") }
        if reasons.contains(.privacy) { parts.append("privacy") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    private func dtLabel(_ dt: DynamicTypeSize) -> String {
        switch dt {
        case .xSmall: return "xS"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .xLarge: return "xL"
        case .xxLarge: return "xxL"
        case .xxxLarge: return "xxxL"
        case .accessibility1: return "AX1"
        case .accessibility2: return "AX2"
        case .accessibility3: return "AX3"
        case .accessibility4: return "AX4"
        case .accessibility5: return "AX5"
        @unknown default: return "?"
        }
    }

    private func entryDeltaSeconds(_ entry: Date, _ anchor: Date) -> Int {
        Int((entry.timeIntervalSince(anchor)).rounded())
    }

    private func bundleShortLabel() -> String {
        let bid = Bundle.main.bundleIdentifier ?? "nil"
        let parts = bid.split(separator: ".")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return bid
    }

    private func appGroupDefaultsOK() -> Bool {
        UserDefaults(suiteName: AppGroup.identifier) != nil
    }

    private func appGroupURLOK() -> Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil
    }

}
