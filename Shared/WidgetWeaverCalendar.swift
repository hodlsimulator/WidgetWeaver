//
//  WidgetWeaverCalendar.swift
//  WidgetWeaver
//
//  Calendar snapshot store + EventKit engine + “Next Up” calendar template view.
//

import Foundation
import EventKit
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Models

public struct WidgetWeaverCalendarEvent: Codable, Hashable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
    }
}

public struct WidgetWeaverCalendarSnapshot: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var next: WidgetWeaverCalendarEvent?
    public var second: WidgetWeaverCalendarEvent?

    public init(
        generatedAt: Date,
        next: WidgetWeaverCalendarEvent?,
        second: WidgetWeaverCalendarEvent?
    ) {
        self.generatedAt = generatedAt
        self.next = next
        self.second = second
    }

    public static func sample(now: Date = Date()) -> WidgetWeaverCalendarSnapshot {
        let a = WidgetWeaverCalendarEvent(
            title: "Stand-up",
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60),
            isAllDay: false,
            location: "Room 2"
        )
        let b = WidgetWeaverCalendarEvent(
            title: "Lunch",
            startDate: now.addingTimeInterval(2 * 60 * 60),
            endDate: now.addingTimeInterval(3 * 60 * 60),
            isAllDay: false,
            location: nil
        )
        return WidgetWeaverCalendarSnapshot(
            generatedAt: now,
            next: a,
            second: b
        )
    }
}

// MARK: - Store

public final class WidgetWeaverCalendarStore: @unchecked Sendable {
    public static let shared = WidgetWeaverCalendarStore()

    public enum Keys {
        public static let snapshotData = "widgetweaver.calendar.snapshot.v1"
        public static let lastError = "widgetweaver.calendar.lastError.v1"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func loadSnapshot() -> WidgetWeaverCalendarSnapshot? {
        guard let data = defaults.data(forKey: Keys.snapshotData) else { return nil }
        return try? decoder.decode(WidgetWeaverCalendarSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverCalendarSnapshot?) {
        if let snapshot {
            if let data = try? encoder.encode(snapshot) {
                defaults.set(data, forKey: Keys.snapshotData)
                defaults.set("", forKey: Keys.lastError)
            }
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
        }
    }

    public func setLastError(_ message: String) {
        defaults.set(message, forKey: Keys.lastError)
    }

    public func lastError() -> String? {
        let v = defaults.string(forKey: Keys.lastError) ?? ""
        return v.isEmpty ? nil : v
    }

    public func canReadEvents() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    public func snapshotForRender(context: WidgetWeaverRenderContext) -> WidgetWeaverCalendarSnapshot? {
        switch context {
        case .widget:
            return loadSnapshot()
        case .preview, .simulator:
            return loadSnapshot() ?? .sample()
        }
    }

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        60
    }
}

// MARK: - Engine

public actor WidgetWeaverCalendarEngine {
    public static let shared = WidgetWeaverCalendarEngine()

    public struct Result: Sendable {
        public var didUpdate: Bool
        public var generatedAt: Date?
        public var errorMessage: String?

        public init(didUpdate: Bool, generatedAt: Date?, errorMessage: String?) {
            self.didUpdate = didUpdate
            self.generatedAt = generatedAt
            self.errorMessage = errorMessage
        }
    }

    public var minimumUpdateInterval: TimeInterval = 60

    private var inFlight: Task<Result, Never>?
    private var lastUpdateAt: Date?

    private let store = WidgetWeaverCalendarStore.shared
    private let eventStore = EKEventStore()

    public func updateIfNeeded(force: Bool = false) async -> Result {
        if let inFlight {
            return await inFlight.value
        }

        let t = Task<Result, Never> { [weak self] in
            guard let self else {
                return Result(didUpdate: false, generatedAt: nil, errorMessage: "Update cancelled.")
            }

            let r = await self.update(force: force)
            await self.clearInFlight()
            return r
        }

        inFlight = t
        return await t.value
    }

    private func clearInFlight() {
        inFlight = nil
    }

    public func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, *) {
            if status == .fullAccess { return true }
            if status != .notDetermined { return false }

            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                return granted
            } catch {
                return false
            }
        } else {
            if status == .authorized { return true }
            if status != .notDetermined { return false }

            return await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func update(force: Bool) async -> Result {
        let now = Date()

        if !force, let lastUpdateAt {
            let dt = now.timeIntervalSince(lastUpdateAt)
            if dt < minimumUpdateInterval {
                return Result(didUpdate: false, generatedAt: nil, errorMessage: nil)
            }
        }

        guard store.canReadEvents() else {
            store.saveSnapshot(nil)
            store.setLastError("Calendar access not granted.")
            await notifyWidgetsCalendarUpdated()
            lastUpdateAt = now
            return Result(didUpdate: true, generatedAt: nil, errorMessage: "Calendar access not granted.")
        }

        do {
            let snap = try await fetchSnapshot(now: now)
            store.saveSnapshot(snap)
            store.setLastError("")
            await notifyWidgetsCalendarUpdated()
            lastUpdateAt = now
            return Result(didUpdate: true, generatedAt: snap.generatedAt, errorMessage: nil)
        } catch {
            store.saveSnapshot(nil)
            store.setLastError(error.localizedDescription)
            await notifyWidgetsCalendarUpdated()
            lastUpdateAt = now
            return Result(didUpdate: true, generatedAt: nil, errorMessage: error.localizedDescription)
        }
    }

    private func fetchSnapshot(now: Date) async throws -> WidgetWeaverCalendarSnapshot {
        let calendars = eventStore.calendars(for: .event)
        let end = now.addingTimeInterval(24 * 60 * 60)

        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)

        let future = events
            .filter { $0.endDate > now }
            .sorted { a, b in
                a.startDate < b.startDate
            }

        let mapped: [WidgetWeaverCalendarEvent] = future.prefix(10).map { e in
            WidgetWeaverCalendarEvent(
                title: (e.title ?? "").isEmpty ? "Untitled" : (e.title ?? "Untitled"),
                startDate: e.startDate,
                endDate: e.endDate,
                isAllDay: e.isAllDay,
                location: e.location
            )
        }

        let next = mapped.first
        let second = mapped.dropFirst().first

        return WidgetWeaverCalendarSnapshot(
            generatedAt: now,
            next: next,
            second: second
        )
    }

    private func notifyWidgetsCalendarUpdated() async {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        #endif
    }
}

// MARK: - Formatting helpers

private func wwCalendarShortCountdownValue(from now: Date, to start: Date) -> String {
    let dt = max(0, start.timeIntervalSince(now))
    let minutes = Int(dt / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = Int(Double(minutes) / 60.0)
    return "\(hours)h"
}

private func wwCalendarCountdownLabel(from now: Date, to start: Date) -> String {
    let dt = max(0, start.timeIntervalSince(now))
    let minutes = Int(dt / 60)
    if minutes <= 1 { return "Soon" }
    if minutes < 60 { return "In \(minutes) min" }
    let hours = Int(Double(minutes) / 60.0)
    return "In \(hours) hr"
}

private func wwCalendarTimeRangeString(_ start: Date, _ end: Date) -> String {
    let f = DateFormatter()
    f.locale = .current
    f.timeStyle = .short
    f.dateStyle = .none
    return "\(f.string(from: start))–\(f.string(from: end))"
}

// MARK: - Template View (Calendar)

public struct NextUpCalendarTemplateView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext
    public let accent: Color

    @AppStorage(WidgetWeaverCalendarStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var calendarSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverCalendarStore.Keys.lastError, store: AppGroup.userDefaults)
    private var calendarLastError: String = ""

    @Environment(\.openURL) private var openURL

    @State private var accessRequestInFlight: Bool = false

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext, accent: Color) {
        self.spec = spec
        self.family = family
        self.context = context
        self.accent = accent
    }

    public var body: some View {
        let _ = calendarSnapshotData
        let _ = calendarLastError

        let store = WidgetWeaverCalendarStore.shared
        let hasAccess = store.canReadEvents()
        let snapshot = store.snapshotForRender(context: context)

        Group {
            if context == .widget || context == .simulator {
                TimelineView(.periodic(from: Date(), by: 60)) { tl in
                    content(snapshot: snapshot, now: tl.date, hasAccess: hasAccess)
                }
            } else {
                content(snapshot: snapshot, now: Date(), hasAccess: hasAccess)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(snapshot: snapshot, hasAccess: hasAccess))
    }

    @ViewBuilder
    private func content(snapshot: WidgetWeaverCalendarSnapshot?, now: Date, hasAccess: Bool) -> some View {
        if !hasAccess {
            noAccessView
        } else if let snap = snapshot, let next = snap.next {
            filledView(snapshot: snap, next: next, now: now)
        } else {
            emptyView
        }
    }

    private var noAccessView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(accent)
                    .opacity(0.9)
            }

            Text("Calendar access is off.")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("Enable access to show your upcoming events.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if context != .widget {
                HStack(spacing: 10) {
                    Button {
                        guard !accessRequestInFlight else { return }
                        accessRequestInFlight = true
                        Task {
                            let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()
                            if granted {
                                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                            }
                            await MainActor.run {
                                accessRequestInFlight = false
                            }
                        }
                    } label: {
                        Label(accessRequestInFlight ? "Requesting…" : "Enable", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(accessRequestInFlight)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                Text("Open the app to enable access.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let err = WidgetWeaverCalendarStore.shared.lastError() {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    private func filledView(snapshot: WidgetWeaverCalendarSnapshot, next: WidgetWeaverCalendarEvent, now: Date) -> some View {
        let header = (family == .systemSmall) ? "Next" : "Next Up"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(wwCalendarShortCountdownValue(from: now, to: next.startDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(next.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? 2 : 3)

                Text(wwCalendarCountdownLabel(from: now, to: next.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(wwCalendarTimeRangeString(next.startDate, next.endDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let loc = next.location, !loc.isEmpty, family != .systemSmall {
                    Text(loc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if family != .systemSmall, let second = snapshot.second {
                Divider().opacity(0.35)

                HStack(alignment: .firstTextBaseline) {
                    Text("Then")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(wwCalendarShortCountdownValue(from: now, to: second.startDate))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent.opacity(0.85))
                }

                Text(second.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: "calendar")
                    .foregroundStyle(accent)
                    .opacity(0.9)
            }

            Text("No upcoming events.")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("Events refresh on a cache. Open the app to update now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
    }

    private func accessibilityLabel(snapshot: WidgetWeaverCalendarSnapshot?, hasAccess: Bool) -> String {
        if !hasAccess { return "Calendar access is off." }
        guard let next = snapshot?.next else { return "No upcoming events." }
        return "Next event: \(next.title)."
    }
}
