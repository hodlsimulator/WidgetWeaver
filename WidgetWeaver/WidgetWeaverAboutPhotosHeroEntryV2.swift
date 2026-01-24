//
//  WidgetWeaverAboutPhotosHeroEntryV2.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import Foundation
import SwiftUI
import WidgetKit

/// A Photos-first Explore hero entry that drives a “choose photo now → customise later” flow.
///
/// This surface is feature-flagged via `FeatureFlags.photosExploreV2Enabled`.
struct WidgetWeaverAboutPhotosHeroEntryV2: View {
    let primaryTemplate: WidgetWeaverAboutTemplate
    let variantTemplates: [WidgetWeaverAboutTemplate]

    var onAdd: @MainActor (_ template: WidgetWeaverAboutTemplate, _ makeDefault: Bool) -> Void

    private var styleTemplates: [WidgetWeaverAboutTemplate] {
        var templates: [WidgetWeaverAboutTemplate] = [primaryTemplate]

        for t in variantTemplates {
            if t.id == primaryTemplate.id { continue }
            templates.append(t)
        }

        var seen = Set<String>()
        return templates.filter { seen.insert($0.id).inserted }
    }

    private var additionalStyleTemplates: [WidgetWeaverAboutTemplate] {
        styleTemplates.filter { $0.id != primaryTemplate.id }
    }

    var body: some View {
        WidgetWeaverAboutCard(accent: .pink) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                Text("Choose a photo now, customise later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WidgetWeaverAboutFlowTags(tags: ["Photo", "Quick start", "Poster"])

                previewStrip

                Divider()

                Text("Styles")
                    .font(.subheadline.weight(.semibold))

                styleChipsRow

                Text("After choosing a photo, caption + framing can be adjusted in the Editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.pink)
        .wwAboutListRow()
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Photos")
                    .font(.headline)

                Text("Pick an image first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    onAdd(primaryTemplate, false)
                } label: {
                    Label("Choose photo…", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Menu {
                    Button {
                        onAdd(primaryTemplate, true)
                    } label: {
                        Label("Choose photo… & Make Default", systemImage: "star.fill")
                    }

                    if !additionalStyleTemplates.isEmpty {
                        Divider()
                    }

                    ForEach(additionalStyleTemplates) { template in
                        Button {
                            onAdd(template, false)
                        } label: {
                            Label("Add \(shortStyleLabel(template))", systemImage: "plus")
                        }

                        Button {
                            onAdd(template, true)
                        } label: {
                            Label("Add \(shortStyleLabel(template)) & Make Default", systemImage: "star.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("More")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                WidgetWeaverAboutPreviewLabeled(familyLabel: "Small", accent: .pink) {
                    WidgetPreviewThumbnail(spec: primaryTemplate.spec, family: .systemSmall, height: 86)
                }
                WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium", accent: .pink) {
                    WidgetPreviewThumbnail(spec: primaryTemplate.spec, family: .systemMedium, height: 86)
                }
                WidgetWeaverAboutPreviewLabeled(familyLabel: "Large", accent: .pink) {
                    WidgetPreviewThumbnail(spec: primaryTemplate.spec, family: .systemLarge, height: 86)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var styleChipsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(styleTemplates) { template in
                    Button {
                        onAdd(template, false)
                    } label: {
                        Text(shortStyleLabel(template))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(styleTemplates) { template in
                    Button {
                        onAdd(template, false)
                    } label: {
                        HStack(spacing: 8) {
                            Text(shortStyleLabel(template))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .allowsTightening(true)

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shortStyleLabel(_ template: WidgetWeaverAboutTemplate) -> String {
        switch template.id {
        case "starter-photo-single":
            return "Photo-only"
        case "starter-photo-caption":
            return "Caption"
        case "starter-photo-framed":
            return "Framed"
        default:
            if !template.subtitle.isEmpty {
                return template.subtitle
            }
            return template.title
        }
    }
}
