//
//  ContentView+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

//
//  ContentView+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 11/6/24.
//

import SwiftUI

extension ContentView {
    var editorRoot: some View {
        NavigationStack {
            Form {
                if FeatureFlags.contextAwareEditorToolSuiteEnabled, editorToolContext.selection == .multi {
                    Section {
                        EditorUnavailableStateView(
                            unavailable: .multiSelectionToolListReduced,
                            open: { _ in }
                        )
                    }
                }

                ForEach(editorVisibleToolIDs, id: \.rawValue) { toolID in
                    toolSection(toolID)
                }

#if DEBUG
                if FeatureFlags.uiTestHooksEnabled {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("UI Test: Template Poster") {
                                baseDraft.template = .poster
                                baseDraft.layout.style = .poster
                                saveStatusMessage = "Selected template: poster"
                            }
                            .accessibilityIdentifier("EditorUITestHook.templatePoster")

                            Button("UI Test: Focus Widget") {
                                editorFocusSnapshot = .widgetDefault
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusWidget")

                            Button("UI Test: Focus Smart Photo Crop") {
                                editorFocusSnapshot = .singleNonAlbumElement(id: "smartPhotoCrop")
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusSmartPhotoCrop")

                            Button("UI Test: Focus Smart Rules") {
                                editorFocusSnapshot = .smartRuleEditor
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusSmartRules")

                            Button("UI Test: Focus Smart Album Container") {
                                editorFocusSnapshot = .smartAlbumContainer(id: "uiTest.smartAlbumContainer")
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusAlbumContainer")

                            Button("UI Test: Focus Smart Album Photo Item") {
                                editorFocusSnapshot = .smartAlbumPhotoItem(
                                    albumID: "uiTest.smartAlbumContainer",
                                    itemID: "uiTest.smartAlbumPhotoItem"
                                )
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusAlbumPhotoItem")

                            Button("UI Test: Multi-select Widgets") {
                                let selection = EditorSelectionSet(items: [
                                    .nonAlbumElement(id: "uiTest.widgetA"),
                                    .nonAlbumElement(id: "uiTest.widgetB"),
                                ])
                                editorFocusSnapshot = selection.toFocusSnapshot()
                            }
                            .accessibilityIdentifier("EditorUITestHook.multiSelectWidgets")

                            Button("UI Test: Multi-select Mixed") {
                                let selection = EditorSelectionSet(items: [
                                    .albumContainer(id: "uiTest.smartAlbumContainer", subtype: .smart),
                                    .nonAlbumElement(id: "uiTest.widgetA"),
                                    .nonAlbumElement(id: "uiTest.widgetB"),
                                ])
                                editorFocusSnapshot = selection.toFocusSnapshot()
                            }
                            .accessibilityIdentifier("EditorUITestHook.multiSelectMixed")

                            Button("UI Test: Focus Clock") {
                                editorFocusSnapshot = .clockFocus()
                            }
                            .accessibilityIdentifier("EditorUITestHook.focusClock")
                        }
                    } header: {
                        Text("UI Test Hooks")
                            .accessibilityIdentifier("EditorSectionHeader.UITestHooks")
                    }
                }
#endif
            }
            .navigationTitle("Editor")
        }
    }
}
