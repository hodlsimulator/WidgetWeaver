//
//  ContentView+SectionSmartPhotoCrop.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import WidgetKit

extension ContentView {
    func smartPhotoCropSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()
        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForSmartPhotoFraming(),
                    isBusy: false
                )
            } else if !hasSmartPhoto {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForSmartPhotoFraming(),
                    isBusy: false
                )
            } else if let smart = d.imageSmartPhoto {
                let shuffleEnabled = !((smart.shuffleManifestFileName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty)

                SmartPhotoPreviewStripView(
                    smart: smart,
                    selectedFamily: editingFamily,
                    onSelectFamily: { family in
                        previewFamily = widgetFamily(for: family)
                    }
                )

                if shuffleEnabled {
                    Text("Manual framing is unavailable while Album Shuffle is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let family = editingFamily
                    let familyLabel = editingFamilyLabel

                    let variant: SmartPhotoVariantSpec? = {
                        switch family {
                        case .small: return smart.small
                        case .medium: return smart.medium
                        case .large: return smart.large
                        }
                    }()

                    if let variant {
                        NavigationLink {
                            SmartPhotoCropEditorView(
                                family: family,
                                masterFileName: smart.masterFileName,
                                targetPixels: variant.pixelSize,
                                initialCropRect: variant.cropRect,
                                focus: focus,
                                onApply: { rect in
                                    await applyManualSmartCrop(family: family, cropRect: rect)
                                }
                            )
                        } label: {
                            Label("Fix framing (\(familyLabel))", systemImage: "crop")
                        }
                        .disabled(importInProgress)
                    } else {
                        Text("Smart render data missing for \(familyLabel).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("Smart Photo Framing")
        }
    }

    private func widgetFamily(for family: EditingFamily) -> WidgetFamily {
        switch family {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
        }
    }
}
