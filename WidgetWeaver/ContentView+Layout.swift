//
//  ContentView+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit

extension ContentView {
    @ViewBuilder
    var editorLayout: some View {
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#if DEBUG
        .overlay(alignment: .topTrailing) {
            editorUITestHooksOverlay
                .zIndex(9_999)
        }
#endif
    }

    var editorForm: some View {
        Form {
            if FeatureFlags.contextAwareEditorToolSuiteEnabled {
                if editorToolContext.selection == .multi {
                    Section {
                        EditorUnavailableStateView(
                            state: EditorUnavailableState.multiSelectionToolListReduced(),
                            isBusy: false
                        )
                    }
                }

                if editorVisibleToolIDs.isEmpty {
                    Section {
                        EditorUnavailableStateView(
                            state: EditorUnavailableState.noToolsAvailableForSelection(),
                            isBusy: false
                        )
                    }
                }
            }

            ForEach(editorVisibleToolIDs, id: \.self) { toolID in
                editorSection(for: toolID)
            }
        }
        .accessibilityIdentifier("Editor.Form")
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

        case .smartPhotoCrop:
            smartPhotoCropSection(focus: $editorFocusSnapshot)

        case .smartRules:
            smartRulesSection(focus: $editorFocusSnapshot)

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

#if DEBUG
    private var uiTestHooksEnabled: Bool {
        UserDefaults.standard.bool(forKey: "widgetweaver.uiTestHooks.enabled")
    }

    @ViewBuilder
    private var editorUITestHooksOverlay: some View {
        if uiTestHooksEnabled {
            VStack(alignment: .trailing, spacing: 8) {
                Button("UI Test: Template Poster") {
                    var draft = currentFamilyDraft()
                    draft.template = .poster
                    setCurrentFamilyDraft(draft)
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
                    editorFocusSnapshot = .smartRuleEditor(albumID: "uiTest.smartPhotoRules")
                }
                .accessibilityIdentifier("EditorUITestHook.focusSmartRules")

                Button("UI Test: Focus Album Container") {
                    editorFocusSnapshot = .smartAlbumContainer(id: "uiTest.albumContainer")
                }
                .accessibilityIdentifier("EditorUITestHook.focusAlbumContainer")

                Button("UI Test: Focus Album Photo Item") {
                    editorFocusSnapshot = .smartAlbumPhotoItem(
                        albumID: "uiTest.album",
                        itemID: "uiTest.photo"
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
                        .albumContainer(id: "uiTest.albumContainer", subtype: .smart),
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
            .font(.caption2)
            .padding(8)
            .opacity(0.08)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("EditorUITestHook.overlayRoot")
            .padding(.top, 6)
            .padding(.trailing, 6)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
#endif
}
