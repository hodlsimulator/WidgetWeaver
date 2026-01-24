//
//  PosterSuiteStage1Controls.swift
//  WidgetWeaver
//
//  Created by . . on 1/23/26.
//

import SwiftUI

struct PosterSuiteStage1Controls: View {
    @Binding var posterOverlayMode: PosterOverlayMode
    @Binding var alignment: LayoutAlignmentToken
    @Binding var imageContentMode: ImageContentModeToken
    @Binding var styleDraft: StyleDraft

    private var isCaptionEnabled: Bool {
        posterOverlayMode == .caption
    }

    private var captionPositionBinding: Binding<Bool> {
        Binding(
            get: { alignment.isPosterCaptionTopAligned },
            set: { wantsTop in
                alignment = wantsTop
                    ? Self.topAlignedToken(from: alignment)
                    : Self.bottomAlignedToken(from: alignment)
            }
        )
    }

    private var wantsGlassCaptionBinding: Binding<Bool> {
        Binding(
            get: {
                styleDraft.backgroundOverlay == .subtleMaterial
                    && styleDraft.backgroundOverlayOpacity <= 0.0001
            },
            set: { wantsGlass in
                if wantsGlass {
                    styleDraft.backgroundOverlay = .subtleMaterial
                    styleDraft.backgroundOverlayOpacity = 0
                } else {
                    // Existing poster defaults use the scrim treatment with no full-screen overlay.
                    styleDraft.backgroundOverlay = .plain
                    styleDraft.backgroundOverlayOpacity = 0
                }
            }
        )
    }

    var body: some View {
        Group {
            Picker("Overlay content", selection: $posterOverlayMode) {
                Text("None").tag(PosterOverlayMode.none)
                Text("Caption").tag(PosterOverlayMode.caption)
            }
            .pickerStyle(.segmented)

            Picker("Caption position", selection: captionPositionBinding) {
                Text("Bottom").tag(false)
                Text("Top").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!isCaptionEnabled)

            Picker("Caption style", selection: wantsGlassCaptionBinding) {
                Text("Scrim").tag(false)
                Text("Glass").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!isCaptionEnabled)

            Picker("Treatment", selection: $imageContentMode) {
                Text("Full-bleed").tag(ImageContentModeToken.fill)
                Text("Framed").tag(ImageContentModeToken.fit)
            }
            .pickerStyle(.segmented)
        }
    }

    private static func topAlignedToken(from token: LayoutAlignmentToken) -> LayoutAlignmentToken {
        switch token {
        case .leading, .topLeading:
            return .topLeading
        case .centre, .top:
            return .top
        case .trailing, .topTrailing:
            return .topTrailing
        }
    }

    private static func bottomAlignedToken(from token: LayoutAlignmentToken) -> LayoutAlignmentToken {
        switch token {
        case .topLeading:
            return .leading
        case .top:
            return .centre
        case .topTrailing:
            return .trailing
        case .leading, .centre, .trailing:
            return token
        }
    }
}
