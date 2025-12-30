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
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: !secondsEnabled,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    WWClockSecondHandCoreAnimationOverlay(
                        palette: palette,
                        startOfMinute: minuteAnchor,
                        handsOpacity: handsOpacity
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - CoreAnimation seconds overlay

private struct WWClockSecondHandCoreAnimationOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let endOfMinute = startOfMinute.addingTimeInterval(60.0)

        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let metrics = WWClockSecondHandMetrics(clockSize: s, scale: displayScale)

            ZStack {
                // Heartbeat: keep a host-animated primitive alive.
                ProgressView(timerInterval: startOfMinute...endOfMinute, countsDown: false)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // Core Animation seconds hand (layer rotation).
                WWClockSecondHandCALayerView(
                    accent: UIColor(palette.accent),
                    startOfMinute: startOfMinute,
                    shaftWidth: metrics.shaftWidth,
                    shaftLength: metrics.shaftLength,
                    tipSide: metrics.tipSide,
                    tipOutlineWidth: metrics.tipOutlineWidth
                )
                .opacity(handsOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                // Hub on top (drawn once), using the correct signature.
                WidgetWeaverClockCentreHubView(
                    palette: palette,
                    baseRadius: metrics.hubBaseRadius,
                    capRadius: metrics.hubCapRadius,
                    scale: displayScale
                )
                .opacity(handsOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockSecondHandMetrics {
    let shaftWidth: CGFloat
    let shaftLength: CGFloat
    let tipSide: CGFloat
    let tipOutlineWidth: CGFloat

    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(clockSize s: CGFloat, scale: CGFloat) {
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
        let ringB = WWClock.pixel(
            max(minB, outerRadius - provisionalR - ringA - ringC),
            scale: scale
        )

        let R = outerRadius - ringA - ringB - ringC

        let secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: scale
        )
        let secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: scale
        )
        let secondTipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: scale
        )

        let px = WWClock.px(scale: scale)
        let outline = max(px, secondWidth * 0.14)

        let hubBase = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )
        let hubCap = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )

        self.shaftWidth = secondWidth
        self.shaftLength = secondLength
        self.tipSide = secondTipSide
        self.tipOutlineWidth = outline

        self.hubBaseRadius = hubBase
        self.hubCapRadius = hubCap
    }
}

private struct WWClockSecondHandCALayerView: UIViewRepresentable {
    let accent: UIColor
    let startOfMinute: Date

    let shaftWidth: CGFloat
    let shaftLength: CGFloat
    let tipSide: CGFloat
    let tipOutlineWidth: CGFloat

    func makeUIView(context: Context) -> SecondHandHostView {
        let v = SecondHandHostView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.configure(
            accent: accent,
            startOfMinute: startOfMinute,
            shaftWidth: shaftWidth,
            shaftLength: shaftLength,
            tipSide: tipSide,
            tipOutlineWidth: tipOutlineWidth
        )
        return v
    }

    func updateUIView(_ uiView: SecondHandHostView, context: Context) {
        uiView.configure(
            accent: accent,
            startOfMinute: startOfMinute,
            shaftWidth: shaftWidth,
            shaftLength: shaftLength,
            tipSide: tipSide,
            tipOutlineWidth: tipOutlineWidth
        )
    }

    final class SecondHandHostView: UIView {
        private let handLayer = CALayer()
        private let shaftLayer = CAShapeLayer()
        private let tipLayer = CAShapeLayer()
        private let tipOutlineLayer = CAShapeLayer()

        private var lastMinuteAnchor: TimeInterval = -1

        private var cfgAccent: UIColor = .systemRed
        private var cfgStartOfMinute: Date = Date(timeIntervalSinceReferenceDate: 0)

        private var cfgShaftWidth: CGFloat = 2
        private var cfgShaftLength: CGFloat = 40
        private var cfgTipSide: CGFloat = 6
        private var cfgTipOutlineWidth: CGFloat = 1

        override init(frame: CGRect) {
            super.init(frame: frame)
            setUpLayers()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpLayers()
        }

        private func setUpLayers() {
            isOpaque = false

            layer.addSublayer(handLayer)
            handLayer.addSublayer(shaftLayer)
            handLayer.addSublayer(tipLayer)
            handLayer.addSublayer(tipOutlineLayer)

            tipOutlineLayer.fillColor = UIColor.clear.cgColor
            tipOutlineLayer.lineJoin = .round
        }

        func configure(
            accent: UIColor,
            startOfMinute: Date,
            shaftWidth: CGFloat,
            shaftLength: CGFloat,
            tipSide: CGFloat,
            tipOutlineWidth: CGFloat
        ) {
            cfgAccent = accent
            cfgStartOfMinute = startOfMinute
            cfgShaftWidth = shaftWidth
            cfgShaftLength = shaftLength
            cfgTipSide = tipSide
            cfgTipOutlineWidth = tipOutlineWidth

            updateColours()
            setNeedsLayout()

            let anchorKey = floor(startOfMinute.timeIntervalSinceReferenceDate / 60.0) * 60.0
            if anchorKey != lastMinuteAnchor {
                lastMinuteAnchor = anchorKey
                restartRotationAnimation()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            handLayer.frame = bounds

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updatePaths()
            CATransaction.commit()
        }

        private func updateColours() {
            shaftLayer.fillColor = cfgAccent.withAlphaComponent(0.62).cgColor
            tipLayer.fillColor = cfgAccent.withAlphaComponent(0.82).cgColor

            tipOutlineLayer.strokeColor = UIColor.black.withAlphaComponent(0.10).cgColor
            tipOutlineLayer.lineWidth = cfgTipOutlineWidth
        }

        private func updatePaths() {
            let b = bounds
            let midX = b.midX
            let midY = b.midY

            let shaftRect = CGRect(
                x: midX - cfgShaftWidth * 0.5,
                y: midY - cfgShaftLength,
                width: cfgShaftWidth,
                height: cfgShaftLength
            )
            shaftLayer.path = UIBezierPath(rect: shaftRect).cgPath

            let tipRect = CGRect(
                x: midX - cfgTipSide * 0.5,
                y: (midY - cfgShaftLength) - cfgTipSide * 0.5,
                width: cfgTipSide,
                height: cfgTipSide
            )
            let tipPath = UIBezierPath(rect: tipRect)
            tipLayer.path = tipPath.cgPath
            tipOutlineLayer.path = tipPath.cgPath
        }

        private func restartRotationAnimation() {
            handLayer.removeAnimation(forKey: "ww.secondHand.rotation")

            let now = Date()
            let elapsed = max(0.0, min(now.timeIntervalSince(cfgStartOfMinute), 59.999))
            let t = CACurrentMediaTime()

            let anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = 0.0
            anim.toValue = Double.pi * 2.0
            anim.duration = 60.0
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            anim.beginTime = t - elapsed

            handLayer.add(anim, forKey: "ww.secondHand.rotation")
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
