//
//  SmartPhotoAlbumShuffleControls+Subviews.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI
import UIKit

struct SmartPhotoShuffleSourceSelector: View {
    static let albumSourceKey: String = "album"

    let selectedSourceKey: String
    let selectedSourceDisplayName: String
    let isBusy: Bool
    let onSelectSourceKey: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("Source", systemImage: "square.stack")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Menu {
                Button {
                    onSelectSourceKey(Self.albumSourceKey)
                } label: {
                    if selectedSourceKey == Self.albumSourceKey {
                        Text("✓ Album Shuffle")
                    } else {
                        Text("Album Shuffle")
                    }
                }

                ForEach(SmartPhotoMemoriesMode.allCases) { mode in
                    Button {
                        onSelectSourceKey(mode.rawValue)
                    } label: {
                        if selectedSourceKey == mode.rawValue {
                            Text("✓ \(mode.displayName)")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                Text(selectedSourceDisplayName)
                    .font(.caption)
            }
            .disabled(isBusy)
        }
    }
}

struct SmartPhotoAlbumShuffleActionTileLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))

            Text(title)
                .multilineTextAlignment(.center)
                .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
