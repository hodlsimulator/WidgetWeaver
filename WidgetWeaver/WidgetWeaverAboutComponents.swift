//
//  WidgetWeaverAboutComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetWeaverAboutTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let tags: [String]
    let requiresPro: Bool
    let triggersCalendarPermission: Bool
    let spec: WidgetSpec
}

struct WidgetWeaverAboutTemplateRow: View {
    let template: WidgetWeaverAboutTemplate
    let isProUnlocked: Bool
    let onAdd: @MainActor (_ makeDefault: Bool) -> Void
    let onShowPro: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.headline)

                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if template.requiresPro && !isProUnlocked {
                    Button {
                        onShowPro()
                    } label: {
                        Label("Pro required", systemImage: "lock.fill")
                    }
                    .controlSize(.small)
                } else {
                    Menu {
                        Button { onAdd(false) } label: {
                            Label("Add to library", systemImage: "plus")
                        }
                        Button { onAdd(true) } label: {
                            Label("Add & Make Default", systemImage: "star.fill")
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.small)
                }
            }

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !template.tags.isEmpty {
                WidgetWeaverAboutFlowTags(tags: template.tags)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    WidgetWeaverAboutPreviewLabeled(familyLabel: "S") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 62)
                    }
                    WidgetWeaverAboutPreviewLabeled(familyLabel: "M") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 62)
                    }
                    WidgetWeaverAboutPreviewLabeled(familyLabel: "L") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 62)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

struct WidgetWeaverAboutPreviewLabeled<Content: View>: View {
    let familyLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            content
            Text(familyLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetWeaverAboutPromptRow: View {
    let text: String
    let copyLabel: String
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Button { onCopy() } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copyLabel)
        }
    }
}

struct WidgetWeaverAboutFeatureRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetWeaverAboutBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

struct WidgetWeaverAboutCodeBlock: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10))
            )
            .textSelection(.enabled)
    }
}

struct WidgetWeaverAboutFlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}
