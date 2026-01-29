//
//  ContentView+Toolbar.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import WidgetKit

extension ContentView {
    var toolbarMenu: some View {
        Menu {
            Button {
                selectedTab = .explore
            } label: {
                Label("Explore", systemImage: "sparkles")
            }

            Button {
                selectedTab = .library
            } label: {
                Label("Library", systemImage: "square.grid.2x2")
            }

            Divider()

            Button {
                activeSheet = .weather
            } label: {
                Label("Weather settings", systemImage: "cloud.sun.fill")
            }

            Button {
                Task {
                    let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()
                    if granted {
                        _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                        await MainActor.run { saveStatusMessage = "Calendar refreshed.\nWidgets will update on next reload." }
                    } else {
                        await MainActor.run { saveStatusMessage = "Calendar access is off.\nEnable access to use Next Up." }
                    }
                }
            } label: {
                Label("Next Up: refresh Calendar", systemImage: "calendar")
            }

            Button {
                activeSheet = .steps
            } label: {
                Label("Steps settings", systemImage: "figure.walk")
            }

            Button {
                activeSheet = .activity
            } label: {
                Label("Activity settings", systemImage: "figure.walk.circle")
            }

            if WidgetWeaverFeatureFlags.remindersTemplateEnabled {
                Button {
                    activeSheet = .reminders
                } label: {
                    Label("Reminders settings", systemImage: "checkmark.circle")
                }
            }

            Divider()

            Button {
                activeSheet = .inspector
            } label: {
                Label("Inspector", systemImage: "doc.text.magnifyingglass")
            }

            if hasUnsavedChanges {
                Button(role: .destructive) {
                    showRevertConfirmation = true
                } label: {
                    Label("Revert Unsaved Changes", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button {
                activeSheet = .pro
            } label: {
                Label(proManager.isProUnlocked ? "WidgetWeaver Pro" : "Upgrade to Pro", systemImage: "crown.fill")
            }

            Button {
                activeSheet = .variables
            } label: {
                Label("Variables", systemImage: "slider.horizontal.3")
            }

            Button {
                activeSheet = .widgetHelp
            } label: {
                Label("Widget Help", systemImage: "questionmark.circle")
            }

            #if DEBUG
            Divider()

            Button {
                activeSheet = .clockFaceGallery
            } label: {
                Label("Debug: clock face gallery", systemImage: "square.grid.3x3")
            }

            Toggle(
                "Debug: enable AI",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.aiEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setAIEnabled(newValue)
                        EditorToolRegistry.capabilitiesDidChange(reason: .unknown)
                    }
                )
            )

            Toggle(
                "Debug: enable Reminders template",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.remindersTemplateEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setRemindersTemplateEnabled(newValue)
                        EditorToolRegistry.capabilitiesDidChange(reason: .unknown)
                    }
                )
            )

            Toggle(
                "Debug: enable Photo Filters",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.photoFiltersEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setPhotoFiltersEnabled(newValue)
                        EditorToolRegistry.capabilitiesDidChange(reason: .unknown)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                )
            )

            Toggle(
                "Debug: enable Poster suite",
                isOn: Binding(
                    get: { FeatureFlags.posterSuiteEnabled },
                    set: { newValue in
                        FeatureFlags.setPosterSuiteEnabled(newValue)
                        EditorToolRegistry.capabilitiesDidChange(reason: .unknown)
                    }
                )
            )

            Toggle(
                "Debug: enable Photos Explore V2",
                isOn: Binding(
                    get: { FeatureFlags.photosExploreV2Enabled },
                    set: { newValue in
                        FeatureFlags.setPhotosExploreV2Enabled(newValue)
                    }
                )
            )

            Toggle(
                "Debug: Smart Photos UX hardening",
                isOn: Binding(
                    get: { FeatureFlags.smartPhotosUXHardeningEnabled },
                    set: { newValue in
                        FeatureFlags.setSmartPhotosUXHardeningEnabled(newValue)
                        EditorToolRegistry.capabilitiesDidChange(reason: .unknown)
                    }
                )
            )

            Toggle(
                "Debug: enable Clipboard Actions",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.clipboardActionsEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setClipboardActionsEnabled(newValue)
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.clipboardActions)
                    }
                )
            )

            Toggle(
                "Debug: enable PawPulse",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.pawPulseEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setPawPulseEnabled(newValue)

                        if newValue {
                            PawPulseCache.ensureDirectoryExists()
                            PawPulseBackgroundTasks.scheduleNextEarliest(minutesFromNow: 30)
                        } else {
                            PawPulseBackgroundTasks.cancelPending()
                        }

                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.pawPulseLatestCat)
                    }
                )
            )

            Toggle(
                "Debug: Segmented ring diagnostics",
                isOn: Binding(
                    get: { WidgetWeaverFeatureFlags.segmentedRingDiagnosticsEnabled },
                    set: { newValue in
                        WidgetWeaverFeatureFlags.setSegmentedRingDiagnosticsEnabled(newValue)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                )
            )
            Toggle("Debug: editor diagnostics", isOn: $showEditorDiagnostics)
            #endif

            Divider()

            Button { createNewDesign() } label: { Label("New Design", systemImage: "plus") }
            Button { duplicateCurrentDesign() } label: { Label("Duplicate Design", systemImage: "doc.on.doc") }
                .disabled(savedSpecs.isEmpty)

            Divider()

            Button { saveSelected(makeDefault: true) } label: { Label("Save & Make Default", systemImage: "checkmark.circle") }
            Button { saveSelected(makeDefault: false) } label: { Label("Save (Keep Default)", systemImage: "tray.and.arrow.down") }

            Divider()

            Button { randomiseStyleDraft() } label: { Label("Randomise Style (Draft)", systemImage: "shuffle") }
            Button { presentRemixSheet() } label: { Label("Remix (5 options)", systemImage: "wand.and.stars") }
            Button(role: .destructive) { showImageCleanupConfirmation = true } label: { Label("Clean Up Unused Images", systemImage: "trash.slash") }

            Divider()

            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("WidgetWeaver Design")) {
                Label("Share This Design", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("WidgetWeaver Designs")) {
                Label("Share All Designs", systemImage: "square.and.arrow.up.on.square")
            }
            Button { showImportPicker = true } label: { Label("Import Designs…", systemImage: "square.and.arrow.down") }

            Divider()

            Button { refreshWidgets() } label: { Label("Refresh Widgets", systemImage: "arrow.clockwise") }

            Divider()

            Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete Design", systemImage: "trash") }
                .disabled(savedSpecs.count <= 1)

        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
