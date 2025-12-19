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

struct WidgetWeaverWeatherSettingsView: View {
    var onClose: (() -> Void)? = nil

    @State private var query: String = ""
    @State private var isWorking: Bool = false
    @State private var statusText: String? = nil

    @State private var savedLocation: WidgetWeaverWeatherLocation? = WidgetWeaverWeatherStore.shared.loadLocation()
    @State private var snapshot: WidgetWeaverWeatherSnapshot? = WidgetWeaverWeatherStore.shared.loadSnapshot()
    @State private var unitPreference: WidgetWeaverWeatherUnitPreference = WidgetWeaverWeatherStore.shared.loadUnitPreference()

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

                VStack(alignment: .leading, spacing: 8) {
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
                        Text(pref.displayName)
                            .tag(pref)
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
        }
    }

    private func refreshLocalState() {
        savedLocation = store.loadLocation()
        snapshot = store.loadSnapshot()
        unitPreference = store.loadUnitPreference()
    }

    private func reloadWidgets() {
        AppGroup.userDefaults.synchronize()

        let kind = WidgetWeaverWidgetKinds.main
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        WidgetCenter.shared.reloadAllTimelines()

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
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

            store.saveLocation(stored)
            store.clearSnapshot()
            refreshLocalState()
            reloadWidgets()

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
        store.saveSnapshot(result.snapshot)
        store.saveAttribution(result.attribution)
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
            guard let request = MKGeocodingRequest(addressString: query) else {
                return []
            }

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
