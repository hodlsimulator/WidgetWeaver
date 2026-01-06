//
//  ContentView+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import SwiftUI

extension ContentView {
    private var editorVisibleToolIDs: [EditorToolID] {
        let template = currentFamilyDraft().template

        let capabilities = EditorCapability.derived(for: template)
        let selection = editorFocusSnapshot.selection
        let focus = editorFocusSnapshot.focus
        let focusGroup = focus.editorToolFocusGroup

        let context = EditorToolContext(
            selection: selection,
            focus: focus,
            focusGroup: focusGroup,
            capabilities: capabilities
        )

        return EditorToolRegistry.visibleTools(for: context)
    }

    var editorToolSurface: some View {
        Form {
            // Tool surface is now data-driven by editorVisibleToolIDs.
            ForEach(editorVisibleToolIDs, id: \.self) { toolID in
                switch toolID {
                case .layout:
                    layoutSection

                case .padding:
                    paddingSection

                case .background:
                    backgroundSection

                case .border:
                    borderSection

                case .text:
                    textSection

                case .typography:
                    typographySection

                case .symbols:
                    symbolsSection

                case .image:
                    imageSection

                case .smartPhoto:
                    smartPhotoSection(focus: $editorFocusSnapshot)

                case .smartPhotoCrop:
                    smartPhotoCropSection(focus: $editorFocusSnapshot)

        case .smartRules:
            smartRulesSection(focus: $editorFocusSnapshot)

        case .albumShuffle:
                    albumShuffleSection

                case .style:
                    styleSection

                case .actions:
                    actionsSection
                }
            }
        }
    }
}
