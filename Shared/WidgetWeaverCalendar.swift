//
//  WidgetWeaverCalendar.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Next Up (Calendar) support:
//  - App Group snapshot store (like Weather)
//  - EventKit engine to refresh snapshot
//  - Template view for Home Screen widgets
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
    public var location: String?
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool

    public init(
        title: String,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) {
        self.title = title
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }

    public func normalised() -> WidgetWeaverCalendarEvent {
        var e = self
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        e.title = t.isEmpty ? "Untitled Event" : String(t.prefix(120))

        if let loc = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            e.location = String(loc.prefix(120))
        } else {
            e.location = nil
        }
        return e
    }
}

public struct WidgetWeaverCalendarSnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var next: WidgetWeaverCalendarEvent?
    public var after: WidgetWeaverCalendarEvent?

    public init(
        fetchedAt: Date,
        next: WidgetWeaverCalendarEvent?,
        after: WidgetWeaverCalendarEvent?
    ) {
        self.fetchedAt = fetchedAt
        self.next = next
        self.after = after
    }

    public static func sample(now: Date = Date()) -> WidgetWeaverCalendarSnapshot {
        let cal = Calendar.autoupdatingCurrent
        let base = cal.dateInterval(of: .minute, for: now)?.start ?? now

        let nextStart = base.addingTimeInterval(18 * 60)
        let nextEnd = nextStart.addingTimeInterval(45 * 60)

        let afterStart = base.addingTimeInterval(120 * 60)
        let afterEnd = afterStart.addingTimeInterval(60 * 60)

        let next = WidgetWeaverCalendarEvent(
            title: "Standup",
            location: "Meeting Room 2",
            startDate: nextStart,
            endDate: nextEnd,
            isAllDay: false
        )

        let after = WidgetWeaverCalendarEvent(
            title: "Lunch",
            location: "Café",
            startDate: afterStart,
            endDate: afterEnd,
            isAllDay: false
        )

        return WidgetWeaverCalendarSnapshot(
            fetchedAt: now,
            next: next,
            after: after
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

    @inline(__always)
    private func sync() {
        defaults.synchronize()
        UserDefaults.standard.synchronize()
    }

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSnapshot() -> WidgetWeaverCalendarSnapshot? {
        sync()

        if let data = defaults.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverCalendarSnapshot.self, from: data) {
            return snap
        }

        if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverCalendarSnapshot.self, from: data) {
            if let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.snapshotData)
            }
            sync()
            return snap
        }

        return nil
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverCalendarSnapshot?) {
        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshotData)
            UserDefaults.standard.set(data, forKey: Keys.snapshotData)
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }
        sync()
    }

    public func clearSnapshot() {
        defaults.removeObject(forKey: Keys.snapshotData)
        UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        sync()
    }

    public func loadLastError() -> String? {
        sync()

        if let s = defaults.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }

        if let s = UserDefaults.standard.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                defaults.set(t, forKey: Keys.lastError)
                sync()
                return t
            }
        }

        return nil
    }

    public func saveLastError(_ error: String?) {
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: Keys.lastError)
            UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }
        sync()
    }

    public func clearLastError() {
        defaults.removeObject(forKey: Keys.lastError)
        UserDefaults.standard.removeObject(forKey: Keys.lastError)
        sync()
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
        if let snap = loadSnapshot() { return snap }
        switch context {
        case .preview, .simulator:
            return .sample()
        case .widget:
            return nil
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
        public var snapshot: WidgetWeaverCalendarSnapshot?
        public var errorDescription: String?

        public init(snapshot: WidgetWeaverCalendarSnapshot?, errorDescription: String?) {
            self.snapshot = snapshot
            self.errorDescription = errorDescription
        }
    }

    public var minimumUpdateInterval: TimeInterval = 60

    private var inFlight: Task<Result, Never>?

    public func updateIfNeeded(force: Bool = false) async -> Result {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.update(force: force) }
        inFlight = task
        let out = await task.value
        inFlight = nil
        return out
    }

    /// Intended for the main app (permission prompt).
    public func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            if status == .fullAccess { return true }
            if status != .notDetermined { return false }

            let store = EKEventStore()
            do {
                let granted = try await store.requestFullAccessToEvents()
                return granted
            } catch {
                return false
            }
        } else {
            if status == .authorized { return true }
            if status != .notDetermined { return false }

            let store = EKEventStore()
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func update(force: Bool) async -> Result {
        let store = WidgetWeaverCalendarStore.shared

        guard store.canReadEvents() else {
            store.saveLastError("Calendar access not enabled.")
            store.saveSnapshot(nil)
            notifyWidgetsCalendarUpdated()
            return Result(snapshot: nil, errorDescription: "Calendar access not enabled.")
        }

        if !force, let existing = store.loadSnapshot() {
            let age = Date().timeIntervalSince(existing.fetchedAt)
            if age < minimumUpdateInterval {
                store.saveLastError(nil)
                return Result(snapshot: existing, errorDescription: nil)
            }
        }

        do {
            let snap = try fetchSnapshot(now: Date()).normalised()
            store.saveSnapshot(snap)
            store.saveLastError(nil)
            notifyWidgetsCalendarUpdated()
            return Result(snapshot: snap, errorDescription: nil)
        } catch {
            let message = String(describing: error)
            store.saveLastError(message)
            notifyWidgetsCalendarUpdated()
            return Result(snapshot: store.loadSnapshot(), errorDescription: message)
        }
    }

    private func fetchSnapshot(now: Date) throws -> WidgetWeaverCalendarSnapshot {
        let eventStore = EKEventStore()

        // Include a small past window to catch “currently happening” events.
        let start = now.addingTimeInterval(-60 * 60)
        let end = now.addingTimeInterval(24 * 60 * 60)

        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)

        let all = eventStore.events(matching: predicate)

        let upcoming = all
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        // Prefer non-all-day for “Next Up”.
        let nonAllDay = upcoming.filter { !$0.isAllDay }
        let chosen = nonAllDay.isEmpty ? upcoming : nonAllDay

        guard let first = chosen.first else {
            return WidgetWeaverCalendarSnapshot(fetchedAt: now, next: nil, after: nil)
        }

        let second = chosen.dropFirst().first

        let next = WidgetWeaverCalendarEvent(
            title: first.title,
            location: first.location,
            startDate: first.startDate,
            endDate: first.endDate,
            isAllDay: first.isAllDay
        ).normalised()

        let after = second.map {
            WidgetWeaverCalendarEvent(
                title: $0.title,
                location: $0.location,
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay
            ).normalised()
        }

        return WidgetWeaverCalendarSnapshot(fetchedAt: now, next: next, after: after)
    }

    private func notifyWidgetsCalendarUpdated() {
        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }
}

private extension WidgetWeaverCalendarSnapshot {
    func normalised() -> WidgetWeaverCalendarSnapshot {
        var s = self
        s.next = s.next?.normalised()
        s.after = s.after?.normalised()
        return s
    }
}

// MARK: - Countdown helpers (shared by template + lock screen widget)

@inline(__always)
func wwCalendarShortCountdownValue(now: Date, start: Date, end: Date) -> String {
    if start <= now, end > now {
        return wwCalendarCompactIntervalString(seconds: end.timeIntervalSince(now))
    }
    if start > now {
        return wwCalendarCompactIntervalString(seconds: start.timeIntervalSince(now))
    }
    return "Now"
}

@inline(__always)
func wwCalendarCountdownLabel(now: Date, start: Date, end: Date) -> String {
    if start <= now, end > now {
        return "ends in \(wwCalendarCompactIntervalString(seconds: end.timeIntervalSince(now)))"
    }
    if start > now {
        return "in \(wwCalendarCompactIntervalString(seconds: start.timeIntervalSince(now)))"
    }
    return "now"
}

private func wwCalendarCompactIntervalString(seconds: TimeInterval) -> String {
    let s = max(0, seconds)
    let minutes = Int(ceil(s / 60.0))

    if minutes < 60 {
        return "\(minutes)m"
    }

    let hours = minutes / 60
    let remM = minutes % 60

    if hours < 24 {
        if remM == 0 { return "\(hours)h" }
        return "\(hours)h \(remM)m"
    }

    let days = Int(ceil(Double(hours) / 24.0))
    return "\(days)d"
}

// MARK: - Template View (Layout Template)

struct NextUpCalendarTemplateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let accent: Color

    init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext, accent: Color) {
        self.spec = spec
        self.family = family
        self.context = context
        self.accent = accent
    }

    var body: some View {
        let store = WidgetWeaverCalendarStore.shared
        let snapshot = store.snapshotForRender(context: context)
        let hasAccess: Bool = (context == .widget) ? store.canReadEvents() : true

        Group {
            if context == .widget || context == .simulator {
                TimelineView(.periodic(from: Date(), by: 60)) { timeline in
                    content(snapshot: snapshot, now: timeline.date, hasAccess: hasAccess)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(accent)
                    Text("Next Up")
                        .font(.headline)
                }
                Text("Enable Calendar access in the app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Tap to open settings")
                    .font(.caption2)
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let snap = snapshot, let next = snap.next {
            filled(next: next, after: snap.after, now: now)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(accent)
                    Text("Next Up")
                        .font(.headline)
                }
                Text("No upcoming events.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func filled(next: WidgetWeaverCalendarEvent, after: WidgetWeaverCalendarEvent?, now: Date) -> some View {
        let countdown = wwCalendarCountdownLabel(now: now, start: next.startDate, end: next.endDate)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(accent)
                Text("Next Up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(countdown)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(next.title)
                .font(family == .systemSmall ? .headline : .title3)
                .lineLimit(family == .systemSmall ? 2 : 3)

            if let loc = next.location {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let after, family == .systemSmall {
                let afterText = wwCalendarCountdownLabel(now: now, start: after.startDate, end: after.endDate)
                Text("After that: \(after.title) (\(afterText))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func accessibilityLabel(snapshot: WidgetWeaverCalendarSnapshot?, hasAccess: Bool) -> String {
        if !hasAccess { return "Next Up. Calendar access not enabled." }
        guard let snapshot, let next = snapshot.next else { return "Next Up. No upcoming events." }
        return "Next Up. \(next.title). \(wwCalendarCountdownLabel(now: Date(), start: next.startDate, end: next.endDate))."
    }
}
