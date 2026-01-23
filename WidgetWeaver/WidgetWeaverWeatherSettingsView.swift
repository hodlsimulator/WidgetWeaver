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

struct WidgetWeaverWeatherSettingsView: View {

    var onClose: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    @State private var query: String = ""
    @State private var isWorking: Bool = false
    @State private var statusText: String? = nil

    @State private var savedLocation: WidgetWeaverWeatherLocation? = WidgetWeaverWeatherStore.shared.loadLocation()
    @State private var snapshot: WidgetWeaverWeatherSnapshot? = WidgetWeaverWeatherStore.shared.loadSnapshot()
    @State private var unitPreference: WidgetWeaverWeatherUnitPreference = WidgetWeaverWeatherStore.shared.loadUnitPreference()

    @State private var lastError: String? = WidgetWeaverWeatherStore.shared.loadLastError()

    @State private var locationAuthStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    private let store = WidgetWeaverWeatherStore.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Weather")
                            .font(.headline)

                        Spacer()

                        if let onClose {
                            Button("Done") { onClose() }
                                .font(.headline)
                        }
                    }

                    Text("Used by the Weather layout template and the __weather_* built-in variables.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

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
                        store.clearSnapshot()
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
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Button {
                        Task { await geocodeAndSave() }
                    } label: {
                        Label("Save location", systemImage: "location.magnifyingglass")
                    }
                    .disabled(isWorking || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

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

            Section("Now") {
                if let snap = snapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snap.conditionDescription)
                            .font(.headline)

                        Text("Updated \(snap.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        let unit = store.resolvedUnitTemperature()
                        let tempValue = Measurement(value: snap.temperatureC, unit: UnitTemperature.celsius)
                            .converted(to: unit)
                            .value

                        Text("Temp \(Int(round(tempValue)))°")
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
                    store.resetAll()
                    query = ""
                    refreshLocalState()
                    reloadWidgets()
                } label: {
                    Label("Reset Weather", systemImage: "arrow.counterclockwise")
                }
            }

            if let statusText {
                Section {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weather")
        .overlay {
            if isWorking {
                ProgressView()
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .onAppear {
            refreshLocalState()
            refreshLocationAuthStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshLocationAuthStatus()
        }
        .tint(.blue)
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
    }

    private func reloadWidgets() {
        AppGroup.userDefaults.synchronize()

        let kind = WidgetWeaverWidgetKinds.main

        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()

            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
    }

    private func useCurrentLocation() async {
        isWorking = true
        statusText = nil
        defer {
            isWorking = false
            refreshLocationAuthStatus()
        }

        let status = await WidgetWeaverLocationService.shared.ensureWhenInUseAuthorisation()
        refreshLocationAuthStatus()

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            switch status {
            case .denied, .restricted:
                statusText = "Location permission is disabled. Enable it in Settings to use Current Location."
            case .notDetermined:
                statusText = "Location permission was not granted."
            default:
                statusText = "Location permission is unavailable (status: \(status.rawValue))."
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

            // Keep the existing snapshot until a new one is successfully fetched.
            store.saveLocation(stored)
            refreshLocalState()

            await updateNow(force: true)
        } catch {
            statusText = "Location failed: \(String(describing: error))"
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
        statusText = nil
        defer { isWorking = false }

        do {
            let candidates = try await geocode(trimmed)
            guard let best = candidates.first else {
                statusText = "No results found."
                return
            }

            let name = (best.name?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? trimmed

            let stored = WidgetWeaverWeatherLocation(
                name: name,
                latitude: best.latitude,
                longitude: best.longitude,
                updatedAt: Date()
            )

            // Keep the existing snapshot until a new one is successfully fetched.
            store.saveLocation(stored)
            refreshLocalState()

            await updateNow(force: true)
        } catch {
            statusText = "Geocoding failed: \(String(describing: error))"
        }
    }

    private func updateNow(force: Bool) async {
        isWorking = true
        statusText = nil
        defer { isWorking = false }

        let result = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: force)

        // Preserve last known-good data if the refresh fails.
        if let snap = result.snapshot {
            store.saveSnapshot(snap)
        }
        if let attr = result.attribution {
            store.saveAttribution(attr)
        }

        refreshLocalState()
        reloadWidgets()

        if let err = result.errorDescription {
            statusText = "Update finished with an issue: \(err)"
        } else {
            statusText = "Updated."
        }
    }

    private struct GeocodeCandidate: Sendable {
        let name: String?
        let latitude: Double
        let longitude: Double
    }

    private func geocode(_ query: String) async throws -> [GeocodeCandidate] {
        try await Task.detached(priority: .userInitiated) { () -> [GeocodeCandidate] in
            guard let request = MKGeocodingRequest(addressString: query) else { return [] }
            let items = try await request.mapItems

            return items.map { item in
                let loc = item.location
                return GeocodeCandidate(
                    name: item.name,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
            }
        }.value
    }
}
