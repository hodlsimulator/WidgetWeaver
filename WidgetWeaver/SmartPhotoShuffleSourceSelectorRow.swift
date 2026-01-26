//
//  SmartPhotoShuffleSourceSelectorRow.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI

enum SmartPhotoShuffleSourceKey {
    static let album: String = "album"
}

struct SmartPhotoShuffleSourceSelectorRow: View {
    @Binding var selectedSourceKey: String

    let isDisabled: Bool
    let onSelectionHint: (String) -> Void

    private var selectedMemoriesMode: SmartPhotoMemoriesMode? {
        SmartPhotoMemoriesMode(rawValue: selectedSourceKey)
    }

    private var displayName: String {
        selectedMemoriesMode?.displayName ?? "Album Shuffle"
    }

    var body: some View {
        HStack(spacing: 10) {
            Label("Source", systemImage: "square.stack")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Menu {
                Button {
                    selectedSourceKey = SmartPhotoShuffleSourceKey.album
                    onSelectionHint("Source: Album Shuffle.\nChoose an album to start.")
                } label: {
                    if selectedSourceKey == SmartPhotoShuffleSourceKey.album {
                        Text("✓ Album Shuffle")
                    } else {
                        Text("Album Shuffle")
                    }
                }

                Divider()

                ForEach(SmartPhotoMemoriesMode.allCases) { mode in
                    Button {
                        selectedSourceKey = mode.rawValue
                        onSelectionHint("Source: \(mode.displayName).\nTap Build to create a Memories set.")
                    } label: {
                        if selectedSourceKey == mode.rawValue {
                            Text("✓ \(mode.displayName)")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                Text(displayName)
                    .font(.caption)
            }
            .disabled(isDisabled)
        }
    }
}
