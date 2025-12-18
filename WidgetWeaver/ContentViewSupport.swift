//
//  ContentViewSupport.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import UIKit

struct WidgetWorkflowHelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Widgets update when the saved design changes and WidgetKit reloads timelines.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("How widgets update")
                }

                Section {
                    Text("Each widget instance can follow \"Default (App)\" or a specific saved design.")
                        .foregroundStyle(.secondary)
                    Text("To change this: long-press the widget → Edit Widget → Design.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Design selection")
                }

                Section {
                    Text("Try \"Refresh Widgets\" in the app, then wait a moment.")
                        .foregroundStyle(.secondary)
                    Text("If it still doesn’t update, reselect the Design in Edit Widget. Removing and re-adding the widget is only needed after major schema changes.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("If a widget doesn’t change")
                }
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct EditorBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 640
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 760
            )
            .ignoresSafeArea()
        }
    }
}

enum Keyboard {
    static func dismiss() {
        Task { @MainActor in
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}
