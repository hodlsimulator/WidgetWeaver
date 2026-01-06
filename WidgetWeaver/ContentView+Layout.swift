//
//  ContentView+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import WidgetKit

extension ContentView {
    @ViewBuilder
    var editorLayout: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 16) {
                previewDock(presentation: .sidebar)
                    .frame(width: 420)
                    .padding(.top, 8)

                editorForm
            }
            .padding(.horizontal, 16)
        } else {
            editorForm
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: WidgetPreviewDock.reservedInsetHeight(verticalSizeClass: verticalSizeClass))
                }
                .overlay(alignment: .bottom) {
                    previewDock(presentation: .dock)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
        }
    }

    var editorForm: some View {
        let visibleTools = editorVisibleToolIDs

        return Form {
            ForEach(visibleTools, id: \.self) { toolID in
                editorSection(for: toolID)
            }
        }
        .font(.subheadline)
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, 36)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.15), value: visibleTools)
    }

    @ViewBuilder
    private func editorSection(for toolID: EditorToolID) -> some View {
        switch toolID {
        case .status:
            statusSection

        case .designs:
            designsSection

        case .widgets:
            widgetWorkflowSection

        case .layout:
            layoutSection

        case .text:
            editorTextSection

        case .symbol:
            symbolSection

        case .image:
            imageSection

        case .style:
            styleSection

        case .typography:
            typographySection

        case .actions:
            actionsSection

        case .matchedSet:
            matchedSetSection

        case .variables:
            variablesManagerSection

        case .sharing:
            sharingSection

        case .ai:
            aiSection

        case .pro:
            proSection
        }
    }

    private var editorTextSection: some View {
        let template = currentFamilyDraft().template

        return Section {
            TextField("Design name", text: $designName)
                .textInputAutocapitalization(.words)

            switch template {
            case .nextUpCalendar:
                Text("This template is driven by Calendar events.\nUse Style/Background to customise the look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .weather:
                TextField("Title (optional)", text: binding(\.primaryText))

                Text("The title is shown in the Weather template’s empty state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .classic, .hero, .poster:
                TextField("Primary text", text: binding(\.primaryText))
                TextField("Secondary text (optional)", text: binding(\.secondaryText))

                if matchedSetEnabled {
                    Text("Text fields are currently editing: \(editingFamilyLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Text")
        }
    }

    func previewDock(presentation: WidgetPreviewDock.Presentation) -> some View {
        WidgetPreviewDock(
            spec: draftSpec(id: selectedSpecID),
            family: $previewFamily,
            presentation: presentation
        )
    }
}
