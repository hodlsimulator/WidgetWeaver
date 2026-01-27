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

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let loc = savedLocation {
                query = loc.name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshLocationAuthStatus()
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
                Text("Used by the Weather layout template and the __weather_* built-in variables.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Tip: pull down to refresh once a location is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if let loc = savedLocation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.name)
                        .font(.headline)

                    Text("Lat \(loc.latitudeString), Lon \(loc.longitudeString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Updated \(loc.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    store.saveLocation(nil)
                    query = ""
                    refreshLocalState()
                    reloadWidgets()
                } label: {
                    Label("Clear location", systemImage: "trash")
                }
            } else {
                Text("No location saved yet.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    Label(currentLocationButtonTitle, systemImage: "location.fill")
                }
                .disabled(isWorking)
                .buttonStyle(.bordered)

                if locationAuthStatus == .denied || locationAuthStatus == .restricted {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Location Settings", systemImage: "gear")
                    }
                    .disabled(isWorking)
                }

                TextField("City, town, postcode…", text: $query)
                    .submitLabel(.search)
                    .onSubmit {
                        guard !isWorking else { return }
                        Task { await geocodeAndSave() }
                    }
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)

                Button {
                    Task { await geocodeAndSave() }
                } label: {
                    Label("Save location", systemImage: "location.magnifyingglass")
                }
                .disabled(isWorking || trimmedQuery.isEmpty)
            }
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Temperature", selection: $unitPreference) {
                ForEach(WidgetWeaverWeatherUnitPreference.allCases) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .onChange(of: unitPreference) { _, newValue in
                store.saveUnitPreference(newValue)
                reloadWidgets()
            }
        }
    }

    private var nowSection: some View {
        Section("Now") {
            if let snap = snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snap.conditionDescription)
                        .font(.headline)

                    Text("Updated \(snap.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(nowTemperatureText(for: snap))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No cached weather yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await updateNow(force: true) }
            } label: {
                Label("Update now", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking || savedLocation == nil)

            Button(role: .destructive) {
                store.clearSnapshot()
                refreshLocalState()
                reloadWidgets()
            } label: {
                Label("Clear cached weather", systemImage: "trash")
            }
            .disabled(snapshot == nil)
        }
    }

    private var builtInVariablesSection: some View {
        Section {
            if weatherVariableItems.isEmpty {
                Text("No weather variables yet.\nSet a location, then tap Update now.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    copyAllWeatherVariables()
                } label: {
                    Label("Copy all __weather_* values", systemImage: "doc.on.doc")
                }

                ForEach(weatherVariableItems) { item in
                    weatherVariableRow(key: item.key, value: item.value)
                }
            }
        } header: {
            Text("Built-in variables")
        } footer: {
            Text("These values back the __weather_* built-in keys used by templates and Variables.")
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

            Text("Weather refreshes when the app becomes active and during iOS background fetch windows.")
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
            if let lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No stored errors.")
                    .foregroundStyle(.secondary)
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

    private func refreshFromPullToRefresh() async {
        guard !isWorking else { return }

        guard savedLocation != nil else {
            showToast("Set a location first.", systemImage: "location.magnifyingglass", durationNanoseconds: 2_200_000_000)
            return
        }

        await updateNow(force: true)
    }

    private func reloadWidgets() {
        AppGroup.userDefaults.synchronize()

        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenWeather)

            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
    }

    private struct ToastItem: Identifiable, Hashable {
        let id: UUID
        let text: String
        let systemImage: String
        let durationNanoseconds: UInt64

        init(
            id: UUID = UUID(),
            text: String,
            systemImage: String,
            durationNanoseconds: UInt64
        ) {
            self.id = id
            self.text = text
            self.systemImage = systemImage
            self.durationNanoseconds = durationNanoseconds
        }
    }

    private func clearToast() {
        toastDismissTask?.cancel()
        withAnimation(.spring(duration: 0.28)) {
            toastItem = nil
        }
    }

    private func showToast(
        _ text: String,
        systemImage: String,
        durationNanoseconds: UInt64
    ) {
        toastDismissTask?.cancel()

        let item = ToastItem(text: text, systemImage: systemImage, durationNanoseconds: durationNanoseconds)
        withAnimation(.spring(duration: 0.35)) {
            toastItem = item
        }

        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard toastItem?.id == item.id else { return }
            withAnimation(.spring(duration: 0.35)) {
                toastItem = nil
            }
        }
    }

    private struct WeatherVariableItem: Identifiable, Hashable {
        let key: String
        let value: String

        var id: String { key }
    }

    private var weatherVariableItems: [WeatherVariableItem] {
        let vars = store.variablesDictionary(now: WidgetWeaverRenderClock.now)

        return vars
            .filter { $0.key.hasPrefix("__weather_") }
            .sorted { $0.key < $1.key }
            .map { WeatherVariableItem(key: $0.key, value: $0.value) }
    }

    private func copyAllWeatherVariables() {
        let lines: [String] = weatherVariableItems.map { item in
            let sanitisedValue = item.value
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if sanitisedValue.isEmpty {
                return "\(item.key)=—"
            }

            return "\(item.key)=\(sanitisedValue)"
        }

        UIPasteboard.general.string = lines.joined(separator: "\n")
        showToast("Copied \(lines.count) variables.", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
    }

    private func weatherVariableRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(displayValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                UIPasteboard.general.string = snippet
                showToast("Copied \(snippet).", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy template")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = snippet
            showToast("Copied \(snippet).", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
        }
        .contextMenu {
            Button("Copy template") {
                UIPasteboard.general.string = snippet
                showToast("Copied \(snippet).", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
            }

            Button("Copy value") {
                UIPasteboard.general.string = displayValue
                showToast("Copied value for \(key).", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
            }

            Button("Copy key") {
                UIPasteboard.general.string = key
                showToast("Copied \(key).", systemImage: "doc.on.doc", durationNanoseconds: 1_400_000_000)
            }
        }
    }

    private func nowTemperatureText(for snapshot: WidgetWeaverWeatherSnapshot) -> String {
        let unit = store.resolvedUnitTemperature()
        let tempValue = Measurement(value: snapshot.temperatureC, unit: UnitTemperature.celsius)
            .converted(to: unit)
            .value

        return "Temp \(Int(round(tempValue)))°"
    }

    private func useCurrentLocation() async {
        isWorking = true
        clearToast()
        defer {
            isWorking = false
            refreshLocationAuthStatus()
        }

        let status = await WidgetWeaverLocationService.shared.ensureWhenInUseAuthorisation()
        refreshLocationAuthStatus()

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            switch status {
            case .denied, .restricted:
                showToast("Location permission is disabled. Enable it in Settings to use Current Location.", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
            case .notDetermined:
                showToast("Location permission was not granted.", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
            default:
                showToast("Location permission is unavailable (status: \(status.rawValue)).", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
            }
            return
        }

        do {
            let location = try await WidgetWeaverLocationService.shared.fetchOneLocation()
            let name = await reverseGeocodedName(for: location) ?? "Current Location"

            let stored = WidgetWeaverWeatherLocation(
                name: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                updatedAt: Date()
            )

            store.saveLocation(stored)
            query = stored.name
            refreshLocalState()

            await updateNow(force: true)
        } catch {
            showToast("Location failed: \(String(describing: error))", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
        }
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }

        do {
            let items = try await request.mapItems
            guard let item = items.first else { return nil }

            if let address = item.address {
                let short = address.shortAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !short.isEmpty { return short }

                let full = address.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                if !full.isEmpty { return full }
            }

            if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }

            return nil
        } catch {
            return nil
        }
    }

    private func geocodeAndSave() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isWorking = true
        clearToast()
        defer { isWorking = false }

        do {
            let candidates = try await geocode(trimmed)
            guard let first = candidates.first else {
                showToast("No results found.", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
                return
            }

            if candidates.count == 1 {
                await saveGeocodeCandidate(first, fallbackQuery: trimmed)
            } else {
                geocodeCandidatesQuery = trimmed
                geocodeCandidates = candidates
                geocodeCandidatesPresented = true
            }
        } catch {
            showToast("Geocoding failed: \(String(describing: error))", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
        }
    }

    private func saveGeocodeCandidate(
        _ candidate: WidgetWeaverWeatherGeocodeCandidate,
        fallbackQuery: String
    ) async {
        let trimmedTitle = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedTitle.isEmpty ? fallbackQuery : trimmedTitle

        let stored = WidgetWeaverWeatherLocation(
            name: name,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            updatedAt: Date()
        )

        store.saveLocation(stored)
        query = name
        refreshLocalState()

        await updateNow(force: true)
    }

    private func updateNow(force: Bool) async {
        isWorking = true
        clearToast()
        defer { isWorking = false }

        let result = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: force)

        if let snap = result.snapshot {
            store.saveSnapshot(snap)
        }
        if let attr = result.attribution {
            store.saveAttribution(attr)
        }

        refreshLocalState()
        reloadWidgets()

        if let err = result.errorDescription {
            showToast("Update finished with an issue: \(err)", systemImage: "exclamationmark.triangle.fill", durationNanoseconds: 3_400_000_000)
        } else {
            showToast("Updated.", systemImage: "checkmark.circle.fill", durationNanoseconds: 1_400_000_000)
        }
    }

    private func geocode(_ query: String) async throws -> [WidgetWeaverWeatherGeocodeCandidate] {
        try await Task.detached(priority: .userInitiated) { () -> [WidgetWeaverWeatherGeocodeCandidate] in
            guard let request = MKGeocodingRequest(addressString: query) else { return [] }
            let items = try await request.mapItems

            var out: [WidgetWeaverWeatherGeocodeCandidate] = []
            out.reserveCapacity(items.count)

            for item in items {
                let loc = item.location

                let title: String = {
                    if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !name.isEmpty {
                        return name
                    }

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
}
