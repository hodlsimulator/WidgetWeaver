//
//  WidgetWeaverAboutComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI
import WidgetKit

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

// MARK: - Badges

struct WidgetWeaverAboutBadge: View {
    let text: String
    let accent: Color

    init(_ text: String, accent: Color = WidgetWeaverAboutTheme.pageTint) {
        self.text = text
        self.accent = accent
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
            )
            .accessibilityLabel(text)
    }
}


struct WidgetWeaverAboutTemplateRow: View {
    let template: WidgetWeaverAboutTemplate
    let isProUnlocked: Bool
    let onAdd: @MainActor (_ makeDefault: Bool) -> Void
    let onShowPro: @MainActor () -> Void

    @State private var remindersGuidePresented: Bool = false

    private var templateAccent: Color {
        template.spec.style.accent.swiftUIColor
    }

    private var smartStackGroupAccent: Color {
        .orange
    }

    private var remindersSmartStackIndex: Int? {
        switch template.id {
        case "starter-reminders-today":
            return 1
        case "starter-reminders-overdue":
            return 2
        case "starter-reminders-soon":
            return 3
        case "starter-reminders-priority":
            return 4
        case "starter-reminders-focus":
            return 5
        case "starter-reminders-list":
            return 6
        default:
            return nil
        }
    }

    private var isRemindersSmartStackTemplate: Bool {
        remindersSmartStackIndex != nil
    }

    private var cardAccent: Color {
        isRemindersSmartStackTemplate ? smartStackGroupAccent : templateAccent
    }

    private var cardTint: Color {
        isRemindersSmartStackTemplate ? smartStackGroupAccent : templateAccent
    }

    private var showsSmartStackBadge: Bool {
        isRemindersSmartStackTemplate
    }

    private var showsRemindersSmartStackGroupIntro: Bool {
        template.id == "starter-reminders-today"
    }

    private var showsRemindersSmartStackGroupOutro: Bool {
        template.id == "starter-reminders-list"
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


    private func remindersSmartStackGroupLabel(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cardAccent)

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        WidgetWeaverAboutCard(accent: cardAccent) {
            VStack(alignment: .leading, spacing: 12) {
                if showsRemindersSmartStackGroupIntro {
                    remindersSmartStackGroupLabel(
                        text: "Reminders Smart Stack • 6 templates",
                        systemImage: "square.stack.3d.up.fill"
                    )
                }

                headerRow

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !template.tags.isEmpty {
                    WidgetWeaverAboutFlowTags(tags: template.tags, accentHint: templateAccent)
                }

                previewStrip

                if showsRemindersSmartStackGroupOutro {
                    remindersSmartStackGroupLabel(
                        text: "End of Reminders Smart Stack",
                        systemImage: "checkmark.seal.fill"
                    )
                }
            }
        }
        .tint(cardTint)
        .wwAboutListRow()
        .padding(.bottom, showsRemindersSmartStackGroupOutro ? 12 : 0)
        .sheet(isPresented: $remindersGuidePresented) {
            NavigationStack {
                WidgetWeaverRemindersSmartStackGuideView(onClose: { remindersGuidePresented = false })
            }
        }
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

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)

                    if let idx = remindersSmartStackIndex {
                        WidgetWeaverAboutBadge("Smart Stack \(idx)/6", accent: templateAccent)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            if template.requiresPro && !isProUnlocked {
                ViewThatFits(in: .horizontal) {
                    Button {
                        onShowPro()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                            Text("Pro")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onShowPro()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Pro")
                }
            } else {
                templateControls
            }
        }
    }

    @ViewBuilder
    private var templateControls: some View {
        if isRemindersSmartStackTemplate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    guideButton(showTitle: true)
                    addMenu(showTitle: true)
                }

                HStack(spacing: 8) {
                    guideButton(showTitle: false)
                    addMenu(showTitle: false)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                addMenu(showTitle: true)
                addMenu(showTitle: false)
            }
        }
    }

    @ViewBuilder
    private func guideButton(showTitle: Bool) -> some View {
        Button {
            remindersGuidePresented = true
        } label: {
            if showTitle {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("Guide")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .accessibilityLabel("Guide")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func addMenu(showTitle: Bool) -> some View {
        Menu {
            if isRemindersSmartStackTemplate {
                Button {
                    remindersGuidePresented = true
                } label: {
                    Label("Smart Stack guide", systemImage: "square.stack.3d.up.fill")
                }
                Divider()
            }

            Button { onAdd(false) } label: {
                Label("Add to library", systemImage: "plus")
            }
            Button { onAdd(true) } label: {
                Label("Add & Make Default", systemImage: "star.fill")
            }
        } label: {
            if showTitle {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: "plus.circle.fill")
                    .accessibilityLabel("Add")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
