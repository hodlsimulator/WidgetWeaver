//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import WidgetKit
import UIKit
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.redactionReasons) private var redactionReasons

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        minuteAnchor: Date,
        tickMode: WidgetWeaverClockTickMode
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.minuteAnchor = minuteAnchor
        self.tickMode = tickMode
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)
            let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            let isReduceMotion = UIAccessibility.isReduceMotionEnabled

            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy
                && !isLowPowerMode
                && !isReduceMotion

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

            let baseAngles = WWClockBaseAngles(date: minuteAnchor)

            ZStack {
                // Base clock: hour + minute are minute-boundary timeline-driven (budget-safe).
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    // A tiny host-time view keeps the widget in a “live” render mode on some paths.
                    WWClockHostTimeHeartbeat(startOfMinute: minuteAnchor)

                    // Seconds hand: Core Animation sweep for the remainder of the minute.
                    WWClockSecondHandCoreAnimationOverlay(
                        startOfMinute: minuteAnchor,
                        colour: palette.accent
                    )

                    // Hub on top so the second hand sits visually under the cap.
                    WWClockCentreHubOverlay(
                        palette: palette,
                        handsOpacity: handsOpacity
                    )
                    .privacySensitive(isPrivacy)
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Base angles (minute-anchored)

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        // Degrees with 0 at 12 o’clock.
        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}

// MARK: - Host-time heartbeat

private struct WWClockHostTimeHeartbeat: View {
    let startOfMinute: Date

    var body: some View {
        let end = startOfMinute.addingTimeInterval(60.0)
        ProgressView(timerInterval: startOfMinute...end, countsDown: false)
            .progressViewStyle(.linear)
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Second hand (Core Animation)

private struct WWClockSecondHandCoreAnimationOverlay: View {
    let startOfMinute: Date
    let colour: Color

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        _WWClockSecondHandCAView(
            startOfMinute: startOfMinute,
            colour: UIColor(colour),
            displayScale: displayScale
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct _WWClockSecondHandCAView: UIViewRepresentable {
    let startOfMinute: Date
    let colour: UIColor
    let displayScale: CGFloat

    func makeUIView(context: Context) -> _WWSecondHandUIView {
        let v = _WWSecondHandUIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: _WWSecondHandUIView, context: Context) {
        uiView.configure(
            startOfMinute: startOfMinute,
            colour: colour,
            displayScale: displayScale
        )
    }
}

private final class _WWSecondHandUIView: UIView {
    private let root = CALayer()
    private let shaft = CALayer()
    private let tip = CALayer()
    private let tipBorder = CAShapeLayer()

    private var currentStartOfMinute: Date = Date(timeIntervalSinceReferenceDate: 0)
    private var currentColour: UIColor = .white
    private var currentScale: CGFloat = 2.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        layer.masksToBounds = false

        root.masksToBounds = false
        layer.addSublayer(root)

        root.addSublayer(shaft)
        root.addSublayer(tip)

        tipBorder.fillColor = UIColor.clear.cgColor
        tipBorder.lineJoin = .miter
        tipBorder.lineCap = .butt
        tip.addSublayer(tipBorder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        root.frame = bounds
        applyGeometry()
        ensureAnimationRunning(forceRestart: false)
    }

    func configure(startOfMinute: Date, colour: UIColor, displayScale: CGFloat) {
        let startChanged = abs(startOfMinute.timeIntervalSince(currentStartOfMinute)) > 0.25
        let colourChanged = (colour != currentColour)
        let scaleChanged = abs(displayScale - currentScale) > 0.001

        currentStartOfMinute = startOfMinute
        currentColour = colour
        currentScale = displayScale

        root.frame = bounds
        applyGeometry()
        ensureAnimationRunning(forceRestart: startChanged || colourChanged || scaleChanged)
    }

    private func ensureAnimationRunning(forceRestart: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        if forceRestart {
            restartSweepAnimation()
            return
        }

        if root.animation(forKey: "ww.seconds.sweep") == nil {
            restartSweepAnimation()
        }
    }

    private func restartSweepAnimation() {
        root.removeAnimation(forKey: "ww.seconds.sweep")

        let now = Date()
        let total: Double = 60.0

        let elapsedRaw = now.timeIntervalSince(currentStartOfMinute)
        let elapsed = max(0.0, min(elapsedRaw, total))
        let remaining = max(0.05, total - elapsed)

        let startAngle = CGFloat((elapsed / total) * (Double.pi * 2.0))
        let endAngle = CGFloat(Double.pi * 2.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.transform = CATransform3DMakeRotation(endAngle, 0, 0, 1)
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = startAngle
        anim.toValue = endAngle
        anim.duration = remaining
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        root.add(anim, forKey: "ww.seconds.sweep")
    }

    private func applyGeometry() {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        root.frame = b

        let s = min(b.width, b.height)

        let outerDiameter = WWClock.pixel(s * 0.925, scale: currentScale)
        let outerRadius = outerDiameter * 0.5

        let metalThicknessRatio: CGFloat = 0.062
        let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

        let ringA = WWClock.pixel(provisionalR * 0.010, scale: currentScale)
        let ringC = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
            scale: currentScale
        )
        let minB = WWClock.px(scale: currentScale)
        let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: currentScale)

        let R = outerRadius - ringA - ringB - ringC

        let secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: currentScale
        )
        let secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: currentScale
        )
        let tipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: currentScale
        )

        let cx = b.midX
        let cy = b.midY

        shaft.frame = CGRect(
            x: cx - secondWidth * 0.5,
            y: cy - secondLength,
            width: secondWidth,
            height: secondLength
        )
        shaft.backgroundColor = currentColour.withAlphaComponent(0.62).cgColor

        tip.frame = CGRect(
            x: cx - tipSide * 0.5,
            y: cy - secondLength - tipSide * 0.5,
            width: tipSide,
            height: tipSide
        )
        tip.backgroundColor = currentColour.withAlphaComponent(0.82).cgColor

        let px = WWClock.px(scale: currentScale)
        let borderWidth = max(px, secondWidth * 0.14)

        tipBorder.frame = tip.bounds
        tipBorder.path = UIBezierPath(rect: tip.bounds).cgPath
        tipBorder.strokeColor = UIColor.black.withAlphaComponent(0.10).cgColor
        tipBorder.lineWidth = borderWidth
    }
}

// MARK: - Hub overlay (on top of second hand)

private struct WWClockCentreHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: displayScale)

            let R = outerRadius - ringA - ringB - ringC

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: hubBaseRadius,
                capRadius: hubCapRadius,
                scale: displayScale
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(handsOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
