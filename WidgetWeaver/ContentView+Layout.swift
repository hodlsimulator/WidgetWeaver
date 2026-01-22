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
        .overlay(alignment: .bottomTrailing) {
            editorUITestHooksOverlay
                .zIndex(9_999)
        }
#endif
    }

    var editorForm: some View {
        Form {
            if FeatureFlags.contextAwareEditorToolSuiteEnabled {
                widgetListSelectionSection

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

    private var widgetListSelectionSection: some View {
        Section {
            EditorWidgetListSelectionSurface(
                focus: $editorFocusSnapshot,
                rows: widgetListSelectionRows
            )
        } header: {
            sectionHeader("Widget list")
        } footer: {
            Text("Selection sets the editor context. Multi-select to enter a reduced tool mode that only shows set-safe tools.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var widgetListSelectionRows: [EditorWidgetListSelectionSurface.Row] {
        let draft = currentFamilyDraft()

        if draft.template == .clockIcon {
            return [
                EditorWidgetListSelectionSurface.Row(
                    id: "clock",
                    title: "Clock",
                    subtitle: "Clock editor",
                    item: .clock,
                    accessibilityID: "EditorWidgetListSelection.Item.clock"
                ),
            ]
        }

        var out: [EditorWidgetListSelectionSurface.Row] = [
            EditorWidgetListSelectionSurface.Row(
                id: "text",
                title: "Text element",
                subtitle: "Non‑album selection",
                item: .nonAlbumElement(id: "widgetweaver.element.text"),
                accessibilityID: "EditorWidgetListSelection.Item.text"
            ),
            EditorWidgetListSelectionSurface.Row(
                id: "layout",
                title: "Layout element",
                subtitle: "Non‑album selection",
                item: .nonAlbumElement(id: "widgetweaver.element.layout"),
                accessibilityID: "EditorWidgetListSelection.Item.layout"
            ),
        ]

        if draft.template == .poster {
            let (albumID, subtitle) = resolvedSmartAlbumContainerSelection(from: draft)

            out.append(
                EditorWidgetListSelectionSurface.Row(
                    id: "smartAlbum",
                    title: "Smart Photos (album container)",
                    subtitle: subtitle,
                    item: .albumContainer(id: albumID, subtype: .smart),
                    accessibilityID: "EditorWidgetListSelection.Item.smartAlbumContainer"
                )
            )
        }

        return out
    }


    private func resolvedSmartAlbumContainerSelection(from draft: FamilyDraft) -> (albumID: String, subtitle: String) {
        let fallbackAlbumID = "smartPhoto.album"

        guard
            let manifestFileName = draft.imageSmartPhoto?.shuffleManifestFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !manifestFileName.isEmpty,
            let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName)
        else {
            return (fallbackAlbumID, "Not configured")
        }

        let rawSourceID = manifest.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawSourceID.isEmpty {
            return (fallbackAlbumID, "Not configured")
        }

        return (rawSourceID, "Album ID: \(rawSourceID)")
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
            layoutSectionClockAware

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


    // MARK: - Layout tool (clock-safe)

    /// Provides a clock-safe Layout section.
    ///
    /// The legacy layout section exposes controls that do not apply to the element-less clock template.
    /// This wrapper keeps the Layout tool available (so the user can switch templates) while reducing
    /// the UI surface when `template == .clockIcon`.
    @ViewBuilder
    private var layoutSectionClockAware: some View {
        let currentTemplate = currentFamilyDraft().template

        if currentTemplate != .clockIcon {
            layoutSection
        } else {
            let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled

            let templateTokens: [LayoutTemplateToken] = {
                var tokens = LayoutTemplateToken.allCases.filter { token in
                    // Reminders is feature-flag gated.
                    return remindersEnabled || token != .reminders
                }

                // If a hidden template is already selected (eg. imported design), include it so the
                // picker has a matching tag. Do not expose it as selectable when the flag is off.
                if !remindersEnabled, currentTemplate == .reminders, !tokens.contains(.reminders) {
                    tokens.append(.reminders)
                }

                return tokens
            }()

            Section {
                WidgetWeaverClockFaceSelector(
                    clockFaceRaw: binding(\.clockFaceRaw),
                    clockThemeRaw: currentFamilyDraft().clockThemeRaw
                )
                .accessibilityIdentifier("Editor.Clock.FaceSelector")

                Picker("Clock theme", selection: binding(\.clockThemeRaw)) {
                    Text("Classic").tag("classic")
                    Text("Ocean").tag("ocean")
                    Text("Graphite").tag("graphite")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("Editor.Clock.ThemePicker")

                Picker("Template", selection: binding(\.template)) {
                    ForEach(templateTokens) { token in
                        Text(token.displayName)
                            .tag(token)
                            .disabled(token == .reminders && !remindersEnabled)
                    }
                }

                Text("Clock designs do not use layout controls like accent bars or line limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("Layout")
            } footer: {
                Text("Switch Template to enable standard layout controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private struct EditorUITestHookButton: View {
        let title: String
        let identifier: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var editorUITestHooksOverlay: some View {
        if uiTestHooksEnabled {
            VStack(alignment: .trailing, spacing: 8) {
                EditorUITestHookButton(
                    title: "UI Test: Template Poster",
                    identifier: "EditorUITestHook.templatePoster",
                    action: {
                        var draft = currentFamilyDraft()
                        draft.template = .poster
                        setCurrentFamilyDraft(draft)
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Widget",
                    identifier: "EditorUITestHook.focusWidget",
                    action: {
                        editorFocusSnapshot = .widgetDefault
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Smart Photo Crop",
                    identifier: "EditorUITestHook.focusSmartPhotoCrop",
                    action: {
                        editorFocusSnapshot = .singleNonAlbumElement(id: "smartPhotoCrop")
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Smart Rules",
                    identifier: "EditorUITestHook.focusSmartRules",
                    action: {
                        editorFocusSnapshot = .smartRuleEditor(albumID: "uiTest.smartPhotoRules")
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Album Container",
                    identifier: "EditorUITestHook.focusAlbumContainer",
                    action: {
                        editorFocusSnapshot = .smartAlbumContainer(id: "uiTest.albumContainer")
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Album Photo Item",
                    identifier: "EditorUITestHook.focusAlbumPhotoItem",
                    action: {
                        editorFocusSnapshot = .smartAlbumPhotoItem(
                            albumID: "uiTest.album",
                            itemID: "uiTest.photo"
                        )
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Multi-select Widgets",
                    identifier: "EditorUITestHook.multiSelectWidgets",
                    action: {
                        let selection = EditorSelectionSet(items: [
                            .nonAlbumElement(id: "uiTest.widgetA"),
                            .nonAlbumElement(id: "uiTest.widgetB"),
                        ])
                        editorFocusSnapshot = selection.toFocusSnapshot()
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Multi-select Mixed",
                    identifier: "EditorUITestHook.multiSelectMixed",
                    action: {
                        let selection = EditorSelectionSet(items: [
                            .albumContainer(id: "uiTest.albumContainer", subtype: .smart),
                            .nonAlbumElement(id: "uiTest.widgetA"),
                            .nonAlbumElement(id: "uiTest.widgetB"),
                        ])
                        editorFocusSnapshot = selection.toFocusSnapshot()
                    }
                )

                EditorUITestHookButton(
                    title: "UI Test: Focus Clock",
                    identifier: "EditorUITestHook.focusClock",
                    action: {
                        editorFocusSnapshot = .clockFocus()
                    }
                )
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .opacity(0.92)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("EditorUITestHook.overlayRoot")
            .padding(.bottom, 6)
            .padding(.trailing, 6)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
#endif
}

private struct WidgetWeaverClockFaceSelector: View {
    @Binding var clockFaceRaw: String
    let clockThemeRaw: String

    @Environment(\.colorScheme) private var colorScheme

    private var selectedToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: clockFaceRaw)
    }

    private var palette: WidgetWeaverClockPalette {
        let config = WidgetWeaverClockDesignConfig(theme: clockThemeRaw, face: selectedToken.rawValue)

        let scheme: WidgetWeaverClockColourScheme = {
            switch config.theme {
            case "ocean":
                return .ocean
            case "graphite":
                return .graphite
            default:
                return .classic
            }
        }()

        return WidgetWeaverClockPalette.resolve(scheme: scheme, mode: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Face")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                WidgetWeaverClockFaceSelectorCard(
                    token: .ceramic,
                    isSelected: selectedToken == .ceramic,
                    palette: palette,
                    action: {
                        clockFaceRaw = WidgetWeaverClockFaceToken.ceramic.rawValue
                    }
                )

                WidgetWeaverClockFaceSelectorCard(
                    token: .icon,
                    isSelected: selectedToken == .icon,
                    palette: palette,
                    action: {
                        clockFaceRaw = WidgetWeaverClockFaceToken.icon.rawValue
                    }
                )
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetWeaverClockFaceSelectorCard: View {
    let token: WidgetWeaverClockFaceToken
    let isSelected: Bool
    let palette: WidgetWeaverClockPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                WidgetWeaverClockFaceSelectorClockPreview(face: token, palette: palette)
                    .frame(height: 92)

                HStack(spacing: 6) {
                    Text(token.displayName)
                        .font(.caption2.weight(.semibold))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.small)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("Editor.Clock.FaceCard.\(token.rawValue)")
        .accessibilityLabel(token.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WidgetWeaverClockFaceSelectorClockPreview: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                WidgetWeaverClockBackgroundView(palette: palette)

                WidgetWeaverClockFaceView(
                    face: face,
                    palette: palette,
                    hourAngle: .degrees(310.0),
                    minuteAngle: .degrees(120.0),
                    secondAngle: .degrees(200.0),
                    showsSecondHand: true,
                    showsMinuteHand: true,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: true,
                    handsOpacity: 1.0
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
