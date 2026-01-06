//
//  ContentView+SectionSmartPhoto.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import WidgetKit

extension ContentView {
    func smartPhotoSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()
        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhoto = d.imageSmartPhoto != nil

        let legacyFamilies: [EditingFamily] = {
            guard matchedSetEnabled else { return [] }

            var out: [EditingFamily] = []

            let small = matchedDrafts.small
            let medium = matchedDrafts.medium
            let large = matchedDrafts.large

            if !small.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, small.imageSmartPhoto == nil {
                out.append(.small)
            }
            if !medium.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, medium.imageSmartPhoto == nil {
                out.append(.medium)
            }
            if !large.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, large.imageSmartPhoto == nil {
                out.append(.large)
            }

            return out
        }()

        let legacyFamiliesLabel = legacyFamilies.map { $0.label }.joined(separator: ", ")

        return Section {
            if !hasImage {
                Text("Choose a photo in Image first to enable Smart Photo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasSmartPhoto, let smart = d.imageSmartPhoto {
                Button {
                    Task { await regenerateSmartPhotoRenders() }
                } label: {
                    Label("Regenerate smart renders", systemImage: "arrow.clockwise")
                }
                .disabled(importInProgress)

                Text("Smart Photo: v\(smart.algorithmVersion) • prepared \(smart.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SmartPhotoPreviewStripView(
                    smart: smart,
                    selectedFamily: editingFamily,
                    onSelectFamily: { family in
                        previewFamily = widgetFamily(for: family)
                    }
                )

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
            } else {
                Button {
                    Task { await regenerateSmartPhotoRenders() }
                } label: {
                    Label("Make Smart Photo (per-size renders)", systemImage: "sparkles")
                }
                .disabled(importInProgress)

                Text("Generates per-size crops for Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if matchedSetEnabled, !legacyFamilies.isEmpty {
                Button {
                    Task { await upgradeLegacyPhotosInCurrentDesign(maxUpgrades: 3) }
                } label: {
                    Label("Upgrade legacy photos to Smart Photo (\(legacyFamiliesLabel))", systemImage: "sparkles")
                }
                .disabled(importInProgress)

                Text("Upgrades up to 3 legacy image files per tap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Smart Photo")
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
