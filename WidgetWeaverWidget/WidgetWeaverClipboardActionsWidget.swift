//
//  WidgetWeaverClipboardActionsWidget.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

#if CLIPBOARD_ACTIONS
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
        .configurationDisplayName("Clipboard Actions")
        .description("Parked: internal builds only.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    // MARK: - Provider

    private struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date(), snapshot: .sample())
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let snap = snapshot(for: context)
            completion(Entry(date: Date(), snapshot: snap))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let snap = snapshot(for: context)

            // Keep it very lightweight: this widget is parked and should not do heavy work.
            let entry = Entry(date: Date(), snapshot: snap)
            let next = Date().addingTimeInterval(60 * 10)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }

        private func snapshot(for context: Context) -> WidgetWeaverClipboardInboxSnapshot {
            if context.isPreview {
                return .sample()
            }

            guard WidgetWeaverFeatureFlags.clipboardActionsEnabled else { return WidgetWeaverClipboardInboxSnapshot() }
            return WidgetWeaverClipboardInboxStore.load()
        }
    }

    // MARK: - Entry

    public struct Entry: TimelineEntry {
        public let date: Date
        public let snapshot: WidgetWeaverClipboardInboxSnapshot

        public init(date: Date, snapshot: WidgetWeaverClipboardInboxSnapshot) {
            self.date = date
            self.snapshot = snapshot
        }
    }
}

// MARK: - Views

private struct WidgetWeaverClipboardActionsDisabledView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)

                Text("Clipboard Actions")
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Text("Parked for this release.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Enable Clipboard Actions in Feature Flags to use this widget.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                Text("Open app")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

private struct WidgetWeaverActionInboxStatusView: View {
    let entry: WidgetWeaverClipboardActionsWidget.Entry

    var body: some View {
        let model = buildModel(snapshot: entry.snapshot)

        VStack(alignment: .leading, spacing: 10) {
            header(model: model)

            Divider()

            content(model: model)

            Spacer(minLength: 0)

            footer(model: model)
        }
        .padding(14)
    }

    private func header(model: ActionInboxModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: model.icon)
                .font(.title3)

            Text(model.title)
                .font(.headline)

            Spacer(minLength: 0)

            if let badge = model.badgeText {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .foregroundStyle(model.headerTint)
    }

    private func content(model: ActionInboxModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let primary = model.primaryLine {
                Text(primary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if let secondary = model.secondaryLine {
                Text(secondary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let detail = model.detailLine {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func footer(model: ActionInboxModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if model.showsClearButton {
                Button(intent: WidgetWeaverClipboardClearInboxIntent()) {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                    Text("Run")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model

    private struct ActionInboxModel {
        let icon: String
        let title: String
        let headerTint: AnyShapeStyle

        let badgeText: String?

        let primaryLine: String?
        let secondaryLine: String?
        let detailLine: String?

        let status: String?

        let showsClearButton: Bool
    }

    private func buildModel(snapshot: WidgetWeaverClipboardInboxSnapshot) -> ActionInboxModel {
        let cleanedText = snapshot.inboxText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInbox = !cleanedText.isEmpty

        if !hasInbox {
            let subtitle = "Paste or share text into the inbox, then run auto-detect."
            return ActionInboxModel(
                icon: "tray",
                title: "Action Inbox",
                headerTint: AnyShapeStyle(.secondary),
                badgeText: nil,
                primaryLine: "Empty",
                secondaryLine: subtitle,
                detailLine: nil,
                status: snapshot.lastActionMessage,
                showsClearButton: false
            )
        }

        let decision = ScreenActionsCore.ActionRouter.route(text: cleanedText)

        let kind = ScreenActionKind(from: decision.kind)
        let detail = buildDetailLine(text: cleanedText, kind: kind, dateRange: decision.dateRange)

        let badge: String? = {
            switch kind {
            case .receipt: return "Receipt"
            case .event: return "Event"
            case .reminder: return "Reminder"
            case .contact: return "Contact"
            case .unknown: return nil
            }
        }()

        let title: String = {
            switch kind {
            case .receipt: return "Receipt"
            case .event: return "Event"
            case .reminder: return "Reminder"
            case .contact: return "Contact"
            case .unknown: return "Auto-detect"
            }
        }()

        let icon: String = {
            switch kind {
            case .receipt: return "doc.text"
            case .event: return "calendar"
            case .reminder: return "checklist"
            case .contact: return "person.crop.circle"
            case .unknown: return "sparkles"
            }
        }()

        let tint: AnyShapeStyle = {
            switch kind {
            case .receipt: return AnyShapeStyle(.blue)
            case .event: return AnyShapeStyle(.orange)
            case .reminder: return AnyShapeStyle(.green)
            case .contact: return AnyShapeStyle(.purple)
            case .unknown: return AnyShapeStyle(.secondary)
            }
        }()

        let primaryLine = cleanedText.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ActionInboxModel(
            icon: icon,
            title: title,
            headerTint: tint,
            badgeText: badge,
            primaryLine: primaryLine,
            secondaryLine: snapshot.lastActionMessage,
            detailLine: detail,
            status: snapshot.capturedAtText,
            showsClearButton: true
        )
    }

    private enum ScreenActionKind: String {
        case receipt
        case event
        case reminder
        case contact
        case unknown

        init(from kind: ScreenActionsCore.ScreenActionKind) {
            switch kind {
            case .receipt: self = .receipt
            case .event: self = .event
            case .reminder: self = .reminder
            case .contact: self = .contact
            @unknown default: self = .unknown
            }
        }
    }

    private func buildDetailLine(text: String, kind: ScreenActionKind?, dateRange: ScreenActionsCore.DetectedDateRange?) -> String? {
        guard let kind else { return nil }

        switch kind {
        case .receipt:
            return "Receipt-like text detected."

        case .event:
            if let dateRange {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = .current
                df.dateStyle = .medium
                df.timeStyle = .short
                return "\(df.string(from: dateRange.start)) → \(df.string(from: dateRange.end))"
            }
            return "Event-like text detected."

        case .reminder:
            if let dateRange {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = .current
                df.dateStyle = .medium
                df.timeStyle = .short
                return "Due \(df.string(from: dateRange.start))"
            }
            return "Reminder-like text detected."

        case .contact:
            return "Contact creation is disabled."

        case .unknown:
            return nil
        }
    }
}

// MARK: - Shortcuts

private enum ActionInboxShortcuts {
    static let openAppURL = URL(string: "widgetweaver://")!
    static let runAppURL = URL(string: "widgetweaver://clipboardActions/run")!
}

// MARK: - Sample

private extension WidgetWeaverClipboardInboxSnapshot {
    static func sample() -> WidgetWeaverClipboardInboxSnapshot {
        WidgetWeaverClipboardInboxSnapshot(
            inboxText: "Dinner with Alex\nFri 7pm\nThe Winding Stair",
            capturedAt: Date(),
            lastActionKind: "auto-event",
            lastActionMessage: "Event created.",
            lastActionExportedCSVURLString: nil,
            lastActionAt: Date()
        )
    }

    var capturedAtText: String? {
        guard let capturedAt else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateStyle = .none
        df.timeStyle = .short
        return "Captured \(df.string(from: capturedAt))"
    }
}
#endif
