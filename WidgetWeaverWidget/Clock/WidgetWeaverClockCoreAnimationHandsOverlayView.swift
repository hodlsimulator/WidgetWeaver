//
//  WidgetWeaverClockCoreAnimationHandsOverlayView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import UIKit

struct WidgetWeaverClockCoreAnimationHandsOverlayView: UIViewRepresentable {
    let palette: WidgetWeaverClockPalette
    let date: Date

    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let showsSecondHand: Bool
    let scale: CGFloat

    func makeUIView(context: Context) -> WWClockAnimatedHandsUIView {
        let v = WWClockAnimatedHandsUIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.configure(
            palette: palette,
            date: date,
            hourLength: hourLength,
            hourWidth: hourWidth,
            minuteLength: minuteLength,
            minuteWidth: minuteWidth,
            secondLength: secondLength,
            secondWidth: secondWidth,
            secondTipSide: secondTipSide,
            showsSecondHand: showsSecondHand,
            scale: scale
        )
        return v
    }

    func updateUIView(_ uiView: WWClockAnimatedHandsUIView, context: Context) {
        uiView.configure(
            palette: palette,
            date: date,
            hourLength: hourLength,
            hourWidth: hourWidth,
            minuteLength: minuteLength,
            minuteWidth: minuteWidth,
            secondLength: secondLength,
            secondWidth: secondWidth,
            secondTipSide: secondTipSide,
            showsSecondHand: showsSecondHand,
            scale: scale
        )
    }
}

final class WWClockAnimatedHandsUIView: UIView {
    private let hourLayer = CAShapeLayer()
    private let minuteLayer = CAShapeLayer()
    private let secondLayer = CAShapeLayer()
    private let secondTipStrokeLayer = CAShapeLayer()

    private var configuredPalette: WidgetWeaverClockPalette?
    private var configuredDate: Date = .distantPast

    private var configuredHourLength: CGFloat = 0
    private var configuredHourWidth: CGFloat = 0

    private var configuredMinuteLength: CGFloat = 0
    private var configuredMinuteWidth: CGFloat = 0

    private var configuredSecondLength: CGFloat = 0
    private var configuredSecondWidth: CGFloat = 0
    private var configuredSecondTipSide: CGFloat = 0

    private var configuredShowsSecondHand: Bool = true
    private var configuredScale: CGFloat = 0

    private var lastStartedDate: Date = .distantPast
    private var lastStartedSize: CGSize = .zero
    private var lastStartedShowsSecondHand: Bool = true

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

        for l in [hourLayer, minuteLayer, secondLayer, secondTipStrokeLayer] {
            l.contentsScale = traitCollection.displayScale
            l.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "path": NSNull(),
                "transform": NSNull()
            ]
        }

        hourLayer.fillRule = .evenOdd
        minuteLayer.fillRule = .evenOdd
        secondLayer.fillRule = .evenOdd
        secondTipStrokeLayer.fillRule = .evenOdd

        layer.addSublayer(hourLayer)
        layer.addSublayer(minuteLayer)
        layer.addSublayer(secondLayer)
        layer.addSublayer(secondTipStrokeLayer)
    }

    func configure(
        palette: WidgetWeaverClockPalette,
        date: Date,
        hourLength: CGFloat,
        hourWidth: CGFloat,
        minuteLength: CGFloat,
        minuteWidth: CGFloat,
        secondLength: CGFloat,
        secondWidth: CGFloat,
        secondTipSide: CGFloat,
        showsSecondHand: Bool,
        scale: CGFloat
    ) {
        configuredPalette = palette
        configuredDate = date

        configuredHourLength = hourLength
        configuredHourWidth = hourWidth

        configuredMinuteLength = minuteLength
        configuredMinuteWidth = minuteWidth

        configuredSecondLength = secondLength
        configuredSecondWidth = secondWidth
        configuredSecondTipSide = secondTipSide

        configuredShowsSecondHand = showsSecondHand
        configuredScale = scale

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let palette = configuredPalette else { return }
        if bounds.width <= 1 || bounds.height <= 1 { return }

        let displayScale = max(1.0, (configuredScale > 0 ? configuredScale : traitCollection.displayScale))
        let px = 1.0 / displayScale

        for l in [hourLayer, minuteLayer, secondLayer, secondTipStrokeLayer] {
            l.contentsScale = displayScale
        }

        let centre = CGPoint(x: bounds.midX, y: bounds.midY)

        hourLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        hourLayer.position = centre
        hourLayer.bounds = CGRect(x: 0, y: 0, width: configuredHourWidth, height: configuredHourLength)
        hourLayer.path = Self.hourWedgePath(width: configuredHourWidth, height: configuredHourLength)
        hourLayer.fillColor = UIColor(palette.handMid).cgColor
        hourLayer.strokeColor = UIColor(palette.handEdge).cgColor
        hourLayer.lineWidth = max(px, configuredHourWidth * 0.045)

        minuteLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        minuteLayer.position = centre
        minuteLayer.bounds = CGRect(x: 0, y: 0, width: configuredMinuteWidth, height: configuredMinuteLength)
        minuteLayer.path = Self.minuteNeedlePath(width: configuredMinuteWidth, height: configuredMinuteLength)
        minuteLayer.fillColor = UIColor(palette.handMid).cgColor
        minuteLayer.strokeColor = UIColor(palette.handEdge).cgColor
        minuteLayer.lineWidth = max(px, configuredMinuteWidth * 0.075)

        let showSecond = configuredShowsSecondHand
            && configuredSecondLength > 0
            && configuredSecondWidth > 0
            && configuredSecondTipSide > 0

        secondLayer.isHidden = !showSecond
        secondTipStrokeLayer.isHidden = !showSecond

        if showSecond {
            let secondBoundsW = max(configuredSecondWidth, configuredSecondTipSide)
            let secondBoundsH = configuredSecondLength + configuredSecondTipSide

            secondLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            secondLayer.position = centre
            secondLayer.bounds = CGRect(x: 0, y: 0, width: secondBoundsW, height: secondBoundsH)
            secondLayer.path = Self.secondHandPath(
                boundsWidth: secondBoundsW,
                boundsHeight: secondBoundsH,
                shaftWidth: configuredSecondWidth,
                shaftLength: configuredSecondLength,
                tipSide: configuredSecondTipSide
            )
            secondLayer.fillColor = UIColor(palette.accent).withAlphaComponent(0.72).cgColor
            secondLayer.strokeColor = nil
            secondLayer.lineWidth = 0

            secondTipStrokeLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            secondTipStrokeLayer.position = centre
            secondTipStrokeLayer.bounds = CGRect(x: 0, y: 0, width: secondBoundsW, height: secondBoundsH)
            secondTipStrokeLayer.path = Self.secondTipStrokePath(
                boundsWidth: secondBoundsW,
                tipSide: configuredSecondTipSide
            )
            secondTipStrokeLayer.fillColor = nil
            secondTipStrokeLayer.strokeColor = UIColor.black.withAlphaComponent(0.10).cgColor
            secondTipStrokeLayer.lineWidth = max(px, configuredSecondWidth * 0.14)
        }

        let needsRestart = (lastStartedSize != bounds.size)
            || (lastStartedShowsSecondHand != showSecond)
            || (lastStartedDate != configuredDate)

        if needsRestart {
            lastStartedSize = bounds.size
            lastStartedShowsSecondHand = showSecond
            lastStartedDate = configuredDate
            applyTimeAndStartAnimations(date: configuredDate, showSecond: showSecond)
        }
    }

    private func applyTimeAndStartAnimations(date: Date, showSecond: Bool) {
        let angles = Self.angles(for: date)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        hourLayer.removeAnimation(forKey: "ww_rotation")
        minuteLayer.removeAnimation(forKey: "ww_rotation")
        secondLayer.removeAnimation(forKey: "ww_rotation")
        secondTipStrokeLayer.removeAnimation(forKey: "ww_rotation")

        hourLayer.setAffineTransform(CGAffineTransform(rotationAngle: angles.hour))
        minuteLayer.setAffineTransform(CGAffineTransform(rotationAngle: angles.minute))

        if showSecond {
            secondLayer.setAffineTransform(CGAffineTransform(rotationAngle: angles.second))
            secondTipStrokeLayer.setAffineTransform(CGAffineTransform(rotationAngle: angles.second))
        }

        CATransaction.commit()

        startContinuousRotation(layer: hourLayer, period: 12.0 * 60.0 * 60.0)
        startContinuousRotation(layer: minuteLayer, period: 60.0 * 60.0)

        if showSecond {
            startContinuousRotation(layer: secondLayer, period: 60.0)
            startContinuousRotation(layer: secondTipStrokeLayer, period: 60.0)
        }
    }

    private func startContinuousRotation(layer: CALayer, period: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.byValue = Double.pi * 2.0
        anim.duration = period
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isAdditive = true
        anim.beginTime = CACurrentMediaTime()
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        layer.add(anim, forKey: "ww_rotation")
    }

    private static func angles(for date: Date) -> (hour: CGFloat, minute: CGFloat, second: CGFloat) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = CGFloat(comps.hour ?? 0)
        let minuteInt = CGFloat(comps.minute ?? 0)
        let secondInt = CGFloat(comps.second ?? 0)
        let nano = CGFloat(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        let secondDeg = sec * 6.0
        let minuteDeg = (minuteInt + (sec / 60.0)) * 6.0
        let hourDeg = (hour12 + (minuteInt / 60.0) + (sec / 3600.0)) * 30.0

        let d2r = (CGFloat.pi / 180.0)
        return (hourDeg * d2r, minuteDeg * d2r, secondDeg * d2r)
    }

    private static func hourWedgePath(width: CGFloat, height: CGFloat) -> CGPath {
        let w = width
        let h = height

        let baseInset = w * 0.035
        let baseLeft = CGPoint(x: baseInset, y: h)
        let baseRight = CGPoint(x: w - baseInset, y: h)
        let tip = CGPoint(x: w * 0.5, y: 0)

        let p = UIBezierPath()
        p.move(to: baseLeft)
        p.addLine(to: tip)
        p.addLine(to: baseRight)
        p.close()
        return p.cgPath
    }

    private static func minuteNeedlePath(width: CGFloat, height: CGFloat) -> CGPath {
        let w = width
        let h = height

        let tipHeight = max(1.0, w * 0.95)
        let shaftTopY = tipHeight
        let shaftInset = w * 0.10

        let bottomLeft = CGPoint(x: shaftInset, y: h)
        let bottomRight = CGPoint(x: w - shaftInset, y: h)

        let shaftTopLeft = CGPoint(x: shaftInset, y: shaftTopY)
        let shaftTopRight = CGPoint(x: w - shaftInset, y: shaftTopY)

        let tip = CGPoint(x: w * 0.5, y: 0)

        let p = UIBezierPath()
        p.move(to: bottomLeft)
        p.addLine(to: shaftTopLeft)
        p.addLine(to: tip)
        p.addLine(to: shaftTopRight)
        p.addLine(to: bottomRight)
        p.close()
        return p.cgPath
    }

    private static func secondHandPath(
        boundsWidth: CGFloat,
        boundsHeight: CGFloat,
        shaftWidth: CGFloat,
        shaftLength: CGFloat,
        tipSide: CGFloat
    ) -> CGPath {
        let w = boundsWidth
        let h = boundsHeight

        let shaftX = (w - shaftWidth) * 0.5
        let shaftY = h - shaftLength
        let shaftRect = CGRect(x: shaftX, y: shaftY, width: shaftWidth, height: shaftLength)

        let tipX = (w - tipSide) * 0.5
        let tipY = h - shaftLength - tipSide
        let tipRect = CGRect(x: tipX, y: tipY, width: tipSide, height: tipSide)

        let p = UIBezierPath(rect: shaftRect)
        p.append(UIBezierPath(rect: tipRect))
        return p.cgPath
    }

    private static func secondTipStrokePath(
        boundsWidth: CGFloat,
        tipSide: CGFloat
    ) -> CGPath {
        let w = boundsWidth
        let tipX = (w - tipSide) * 0.5
        let tipRect = CGRect(x: tipX, y: 0, width: tipSide, height: tipSide)
        return UIBezierPath(rect: tipRect).cgPath
    }
}
