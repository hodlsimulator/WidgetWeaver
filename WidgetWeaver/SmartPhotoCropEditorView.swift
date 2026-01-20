//
//  SmartPhotoCropEditorView.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import SwiftUI
import UIKit

struct SmartPhotoCropEditorView: View {
    let family: EditingFamily
    let masterFileName: String
    let targetPixels: PixelSize
    let initialCropRect: NormalisedRect
    let initialStraightenDegrees: Double
    let initialRotationQuarterTurns: Int
    let autoCropRect: NormalisedRect?
    let focus: Binding<EditorFocusSnapshot>?
    let onResetToAuto: (() async -> Void)?
    let onApply: (NormalisedRect, Double, Int) async -> Void

    @State private var masterImage: UIImage?
    @State private var previewImage: UIImage?

    @State private var cropRect: NormalisedRect
    @State private var straightenDegrees: Double
    @State private var rotationQuarterTurns: Int

    @State private var isStraightenEditing: Bool = false
    @State private var nudgeStepPixels: Int = 1

    @State private var isApplying: Bool = false
    @State private var loadErrorMessage: String = ""

    @State private var dragStartRect: NormalisedRect?
    @State private var pinchStartRect: NormalisedRect?
    @State private var isPinching: Bool = false

    @State private var isPrecisionDragActive: Bool = false
    @State private var precisionStartRect: NormalisedRect?

    @State private var previousFocusSnapshot: EditorFocusSnapshot?

    @State private var isUpdatingPreview: Bool = false
    @State private var previewRequestID: Int = 0

#if DEBUG
    @State private var debugOverlayEnabled: Bool = false
    @State private var debugDetection: SmartPhotoDetection?
    @State private var debugStatusMessage: String = ""
#endif

    @Environment(\.dismiss) private var dismiss

    init(
        family: EditingFamily,
        masterFileName: String,
        targetPixels: PixelSize,
        initialCropRect: NormalisedRect,
        initialStraightenDegrees: Double = 0,
        initialRotationQuarterTurns: Int = 0,
        autoCropRect: NormalisedRect? = nil,
        focus: Binding<EditorFocusSnapshot>? = nil,
        onResetToAuto: (() async -> Void)? = nil,
        onApply: @escaping (NormalisedRect, Double, Int) async -> Void
    ) {
        let normalisedInitialRotation = SmartPhotoCropMath.normalisedRotationQuarterTurns(initialRotationQuarterTurns)

        self.family = family
        self.masterFileName = masterFileName
        self.targetPixels = targetPixels
        self.initialCropRect = initialCropRect.normalised()
        self.initialStraightenDegrees = Self.normalisedStraightenDegrees(initialStraightenDegrees)
        self.initialRotationQuarterTurns = normalisedInitialRotation
        self.autoCropRect = autoCropRect?.normalised()
        self.focus = focus
        self.onResetToAuto = onResetToAuto
        self.onApply = onApply

        _cropRect = State(initialValue: initialCropRect.normalised())
        _straightenDegrees = State(initialValue: Self.normalisedStraightenDegrees(initialStraightenDegrees))
        _rotationQuarterTurns = State(initialValue: normalisedInitialRotation)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let displayImage = previewImage {
                let masterPixels = SmartPhotoCropMath.pixelSize(of: displayImage)
                let masterAspect = SmartPhotoCropMath.safeAspect(width: masterPixels.width, height: masterPixels.height)
                let targetAspect = SmartPhotoCropMath.safeAspect(width: targetPixels.width, height: targetPixels.height)
                let rectAspect = targetAspect / masterAspect

                VStack(spacing: 0) {
                    cropCanvas(masterImage: displayImage)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    cropControls(masterPixels: masterPixels, rectAspect: rectAspect)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
            } else if !loadErrorMessage.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.yellow)
                    Text(loadErrorMessage)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            if isApplying {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Applying…")
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(18)
                .background(.black.opacity(0.6))
                .cornerRadius(14)
            } else if isUpdatingPreview {
                VStack {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .navigationTitle("Fix framing (\(family.uiName))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isApplying)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    Task { await applyAndDismissIfPossible() }
                }
                .disabled(isApplying || previewImage == nil)
            }

#if DEBUG
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $debugOverlayEnabled) {
                        Text("Debug crop overlay")
                    }
                    Button("Force refresh detection") {
                        Task { await runDebugDetection(force: true) }
                    }
                } label: {
                    Image(systemName: "ladybug")
                }
            }
#endif
        }
        .onAppear {
            previousFocusSnapshot = focus?.wrappedValue
            focus?.wrappedValue = .smartPhotoManualFraming(
                masterFileName: masterFileName,
                family: family
            )
        }
        .onDisappear {
            if let prev = previousFocusSnapshot {
                focus?.wrappedValue = prev
            }
        }
        .task {
            loadMasterImage()
        }
#if DEBUG
        .task(id: debugOverlayEnabled) {
            if debugOverlayEnabled {
                await runDebugDetection(force: false)
            } else {
                debugDetection = nil
                debugStatusMessage = ""
            }
        }
#endif
    }

    private func loadMasterImage() {
        let loaded = AppGroup.loadUIImage(fileName: masterFileName)
        if let loaded {
            masterImage = loaded
            loadErrorMessage = ""
            refreshPreviewImage(master: loaded, quarterTurns: rotationQuarterTurns)
        } else {
            masterImage = nil
            previewImage = nil
            loadErrorMessage = "Failed to load image: \(masterFileName)"
        }
    }

    private func refreshPreviewImage(master: UIImage, quarterTurns: Int) {
        let requestID = previewRequestID + 1
        previewRequestID = requestID
        isUpdatingPreview = true

        let turns = SmartPhotoCropMath.normalisedRotationQuarterTurns(quarterTurns)

        Task.detached(priority: .userInitiated) {
            let rotated = SmartPhotoManualCropRenderer.previewImage(master: master, rotationQuarterTurns: turns)
            await MainActor.run {
                guard requestID == previewRequestID else { return }
                previewImage = rotated
                rotationQuarterTurns = turns
                isUpdatingPreview = false
            }
        }
    }

    private func setTransform(
        rotationQuarterTurns newQuarterTurns: Int,
        cropRect newCropRect: NormalisedRect,
        straightenDegrees newStraightenDegrees: Double
    ) {
        let safeTurns = SmartPhotoCropMath.normalisedRotationQuarterTurns(newQuarterTurns)
        let safeCrop = newCropRect.normalised()
        let safeStraighten = Self.normalisedStraightenDegrees(newStraightenDegrees)

        guard let masterImage else {
            rotationQuarterTurns = safeTurns
            cropRect = safeCrop
            straightenDegrees = safeStraighten
            return
        }

        let requestID = previewRequestID + 1
        previewRequestID = requestID
        isUpdatingPreview = true

        Task.detached(priority: .userInitiated) {
            let rotated = SmartPhotoManualCropRenderer.previewImage(master: masterImage, rotationQuarterTurns: safeTurns)
            await MainActor.run {
                guard requestID == previewRequestID else { return }
                previewImage = rotated
                rotationQuarterTurns = safeTurns
                cropRect = safeCrop
                straightenDegrees = safeStraighten
                isUpdatingPreview = false
            }
        }
    }

    private func rotate90(clockwise: Bool) {
        guard !isApplying else { return }
        guard let masterImage else { return }

        let fromTurns = rotationQuarterTurns
        let toTurns = SmartPhotoCropMath.normalisedRotationQuarterTurns(fromTurns + (clockwise ? 1 : -1))

        let originalPixels = SmartPhotoCropMath.pixelSize(of: masterImage)
        let oldRectAspect = SmartPhotoCropMath.rectAspect(originalMasterPixels: originalPixels, quarterTurns: fromTurns, targetPixels: targetPixels)
        let newRectAspect = SmartPhotoCropMath.rectAspect(originalMasterPixels: originalPixels, quarterTurns: toTurns, targetPixels: targetPixels)

        let rotatedCrop = SmartPhotoCropMath.rotatedCropRectForQuarterTurn(
            current: cropRect,
            clockwise: clockwise,
            oldRectAspect: oldRectAspect,
            newRectAspect: newRectAspect
        )

        setTransform(rotationQuarterTurns: toTurns, cropRect: rotatedCrop, straightenDegrees: straightenDegrees)
    }

    private func resetToInitial() {
        setTransform(
            rotationQuarterTurns: initialRotationQuarterTurns,
            cropRect: initialCropRect,
            straightenDegrees: initialStraightenDegrees
        )
    }

    private func applyAndDismissIfPossible() async {
        guard !isApplying else { return }
        guard previewImage != nil else { return }

        isApplying = true
        defer { isApplying = false }

        let safeRect = cropRect.normalised()
        let safeDegrees = Self.normalisedStraightenDegrees(straightenDegrees)
        let safeTurns = SmartPhotoCropMath.normalisedRotationQuarterTurns(rotationQuarterTurns)

        await onApply(safeRect, safeDegrees, safeTurns)
        dismiss()
    }

    private func resetToAutoAndDismissIfPossible() async {
        guard !isApplying else { return }

        if let onResetToAuto {
            await onResetToAuto()
            dismiss()
        } else if let autoCropRect {
            setTransform(rotationQuarterTurns: 0, cropRect: autoCropRect, straightenDegrees: 0)
        }
    }

    private func cropCanvas(masterImage: UIImage) -> some View {
        GeometryReader { geo in
            let masterPixelSize = SmartPhotoCropMath.pixelSize(of: masterImage)
            let masterAspect = SmartPhotoCropMath.safeAspect(width: masterPixelSize.width, height: masterPixelSize.height)
            let targetAspect = SmartPhotoCropMath.safeAspect(width: targetPixels.width, height: targetPixels.height)
            let rectAspect = targetAspect / masterAspect

            let bounds = geo.size
            let displayRect = SmartPhotoCropMath.aspectFitRect(
                containerSize: bounds,
                imageAspect: masterAspect,
                padding: 0
            )

            let cropFrame = CGRect(
                x: displayRect.origin.x + CGFloat(cropRect.x) * displayRect.size.width,
                y: displayRect.origin.y + CGFloat(cropRect.y) * displayRect.size.height,
                width: CGFloat(cropRect.width) * displayRect.size.width,
                height: CGFloat(cropRect.height) * displayRect.size.height
            )

            let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard !isApplying else { return }
                    guard !isPinching else { return }

                    if dragStartRect == nil {
                        dragStartRect = cropRect
                    }
                    guard let start = dragStartRect else { return }

                    let dx = Double(value.translation.width / displayRect.size.width)
                    let dy = Double(value.translation.height / displayRect.size.height)

                    let proposed = NormalisedRect(
                        x: start.x + dx,
                        y: start.y + dy,
                        width: start.width,
                        height: start.height
                    )
                    cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
                }
                .onEnded { _ in
                    dragStartRect = nil
                }

            let magnifyGesture = MagnificationGesture()
                .onChanged { scale in
                    guard !isApplying else { return }
                    if pinchStartRect == nil {
                        pinchStartRect = cropRect
                        isPinching = true
                    }
                    guard let start = pinchStartRect else { return }

                    let proposedWidth = start.width * Double(scale)
                    let newWidth = SmartPhotoCropMath.clampWidth(proposedWidth, rectAspect: rectAspect)
                    let newHeight = newWidth / rectAspect

                    let cx = start.x + start.width / 2
                    let cy = start.y + start.height / 2

                    let proposed = NormalisedRect(
                        x: cx - newWidth / 2,
                        y: cy - newHeight / 2,
                        width: newWidth,
                        height: newHeight
                    )
                    cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
                }
                .onEnded { _ in
                    pinchStartRect = nil
                    isPinching = false
                }

            let precisionDragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard !isApplying else { return }
                    guard isPrecisionDragActive else { return }

                    if precisionStartRect == nil {
                        precisionStartRect = cropRect
                    }
                    guard let start = precisionStartRect else { return }

                    let dx = Double(value.translation.width / displayRect.size.width)
                    let dy = Double(value.translation.height / displayRect.size.height)

                    let proposed = NormalisedRect(
                        x: start.x + dx,
                        y: start.y + dy,
                        width: start.width,
                        height: start.height
                    )
                    cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
                }
                .onEnded { _ in
                    precisionStartRect = nil
                    isPrecisionDragActive = false
                }

            ZStack {
                Image(uiImage: masterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .rotationEffect(.degrees(straightenDegrees))
                    .position(x: displayRect.midX, y: displayRect.midY)

                Path { path in
                    path.addRect(displayRect)
                    path.addRect(cropFrame)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                if isStraightenEditing {
                    StraightenGridOverlay(rect: displayRect, divisions: 12)
                        .allowsHitTesting(false)
                }

                CropThirdsGridOverlay(frame: cropFrame, divisions: 3)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .path(in: cropFrame)
                    .stroke(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .gesture(dragGesture)
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(precisionDragGesture)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .onEnded { _ in
                                isPrecisionDragActive = true
                                precisionStartRect = cropRect
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                toggleZoomRect(rectAspect: rectAspect)
                            }
                    )

#if DEBUG
                if debugOverlayEnabled, rotationQuarterTurns == 0, let det = debugDetection {
                    SmartPhotoDebugOverlayView(
                        displayRect: displayRect,
                        detection: det
                    )
                    .allowsHitTesting(false)
                }

                if debugOverlayEnabled, rotationQuarterTurns == 0 {
                    debugHUD(displayRect: displayRect)
                }
#endif
            }
        }
    }

    private func cropControls(masterPixels: PixelSize, rectAspect: Double) -> some View {
        let step = nudgeStepPixels

        func nudge(dxPixels: Int, dyPixels: Int) {
            guard !isApplying else { return }

            let dx = Double(dxPixels) / Double(max(1, masterPixels.width))
            let dy = Double(dyPixels) / Double(max(1, masterPixels.height))

            let proposed = NormalisedRect(
                x: cropRect.x + dx,
                y: cropRect.y + dy,
                width: cropRect.width,
                height: cropRect.height
            )
            cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
        }

        func zoom(deltaPixels: Int) {
            guard !isApplying else { return }

            let delta = Double(deltaPixels) / Double(max(1, masterPixels.width))
            let newWidth = SmartPhotoCropMath.clampWidth(cropRect.width + delta, rectAspect: rectAspect)
            let newHeight = newWidth / rectAspect

            let cx = cropRect.x + cropRect.width / 2
            let cy = cropRect.y + cropRect.height / 2

            let proposed = NormalisedRect(
                x: cx - newWidth / 2,
                y: cy - newHeight / 2,
                width: newWidth,
                height: newHeight
            )
            cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
        }

        func recenter() {
            guard !isApplying else { return }
            cropRect = SmartPhotoCropMath.clampRect(
                NormalisedRect(
                    x: (1.0 - cropRect.width) / 2.0,
                    y: (1.0 - cropRect.height) / 2.0,
                    width: cropRect.width,
                    height: cropRect.height
                ),
                rectAspect: rectAspect
            )
        }

        let canResetToAuto = (autoCropRect != nil) || (onResetToAuto != nil)
        let rotationLabel = SmartPhotoCropMath.rotationLabel(forQuarterTurns: rotationQuarterTurns)

        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("Reset") {
                    resetToInitial()
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)

                if canResetToAuto {
                    Button("Reset to Auto") {
                        Task { await resetToAutoAndDismissIfPossible() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying || isUpdatingPreview)
                }

                Spacer()

                Button {
                    rotate90(clockwise: false)
                } label: {
                    Image(systemName: "rotate.left")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)

                Button {
                    rotate90(clockwise: true)
                } label: {
                    Image(systemName: "rotate.right")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)
            }

            Text("\(family.uiName) • \(targetPixels.width)×\(targetPixels.height) px • \(rotationLabel)")
                .font(.headline)
                .foregroundColor(.white.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Text("Straighten")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                Slider(
                    value: $straightenDegrees,
                    in: -15...15,
                    step: 0.1,
                    onEditingChanged: { editing in
                        isStraightenEditing = editing
                    }
                )
                .disabled(isApplying || isUpdatingPreview)

                Text(String(format: "%+.1f°", straightenDegrees))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 54, alignment: .trailing)

                Button {
                    straightenDegrees = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview || abs(straightenDegrees) < 0.01)
            }

            HStack {
                Text("Nudge")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Picker("Step", selection: $nudgeStepPixels) {
                    Text("1 px").tag(1)
                    Text("5 px").tag(5)
                    Text("10 px").tag(10)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(isApplying || isUpdatingPreview)
            }

            HStack {
                Spacer()

                Button {
                    zoom(deltaPixels: 12)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)

                Button {
                    zoom(deltaPixels: -12)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)

                Spacer()
            }

            VStack(spacing: 10) {
                Button {
                    nudge(dxPixels: 0, dyPixels: -step)
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)

                HStack(spacing: 10) {
                    Button {
                        nudge(dxPixels: -step, dyPixels: 0)
                    } label: {
                        Image(systemName: "arrow.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying || isUpdatingPreview)

                    Button {
                        recenter()
                    } label: {
                        Image(systemName: "scope")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying || isUpdatingPreview)

                    Button {
                        nudge(dxPixels: step, dyPixels: 0)
                    } label: {
                        Image(systemName: "arrow.right")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying || isUpdatingPreview)
                }

                Button {
                    nudge(dxPixels: 0, dyPixels: step)
                } label: {
                    Image(systemName: "arrow.down")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || isUpdatingPreview)
            }

            Text("Drag to move. Pinch to resize crop. Double-tap toggles zoom. Press and hold, then drag for fine moves.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.35))
        .cornerRadius(16)
    }

    private func toggleZoomRect(rectAspect: Double) {
        let maxWidth = min(1.0, rectAspect)
        let currentWidth = cropRect.width
        let nearlyFull = abs(currentWidth - maxWidth) < 0.02

        let targetWidth = nearlyFull ? SmartPhotoCropMath.clampWidth(maxWidth * 0.5, rectAspect: rectAspect) : maxWidth
        let targetHeight = targetWidth / rectAspect

        let cx = cropRect.x + cropRect.width / 2
        let cy = cropRect.y + cropRect.height / 2

        let proposed = NormalisedRect(
            x: cx - targetWidth / 2,
            y: cy - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: rectAspect)
    }

    private static func normalisedStraightenDegrees(_ degrees: Double) -> Double {
        if let normalised = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(degrees) {
            return normalised
        }
        return 0
    }

#if DEBUG
    private func debugHUD(displayRect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug overlay enabled")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)

            Text(debugStatusMessage)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(10)
        .background(.black.opacity(0.55))
        .cornerRadius(10)
        .frame(maxWidth: displayRect.width, alignment: .leading)
        .position(x: displayRect.minX + 10 + 140, y: displayRect.minY + 22)
        .allowsHitTesting(false)
    }

    private func runDebugDetection(force: Bool) async {
        guard debugOverlayEnabled else { return }
        guard rotationQuarterTurns == 0 else {
            await MainActor.run {
                debugDetection = nil
                debugStatusMessage = "Rotation is active; debug overlay is hidden."
            }
            return
        }

        if !force, debugDetection != nil {
            return
        }

        await MainActor.run {
            debugStatusMessage = "Running detection…"
        }

        guard let masterImage else {
            await MainActor.run {
                debugStatusMessage = "No image loaded."
                debugDetection = nil
            }
            return
        }

        let result = await Task.detached(priority: .userInitiated) { () -> SmartPhotoDetection? in
            let detector = SmartPhotoDetector()
            return detector.detect(in: masterImage)
        }.value

        await MainActor.run {
            debugDetection = result
            if result == nil {
                debugStatusMessage = "Detection failed."
            } else {
                debugStatusMessage = "Detection ready."
            }
        }
    }
#endif
}
