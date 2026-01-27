//
//  WidgetWeaverClockFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import SwiftUI

/// Central router for selecting a clock face renderer from a `WidgetWeaverClockFaceToken`.
struct WidgetWeaverClockFaceView: View {
    let face: WidgetWeaverClockFaceToken

    let palette: WidgetWeaverClockPalette

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    let showsSecondHand: Bool
    let showsMinuteHand: Bool
    let showsHandShadows: Bool
    let showsGlows: Bool
    let showsCentreHub: Bool

    let handsOpacity: Double

    init(
        face: WidgetWeaverClockFaceToken,
        palette: WidgetWeaverClockPalette,
        hourAngle: Angle = .degrees(310.0),
        minuteAngle: Angle = .degrees(120.0),
        secondAngle: Angle = .degrees(180.0),
        showsSecondHand: Bool = true,
        showsMinuteHand: Bool = true,
        showsHandShadows: Bool = true,
        showsGlows: Bool = true,
        showsCentreHub: Bool = true,
        handsOpacity: Double = 1.0
    ) {
        self.face = face
        self.palette = palette
        self.hourAngle = hourAngle
        self.minuteAngle = minuteAngle
        self.secondAngle = secondAngle
        self.showsSecondHand = showsSecondHand
        self.showsMinuteHand = showsMinuteHand
        self.showsHandShadows = showsHandShadows
        self.showsGlows = showsGlows
        self.showsCentreHub = showsCentreHub
        self.handsOpacity = handsOpacity
    }

    var body: some View {
        switch face {
        case .ceramic:
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                showsSecondHand: showsSecondHand,
                showsMinuteHand: showsMinuteHand,
                showsHandShadows: showsHandShadows,
                showsGlows: showsGlows,
                showsCentreHub: showsCentreHub,
                handsOpacity: handsOpacity
            )

        case .icon:
            WidgetWeaverClockIconFaceView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                showsSecondHand: showsSecondHand,
                showsMinuteHand: showsMinuteHand,
                showsHandShadows: showsHandShadows,
                showsGlows: showsGlows,
                showsCentreHub: showsCentreHub,
                handsOpacity: handsOpacity
            )

        case .segmented:
            WidgetWeaverClockSegmentedFaceView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                showsSecondHand: showsSecondHand,
                showsMinuteHand: showsMinuteHand,
                showsHandShadows: showsHandShadows,
                showsGlows: showsGlows,
                showsCentreHub: showsCentreHub,
                handsOpacity: handsOpacity
            )
        }
    }
}
