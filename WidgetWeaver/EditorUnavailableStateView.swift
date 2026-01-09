//
//  EditorUnavailableStateView.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import SwiftUI
import UIKit

struct EditorUnavailableStateView: View {
    var state: EditorUnavailableState
    var isBusy: Bool

    /// Handler for non-Link CTAs (requestable permissions, upsells, etc).
    ///
    /// When nil, action-style CTAs are hidden (the message remains visible).
    var onPerformCTA: (@MainActor (EditorUnavailableCTAKind) async -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("EditorUnavailableStateView.Message")

            if let cta = state.cta {
                switch cta.kind {
                case .openAppSettings:
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settingsURL) {
                            Label(cta.title, systemImage: cta.systemImage)
                        }
                        .accessibilityIdentifier("EditorUnavailableStateView.CTA")
                    }

                case .requestPhotosAccess, .showPro:
                    if let onPerformCTA {
                        Button {
                            Task { @MainActor in
                                await onPerformCTA(cta.kind)
                            }
                        } label: {
                            Label(cta.title, systemImage: cta.systemImage)
                        }
                        .accessibilityIdentifier("EditorUnavailableStateView.CTA")
                        .disabled(isBusy)
                    }
                }
            }
        }
    }
}
