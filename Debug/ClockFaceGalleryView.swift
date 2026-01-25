//
//  ClockFaceGalleryView.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

#if DEBUG

import SwiftUI

/// DEBUG-only clock face gallery used for visual regression.
///
/// The gallery renders the clock face at multiple fixed square sizes so one screenshot
/// can serve as the baseline artefact.
struct ClockFaceGalleryView: View {
    let config: WidgetWeaverClockDesignConfig

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let c = config.normalised()
        let resolved = WidgetWeaverClockAppearanceResolver.resolve(config: c, mode: colorScheme)

        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                ClockFaceGalleryHeaderView(
                    schemeName: resolved.schemeDisplayName,
                    faceName: c.faceToken.displayName
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ClockFaceGalleryGrid(
                    face: c.faceToken,
                    palette: resolved.palette
                )
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .navigationTitle("Clock Face Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct ClockFaceGalleryHeaderView: View {
    let schemeName: String
    let faceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scheme: \(schemeName)")
                .font(.headline)

            Text("Face: \(faceName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Capture one screenshot as the baseline artefact (suggested path: Docs/ClockFaceBaseline.png).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClockFaceGalleryGrid: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Spacer(minLength: 0)
                ClockFaceGalleryCell(side: 200, face: face, palette: palette)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                ClockFaceGalleryCell(side: 160, face: face, palette: palette)
                ClockFaceGalleryCell(side: 120, face: face, palette: palette)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                ClockFaceGalleryCell(side: 80, face: face, palette: palette)
                ClockFaceGalleryCell(side: 60, face: face, palette: palette)
                ClockFaceGalleryCell(side: 44, face: face, palette: palette)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ClockFaceGalleryCell: View {
    let side: CGFloat
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette

    private var cornerRadius: CGFloat { max(10, side * 0.08) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                WidgetWeaverClockBackgroundView(palette: palette)

                WidgetWeaverClockFaceView(
                    face: face,
                    palette: palette,
                    hourAngle: .degrees(305.0),
                    minuteAngle: .degrees(60.0),
                    secondAngle: .degrees(210.0),
                    showsSecondHand: true,
                    showsMinuteHand: true,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: true,
                    handsOpacity: 1.0
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )

            Text("\(Int(side))pt")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clock face preview at \(Int(side)) points")
    }
}

#endif
