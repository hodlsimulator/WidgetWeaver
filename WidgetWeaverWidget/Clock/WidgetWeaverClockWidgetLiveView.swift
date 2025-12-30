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
    @Environment(\.displayScale) private var displayScale

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
                // Base clock: hour + minute are minute-boundary timeline-driven.
                // Centre hub is disabled so the seconds hand can sit under it.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    // Heartbeat stays extremely cheap.
                    WWClockHostHeartbeat(startOfMinute: minuteAnchor)

                    // Seconds hand is Core Animation driven (no SwiftUI invalidation needed).
                    WWClockSecondHandCoreAnimationOverlay(
                        startOfMinute: minuteAnchor,
                        colour: palette.accent,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)

                    // Hub on top (drawn once).
                    WWClockCentreHubOverlay(palette: palette, scale: displayScale)
                        .opacity(handsOpacity)
                        .privacySensitive(isPrivacy)
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Host heartbeat

private struct WWClockHostHeartbeat: View {
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
    let scale: CGFloat

    var body: some View {
        _WWClockSecondHandCAView(
            startOfMinute: startOfMinute,
            colour: colour,
            scale: scale
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct _WWClockSecondHandCAView: UIViewRepresentable {
    let startOfMinute: Date
    let colour: Color
    let scale: CGFloat

    func makeUIView(context: Context) -> _WWSecondHandUIView {
        let v = _WWSecondHandUIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: _WWSecondHandUIView, context: Context) {
        uiView.configure(startOfMinute: startOfMinute, colour: colour, scale: scale)
    }
}

private final class _WWSecondHandUIView: UIView {
    private let root = CALayer()
    private let shaft = CALayer()
    private let tip = CALayer()
    private let tipBorder = CAShapeLayer()

    private var currentStartOfMinute: Date = Date(timeIntervalSinceReferenceDate: 0)
    private var currentScale: CGFloat = 2.0
    private var currentColour: UIColor = .white

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

    func configure(startOfMinute: Date, colour: Color, scale: CGFloat) {
        let startChanged = abs(startOfMinute.timeIntervalSince(currentStartOfMinute)) > 0.25
        let scaleChanged = abs(scale - currentScale) > 0.001

        let uiColour = UIColor(colour)
        let colourChanged = (uiColour != currentColour)

        currentStartOfMinute = startOfMinute
        currentScale = scale
        currentColour = uiColour

        root.frame = bounds
        applyGeometry()
        ensureAnimationRunning(forceRestart: startChanged || scaleChanged || colourChanged)
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

        let fromAngle = (elapsed / total) * (Double.pi * 2.0)
        let toAngle = Double.pi * 2.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.transform = CATransform3DMakeRotation(CGFloat(fromAngle), 0, 0, 1)
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = fromAngle
        anim.toValue = toAngle
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

// MARK: - Centre hub (drawn once on top)

private struct WWClockCentreHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.pixel(s * 0.925, scale: scale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: scale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: scale
            )
            let minB = WWClock.px(scale: scale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: scale)

            let R = outerRadius - ringA - ringB - ringC

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: scale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: scale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: hubBaseRadius,
                capRadius: hubCapRadius,
                scale: scale
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}
