//
//  SmartPhotoAlbumShuffleControls.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation
import SwiftUI
import WidgetKit

/// App-only progressive processing for Smart Photo album shuffle.
///
/// Rules:
/// - App does all heavy work (Photos fetch, rendering, scoring).
/// - Widget reads manifest + loads exactly one pre-rendered file.
struct SmartPhotoAlbumShuffleControls: View {
    @Binding var smartPhoto: SmartPhotoSpec?
    @Binding var importInProgress: Bool
    @Binding var saveStatusMessage: String

    let specID: UUID

    var focus: Binding<EditorFocusSnapshot>? = nil

    var albumPickerPresented: Binding<Bool>? = nil

    @Environment(\.scenePhase) var scenePhase

    let batchSize: Int = 10
    private let rotationOptionsMinutes: [Int] = {
        #if DEBUG
        return [0, 2, 15, 30, 60, 180, 360, 720, 1440]
        #else
        return [0, 15, 30, 60, 180, 360, 720, 1440]
        #endif
    }()

    @State private var internalAlbumPickerPresented: Bool = false
    @State private var previousFocusSnapshot: EditorFocusSnapshot?
    @State var albumPickerState: AlbumPickerState = .idle
    @State var albums: [AlbumOption] = []

    @State var progress: ProgressSummary?

    @State var rotationIntervalMinutes: Int = 60
    @State var nextChangeDate: Date?

    @State var isPreparingBatch: Bool = false

    @State var selectedSourceKey: String = SmartPhotoShuffleSourceKey.album
    @State var configuredSourceKey: String = SmartPhotoShuffleSourceKey.album

    private var selectedMemoriesMode: SmartPhotoMemoriesMode? {
        guard FeatureFlags.smartPhotoMemoriesEnabled else { return nil }
        return SmartPhotoMemoriesMode(rawValue: selectedSourceKey)
    }

    var manifestFileName: String {
        (smartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !manifestFileName.isEmpty
    }

    var albumPickerPresentedBinding: Binding<Bool> {
        albumPickerPresented ?? $internalAlbumPickerPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            if FeatureFlags.smartPhotoMemoriesEnabled {
                SmartPhotoShuffleSourceSelectorRow(
                    selectedSourceKey: $selectedSourceKey,
                    isDisabled: importInProgress || isPreparingBatch || smartPhoto == nil,
                    onSelectionHint: { hint in
                        saveStatusMessage = hint
                    }
                )
            }

            statusText

            actionRow
                .padding(.top, 2)

            rotationControls
                .padding(.top, 4)

            Divider()
        }
        .onAppear {
            handleAlbumPickerPresentationChange(isPresented: albumPickerPresentedBinding.wrappedValue)
        }
        .sheet(isPresented: albumPickerPresentedBinding) {
            NavigationStack {
                Group {
                    switch albumPickerState {
                    case .idle:
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading albums…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .loading:
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Requesting access…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .ready:
                        List {
                            ForEach($albums, id: \.id) { album in
                                Button {
                                    Task { await configureShuffle(album: album.wrappedValue) }
                                } label: {
                                    let a = album.wrappedValue

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(a.title)
                                            .font(.body)

                                        Text("\(a.count) photos")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(importInProgress)
                            }
                        }

                    case .failed(let message):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28))
                                .foregroundStyle(.orange)
                            Text(message)
                                .multilineTextAlignment(.center)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
                .navigationTitle("Choose album")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            albumPickerPresentedBinding.wrappedValue = false
                        }
                    }
                }
            }
            .task {
                await loadAlbumsIfNeeded()
            }
        }
        .onChange(of: albumPickerPresentedBinding.wrappedValue) { _, newValue in
            handleAlbumPickerPresentationChange(isPresented: newValue)
        }
        .task(id: manifestFileName) {
            await refreshFromManifest()
            await autoPrepareWhilePossible()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if smartPhoto == nil {
            if FeatureFlags.smartPhotoMemoriesEnabled {
                Text("Shuffle requires Smart Photo.\nPick a photo and create Smart Photo renders first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Album shuffle requires Smart Photo.\nPick a photo and create Smart Photo renders first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !shuffleEnabled {
            if let mode = selectedMemoriesMode {
                Text("Build a Memories set for “\(mode.displayName)”. While the app is open, it will progressively pre-render it (in batches of \(batchSize)).\n\nIf nothing appears, try a different mode or choose an album. Screenshots and very low-res images are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose an album to start. While the app is open, it will progressively pre-render the album (in batches of \(batchSize)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let progress {
            HStack(spacing: 8) {
                if isPreparingBatch {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Prepared \(progress.prepared)/\(progress.total) • failed \(progress.failed) • currentIndex \(progress.currentIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                if isPreparingBatch {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Loading shuffle status…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Label("Rotate", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Menu {
                    ForEach(rotationOptionsMinutes, id: \.self) { minutes in
                        Button {
                            Task { await setRotationInterval(minutes: minutes) }
                        } label: {
                            if minutes == rotationIntervalMinutes {
                                Text("✓ \(rotationLabel(minutes: minutes))")
                            } else {
                                Text(rotationLabel(minutes: minutes))
                            }
                        }
                    }
                } label: {
                    Text(rotationLabel(minutes: rotationIntervalMinutes))
                        .font(.caption)
                }
                .disabled(importInProgress || isPreparingBatch)
            }

            if rotationIntervalMinutes > 0, let nextChangeDate {
                Text("Next change: \(nextChangeDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rotation is off (manual only).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct ActionTileLabel: View {
        let title: String
        let systemImage: String

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 20)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.vertical, 4)
        }
    }

    private var actionRow: some View {
        Group {
            if shuffleEnabled {
                ViewThatFits(in: .horizontal) {
                    actionGrid(columns: 4)
                    actionGrid(columns: 2)
                }
            } else {
                actionGrid(columns: 1)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func actionGrid(columns: Int) -> some View {
        let minTileWidth: CGFloat = 120
        let cols = Array(repeating: GridItem(.flexible(minimum: minTileWidth), spacing: 12), count: columns)

        LazyVGrid(columns: cols, spacing: 12) {
            if let mode = selectedMemoriesMode {
                let isConfiguredForMode = configuredSourceKey == mode.rawValue

                Button {
                    Task { await configureMemories(mode: mode) }
                } label: {
                    let verb = isConfiguredForMode ? "Refresh" : "Build"
                    let icon = isConfiguredForMode ? "arrow.clockwise" : "calendar"
                    ActionTileLabel(title: "\(verb)\n\(mode.displayName)", systemImage: icon)
                }
                .disabled(importInProgress || smartPhoto == nil || isPreparingBatch)
            } else {
                Button {
                    albumPickerPresentedBinding.wrappedValue = true
                } label: {
                    ActionTileLabel(title: "Choose\nalbum…", systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(importInProgress || smartPhoto == nil || isPreparingBatch)
            }

            if shuffleEnabled {
                Button {
                    Task { await prepareNextBatch(alreadyBusy: false) }
                } label: {
                    ActionTileLabel(title: "Prepare\nnext \(batchSize)", systemImage: "gearshape.2")
                }
                .disabled(importInProgress || isPreparingBatch)

                Button {
                    Task { await advanceToNextPrepared() }
                } label: {
                    ActionTileLabel(title: "Next\nphoto", systemImage: "arrow.right.circle")
                }
                .disabled(importInProgress || isPreparingBatch)

                Button(role: .destructive) {
                    disableShuffle()
                } label: {
                    ActionTileLabel(title: "Disable", systemImage: "xmark.circle")
                }
                .disabled(importInProgress || isPreparingBatch)
            }
        }
    }
}
