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

                WidgetWeaverClockThemePicker(
                    clockThemeRaw: binding(\.clockThemeRaw),
                    clockFaceRaw: currentFamilyDraft().clockFaceRaw
                )
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

private struct WidgetWeaverClockThemePicker: View {
    @Binding var clockThemeRaw: String
    let clockFaceRaw: String

    @Environment(\.colorScheme) private var colorScheme

    private var selectedFaceToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: clockFaceRaw)
    }

    private struct Option: Identifiable {
        let id: String
        let themeRaw: String
        let displayName: String
    }

    private static let options: [Option] = [
        Option(id: "classic", themeRaw: "classic", displayName: "Classic"),
        Option(id: "ocean", themeRaw: "ocean", displayName: "Ocean"),
        Option(id: "mint", themeRaw: "mint", displayName: "Mint"),
        Option(id: "orchid", themeRaw: "orchid", displayName: "Orchid"),
        Option(id: "sunset", themeRaw: "sunset", displayName: "Sunset"),
        Option(id: "ember", themeRaw: "ember", displayName: "Ember"),
        Option(id: "graphite", themeRaw: "graphite", displayName: "Graphite"),
    ]

    private var selectedTheme: String {
        WidgetWeaverClockDesignConfig(theme: clockThemeRaw, face: clockFaceRaw).theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scheme")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(Self.options) { option in
                    let isSelected = (selectedTheme == option.themeRaw)

                    let palette = WidgetWeaverClockAppearanceResolver
                        .resolve(
                            config: WidgetWeaverClockDesignConfig(theme: option.themeRaw, face: clockFaceRaw),
                            mode: colorScheme
                        )
                        .palette

                    WidgetWeaverClockThemeChip(
                        title: option.displayName,
                        face: selectedFaceToken,
                        palette: palette,
                        themeRaw: option.themeRaw,
                        isSelected: isSelected,
                        action: {
                            clockThemeRaw = option.themeRaw
                        }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetWeaverClockThemeChip: View {
    let title: String
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette
    let themeRaw: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                WidgetWeaverClockThemeSwatch(face: face, palette: palette)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
        .accessibilityIdentifier("Editor.Clock.ThemeChip.\(themeRaw)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WidgetWeaverClockThemeSwatch: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.backgroundTop,
                            palette.backgroundBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WidgetWeaverClockFaceView(
                face: face,
                palette: palette,
                hourAngle: .degrees(310.0),
                minuteAngle: .degrees(120.0),
                secondAngle: .degrees(200.0),
                showsSecondHand: false,
                showsMinuteHand: true,
                showsHandShadows: false,
                showsGlows: false,
                showsCentreHub: true,
                handsOpacity: 1.0
            )
            .padding(2)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockFaceSelector: View {
    @Binding var clockFaceRaw: String
    let clockThemeRaw: String

    @Environment(\.colorScheme) private var colorScheme

    private var selectedToken: WidgetWeaverClockFaceToken {
        WidgetWeaverClockFaceToken.canonical(from: clockFaceRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Face")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Choose the dial style. This can be changed later.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)


            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(WidgetWeaverClockFaceToken.orderedForPicker, id: \.rawValue) { token in
                    let palette = WidgetWeaverClockAppearanceResolver
                        .resolve(
                            config: WidgetWeaverClockDesignConfig(theme: clockThemeRaw, face: token.rawValue),
                            mode: colorScheme
                        )
                        .palette

                    WidgetWeaverClockFaceSelectorCard(
                        token: token,
                        isSelected: selectedToken == token,
                        palette: palette,
                        action: {
                            clockFaceRaw = token.rawValue
                        }
                    )
                }
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

                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Text(token.displayName)
                            .font(.caption2.weight(.semibold))

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.small)
                        }
                    }
                    .foregroundStyle(.primary)

                    Text(token.numeralsDescriptor)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
        .accessibilityLabel("\(token.displayName), \(token.numeralsDescriptor)")
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
