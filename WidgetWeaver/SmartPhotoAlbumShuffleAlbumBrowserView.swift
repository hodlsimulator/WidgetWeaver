//
//  SmartPhotoAlbumShuffleAlbumBrowserView.swift
//  WidgetWeaver
//
//  Created by . . on 1/9/26.
//

import SwiftUI

/// A lightweight manifest-backed album browser.
///
/// Purpose:
/// - Provide a production navigation surface that treats the currently configured shuffle album as a
///   first-class selection origin (album container focus).
/// - Provide a production navigation surface that treats a specific album photo item as a selection
///   origin (photo item focus), without relying on debug-only ranking flows.
struct SmartPhotoAlbumShuffleAlbumBrowserView: View {
    let manifestFileName: String
    var focus: Binding<EditorFocusSnapshot>? = nil

    @Environment(\.presentationMode) private var presentationMode

    @State private var previousFocusSnapshot: EditorFocusSnapshot?

    private var trimmedManifestFileName: String {
        manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var manifest: SmartPhotoShuffleManifest? {
        let mf = trimmedManifestFileName
        if mf.isEmpty { return nil }
        return SmartPhotoShuffleManifestStore.load(fileName: mf)
    }

    private var resolvedAlbumID: String? {
        let albumID = manifest?.sourceID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return albumID.isEmpty ? nil : albumID
    }

    private var targetFocus: EditorFocusTarget? {
        guard let resolvedAlbumID else { return nil }
        return .albumContainer(id: resolvedAlbumID, subtype: .smart)
    }

    var body: some View {
        Form {
            albumMetadataSection
            entriesSection
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pushFocusIfPossible()
        }
        .onDisappear {
            // In a NavigationStack, onDisappear is invoked both when pushing a new destination and
            // when popping back. Restore only when popped (i.e. no longer presented).
            if !presentationMode.wrappedValue.isPresented {
                restoreFocusIfNeeded()
            }
        }
        .accessibilityIdentifier("AlbumShuffle.AlbumBrowser")
    }

    private var albumMetadataSection: some View {
        Section("Album") {
            if let resolvedAlbumID, let manifest {
                LabeledContent("Album ID", value: resolvedAlbumID)
                    .textSelection(.enabled)

                LabeledContent("Photos", value: "\(manifest.entries.count)")
                LabeledContent("Prepared", value: "\(manifest.entries.filter(\.isPrepared).count)")

                LabeledContent("Current index", value: "\(manifest.currentIndex)")
                LabeledContent("Rotation", value: rotationLabel(minutes: manifest.rotationIntervalMinutes))
            } else if trimmedManifestFileName.isEmpty {
                Text("No shuffle manifest configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Shuffle manifest not found or unreadable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var entriesSection: some View {
        Section("Photos") {
            guard let manifest, let albumID = resolvedAlbumID else {
                Text("No photos available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                return
            }

            if manifest.entries.isEmpty {
                Text("No photos in this album.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                return
            }

            let maxRows = 200
            let entriesToShow = Array(manifest.entries.prefix(maxRows))

            ForEach(Array(entriesToShow.enumerated()), id: \.element.id) { idx, entry in
                NavigationLink {
                    SmartPhotoAlbumShufflePhotoDetailView(
                        manifestFileName: trimmedManifestFileName,
                        albumID: albumID,
                        itemID: entry.id,
                        focus: focus
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.isPrepared ? "✓" : "·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .leading)

                        Text(entry.id)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        if entry.flags.contains("failed") {
                            Text("failed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("AlbumShuffle.AlbumBrowser.Row.\(idx)")
            }

            if manifest.entries.count > maxRows {
                Text("Showing first \(maxRows) photos.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pushFocusIfPossible() {
        guard let focus else { return }
        guard let resolvedAlbumID else { return }

        if previousFocusSnapshot == nil {
            previousFocusSnapshot = focus.wrappedValue
        }

        focus.wrappedValue = .smartAlbumContainer(id: resolvedAlbumID)
    }

    private func restoreFocusIfNeeded() {
        guard let focus else { return }
        guard let previous = previousFocusSnapshot else { return }
        defer { previousFocusSnapshot = nil }

        if let targetFocus, focus.wrappedValue.focus == targetFocus {
            focus.wrappedValue = previous
        }
    }

    private func rotationLabel(minutes: Int) -> String {
        if minutes <= 0 { return "Off" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            if hours == 24 { return "1d" }
            if hours > 24, hours % 24 == 0 { return "\(hours / 24)d" }
            return "\(hours)h"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
}
