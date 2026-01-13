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
            WidgetWeaverActionInboxStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Makes the widget itself useful: tap anywhere (not a button) to run the shortcut.
                .widgetURL(ActionInboxShortcuts.runURL)
        }
        .configurationDisplayName("Action Inbox")
        .description("Shows the last text sent to WidgetWeaver and a suggested action.")
        .supportedFamilies([.systemSmall, .systemMedium])

        // IMPORTANT:
        // No .contentMarginsDisabled() here. Disabling margins is what causes the rounded-corner clipping.
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
            completion(Timeline(entries: [Entry(date: now, snapshot: snap)], policy: .after(now.addingTimeInterval(60 * 60))))
        }
    }
}

// MARK: - Shortcuts links

private enum ActionInboxShortcuts {
    /// Shortcut name to run from the widget background tap + Run button.
    static let runShortcutName: String = "WW AutoDetect"

    static var runURL: URL {
        let encoded = runShortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? runShortcutName
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")!
    }

    static let openAppURL: URL = URL(string: "widgetweaver://clipboard")!
}

// MARK: - View

private struct ActionInboxModel {
    var isEmpty: Bool

    var title: String
    var lines: [String]

    var kind: ScreenActionKind?
    var detailLine: String?

    var capturedAt: Date?
    var lastActionMessage: String?
    var lastActionAt: Date?

    var exportedFileName: String?
}

private struct WidgetWeaverActionInboxStatusView: View {
    let entry: WidgetWeaverClipboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let model = buildModel(snapshot: entry.snapshot)

        Group {
            if model.isEmpty {
                ViewThatFits(in: .vertical) {
                    emptyFull(model: model)
                    emptyCompact(model: model)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    full(model: model)
                    compact(model: model)
                    minimal(model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Layout variants (ViewThatFits)

    private func full(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            VStack(alignment: .leading, spacing: 8) {
                titleRow(model: model)

                if let preview = previewText(lines: model.lines, maxLines: family == .systemSmall ? 3 : 5) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? 3 : 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let detail = model.detailLine, !detail.isEmpty {
                    infoRow(systemImage: "info.circle", text: detail)
                }

                if let msg = model.lastActionMessage, !msg.isEmpty {
                    lastActionRow(message: msg, at: model.lastActionAt)
                }

                if family == .systemMedium, let file = model.exportedFileName, !file.isEmpty {
                    infoRow(systemImage: "doc.text", text: "Last export: \(file)")
                }
            }

            Spacer(minLength: 0)

            controls(model: model)
        }
    }

    private func compact(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            VStack(alignment: .leading, spacing: 8) {
                titleRow(model: model)

                if let preview = previewText(lines: model.lines, maxLines: family == .systemSmall ? 2 : 3) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let detail = model.detailLine, !detail.isEmpty {
                    infoRow(systemImage: "info.circle", text: detail)
                }
            }

            Spacer(minLength: 0)

            controls(model: model)
        }
    }

    private func minimal(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)
            titleRow(model: model)
            Spacer(minLength: 0)
            controls(model: model)
        }
    }

    private func emptyFull(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            Text("No text yet")
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Text("Tap the widget (or Run) to execute “\(ActionInboxShortcuts.runShortcutName)” and send clipboard text here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 3 : 4)

            Spacer(minLength: 0)

            controls(model: model)
        }
    }

    private func emptyCompact(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            Text("No text yet")
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("Tap to run “\(ActionInboxShortcuts.runShortcutName)”.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            controls(model: model)
        }
    }

    // MARK: - Building blocks

    private func header(model: ActionInboxModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.headline)

            Text("Action Inbox")
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let capturedAt = model.capturedAt {
                Text(capturedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func titleRow(model: ActionInboxModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let kind = model.kind {
                kindPill(kind: kind)
            }
        }
    }

    private func infoRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func lastActionRow(message: String, at: Date?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let at {
                Text(at, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func controls(model: ActionInboxModel) -> some View {
        HStack(spacing: 10) {
            Link(destination: ActionInboxShortcuts.runURL) {
                Label("Run", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)

            if family == .systemMedium {
                Link(destination: ActionInboxShortcuts.openAppURL) {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            Button(intent: WidgetWeaverClipboardClearInboxIntent()) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(model.isEmpty)
        }
        .labelStyle(.iconOnly)
    }

    private func kindPill(kind: ScreenActionKind) -> some View {
        let (symbol, label) = kindBadge(kind)
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private func kindBadge(_ kind: ScreenActionKind) -> (String, String) {
        switch kind {
        case .reminder: return ("checklist", "Reminder")
        case .event:    return ("calendar", "Event")
        case .contact:  return ("person.crop.circle", "Contact")
        case .receipt:  return ("tablecells", "Receipt")
        }
    }

    // MARK: - Model

    private func buildModel(snapshot: WidgetWeaverClipboardInboxSnapshot) -> ActionInboxModel {
        let cleanedText: String? = {
            guard let t = snapshot.text else { return nil }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let lines: [String] = {
            guard let cleanedText else { return [] }
            return cleanedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }()

        let title: String = {
            guard let first = lines.first else { return "No text" }
            return String(first.prefix(80))
        }()

        let exportedFileName: String? = {
            guard let path = snapshot.lastExportedCSVPath, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path).lastPathComponent
        }()

        guard let cleanedText else {
            return ActionInboxModel(
                isEmpty: true,
                title: title,
                lines: [],
                kind: nil,
                detailLine: nil,
                capturedAt: snapshot.capturedAt,
                lastActionMessage: snapshot.lastActionMessage,
                lastActionAt: snapshot.lastActionAt,
                exportedFileName: exportedFileName
            )
        }

        let decision = ScreenActionsCore.ActionRouter.route(text: cleanedText)
        let detail = buildDetailLine(text: cleanedText, kind: decision.kind, dateRange: decision.dateRange)

        return ActionInboxModel(
            isEmpty: false,
            title: title.isEmpty ? "Untitled" : title,
            lines: lines,
            kind: decision.kind,
            detailLine: detail,
            capturedAt: snapshot.capturedAt,
            lastActionMessage: snapshot.lastActionMessage,
            lastActionAt: snapshot.lastActionAt,
            exportedFileName: exportedFileName
        )
    }

    private func previewText(lines: [String], maxLines: Int) -> String? {
        guard !lines.isEmpty else { return nil }
        return lines.prefix(maxLines).joined(separator: "\n")
    }

    private func buildDetailLine(text: String, kind: ScreenActionKind, dateRange: ScreenActionsCore.DetectedDateRange?) -> String? {
        switch kind {
        case .event:
            let r = dateRange ?? ScreenActionsCore.DateParser.firstDateRange(in: text)
            guard let r else { return "When: No date detected" }
            return "When: \(formatDateRange(start: r.start, end: r.end))"

        case .reminder:
            let due = (dateRange ?? ScreenActionsCore.DateParser.firstDateRange(in: text))?.start
            guard let due else { return "Due: No date detected" }
            return "Due: \(formatDateTime(due))"

        case .contact:
            let c = ScreenActionsCore.ContactParser.detect(in: text)
            var parts: [String] = []
            if !c.emails.isEmpty { parts.append(countString(c.emails.count, singular: "email")) }
            if !c.phones.isEmpty { parts.append(countString(c.phones.count, singular: "phone")) }
            if c.postalAddress != nil { parts.append("address") }
            return parts.isEmpty ? "No contact fields detected" : parts.joined(separator: " · ")

        case .receipt:
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return "\(lines.count) lines"
        }
    }

    private func countString(_ count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    private func formatDateRange(start: Date, end: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = .current
        dayFormatter.timeZone = .current
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none
        dayFormatter.doesRelativeDateFormatting = true

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let day = dayFormatter.string(from: start)
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
