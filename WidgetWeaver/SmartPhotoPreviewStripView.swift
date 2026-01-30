//
//  SmartPhotoPreviewStripView.swift
//  WidgetWeaver
//
//  Created by . . on 2026-01-05.
//

import Foundation
import SwiftUI
import UIKit
import WidgetKit

struct SmartPhotoPreviewStripView: View {
    let smart: SmartPhotoSpec
    let selectedFamily: EditingFamily
    let onSelectFamily: (EditingFamily) -> Void

    let filterSpec: PhotoFilterSpec?

    /// When Album Shuffle is enabled, this view normally follows `manifest.entryForRender()`.
    /// In the manual framing editor, the selected entry should be stable so edits apply to a
    /// single photo at a time.
    let fixedShuffleEntry: SmartPhotoShuffleManifest.Entry?

    init(
        smart: SmartPhotoSpec,
        selectedFamily: EditingFamily,
        onSelectFamily: @escaping (EditingFamily) -> Void,
        filterSpec: PhotoFilterSpec? = nil,
        fixedShuffleEntry: SmartPhotoShuffleManifest.Entry? = nil
    ) {
        self.smart = smart
        self.selectedFamily = selectedFamily
        self.onSelectFamily = onSelectFamily
        self.filterSpec = filterSpec
        self.fixedShuffleEntry = fixedShuffleEntry
    }

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    @AppStorage(FeatureFlags.Keys.smartPhotosUXHardeningEnabled)
    private var uxHardeningEnabled: Bool = FeatureFlags.defaultSmartPhotosUXHardeningEnabled

    private var shuffleManifestFileName: String {
        (smart.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !shuffleManifestFileName.isEmpty
    }

    private var usesShuffleRotation: Bool {
        if fixedShuffleEntry != nil { return false }
        guard shuffleEnabled else { return false }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return true }
        return manifest.rotationIntervalMinutes > 0
    }

    private var activeFilterSpec: PhotoFilterSpec? {
        guard WidgetWeaverFeatureFlags.photoFiltersEnabled else { return nil }
        guard let spec = filterSpec else { return nil }
        return spec.normalisedOrNil()
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
        let entry: SmartPhotoShuffleManifest.Entry? = {
            if let fixedShuffleEntry { return fixedShuffleEntry }
            guard shuffleEnabled else { return nil }
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return nil }
            return manifest.entryForRender()
        }()

        let displayFamily = resolvedDisplayFamily(selectedFamily, entry: entry)

        return HStack(spacing: 8) {
            previewCell(
                family: .small,
                displayFamily: displayFamily,
                renderFileName: resolvedRenderFileName(.small, entry: entry)
            )
            previewCell(
                family: .medium,
                displayFamily: displayFamily,
                renderFileName: resolvedRenderFileName(.medium, entry: entry)
            )
            previewCell(
                family: .large,
                displayFamily: displayFamily,
                renderFileName: resolvedRenderFileName(.large, entry: entry)
            )
        }
    }

    private func resolvedDisplayFamily(_ selected: EditingFamily, entry: SmartPhotoShuffleManifest.Entry?) -> EditingFamily {
        guard uxHardeningEnabled else { return selected }
        let available = availableFamilies(entry: entry)
        if available.contains(selected) { return selected }
        if let first = EditingFamily.allCases.first(where: { available.contains($0) }) { return first }
        return selected
    }

    private func availableFamilies(entry: SmartPhotoShuffleManifest.Entry?) -> Set<EditingFamily> {
        var result: Set<EditingFamily> = []
        if resolvedRenderFileName(.small, entry: entry) != nil { result.insert(.small) }
        if resolvedRenderFileName(.medium, entry: entry) != nil { result.insert(.medium) }
        if resolvedRenderFileName(.large, entry: entry) != nil { result.insert(.large) }
        return result
    }

    private func resolvedRenderFileName(_ family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry?) -> String? {
        if let entry {
            let name: String? = {
                switch family {
                case .small:
                    return (entry.smallManualFile ?? entry.smallFile)
                case .medium:
                    return (entry.mediumManualFile ?? entry.mediumFile)
                case .large:
                    return (entry.largeManualFile ?? entry.largeFile)
                }
            }()
            let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let name: String? = {
            switch family {
            case .small:
                return smart.small?.renderFileName
            case .medium:
                return smart.medium?.renderFileName
            case .large:
                return smart.large?.renderFileName
            }
        }()
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func previewCell(
        family: EditingFamily,
        displayFamily: EditingFamily,
        renderFileName: String?
    ) -> some View {
        Button {
            onSelectFamily(family)
        } label: {
            previewImage(renderFileName: renderFileName)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(displayFamily == family ? Color.accentColor : Color.white.opacity(0.25), lineWidth: displayFamily == family ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(family.label) preview"))
        .accessibilityAddTraits(displayFamily == family ? .isSelected : [])
    }

    @ViewBuilder
    private func previewImage(renderFileName: String?) -> some View {
        if let renderName = renderFileName,
           let uiImage = AppGroup.loadUIImage(fileName: renderName) {
            let displayImage: UIImage = {
                guard let spec = activeFilterSpec else { return uiImage }
                return PhotoFilterEngine.shared.apply(to: uiImage, spec: spec)
            }()

            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.08))
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
