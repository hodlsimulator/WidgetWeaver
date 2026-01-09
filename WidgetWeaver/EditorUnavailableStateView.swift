//
//  EditorUnavailableStateView.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import SwiftUI

struct EditorUnavailableStateView: View {
    let state: EditorUnavailableState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("EditorUnavailableStateView.Message")

            if let action = state.action {
                switch action {
                case .requestPro:
                    Text("Pro required.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .openURL(let url, let title):
                    Link(title, destination: url)
                        .font(.caption)

                case .openAppSettings:
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settingsURL)
                            .font(.caption)
                            .accessibilityIdentifier("EditorUnavailableStateView.CTA")
                    }
                case .custom(let title, let handler):
                    Button(title) {
                        handler()
                    }
                    .font(.caption)
                    .accessibilityIdentifier("EditorUnavailableStateView.CTA")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
