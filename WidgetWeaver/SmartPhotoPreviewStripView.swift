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

    /// When Album Shuffle is enabled, this view normally follows `manifest.entryForRender()`.
    /// In the manual framing editor, the selected entry should be stable so edits apply to a
    /// single photo at a time.
    let fixedShuffleEntry: SmartPhotoShuffleManifest.Entry?

    init(
        smart: SmartPhotoSpec,
        selectedFamily: EditingFamily,
        onSelectFamily: @escaping (EditingFamily) -> Void,
        fixedShuffleEntry: SmartPhotoShuffleManifest.Entry? = nil
    ) {
        self.smart = smart
        self.selectedFamily = selectedFamily
        self.onSelectFamily = onSelectFamily
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
        let entry = fixedShuffleEntry ?? currentShuffleEntry()
        let hint = previewStripHint(entry: entry)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                previewButton(family: .small, entry: entry)
                previewButton(family: .medium, entry: entry)
                previewButton(family: .large, entry: entry)
            }

            Text("Tap a preview to select that size.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let hint {
                hintView(text: hint)
            }
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

                    if shouldShowManualBadge(for: family, entry: entry, renderFileName: renderFileName) {
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

    @ViewBuilder
    private func hintView(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func currentShuffleEntry() -> SmartPhotoShuffleManifest.Entry? {
        guard shuffleEnabled else { return nil }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return nil }
        return manifest.entryForRender()
    }

    private func resolvedRenderFileName(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry?) -> String? {
        if shuffleEnabled, let entry {
            return entry.fileName(for: widgetFamily(for: family))
        }

        switch family {
        case .small: return smart.small?.renderFileName
        case .medium: return smart.medium?.renderFileName
        case .large: return smart.large?.renderFileName
        }
    }

    private func fileExistsInAppGroup(_ fileName: String?) -> Bool {
        let trimmed = (fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let url = AppGroup.imageFileURL(fileName: trimmed)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func previewStripHint(entry: SmartPhotoShuffleManifest.Entry?) -> String? {
        guard uxHardeningEnabled else { return nil }

        if shuffleEnabled, fixedShuffleEntry == nil {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else {
                return "Album Shuffle is enabled, but the shuffle manifest is missing.\nOpen Album Shuffle and re-select an album."
            }

            if manifest.entryForRender() == nil {
                return "Album Shuffle is enabled, but no photos have been prepared yet.\nOpen Album Shuffle and tap “Prepare next batch”."
            }
        }

        let checks: [(family: EditingFamily, fileName: String?)] = [
            (.small, resolvedRenderFileName(for: .small, entry: entry)),
            (.medium, resolvedRenderFileName(for: .medium, entry: entry)),
            (.large, resolvedRenderFileName(for: .large, entry: entry)),
        ]

        let missing = checks.filter { pair in
            fileExistsInAppGroup(pair.fileName) == false
        }

        guard !missing.isEmpty else { return nil }

        let labels = missing.map { $0.family.label }.joined(separator: ", ")

        if shuffleEnabled {
            return "Some shuffle preview renders are missing (\(labels)).\nTap “Prepare next batch” in Album Shuffle, or tap “Regenerate smart renders”."
        }

        return "Some Smart Photo preview renders are missing (\(labels)).\nTap “Regenerate smart renders”."
    }

    private func isManual(renderFileName: String?) -> Bool {
        guard let renderFileName else { return false }
        return renderFileName.contains("-manual")
    }

    private func shouldShowManualBadge(
        for family: EditingFamily,
        entry: SmartPhotoShuffleManifest.Entry?,
        renderFileName: String?
    ) -> Bool {
        if shuffleEnabled {
            guard let entry else { return false }
            switch family {
            case .small:
                return !(entry.smallManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .medium:
                return !(entry.mediumManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .large:
                return !(entry.largeManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        return isManual(renderFileName: renderFileName)
    }

    private func widgetFamily(for family: EditingFamily) -> WidgetFamily {
        switch family {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
        }
    }
}
