//
//  IconClockFaceGlyphView.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import SwiftUI

public struct IconClockHandAngles: Equatable, Sendable {
    public var hour: Angle
    public var minute: Angle
    public var second: Angle

    public init(hour: Angle, minute: Angle, second: Angle) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// Convenience for previews and standalone usage.
    /// Angle convention: 0° points to 12 o’clock, positive rotates clockwise.
    public static func from(date: Date, calendar: Calendar = .autoupdatingCurrent) -> IconClockHandAngles {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let ns = calendar.component(.nanosecond, from: date)

        let seconds = Double(s) + (Double(ns) / 1_000_000_000.0)
        let hours = Double(h % 12)

        let hourDeg = (hours + (Double(m) / 60.0) + (seconds / 3600.0)) * 30.0
        let minuteDeg = (Double(m) + (seconds / 60.0)) * 6.0
        let secondDeg = seconds * 6.0

        return IconClockHandAngles(
            hour: .degrees(hourDeg),
            minute: .degrees(minuteDeg),
            second: .degrees(secondDeg)
        )
    }

    public static func accessibilityLabel(for date: Date) -> String {
        if #available(iOS 15.0, *) {
            return date.formatted(date: .omitted, time: .standard)
        } else {
            let df = DateFormatter()
            df.dateStyle = .none
            df.timeStyle = .medium
            return df.string(from: date)
        }
    }
}

public struct IconClockFaceGlyphView: View {
    public var angles: IconClockHandAngles
    public var showsSeconds: Bool

    /// Glyph images for minute + second hands.
    /// Expected glyph orientation: pointing up, with pivot at bottom-centre of its bounds.
    /// A transparent background is expected.
    public var minuteHandGlyph: Image
    public var secondHandGlyph: Image

    public init(
        angles: IconClockHandAngles,
        minuteHandGlyph: Image,
        secondHandGlyph: Image,
        showsSeconds: Bool = true
    ) {
        self.angles = angles
        self.minuteHandGlyph = minuteHandGlyph
        self.secondHandGlyph = secondHandGlyph
        self.showsSeconds = showsSeconds
    }

    /// Convenience initialiser intended for previews and basic usage.
    /// For “same mechanism” integration, prefer the `angles:` initialiser.
    public init(
        date: Date,
        minuteHandGlyph: Image,
        secondHandGlyph: Image,
        showsSeconds: Bool = true,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.angles = .from(date: date, calendar: calendar)
        self.minuteHandGlyph = minuteHandGlyph
        self.secondHandGlyph = secondHandGlyph
        self.showsSeconds = showsSeconds
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                IconClockBezel(size: size)
                IconClockDial(size: size)

                IconClockTickMarks(size: size)
                IconClockNumbers(size: size)

                IconClockHandsGlyphMinuteSecond(
                    size: size,
                    angles: angles,
                    minuteHandGlyph: minuteHandGlyph,
                    secondHandGlyph: secondHandGlyph,
                    showsSeconds: showsSeconds
                )

                IconClockCentreCap(size: size)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2.0, y: geo.size.height / 2.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(IconClockHandAngles.accessibilityLabel(for: Date())))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Palette

private enum IconClockPalette {
    static let dialTop = Color(red: 0.22, green: 0.29, blue: 0.38)
    static let dialMid = Color(red: 0.17, green: 0.23, blue: 0.30)
    static let dialBottom = Color(red: 0.11, green: 0.15, blue: 0.20)

    static let bezelOuterDark = Color(red: 0.03, green: 0.04, blue: 0.05)
    static let bezelOuterMid = Color(red: 0.18, green: 0.21, blue: 0.25)
    static let bezelHighlight = Color(red: 0.93, green: 0.95, blue: 0.98)

    static let tick = Color(white: 0.92).opacity(0.95)
    static let tickMinor = Color(white: 0.90).opacity(0.75)

    static let numberFill = Color(white: 0.92)
    static let numberShadow = Color.black.opacity(0.70)
    static let numberHighlight = Color.white.opacity(0.25)

    static let handLight = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let handMid = Color(red: 0.76, green: 0.79, blue: 0.83)
    static let handDark = Color(red: 0.46, green: 0.50, blue: 0.56)
    static let handEdge = Color.black.opacity(0.35)

    static let secondRed = Color(red: 0.96, green: 0.22, blue: 0.26)

    static let centreOuterDark = Color(red: 0.10, green: 0.12, blue: 0.14)
    static let centreOuterMid = Color(red: 0.22, green: 0.25, blue: 0.29)
    static let centreInnerLight = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let centreInnerMid = Color(red: 0.70, green: 0.73, blue: 0.78)
    static let centreStroke = Color.black.opacity(0.55)

    static func metalGradient(size: CGFloat) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: handLight, location: 0.00),
                .init(color: handMid, location: 0.50),
                .init(color: handDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Layout helpers

private enum IconClockLayout {
    static func dialInset(for size: CGFloat) -> CGFloat { size * 0.075 }
    static func dialRadius(for size: CGFloat) -> CGFloat { (size / 2.0) - dialInset(for: size) }

    static func tickRingInset(for size: CGFloat) -> CGFloat { dialInset(for: size) + (size * 0.022) }
    static func tickRadius(for size: CGFloat) -> CGFloat { (size / 2.0) - tickRingInset(for: size) }

    static func numberRadius(for size: CGFloat) -> CGFloat { dialRadius(for: size) * 0.78 }

    static func hourHandLength(for size: CGFloat) -> CGFloat { dialRadius(for: size) * 0.53 }
    static func minuteHandLength(for size: CGFloat) -> CGFloat { dialRadius(for: size) * 0.80 }
    static func secondHandLength(for size: CGFloat) -> CGFloat { dialRadius(for: size) * 0.90 }

    static func hourHandWidth(for size: CGFloat) -> CGFloat { size * 0.075 }
    static func minuteHandWidth(for size: CGFloat) -> CGFloat { size * 0.060 }
    static func secondHandWidth(for size: CGFloat) -> CGFloat { max(1.0, size * 0.012) }

    static func centreOuterRadius(for size: CGFloat) -> CGFloat { size * 0.060 }
    static func centreInnerRadius(for size: CGFloat) -> CGFloat { size * 0.037 }
}

// MARK: - Bezel + dial

private struct IconClockBezel: View {
    let size: CGFloat

    var body: some View {
        let outerStroke = size * 0.020
        let innerStroke = size * 0.010

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: IconClockPalette.bezelHighlight.opacity(0.55), location: 0.00),
                            .init(color: IconClockPalette.bezelOuterMid, location: 0.40),
                            .init(color: IconClockPalette.bezelOuterDark, location: 1.00)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .shadow(color: Color.black.opacity(0.65), radius: size * 0.030, x: 0, y: size * 0.020)

            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: IconClockPalette.bezelHighlight.opacity(0.85), location: 0.00),
                            .init(color: IconClockPalette.bezelOuterMid.opacity(0.85), location: 0.18),
                            .init(color: IconClockPalette.bezelOuterDark.opacity(0.95), location: 0.40),
                            .init(color: IconClockPalette.bezelOuterMid.opacity(0.80), location: 0.72),
                            .init(color: IconClockPalette.bezelHighlight.opacity(0.75), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    lineWidth: outerStroke
                )
                .blendMode(.overlay)

            Circle()
                .inset(by: outerStroke * 0.85)
                .strokeBorder(Color.black.opacity(0.65), lineWidth: innerStroke)
        }
    }
}

private struct IconClockDial: View {
    let size: CGFloat

    var body: some View {
        let inset = IconClockLayout.dialInset(for: size)

        ZStack {
            Circle()
                .inset(by: inset)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: IconClockPalette.dialTop, location: 0.00),
                            .init(color: IconClockPalette.dialMid, location: 0.55),
                            .init(color: IconClockPalette.dialBottom, location: 1.00)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .inset(by: inset)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.12), location: 0.00),
                            .init(color: Color.white.opacity(0.03), location: 0.40),
                            .init(color: Color.black.opacity(0.28), location: 1.00)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.80
                    )
                )
                .blendMode(.overlay)

            Circle()
                .inset(by: inset + (size * 0.006))
                .strokeBorder(Color.black.opacity(0.40), lineWidth: size * 0.010)

            Circle()
                .inset(by: inset + (size * 0.020))
                .strokeBorder(Color.white.opacity(0.10), lineWidth: size * 0.004)
        }
    }
}

// MARK: - Tick marks + numbers

private struct IconClockTickMarks: View {
    let size: CGFloat

    var body: some View {
        let radius = IconClockLayout.tickRadius(for: size)
        let majorHeight = size * 0.060
        let minorHeight = size * 0.030

        ZStack {
            ForEach(0..<60, id: \.self) { idx in
                let isMajor = (idx % 5 == 0)
                let height = isMajor ? majorHeight : minorHeight
                let width = isMajor ? (size * 0.012) : (size * 0.004)
                let yOffset = -(radius - (height / 2.0))

                RoundedRectangle(cornerRadius: width * 0.40, style: .continuous)
                    .fill(isMajor ? IconClockPalette.tick : IconClockPalette.tickMinor)
                    .frame(width: width, height: height)
                    .shadow(
                        color: Color.black.opacity(isMajor ? 0.35 : 0.20),
                        radius: isMajor ? (size * 0.004) : (size * 0.002),
                        x: 0,
                        y: isMajor ? (size * 0.002) : (size * 0.001)
                    )
                    .offset(y: yOffset)
                    .rotationEffect(.degrees(Double(idx) * 6.0))
            }
        }
        .drawingGroup()
    }
}

private struct IconClockNumbers: View {
    let size: CGFloat

    var body: some View {
        let numberRadius = IconClockLayout.numberRadius(for: size)
        let fontSize = size * 0.115

        ZStack {
            ForEach(1..<13, id: \.self) { n in
                Text("\(n)")
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundColor(IconClockPalette.numberFill)
                    .shadow(color: IconClockPalette.numberShadow, radius: 0, x: size * 0.004, y: size * 0.004)
                    .shadow(color: IconClockPalette.numberHighlight, radius: 0, x: -size * 0.002, y: -size * 0.002)
                    .rotationEffect(.degrees(Double(n) * 30.0))
                    .offset(y: -numberRadius)
                    .rotationEffect(.degrees(-Double(n) * 30.0))
            }
        }
        .drawingGroup()
    }
}

// MARK: - Hands (hour is SwiftUI; minute + second are glyph Images)

private struct IconClockHandsGlyphMinuteSecond: View {
    let size: CGFloat
    let angles: IconClockHandAngles
    let minuteHandGlyph: Image
    let secondHandGlyph: Image
    let showsSeconds: Bool

    var body: some View {
        ZStack {
            IconMetalHand(
                size: size,
                length: IconClockLayout.hourHandLength(for: size),
                width: IconClockLayout.hourHandWidth(for: size),
                tipWidthFraction: 0.42
            )
            .rotationEffect(angles.hour)

            IconGlyphHand(
                size: size,
                length: IconClockLayout.minuteHandLength(for: size),
                width: IconClockLayout.minuteHandWidth(for: size),
                angle: angles.minute,
                glyph: minuteHandGlyph,
                fill: AnyView(IconClockPalette.metalGradient(size: size))
            )

            if showsSeconds {
                IconGlyphHand(
                    size: size,
                    length: IconClockLayout.secondHandLength(for: size),
                    width: IconClockLayout.secondHandWidth(for: size),
                    angle: angles.second,
                    glyph: secondHandGlyph,
                    fill: AnyView(IconClockPalette.secondRed)
                )
            }
        }
    }
}

private struct IconGlyphHand: View {
    let size: CGFloat
    let length: CGFloat
    let width: CGFloat
    let angle: Angle
    let glyph: Image
    let fill: AnyView

    private func glyphShape() -> some View {
        glyph
            .resizable()
            .scaledToFit()
    }

    var body: some View {
        let highlightOffset = CGSize(width: -size * 0.002, height: -size * 0.002)
        let shadowOffset = CGSize(width: size * 0.003, height: size * 0.003)

        ZStack {
            fill
                .mask(glyphShape())

            Color.white.opacity(0.22)
                .mask(glyphShape())
                .offset(highlightOffset)

            Color.black.opacity(0.40)
                .mask(glyphShape())
                .offset(shadowOffset)
        }
        .frame(width: width, height: length)
        .shadow(color: Color.black.opacity(0.45), radius: width * 0.35, x: width * 0.08, y: width * 0.15)
        .rotationEffect(angle, anchor: .bottom)
        .offset(y: -(length / 2.0))
        .drawingGroup()
    }
}

private struct IconMetalHand: View {
    let size: CGFloat
    let length: CGFloat
    let width: CGFloat
    let tipWidthFraction: CGFloat

    var body: some View {
        let edgeLine = max(1.0, width * 0.06)
        let baseBlockHeight = width * 0.42
        let baseBlockWidth = width * 0.96

        ZStack(alignment: .bottom) {
            TaperedHandShape(tipWidthFraction: tipWidthFraction)
                .fill(IconClockPalette.metalGradient(size: size))
                .overlay(
                    TaperedHandShape(tipWidthFraction: tipWidthFraction)
                        .strokeBorder(IconClockPalette.handEdge, lineWidth: edgeLine)
                )
                .shadow(color: Color.black.opacity(0.45),
                        radius: width * 0.35,
                        x: width * 0.08,
                        y: width * 0.15)

            RoundedRectangle(cornerRadius: baseBlockHeight * 0.25, style: .continuous)
                .fill(IconClockPalette.metalGradient(size: size))
                .frame(width: baseBlockWidth, height: baseBlockHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: baseBlockHeight * 0.25, style: .continuous)
                        .strokeBorder(IconClockPalette.handEdge, lineWidth: edgeLine)
                )
                .shadow(color: Color.black.opacity(0.35),
                        radius: width * 0.20,
                        x: width * 0.06,
                        y: width * 0.10)
        }
        .frame(width: width, height: length)
        .offset(y: -(length / 2.0))
        .drawingGroup()
    }
}

private struct TaperedHandShape: InsettableShape {
    var tipWidthFraction: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w0 = max(1.0, rect.width - (insetAmount * 2.0))
        let w1 = max(1.0, w0 * max(0.12, min(0.95, tipWidthFraction)))
        let h = max(1.0, rect.height - (insetAmount * 2.0))

        let cx = rect.midX
        let topY = rect.minY + insetAmount
        let bottomY = rect.minY + insetAmount + h

        let baseLeft = CGPoint(x: cx - (w0 / 2.0), y: bottomY)
        let baseRight = CGPoint(x: cx + (w0 / 2.0), y: bottomY)
        let tipLeft = CGPoint(x: cx - (w1 / 2.0), y: topY)
        let tipRight = CGPoint(x: cx + (w1 / 2.0), y: topY)

        var p = Path()
        p.move(to: baseLeft)
        p.addLine(to: tipLeft)
        p.addLine(to: tipRight)
        p.addLine(to: baseRight)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// MARK: - Centre cap

private struct IconClockCentreCap: View {
    let size: CGFloat

    var body: some View {
        let outerR = IconClockLayout.centreOuterRadius(for: size)
        let innerR = IconClockLayout.centreInnerRadius(for: size)

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: IconClockPalette.centreOuterMid, location: 0.00),
                            .init(color: IconClockPalette.centreOuterDark, location: 1.00)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: outerR * 2.2
                    )
                )
                .frame(width: outerR * 2.0, height: outerR * 2.0)
                .overlay(
                    Circle()
                        .strokeBorder(IconClockPalette.centreStroke, lineWidth: max(1.0, size * 0.006))
                )
                .shadow(color: Color.black.opacity(0.55), radius: size * 0.010, x: 0, y: size * 0.006)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: IconClockPalette.centreInnerLight, location: 0.00),
                            .init(color: IconClockPalette.centreInnerMid, location: 0.75),
                            .init(color: IconClockPalette.handDark.opacity(0.85), location: 1.00)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: innerR * 2.0
                    )
                )
                .frame(width: innerR * 2.0, height: innerR * 2.0)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.30), lineWidth: max(1.0, size * 0.003))
                )
        }
        .drawingGroup()
    }
}

// MARK: - Preview

struct IconClockFaceGlyphView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDateComponents = DateComponents(calendar: .autoupdatingCurrent, year: 2026, month: 1, day: 20, hour: 10, minute: 10, second: 30)
        let previewDate = previewDateComponents.date ?? Date()

        VStack(spacing: 24) {
            IconClockFaceGlyphView(
                date: previewDate,
                minuteHandGlyph: Image(systemName: "arrow.up"),
                secondHandGlyph: Image(systemName: "line.vertical"),
                showsSeconds: true
            )
            .frame(width: 280, height: 280)

            IconClockFaceGlyphView(
                angles: .from(date: Date()),
                minuteHandGlyph: Image(systemName: "arrow.up"),
                secondHandGlyph: Image(systemName: "line.vertical"),
                showsSeconds: true
            )
            .frame(width: 140, height: 140)
        }
        .padding()
        .background(Color.black.opacity(0.10))
        .previewLayout(.sizeThatFits)
    }
}
