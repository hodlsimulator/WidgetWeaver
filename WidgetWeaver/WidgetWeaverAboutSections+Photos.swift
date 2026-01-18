//
//  WidgetWeaverAboutSections+Photos.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
    // MARK: - Featured Photos

    var featuredPhotosSection: some View {
        let template = Self.featuredPhotoTemplate

        return Section {
            WidgetWeaverAboutCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.headline)
                            Text("Full-bleed • photo-only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            Button { handleAdd(template: template, makeDefault: false) } label: {
                                Label("Add to library", systemImage: "plus")
                            }
                            Button { handleAdd(template: template, makeDefault: true) } label: {
                                Label("Add & Make Default", systemImage: "star.fill")
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(
                        """
                        A photo-first poster layout with no caption overlay.
                        Add it, then choose a photo when prompted (or in Editor → Image).
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !template.tags.isEmpty {
                        WidgetWeaverAboutFlowTags(tags: template.tags)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Small", accent: .pink) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium", accent: .pink) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Large", accent: .pink) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 86)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    Text("Setup")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Add Photo (Single) to your library.",
                        "Choose a photo when prompted (or open Image → Choose photo).",
                        "Add a WidgetWeaver widget and pick the design.",
                    ])
                }
            }
            .tint(.pink)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Photos", systemImage: "photo", accent: .pink)
        } footer: {
            Text("Photo designs show a placeholder until a photo is chosen (or if an image file can’t be loaded).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
