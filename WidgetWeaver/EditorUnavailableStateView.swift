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

    /// Handler for requestable Photos permission prompts.
    ///
    /// When nil, the request-style CTA is hidden (the message remains visible).
    var onRequestPhotosAccess: (() async -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let cta = state.cta {
                switch cta.kind {
                case .requestPhotosAccess:
                    if let onRequestPhotosAccess {
                        Button {
                            Task { await onRequestPhotosAccess() }
                        } label: {
                            Label(cta.title, systemImage: cta.systemImage)
                        }
                        .disabled(isBusy)
                    }

                case .openAppSettings:
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: settingsURL) {
                            Label(cta.title, systemImage: cta.systemImage)
                        }
                    }
                }
            }
        }
    }
}
