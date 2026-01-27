//
//  WidgetWeaverWeatherSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import CoreLocation
@preconcurrency import MapKit
import WidgetKit
import UIKit

@MainActor
struct WidgetWeaverWeatherSettingsView: View {

    var onClose: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    @State private var query: String = ""
    @State private var isWorking: Bool = false

    @State private var toastItem: ToastItem? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    @State private var geocodeCandidates: [WidgetWeaverWeatherGeocodeCandidate] = []
    @State private var geocodeCandidatesQuery: String = ""
    @State private var geocodeCandidatesPresented: Bool = false

    @State private var savedLocation: WidgetWeaverWeatherLocation? = WidgetWeaverWeatherStore.shared.loadLocation()
    @State private var snapshot: WidgetWeaverWeatherSnapshot? = WidgetWeaverWeatherStore.shared.loadSnapshot()
    @State private var unitPreference: WidgetWeaverWeatherUnitPreference = WidgetWeaverWeatherStore.shared.loadUnitPreference()

    @State private var lastError: String? = WidgetWeaverWeatherStore.shared.loadLastError()

    @State private var lastRefreshAttemptAt: Date? = WidgetWeaverWeatherStore.shared.loadLastRefreshAttemptAt()
    @State private var lastSuccessfulRefreshAt: Date? = WidgetWeaverWeatherStore.shared.loadLastSuccessfulRefreshAt()

    @State private var locationAuthStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
    @State private var lowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    private let store = WidgetWeaverWeatherStore.shared

    var body: some View {
        List {
            headerSection
            locationSection
            unitsSection
            nowSection
            builtInVariablesSection
            autoRefreshSection
            attributionSection
            diagnosticsSection
        }
        .navigationTitle("Weather")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await updateNow(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isWorking || savedLocation == nil)
                .accessibilityLabel("Update now")

                if let onClose {
                    Button("Done") { onClose() }
                }

            }
        }
        .refreshable {
            await refreshFromPullToRefresh()
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .overlay { workingOverlay }
        .onAppear {
            refreshLocalState()
            refreshLocationAuthStatus()
            refreshSystemRefreshStatus()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let loc = savedLocation {
                query = loc.name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshLocationAuthStatus()
            refreshSystemRefreshStatus()
        }
        .sheet(isPresented: $geocodeCandidatesPresented) {
            NavigationStack {
                WidgetWeaverWeatherLocationSearchResultsView(
                    query: geocodeCandidatesQuery,
                    candidates: geocodeCandidates,
                    onSelect: { candidate in
                        Task { await saveGeocodeCandidate(candidate, fallbackQuery: geocodeCandidatesQuery) }
                    }
                )
            }
        }
        .tint(.blue)
    }

    @ViewBuilder
    private var workingOverlay: some View {
        if isWorking {
            ProgressView()
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Weather Pack", systemImage: "cloud.sun.fill")
                    .font(.headline)

                Text("Weather widgets refresh based on your saved location, unit preferences, and iOS background fetch windows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tip: if widgets feel stale, check Background App Refresh and Low Power Mode in the Auto-refresh section below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if let savedLocation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(savedLocation.name)
                        .font(.headline)

                    Text("Lat \(savedLocation.latitude, specifier: "%.4f"), Lon \(savedLocation.longitude, specifier: "%.4f")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("No location saved yet.")
                    .foregroundStyle(.secondary)
            }

            TextField("Search (city, town, postcode)", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Button {
                Task { await runGeocodeSearch() }
            } label: {
                Label("Search locations", systemImage: "magnifyingglass")
            }
            .disabled(trimmedQuery.isEmpty || isWorking)

            Button {
                Task { await useCurrentLocation() }
            } label: {
                Label(currentLocationButtonTitle, systemImage: "location.fill")
            }
            .disabled(isWorking)

            if locationAuthStatus == .denied || locationAuthStatus == .restricted {
                Button {
                    openAppSettings()
                } label: {
                    Label("Open Settings (Location)", systemImage: "gear")
                }
            }

            if let savedLocation {
                Button(role: .destructive) {
                    store.clearLocation()
                    refreshLocalState()
                    reloadWidgets()
                } label: {
                    Label("Clear location", systemImage: "trash")
                }
            }
        } footer: {
            Text("Weather widgets use the saved location. Searching uses Apple geocoding. Current Location requires permission.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Temperature", selection: $unitPreference) {
                ForEach(WidgetWeaverWeatherUnitPreference.allCases) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: unitPreference) { _, newValue in
                store.saveUnitPreference(newValue)
                reloadWidgets()
            }

            Text("Unit preference controls __weather_temp_* variables and the weather template display.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nowSection: some View {
        Section("Now") {
            if let snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.locationName)
                        .font(.headline)

                    Text("Updated \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let headline = snapshot.headline, !headline.isEmpty {
                        Text(headline)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Temp: \(snapshot.temperatureC, specifier: "%.1f")°C")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let precip = snapshot.precipitationNextHourTotalMM {
                        Text("Rain next hour: \(precip, specifier: "%.1f") mm")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("No snapshot yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await updateNow(force: true) }
            } label: {
                Label("Update now", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking || savedLocation == nil)

            if savedLocation == nil {
                Text("Set a location first to fetch weather.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let lastError, !lastError.isEmpty {
                Text("Last error: \(lastError)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var builtInVariablesSection: some View {
        let values = store.variablesDictionary()

        return Section("__weather_* variables") {
            if values.isEmpty {
                Text("No variables yet. Fetch weather to populate __weather_* keys.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    copyWeatherVariables(values)
                    showToast("Copied \(values.count) variables.", systemImage: "doc.on.doc")
                } label: {
                    Label("Copy all __weather_* values", systemImage: "doc.on.doc")
                }

                ForEach(values.keys.sorted(), id: \.self) { key in
                    let val = values[key] ?? ""
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(val.isEmpty ? "—" : val)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Button {
                            UIPasteboard.general.string = "{{\(key)}}"
                            showToast("Copied {{\(key)}}", systemImage: "doc.on.doc")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy snippet")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = "{{\(key)}}"
                        showToast("Copied {{\(key)}}", systemImage: "doc.on.doc")
                    }
                }
            }
        } footer: {
            Text("Tap a row to copy {{key}}. Widgets render from a cached snapshot, not live network calls.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var autoRefreshSection: some View {
        Section("Auto-refresh") {
            if let lastRefreshAttemptAt {
                Text("Last attempt \(lastRefreshAttemptAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No refresh attempts yet.")
                    .foregroundStyle(.secondary)
            }

            if let lastSuccessfulRefreshAt {
                Text("Last success \(lastSuccessfulRefreshAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No successful refresh yet.")
                    .foregroundStyle(.secondary)
            }


            HStack {
                Text("Background App Refresh")
                Spacer()
                Text(backgroundRefreshStatusLabel)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Low Power Mode")
                Spacer()
                Text(lowPowerModeEnabled ? "On" : "Off")
                    .foregroundStyle(.secondary)
            }

            Text(autoRefreshFooterText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var attributionSection: some View {
        Section("Attribution") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weather data is provided by Weather.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let url = store.attributionLegalURL() {
                    Link(destination: url) {
                        Label("Legal & data sources", systemImage: "link")
                    }
                } else {
                    Text("Legal link will appear after the first successful update.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Button {
                let loc = store.loadLocation()
                let snap = store.loadSnapshot()
                let err = store.loadLastError() ?? ""
                let msg = """
                Location: \(loc?.name ?? "nil")
                Snapshot: \(snap == nil ? "nil" : "present")
                Last error: \(err.isEmpty ? "none" : err)
                """
                UIPasteboard.general.string = msg
                showToast("Copied diagnostics.", systemImage: "doc.on.doc")
            } label: {
                Label("Copy diagnostics", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                store.clearLastError()
                refreshLocalState()
                reloadWidgets()
            } label: {
                Label("Clear last error", systemImage: "trash")
            }
            .disabled(lastError == nil)

            Button(role: .destructive) {
                store.clearRefreshTimestamps()
                refreshLocalState()
                reloadWidgets()
            } label: {
                Label("Clear refresh history", systemImage: "clock.arrow.circlepath")
            }
            .disabled(lastRefreshAttemptAt == nil && lastSuccessfulRefreshAt == nil)

            Button(role: .destructive) {
                store.resetAll()
                query = ""
                refreshLocalState()
                reloadWidgets()
            } label: {
                Label("Reset Weather", systemImage: "arrow.counterclockwise")
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastItem {
            WidgetWeaverToastView(text: toastItem.text, systemImage: toastItem.systemImage)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var currentLocationButtonTitle: String {
        switch locationAuthStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Use Current Location"
        case .notDetermined:
            return "Use Current Location"
        case .denied, .restricted:
            return "Use Current Location (Permission Needed)"
        @unknown default:
            return "Use Current Location"
        }
    }

    private func refreshLocationAuthStatus() {
        locationAuthStatus = CLLocationManager().authorizationStatus
    }

    private func refreshLocalState() {
        savedLocation = store.loadLocation()
        snapshot = store.loadSnapshot()
        unitPreference = store.loadUnitPreference()
        lastError = store.loadLastError()
        lastRefreshAttemptAt = store.loadLastRefreshAttemptAt()
        lastSuccessfulRefreshAt = store.loadLastSuccessfulRefreshAt()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.weather)
    }

    private func showToast(_ text: String, systemImage: String? = nil) {
        toastDismissTask?.cancel()
        toastDismissTask = nil

        withAnimation(.spring(duration: 0.35)) {
            toastItem = ToastItem(text: text, systemImage: systemImage)
        }

        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(.spring(duration: 0.35)) {
                toastItem = nil
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func refreshFromPullToRefresh() async {
        refreshLocalState()
        refreshLocationAuthStatus()
        refreshSystemRefreshStatus()

        guard savedLocation != nil else {
            showToast("Set a location first.", systemImage: "location.fill")
            return
        }

        await updateNow(force: true)
    }

    private func updateNow(force: Bool) async {
        guard !isWorking else { return }
        guard store.loadLocation() != nil else { return }

        isWorking = true
        defer { isWorking = false }

        _ = await store.refreshSnapshot(force: force)
        refreshLocalState()
        reloadWidgets()

        if let lastError, !lastError.isEmpty {
            showToast("Update failed.", systemImage: "exclamationmark.triangle.fill")
        } else {
            showToast("Weather updated.", systemImage: "checkmark.circle.fill")
        }
    }

    private func runGeocodeSearch() async {
        guard !isWorking else { return }

        let q = trimmedQuery
        guard !q.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let candidates = try await geocodeCandidatesForQuery(q)
            geocodeCandidates = candidates
            geocodeCandidatesQuery = q

            if candidates.isEmpty {
                showToast("No matches.", systemImage: "xmark.circle")
            } else if candidates.count == 1, let only = candidates.first {
                await saveGeocodeCandidate(only, fallbackQuery: q)
            } else {
                geocodeCandidatesPresented = true
            }
        } catch {
            showToast("Search failed.", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func saveGeocodeCandidate(_ candidate: WidgetWeaverWeatherGeocodeCandidate, fallbackQuery: String) async {
        geocodeCandidatesPresented = false

        let name = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackQuery : candidate.title

        let newLocation = WidgetWeaverWeatherLocation(
            name: name,
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )

        store.saveLocation(newLocation)
        refreshLocalState()
        reloadWidgets()

        showToast("Location saved.", systemImage: "checkmark.circle.fill")

        await updateNow(force: true)
    }

    private func useCurrentLocation() async {
        isWorking = true
        defer { isWorking = false }

        let status = CLLocationManager().authorizationStatus
        if status == .notDetermined {
            let ok = await requestWhenInUseAuthorisation()
            refreshLocationAuthStatus()
            if !ok {
                showToast("Location permission not granted.", systemImage: "exclamationmark.triangle.fill")
                return
            }
        }

        if CLLocationManager().authorizationStatus == .denied || CLLocationManager().authorizationStatus == .restricted {
            showToast("Location permission is off. Enable it in Settings.", systemImage: "exclamationmark.triangle.fill")
            return
        }

        do {
            let loc = try await currentLocationOnce()
            let place = try? await reverseGeocode(loc: loc)
            let name = place?.locality ?? place?.name ?? "Current Location"

            let newLocation = WidgetWeaverWeatherLocation(
                name: name,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )

            store.saveLocation(newLocation)
            query = name
            refreshLocalState()
            reloadWidgets()

            showToast("Location saved.", systemImage: "checkmark.circle.fill")

            await updateNow(force: true)
        } catch {
            showToast("Failed to read current location.", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func requestWhenInUseAuthorisation() async -> Bool {
        let manager = CLLocationManager()
        return await withCheckedContinuation { continuation in
            let delegate = WidgetWeaverLocationAuthDelegate { granted in
                continuation.resume(returning: granted)
            }
            manager.delegate = delegate
            objc_setAssociatedObject(manager, Unmanaged.passUnretained(manager).toOpaque(), delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            manager.requestWhenInUseAuthorization()
        }
    }

    private func currentLocationOnce() async throws -> CLLocation {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = WidgetWeaverLocationOnceDelegate { result in
                continuation.resume(with: result)
            }
            manager.delegate = delegate
            objc_setAssociatedObject(manager, Unmanaged.passUnretained(manager).toOpaque(), delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            manager.requestLocation()
        }
    }

    private func reverseGeocode(loc: CLLocation) async throws -> CLPlacemark? {
        let coder = CLGeocoder()
        let placemarks = try await coder.reverseGeocodeLocation(loc)
        return placemarks.first
    }

    private func copyWeatherVariables(_ values: [String: String]) {
        let lines = values
            .keys
            .sorted()
            .map { key in
                let value = values[key] ?? ""
                return "\(key)=\(value)"
            }

        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    private struct ToastItem: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let systemImage: String?
    }
}

// MARK: - Location helpers (UIKit delegates)

private final class WidgetWeaverLocationAuthDelegate: NSObject, CLLocationManagerDelegate {
    private let onFinish: (Bool) -> Void

    init(onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            onFinish(true)
        case .denied, .restricted:
            onFinish(false)
        default:
            break
        }
    }
}

private final class WidgetWeaverLocationOnceDelegate: NSObject, CLLocationManagerDelegate {
    private let onFinish: (Result<CLLocation, Error>) -> Void

    init(onFinish: @escaping (Result<CLLocation, Error>) -> Void) {
        self.onFinish = onFinish
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            onFinish(.success(loc))
        } else {
            onFinish(.failure(NSError(domain: "location", code: 0)))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFinish(.failure(error))
    }
}

// MARK: - Search results UI

struct WidgetWeaverWeatherLocationSearchResultsView: View {
    let query: String
    let candidates: [WidgetWeaverWeatherGeocodeCandidate]
    let onSelect: (WidgetWeaverWeatherGeocodeCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("Results for “\(query)”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Matches") {
                ForEach(candidates) { candidate in
                    Button {
                        onSelect(candidate)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title)
                                .font(.headline)

                            if let subtitle = candidate.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Lat \(candidate.latitude, specifier: "%.4f"), Lon \(candidate.longitude, specifier: "%.4f")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }
}

// MARK: - Geocode candidate model

struct WidgetWeaverWeatherGeocodeCandidate: Identifiable, Hashable {
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    var id: String {
        "\(title)|\(subtitle ?? "")|\(latitude)|\(longitude)"
    }
}

// MARK: - Geocoding

private func geocodeCandidatesForQuery(_ query: String) async throws -> [WidgetWeaverWeatherGeocodeCandidate] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.resultTypes = .address

    let search = MKLocalSearch(request: request)
    let response = try await search.start()

    return await Task.detached {
        var out: [WidgetWeaverWeatherGeocodeCandidate] = []

        for item in response.mapItems {
            guard let loc = item.placemark.location else { continue }

            let title: String = {
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !name.isEmpty { return name }

                let locality = item.placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !locality.isEmpty { return locality }

                if let address = item.address {
                    let short = address.shortAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !short.isEmpty { return short }

                    let full = address.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !full.isEmpty { return full }
                }

                return query
            }()

            let subtitle: String? = {
                guard let address = item.address else { return nil }

                let short = address.shortAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !short.isEmpty, short != title { return short }

                let full = address.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !full.isEmpty, full != title { return full }

                return nil
            }()

            out.append(
                WidgetWeaverWeatherGeocodeCandidate(
                    title: title,
                    subtitle: subtitle,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
            )
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }.value
}
