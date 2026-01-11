//
//  ContentView+Sections.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI

extension ContentView {
    // MARK: - Section helpers

    @ViewBuilder
    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
    }

    // MARK: - Status / Tools

    var statusSection: some View {
        Section {
            HStack {
                Label("Preview size", systemImage: "rectangle.3.group")
                Spacer()
                Text(editingFamilyLabel)
                    .foregroundStyle(.secondary)
            }

            if let lastSavedAt {
                Text("Last saved: \(lastSavedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { activeSheet = .inspector } label: {
                    Label("Inspector", systemImage: "info.circle")
                }

                Button { activeSheet = .widgetHelp } label: {
                    Label("Widget help", systemImage: "questionmark.circle")
                }
            }
            .controlSize(.small)

            Button {
                showRevertConfirmation = true
            } label: {
                Label("Revert unsaved changes…", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            sectionHeader("Status")
        } footer: {
            Text("Edits are applied to a draft.\nUse Save to update widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }


    // MARK: - AI

    var aiSection: some View {
        Section {
            if let unavailable = EditorToolRegistry.unavailableState(for: .ai, context: editorToolContext) {
                EditorUnavailableStateView(
                    state: unavailable,
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                TextField("Prompt (generate a new design)", text: $aiPrompt, axis: .vertical)
                    .lineLimit(2...6)

                Toggle("Make generated design default", isOn: $aiMakeGeneratedDefault)

                Button {
                    Task { await generateNewDesignFromPrompt() }
                } label: {
                    Label("Generate design", systemImage: "sparkles")
                }
                .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                TextField("Patch instruction (edit this design)", text: $aiPatchInstruction, axis: .vertical)
                    .lineLimit(2...6)

                Button {
                    Task { await applyPatchToCurrentDesign() }
                } label: {
                    Label("Apply patch", systemImage: "wand.and.stars")
                }
                .disabled(aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !aiStatusMessage.isEmpty {
                    Text(aiStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("AI")
        } footer: {
            Text("AI runs on-device where available.\nGenerated designs are saved to the library like any other design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Existing sections (unchanged)
    var designsSection: some View {
        Section {
            if savedSpecs.isEmpty {
                Text("No saved designs yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Design", selection: $selectedSpecID) {
                    ForEach(savedSpecs) { spec in
                        Text(specDisplayName(spec)).tag(spec.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let defaultName {
                LabeledContent("App default", value: defaultName)
            }

            if !proManager.isProUnlocked {
                LabeledContent("Free tier designs", value: "\(savedSpecs.count)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
            }

            if selectedSpecID == defaultSpecID {
                Text("This design is the app default.\nWidgets set to \"Default (App)\" will show it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This design is not the app default.\nUse \"Save & Make Default\" to update widgets set to \"Default (App)\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { createNewDesign() } label: { Label("New", systemImage: "plus") }
                Button { duplicateCurrentDesign() } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .disabled(savedSpecs.isEmpty)
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(savedSpecs.count <= 1)
            }
            .controlSize(.small)
        } header: {
            sectionHeader("Design")
        } footer: {
            Text("Each widget instance can be configured to follow \"Default (App)\" or a specific saved design (long-press the widget → Edit Widget).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var widgetsSection: some View {
        Section {
            if widgetIDs.isEmpty {
                Text("No widgets.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Widget", selection: $selectedWidgetID) {
                    ForEach(widgetIDs, id: \.self) { id in
                        Text(id.shortWidgetLabel).tag(id)
                    }
                }
                .pickerStyle(.menu)
            }

            ControlGroup {
                Button { focusWidget() } label: { Label("Focus widget", systemImage: "scope") }
                Button { focusClock() } label: { Label("Focus clock", systemImage: "clock") }
            }
            .controlSize(.small)

            ControlGroup {
                Button { addNewWidget() } label: { Label("Add", systemImage: "plus") }
                Button(role: .destructive) { deleteSelectedWidget(selectedWidgetID) } label: { Label("Delete", systemImage: "trash") }
            }
            .controlSize(.small)
        } header: {
            sectionHeader("Widgets")
        } footer: {
            Text("Widgets are generated from the current design.\nUse Focus to pick what you’re editing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var layoutSection: some View {
        Section {
            Picker("Layout", selection: $draftSpec.layout) {
                ForEach(WidgetLayout.allCases) { layout in
                    Text(layout.rawValue).tag(layout)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show grid", isOn: $draftSpec.style.showGrid)

            Toggle("Show debug overlay", isOn: $draftSpec.style.showDebugOverlay)

            Toggle("Show safe area", isOn: $draftSpec.style.showSafeArea)
        } header: {
            sectionHeader("Layout")
        } footer: {
            Text("Layout controls how content is arranged.\nDebug overlays are for development only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var textSection: some View {
        Section {
            TextField("Text", text: $draftSpec.text.content, axis: .vertical)
                .lineLimit(1...6)

            Toggle("All caps", isOn: $draftSpec.text.isAllCaps)

            Toggle("Monospace digits", isOn: $draftSpec.text.monospaceDigits)

            Toggle("Use placeholder when empty", isOn: $draftSpec.text.usePlaceholderWhenEmpty)

            TextField("Placeholder", text: $draftSpec.text.placeholder)
                .disabled(!draftSpec.text.usePlaceholderWhenEmpty)
        } header: {
            sectionHeader("Text")
        } footer: {
            Text("Text is rendered in the widget.\nUse placeholders to preview empty states.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var symbolSection: some View {
        Section {
            Picker("Symbol", selection: $draftSpec.symbol.kind) {
                ForEach(WidgetSymbolKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)

            Toggle("Tint symbol", isOn: $draftSpec.symbol.tintEnabled)

            ColorPicker("Symbol tint", selection: $draftSpec.symbol.tintColor)
                .disabled(!draftSpec.symbol.tintEnabled)
        } header: {
            sectionHeader("Symbol")
        } footer: {
            Text("Symbols use SF Symbols.\nTinting uses the chosen colour.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var imageSection: some View {
        Section {
            if let imageID = specForSelectedWidget.image?.imageID {
                LabeledContent("Image", value: imageID)
            } else {
                Text("No image selected.")
                    .foregroundStyle(.secondary)
            }

            Button {
                showImagePicker = true
            } label: {
                Label("Pick image…", systemImage: "photo")
            }
        } header: {
            sectionHeader("Image")
        } footer: {
            Text("Images are stored in the app’s library.\nThe picker uses Photos access when available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var smartPhotoSection: some View {
        Section {
            if specForSelectedWidget.image?.mode != .smartPhoto {
                Text("Smart Photo is off.")
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $draftSpec.image.mode) {
                ForEach(SmartPhotoMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Toggle("Prefer face-aware crop", isOn: $draftSpec.image.preferFaceAwareCrop)
                .disabled(draftSpec.image.mode != .smartPhoto)

            Toggle("Prefer portrait crop", isOn: $draftSpec.image.preferPortraitCrop)
                .disabled(draftSpec.image.mode != .smartPhoto)

            Button {
                focusSmartPhotoCrop()
            } label: {
                Label("Adjust crop…", systemImage: "crop")
            }
            .disabled(draftSpec.image.mode != .smartPhoto)
        } header: {
            sectionHeader("Smart Photo")
        } footer: {
            Text("Smart Photo automatically picks a crop.\nUse Adjust crop to fine-tune.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var albumShuffleSection: some View {
        Section {
            if draftSpec.image.mode != .smartPhoto {
                Text("Album Shuffle requires Smart Photo.")
                    .foregroundStyle(.secondary)
            }

            Toggle("Enable Album Shuffle", isOn: $draftSpec.image.albumShuffleEnabled)
                .disabled(draftSpec.image.mode != .smartPhoto)

            if draftSpec.image.albumShuffleEnabled {
                Button {
                    focusAlbumShuffle()
                } label: {
                    Label("Choose album…", systemImage: "photo.on.rectangle.angled")
                }
            }
        } header: {
            sectionHeader("Album Shuffle")
        } footer: {
            Text("Album Shuffle rotates images from an album.\nRequires Photos access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var smartRulesSection: some View {
        Section {
            if specForSelectedWidget.image?.imageID == nil {
                EditorUnavailableStateView(
                    state: .missingImageForSmartRules(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else if specForSelectedWidget.image?.mode != .smartPhoto {
                EditorUnavailableStateView(
                    state: .missingSmartPhotoForSmartRules(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                Button {
                    focusSmartRules()
                } label: {
                    Label("Edit Smart Rules…", systemImage: "slider.horizontal.3")
                }
            }
        } header: {
            sectionHeader("Smart Rules")
        } footer: {
            Text("Smart Rules can adjust cropping behaviour.\nRequires an image and Smart Photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var typographySection: some View {
        Section {
            Picker("Font design", selection: $draftSpec.typography.fontDesign) {
                ForEach(FontDesign.allCases) { design in
                    Text(design.rawValue).tag(design)
                }
            }
            .pickerStyle(.menu)

            Stepper("Size: \(draftSpec.typography.size)", value: $draftSpec.typography.size, in: 8...96)

            Stepper("Weight: \(draftSpec.typography.weight.rawValue)", value: $draftSpec.typography.weight, in: Font.Weight.supportedRange)

            Toggle("Uppercase", isOn: $draftSpec.typography.uppercase)

            Toggle("Small caps", isOn: $draftSpec.typography.smallCaps)
        } header: {
            sectionHeader("Typography")
        } footer: {
            Text("Typography controls how text is drawn.\nSome options are template-specific.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var actionsSection: some View {
        Section {
            if !proManager.isProUnlocked {
                EditorUnavailableStateView(
                    state: .proRequiredForActions(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                Toggle("Enable actions", isOn: $draftSpec.actions.enabled)

                if draftSpec.actions.enabled {
                    Text("Actions are configured via Shortcuts/Intents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Actions")
        } footer: {
            Text("Actions allow interactive widget buttons.\nRequires Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var matchedSetSection: some View {
        Section {
            Toggle("Enable matched set", isOn: $draftSpec.matchedSet.enabled)

            if draftSpec.matchedSet.enabled && !proManager.isProUnlocked {
                EditorUnavailableStateView(
                    state: .proRequiredForMatchedSet(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else if draftSpec.matchedSet.enabled {
                TextField("Matched set key", text: $draftSpec.matchedSet.key)
            }
        } header: {
            sectionHeader("Matched Set")
        } footer: {
            Text("Matched sets coordinate styling across widgets.\nRequires Pro to enable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var variablesSection: some View {
        Section {
            if !proManager.isProUnlocked {
                EditorUnavailableStateView(
                    state: .proRequiredForVariables(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                Text("Variables are defined per-design.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Variables")
        } footer: {
            Text("Variables can be used in templates.\nRequires Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var sharingSection: some View {
        Section {
            Button {
                exportCurrentDesign()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
        } header: {
            sectionHeader("Sharing")
        } footer: {
            Text("Export a shareable representation of the current design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Text("Pro is unlocked.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    activeSheet = .pro
                } label: {
                    Label("Unlock Pro…", systemImage: "crown")
                }
            }
        } header: {
            sectionHeader("Pro")
        } footer: {
            Text("Pro unlocks additional tools and higher limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
