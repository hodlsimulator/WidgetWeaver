//
//  WidgetWeaverWeatherLocationSearchResultsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import Foundation
import SwiftUI

struct WidgetWeaverWeatherGeocodeCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    init(
        id: String? = nil,
        title: String,
        subtitle: String?,
        latitude: Double,
        longitude: Double
    ) {
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude

        let roundedLat = String(format: "%.5f", latitude)
        let roundedLon = String(format: "%.5f", longitude)
        let rawID = id ?? "\(roundedLat),\(roundedLon)|\(title)|\(subtitle ?? "")"
        self.id = rawID
    }

    var coordinateText: String {
        "Lat \(String(format: "%.4f", latitude)), Lon \(String(format: "%.4f", longitude))"
    }
}

struct WidgetWeaverWeatherLocationSearchResultsView: View {
    let query: String
    let candidates: [WidgetWeaverWeatherGeocodeCandidate]
    let onSelect: (WidgetWeaverWeatherGeocodeCandidate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("Choose the best match for “\(query)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Results (\(candidates.count))") {
                ForEach(candidates) { candidate in
                    Button {
                        onSelect(candidate)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if let subtitle = candidate.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Text(candidate.coordinateText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Choose location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
