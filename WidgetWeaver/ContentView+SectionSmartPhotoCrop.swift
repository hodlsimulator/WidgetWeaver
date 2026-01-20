//
//  ContentView+SectionSmartPhotoCrop.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
extension ContentView {
    @ViewBuilder
    func sectionSmartPhotoCrop() -> some View {
        if let smart = currentSpec?.layout?.smartPhoto {
            Section("Fix framing") {
                SmartPhotoSingleFramingEditorView(
                    smartPhoto: smart,
                    focus: $editorFocus,
                    onResetToAuto: { family in
                        await resetSmartPhotoVariantToAuto(family: family)
                    },
                    onApplyCrop: { family, cropRect, straightenDegrees, rotationQuarterTurns in
                        await applyManualSmartCropWithStraighten(
                            family: family,
                            cropRect: cropRect,
                            straightenDegrees: straightenDegrees,
                            rotationQuarterTurns: rotationQuarterTurns
                        )
                    }
                )
            }
        }
        if let shuffle = currentSpec?.layout?.smartPhotoShuffle {
            Section("Shuffle framing") {
                SmartPhotoShuffleFramingEditorView(
                    manifestFileName: shuffle.manifestFileName,
                    focus: $editorFocus,
                    onResetToAuto: { entryID in
                        resetManualSmartCropForShuffleEntry(
                            manifestFileName: shuffle.manifestFileName,
                            entryID: entryID
                        )
                    },
                    onApplyCrop: { entryID, family, cropRect, straightenDegrees, rotationQuarterTurns in
                        await applyManualSmartCropForShuffleEntryWithStraighten(
                            manifestFileName: shuffle.manifestFileName,
                            entryID: entryID,
                            family: family,
                            cropRect: cropRect,
                            straightenDegrees: straightenDegrees,
                            rotationQuarterTurns: rotationQuarterTurns
                        )
                    }
                )
            }
        }
    }
}
private struct SmartPhotoSingleFramingEditorView: View {
    let smartPhoto: SmartPhotoSpec
    let focus: Binding<EditorFocusSnapshot>?
    let onResetToAuto: (EditingFamily) async -> Void
    let onApplyCrop: (EditingFamily, NormalisedRect, Double, Int) async -> Void
    @State private var route: CropRoute?
    private struct CropRoute: Identifiable {
        var family: EditingFamily
        var masterFileName: String
        var targetPixels: PixelSize
        var initialCropRect: NormalisedRect
        var initialStraightenDegrees: Double
        var initialRotationQuarterTurns: Int
        var id: String { family.rawValue }
    }
    var body: some View {
        VStack(spacing: 12) {
            Button {
                route = cropRoute(for: .small)
            } label: {
                HStack {
                    Text("Fix Small")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            Button {
                route = cropRoute(for: .medium)
            } label: {
                HStack {
                    Text("Fix Medium")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            Button {
                route = cropRoute(for: .large)
            } label: {
                HStack {
                    Text("Fix Large")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $route) { route in
            NavigationStack {
                SmartPhotoCropEditorView(
                    family: route.family,
                    masterFileName: route.masterFileName,
                    targetPixels: route.targetPixels,
                    initialCropRect: route.initialCropRect,
                    initialStraightenDegrees: route.initialStraightenDegrees,
                    initialRotationQuarterTurns: route.initialRotationQuarterTurns,
                    autoCropRect: nil,
                    focus: focus,
                    onResetToAuto: {
                        await onResetToAuto(route.family)
                    },
                    onApply: { rect, straightenDegrees, rotationQuarterTurns in
                        await onApplyCrop(route.family, rect, straightenDegrees, rotationQuarterTurns)
                    }
                )
            }
        }
    }
    private func cropRoute(for family: EditingFamily) -> CropRoute {
        let masterFileName = smartPhoto.masterFileName
        let variant: SmartPhotoVariantSpec
        switch family {
        case .small:
            variant = smartPhoto.small
        case .medium:
            variant = smartPhoto.medium
        case .large:
            variant = smartPhoto.large
        }
        return CropRoute(
            family: family,
            masterFileName: masterFileName,
            targetPixels: variant.pixelSize,
            initialCropRect: variant.cropRect,
            initialStraightenDegrees: variant.straightenDegrees ?? 0,
            initialRotationQuarterTurns: variant.rotationQuarterTurns ?? 0
        )
    }
}
private struct SmartPhotoShuffleFramingEditorView: View {
    let manifestFileName: String
    let focus: Binding<EditorFocusSnapshot>?
    let onResetToAuto: (String) async -> Void
    let onApplyCrop: (String, EditingFamily, NormalisedRect, Double, Int) async -> Void
    @State private var manifest: SmartPhotoShuffleManifest?
    @State private var route: CropRoute?
    private struct CropRoute: Identifiable {
        var entryID: String
        var family: EditingFamily
        var masterFileName: String
        var targetPixels: PixelSize
        var initialCropRect: NormalisedRect
        var initialStraightenDegrees: Double
        var initialRotationQuarterTurns: Int
        var autoCropRect: NormalisedRect?
        var id: String { "\(entryID)-\(family.rawValue)" }
    }
    var body: some View {
        Group {
            if let manifest {
                VStack(spacing: 14) {
                    ForEach(manifest.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.masterFileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button("Small") {
                                    route = cropRoute(for: .small, entry: entry)
                                }
                                .buttonStyle(.bordered)
                                Button("Medium") {
                                    route = cropRoute(for: .medium, entry: entry)
                                }
                                .buttonStyle(.bordered)
                                Button("Large") {
                                    route = cropRoute(for: .large, entry: entry)
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                if entryHasManual(entry) {
                                    Button("Reset") {
                                        Task { await onResetToAuto(entry.id) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            manifest = AppGroup.loadSmartPhotoShuffleManifest(fileName: manifestFileName)
        }
        .fullScreenCover(item: $route) { route in
            NavigationStack {
                SmartPhotoCropEditorView(
                    family: route.family,
                    masterFileName: route.masterFileName,
                    targetPixels: route.targetPixels,
                    initialCropRect: route.initialCropRect,
                    initialStraightenDegrees: route.initialStraightenDegrees,
                    initialRotationQuarterTurns: route.initialRotationQuarterTurns,
                    autoCropRect: route.autoCropRect,
                    focus: focus,
                    onResetToAuto: {
                        await onResetToAuto(route.entryID)
                    },
                    onApply: { rect, straightenDegrees, rotationQuarterTurns in
                        await onApplyCrop(route.entryID, route.family, rect, straightenDegrees, rotationQuarterTurns)
                    }
                )
            }
        }
    }
    private func entryHasManual(_ entry: SmartPhotoShuffleManifest.Entry) -> Bool {
        (entry.smallManualRenderFileName != nil) ||
            (entry.mediumManualRenderFileName != nil) ||
            (entry.largeManualRenderFileName != nil)
    }
    private func cropRoute(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> CropRoute {
        let targetPixels: PixelSize
        switch family {
        case .small:
            targetPixels = PixelSize(width: 483, height: 483)
        case .medium:
            targetPixels = PixelSize(width: 1010, height: 483)
        case .large:
            targetPixels = PixelSize(width: 1010, height: 1010)
        }
        return CropRoute(
            entryID: entry.id,
            family: family,
            masterFileName: entry.masterFileName,
            targetPixels: targetPixels,
            initialCropRect: initialCropRect(for: family, entry: entry),
            initialStraightenDegrees: initialStraightenDegrees(for: family, entry: entry),
            initialRotationQuarterTurns: initialRotationQuarterTurns(for: family, entry: entry),
            autoCropRect: autoCropRect(for: family, entry: entry)
        )
    }
    private func initialCropRect(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> NormalisedRect {
        let fallback: NormalisedRect
        switch family {
        case .small:
            fallback = entry.smallAutoCropRect
        case .medium:
            fallback = entry.mediumAutoCropRect
        case .large:
            fallback = entry.largeAutoCropRect
        }
        switch family {
        case .small:
            return entry.smallManualCropRect ?? fallback
        case .medium:
            return entry.mediumManualCropRect ?? fallback
        case .large:
            return entry.largeManualCropRect ?? fallback
        }
    }
    private func initialStraightenDegrees(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> Double {
        let fallback: Double = 0
        switch family {
        case .small:
            return entry.smallManualStraightenDegrees ?? fallback
        case .medium:
            return entry.mediumManualStraightenDegrees ?? fallback
        case .large:
            return entry.largeManualStraightenDegrees ?? fallback
        }
    }
    private func initialRotationQuarterTurns(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> Int {
        let fallback: Int = 0
        switch family {
        case .small:
            return entry.smallManualRotationQuarterTurns ?? fallback
        case .medium:
            return entry.mediumManualRotationQuarterTurns ?? fallback
        case .large:
            return entry.largeManualRotationQuarterTurns ?? fallback
        }
    }
    private func autoCropRect(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> NormalisedRect? {
        switch family {
        case .small:
            return entry.smallAutoCropRect
        case .medium:
            return entry.mediumAutoCropRect
        case .large:
            return entry.largeAutoCropRect
        }
    }
}
