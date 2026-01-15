//
//  SmartPhotoPreviewStripView.swift
//  WidgetWeaver
//
//  Created by . . on 2026-01-05.
//

import SwiftUI
import UIKit

struct SmartPhotoPreviewStripView: View {
    let smart: SmartPhotoSpec
    let selectedFamily: EditingFamily
    let onSelectFamily: (EditingFamily) -> Void

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    private var shuffleManifestFileName: String {
        (smart.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !shuffleManifestFileName.isEmpty
    }

    private var usesShuffleRotation: Bool {
        guard shuffleEnabled else { return false }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return true }
        return manifest.rotationIntervalMinutes > 0
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken

        Group {
            if usesShuffleRotation {
                let interval: TimeInterval = liveEnabled ? 5 : 60
                let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                TimelineView(.periodic(from: start, by: interval)) { ctx in
                    WidgetWeaverRenderClock.withNow(ctx.date) {
                        stripBody
                    }
                }
            } else {
                stripBody
            }
        }
    }

    private var stripBody: some View {
        let entry = currentShuffleEntry()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                previewButton(family: .small, entry: entry)
                previewButton(family: .medium, entry: entry)
                previewButton(family: .large, entry: entry)
            }

            Text("Tap a preview to edit that size.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewButton(family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry?) -> some View {
        let renderFileName = resolvedRenderFileName(for: family, entry: entry)

        Button {
            onSelectFamily(family)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    previewImage(renderFileName: renderFileName)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            selectionBorder(family: family)
                        }

                    if isManual(renderFileName: renderFileName) {
                        manualBadge
                    }
                }

                Text(family.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(family.label) preview")
        .accessibilityHint("Switch editor to \(family.label).")
    }

    @ViewBuilder
    private func selectionBorder(family: EditingFamily) -> some View {
        if family == selectedFamily {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint, lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var manualBadge: some View {
        Text("Manual")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
    }

    @ViewBuilder
    private func previewImage(renderFileName: String?) -> some View {
        if let renderName = renderFileName,
           let uiImage = AppGroup.loadUIImage(fileName: renderName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle()
                    .fill(.quaternary)

                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func currentShuffleEntry() -> SmartPhotoShuffleManifest.Entry? {
        guard shuffleEnabled else { return nil }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return nil }
        return manifest.entryForRender()
    }

    private func resolvedRenderFileName(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry?) -> String? {
        if shuffleEnabled {
            switch family {
            case .small: return entry?.smallFile
            case .medium: return entry?.mediumFile
            case .large: return entry?.largeFile
            }
        }

        switch family {
        case .small: return smart.small?.renderFileName
        case .medium: return smart.medium?.renderFileName
        case .large: return smart.large?.renderFileName
        }
    }

    private func isManual(renderFileName: String?) -> Bool {
        guard let renderFileName else { return false }
        return renderFileName.contains("-manual")
    }
}
