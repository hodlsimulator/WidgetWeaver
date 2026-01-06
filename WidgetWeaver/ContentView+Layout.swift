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
        Form {
            ForEach(editorVisibleToolIDs, id: \.self) { toolID in
                editorSection(for: toolID)
            }
        }
        .font(.subheadline)
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, 36)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.15), value: editorVisibleToolIDs)
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
            textSection

        case .symbol:
            symbolSection

        case .image:
            imageSection

        case .smartPhoto:
            smartPhotoSection(focus: $editorFocusSnapshot)

        case .albumShuffle:
            albumShuffleSection

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

    func previewDock(presentation: WidgetPreviewDock.Presentation) -> some View {
        WidgetPreviewDock(
            spec: draftSpec(id: selectedSpecID),
            family: $previewFamily,
            presentation: presentation
        )
    }
}
