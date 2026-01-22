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
            let enabled = WidgetWeaverFeatureFlags.clipboardActionsEnabled
            let url = enabled ? ActionInboxShortcuts.runAppURL : ActionInboxShortcuts.openAppURL

            Group {
                if enabled {
                    WidgetWeaverActionInboxStatusView(entry: entry)
                } else {
                    WidgetWeaverClipboardActionsDisabledView()
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            // Background tap is mapped to a sensible action (Run when enabled, Open when disabled).
            .widgetURL(url)
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

        private func snapshot(for context: Context) -> WidgetWeaverClipboardInboxSnapshot {
            if context.isPreview { return placeholder(in: context).snapshot }
            guard WidgetWeaverFeatureFlags.clipboardActionsEnabled else { return WidgetWeaverClipboardInboxSnapshot() }
            return WidgetWeaverClipboardInboxStore.load()
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let snap = snapshot(for: context)
            completion(Entry(date: Date(), snapshot: snap))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let snap = snapshot(for: context)
            let now = Date()
            completion(Timeline(entries: [Entry(date: now, snapshot: snap)], policy: .after(now.addingTimeInterval(60 * 60))))
        }
    }
}

// MARK: - Shortcuts links

private enum ActionInboxShortcuts {
    /// Shortcut name to run from the widget Run button (and background tap when enabled).
    static let runShortcutName: String = "WW AutoDetect"

    static var runAppURL: URL {
        let encoded = runShortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? runShortcutName
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")!
    }

    static let openAppURL: URL = URL(string: "widgetweaver://clipboard")!
}

// MARK: - View

private struct WidgetWeaverClipboardActionsDisabledView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.slash")
                    .font(.headline)

                Text("Action Inbox")
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text("Hidden by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemMedium ? 3 : 2)

            Spacer(minLength: 0)

            if family == .systemMedium {
                HStack(spacing: 10) {
                    Link(destination: ActionInboxShortcuts.openAppURL) {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding()
    }

    private var detailText: String {
        "Enable Clipboard Actions in Feature Flags to use this widget."
    }
}

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
                }
            }
        }
    }

    private func full(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(model: model)
            content(model: model, maxLines: family == .systemSmall ? 4 : 6)
            footer(model: model)
            controls(model: model)
        }
        .padding()
    }

    private func compact(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(model: model)
            content(model: model, maxLines: family == .systemSmall ? 2 : 3)
            Spacer(minLength: 0)
            controls(model: model)
        }
        .padding()
    }

    private func emptyFull(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.headline)
                Text("Action Inbox")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            Text("Send text into WidgetWeaver, then run AutoDetect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            controls(model: model)
        }
        .padding()
    }

    private func emptyCompact(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.headline)
                Text("Action Inbox")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            Text("No text yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            controls(model: model)
        }
        .padding()
    }

    private func header(model: ActionInboxModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)

                if let kind = model.kind {
                    kindPill(kind: kind)
                } else {
                    Text("No suggestion")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let capturedAt = model.capturedAt {
                Text(capturedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func content(model: ActionInboxModel, maxLines: Int) -> some View {
        let preview = previewText(lines: model.lines, maxLines: maxLines) ?? "—"
        return VStack(alignment: .leading, spacing: 6) {
            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(maxLines)

            if let detail = model.detailLine {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let exported = model.exportedFileName {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(exported)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func footer(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                let message = (model.lastActionMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                Text(message.isEmpty ? "No actions yet." : message)
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

    private func controls(model: ActionInboxModel) -> some View {
        HStack(spacing: 10) {
            Link(destination: ActionInboxShortcuts.runAppURL) {
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

    private func buildDetailLine(text: String, kind: ScreenActionKind?, dateRange: ScreenActionsCore.DetectedDateRange?) -> String? {
        switch kind {
        case .reminder:
            return "Reminder suggestion"

        case .event:
            if let range = dateRange {
                let start = range.start
                let end = range.end
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .short
                return "\(df.string(from: start)) → \(df.string(from: end))"
            }
            return "Event suggestion"

        case .contact:
            return "Contact suggestion"

        case .receipt:
            return "Receipt suggestion"

        case .none:
            return nil
        }
    }
}
