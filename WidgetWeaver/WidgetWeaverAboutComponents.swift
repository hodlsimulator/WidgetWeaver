//
//  WidgetWeaverAboutComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - Theme

enum WidgetWeaverAboutTheme {
    static let pageTint: Color = .orange

    static let backgroundBase: Color = Color(uiColor: .systemGroupedBackground)

    static func sectionAccent(title: String) -> Color {
        let t = title.lowercased()
        if t.contains("weather") { return .blue }
        if t.contains("calendar") { return .green }
        if t.contains("pro") { return .yellow }
        if t.contains("templates") { return .pink }
        if t.contains("ai") { return .indigo }
        if t.contains("variables") { return .teal }
        if t.contains("sharing") { return .mint }
        if t.contains("diagnostics") { return .gray }
        return .purple
    }
}

struct WidgetWeaverAboutBackground: View {
    var body: some View {
        ZStack {
            WidgetWeaverAboutTheme.backgroundBase
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.pink.opacity(0.18), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.orange.opacity(0.16), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 760
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.purple.opacity(0.14), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 820
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - List helpers

extension View {
    func wwAboutListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Cards + headers

struct WidgetWeaverAboutSectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    init(_ title: String, systemImage: String, accent: Color) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.leading, 4)
        .padding(.top, 4)
    }
}

struct WidgetWeaverAboutCard<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.60),
                                accent.opacity(0.18),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.22), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 260
                        )
                    )
            )
            .shadow(color: accent.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

struct WidgetWeaverAboutMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.90), accent.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .frame(width: 40, height: 40)
        .shadow(color: accent.opacity(0.22), radius: 14, x: 0, y: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Templates

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

    private var templateAccent: Color {
        template.spec.style.accent.swiftUIColor
    }

    private var iconName: String {
        switch template.id {
        case "starter-focus":
            return "scope"
        case "starter-countdown":
            return "timer"
        case "starter-quote":
            return "quote.opening"
        case "starter-list":
            return "checklist"
        case "starter-reminders-today":
            return "calendar"
        case "starter-reminders-overdue":
            return "exclamationmark.circle"
        case "starter-reminders-soon":
            return "clock"
        case "starter-reminders-priority":
            return "flag.fill"
        case "starter-reminders-focus":
            return "scope"
        case "starter-reminders-list":
            return "list.bullet.rectangle"
        case "starter-reading":
            return "book.closed"
        case "starter-steps":
            return "figure.walk"
        case "starter-weather":
            return "cloud.rain"
        case "starter-calendar-nextup":
            return "calendar"
        case "pro-habit-streak":
            return "flame.fill"
        case "pro-counter":
            return "plusminus.circle"
        default:
            return "sparkles"
        }
    }

    var body: some View {
        WidgetWeaverAboutCard(accent: templateAccent) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !template.tags.isEmpty {
                    WidgetWeaverAboutFlowTags(tags: template.tags, accentHint: templateAccent)
                }

                previewStrip
            }
        }
        .tint(templateAccent)
        .wwAboutListRow()
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(templateAccent.opacity(0.20))

                Circle()
                    .strokeBorder(templateAccent.opacity(0.35), lineWidth: 1)

                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(templateAccent)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)
            .accessibilityHidden(true)

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
                    Label("Pro", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                WidgetWeaverAboutPreviewLabeled(familyLabel: "S", accent: templateAccent) {
                    WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 62)
                }
                WidgetWeaverAboutPreviewLabeled(familyLabel: "M", accent: templateAccent) {
                    WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 62)
                }
                WidgetWeaverAboutPreviewLabeled(familyLabel: "L", accent: templateAccent) {
                    WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 62)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Preview framing

struct WidgetWeaverAboutPreviewFrame<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.18), radius: 12, x: 0, y: 8)
    }
}

struct WidgetWeaverAboutPreviewLabeled<Content: View>: View {
    let familyLabel: String
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            WidgetWeaverAboutPreviewFrame(accent: accent) {
                content
            }

            Text(familyLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rows + helpers

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
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(copyLabel)
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
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
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

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
    let accent: Color

    init(_ text: String, accent: Color = WidgetWeaverAboutTheme.pageTint) {
        self.text = text
        self.accent = accent
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
                    .strokeBorder(
                        LinearGradient(
                            colors: [accent.opacity(0.55), Color.primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .textSelection(.enabled)
    }
}

// MARK: - Tags

struct WidgetWeaverAboutFlowTags: View {
    let tags: [String]
    let accentHint: Color

    init(tags: [String], accentHint: Color = WidgetWeaverAboutTheme.pageTint) {
        self.tags = tags
        self.accentHint = accentHint
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let c = tagColour(tag)
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(c)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(c.opacity(0.15), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(c.opacity(0.25), lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
        }
    }

    private func tagColour(_ tag: String) -> Color {
        let t = tag.lowercased()

        if t.contains("weather") || t.contains("rain") {
            return .blue
        }
        if t.contains("calendar") || t.contains("events") {
            return .green
        }

        if t.contains("steps") || t.contains("health") {
            return .green
        }
        if t.contains("buttons") {
            return .orange
        }
        if t.contains("variables") {
            return .teal
        }

        let palette: [Color] = [
            accentHint,
            .pink,
            .orange,
            .purple,
            .teal,
            .mint,
            .yellow,
            .red,
            .indigo,
            .green
        ]

        var h: Int = 0
        for u in tag.unicodeScalars {
            h = (h &* 31) &+ Int(u.value)
        }

        let idx = abs(h) % palette.count
        return palette[idx]
    }
}
