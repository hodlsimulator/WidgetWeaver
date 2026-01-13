//
//  WidgetWeaverClipboardActionsWidget.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
import ScreenActionsCore
import SwiftUI
import WidgetKit

public struct WidgetWeaverClipboardActionsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWeaverWidgetKinds.clipboardActions, provider: Provider()) { entry in
            WidgetWeaverClipboardStatusView(entry: entry)
                .widgetURL(URL(string: "widgetweaver://clipboard")!)
        }
        .configurationDisplayName("Action Inbox")
        .description("Shows the last text sent to WidgetWeaver and what it looks like.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct WidgetWeaverClipboardEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetWeaverClipboardInboxSnapshot

    public init(date: Date, snapshot: WidgetWeaverClipboardInboxSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

extension WidgetWeaverClipboardActionsWidget {
    struct Provider: TimelineProvider {
        typealias Entry = WidgetWeaverClipboardEntry

        func placeholder(in context: Context) -> Entry {
            Entry(
                date: Date(),
                snapshot: WidgetWeaverClipboardInboxSnapshot(
                    text: "Dinner with Aoife\nTomorrow 19:30\nAt The Winding Stair",
                    capturedAt: Date(),
                    lastActionKind: "auto-event",
                    lastActionMessage: "Event created.",
                    lastActionAt: Date(),
                    lastExportedCSVPath: nil
                )
            )
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverClipboardInboxStore.load()
            completion(Entry(date: Date(), snapshot: snap))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverClipboardInboxStore.load()
            let now = Date()
            let entry = Entry(date: now, snapshot: snap)

            // Mostly updated via WidgetCenter reloads from intents.
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(60 * 60))))
        }
    }
}

// MARK: - View

private struct ClipboardStatusModel {
    var isEmpty: Bool

    var title: String
    var preview: String?

    var capturedAt: Date?
    var suggestedKind: ScreenActionKind?
    var suggestedReason: String?

    var detailPrimary: String?
    var detailSecondary: String?

    var lastActionMessage: String?
    var lastActionAt: Date?
    var exportedFileName: String?
}

private struct WidgetWeaverClipboardStatusView: View {
    let entry: WidgetWeaverClipboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let model = makeModel(from: entry.snapshot)

        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            if model.isEmpty {
                emptyState(model: model)
            } else {
                content(model: model)
            }

            Spacer(minLength: 0)

            actionsRow(model: model)

            footer(model: model)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(model: ClipboardStatusModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.headline)

            Text("Action Inbox")
                .font(.headline)

            Spacer(minLength: 0)

            if let capturedAt = model.capturedAt {
                Text(capturedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func emptyState(model: ClipboardStatusModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No text received yet.")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Send text via Shortcuts (e.g. Get Clipboard → Auto Detect from Text).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 3 : 4)

            if let msg = model.lastActionMessage, !msg.isEmpty {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func content(model: ClipboardStatusModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let kind = model.suggestedKind {
                    suggestionBadge(kind: kind)
                }
            }

            if let preview = model.preview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? 3 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let p = model.detailPrimary, !p.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(p)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            if family == .systemMedium, let s = model.detailSecondary, !s.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(s)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            if family == .systemMedium, let file = model.exportedFileName, !file.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last export: \(file)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func actionsRow(model: ClipboardStatusModel) -> some View {
        // Status-first: keep actions minimal.
        HStack(spacing: 10) {
            Button(intent: WidgetWeaverClipboardAutoDetectIntent()) {
                Label("Auto", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isEmpty)

            Button(intent: WidgetWeaverClipboardClearInboxIntent()) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private func footer(model: ClipboardStatusModel) -> some View {
        if let msg = model.lastActionMessage, !msg.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let at = model.lastActionAt {
                    Text(at, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Badge

    private func suggestionBadge(kind: ScreenActionKind) -> some View {
        let (symbol, label) = kindBadge(kind)

        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private func kindBadge(_ kind: ScreenActionKind) -> (String, String) {
        switch kind {
        case .reminder:
            return ("checklist", "Reminder")
        case .event:
            return ("calendar", "Event")
        case .contact:
            return ("person.crop.circle", "Contact")
        case .receipt:
            return ("tablecells", "Receipt")
        }
    }

    // MARK: - Model building

    private func makeModel(from snapshot: WidgetWeaverClipboardInboxSnapshot) -> ClipboardStatusModel {
        let cleanedText: String? = {
            guard let t = snapshot.text else { return nil }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let title: String = {
            guard let cleanedText else { return "No text" }
            let first = cleanedText.components(separatedBy: .newlines).first ?? ""
            let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Untitled" : String(t.prefix(64))
        }()

        let preview: String? = {
            guard let cleanedText else { return nil }
            let lines = cleanedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if lines.isEmpty { return nil }

            let maxLines = (family == .systemSmall) ? 4 : 8
            return lines.prefix(maxLines).joined(separator: "\n")
        }()

        let exportedFileName: String? = {
            guard let path = snapshot.lastExportedCSVPath, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path).lastPathComponent
        }()

        guard let cleanedText else {
            return ClipboardStatusModel(
                isEmpty: true,
                title: title,
                preview: nil,
                capturedAt: snapshot.capturedAt,
                suggestedKind: nil,
                suggestedReason: nil,
                detailPrimary: nil,
                detailSecondary: nil,
                lastActionMessage: snapshot.lastActionMessage,
                lastActionAt: snapshot.lastActionAt,
                exportedFileName: exportedFileName
            )
        }

        let decision = ScreenActionsCore.ActionRouter.route(text: cleanedText)

        var detailPrimary: String?
        var detailSecondary: String?

        switch decision.kind {
        case .event:
            if let r = decision.dateRange ?? ScreenActionsCore.DateParser.firstDateRange(in: cleanedText) {
                detailPrimary = "When: \(formatDateRange(start: r.start, end: r.end))"
            } else {
                detailPrimary = "When: No date detected"
            }
            if let reason = cleanedDecisionReason(decision.reason) {
                detailSecondary = "Why: \(reason)"
            }

        case .reminder:
            if let due = (decision.dateRange ?? ScreenActionsCore.DateParser.firstDateRange(in: cleanedText))?.start {
                detailPrimary = "Due: \(formatDateTime(due))"
            } else {
                detailPrimary = "Due: No date detected"
            }
            if let reason = cleanedDecisionReason(decision.reason) {
                detailSecondary = "Why: \(reason)"
            }

        case .contact:
            let c = ScreenActionsCore.ContactParser.detect(in: cleanedText)
            var parts: [String] = []
            if !c.emails.isEmpty { parts.append(pluralCount(c.emails.count, singular: "email")) }
            if !c.phones.isEmpty { parts.append(pluralCount(c.phones.count, singular: "phone")) }
            if c.postalAddress != nil { parts.append("address") }

            detailPrimary = parts.isEmpty ? "No contact fields detected" : parts.joined(separator: " · ")
            if let reason = cleanedDecisionReason(decision.reason) {
                detailSecondary = "Why: \(reason)"
            }

        case .receipt:
            let lines = cleanedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            detailPrimary = "\(lines.count) lines"
            if let reason = cleanedDecisionReason(decision.reason) {
                detailSecondary = "Why: \(reason)"
            }
        }

        return ClipboardStatusModel(
            isEmpty: false,
            title: title,
            preview: preview,
            capturedAt: snapshot.capturedAt,
            suggestedKind: decision.kind,
            suggestedReason: decision.reason,
            detailPrimary: detailPrimary,
            detailSecondary: detailSecondary,
            lastActionMessage: snapshot.lastActionMessage,
            lastActionAt: snapshot.lastActionAt,
            exportedFileName: exportedFileName
        )
    }

    private func cleanedDecisionReason(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return String(trimmed.prefix(60))
    }

    private func pluralCount(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        return "\(count) \(singular)s"
    }

    private func formatDateRange(start: Date, end: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.timeZone = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.doesRelativeDateFormatting = true

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let day = dateFormatter.string(from: start)
        let startTime = timeFormatter.string(from: start)
        let endTime = timeFormatter.string(from: end)

        return "\(day) \(startTime)–\(endTime)"
    }

    private func formatDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateStyle = .medium
        df.timeStyle = .short
        df.doesRelativeDateFormatting = true
        return df.string(from: date)
    }
}
