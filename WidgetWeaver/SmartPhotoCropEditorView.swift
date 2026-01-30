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
    let autoCropRect: NormalisedRect?
    let filterSpec: PhotoFilterSpec?
    let focus: Binding<EditorFocusSnapshot>?

    let onResetToAuto: (() async -> Void)?
    let onApply: (NormalisedRect, Double, Int) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var masterImage: UIImage?
    @State private var previewRotationQuarterTurns: Int = 0
    @State private var previewImage: UIImage?
    @State private var cropRect: NormalisedRect = NormalisedRect(x: 0, y: 0, width: 1, height: 1)
    @State private var cropIntentRect: NormalisedRect = NormalisedRect(x: 0, y: 0, width: 1, height: 1)

    @State private var dragStartRect: NormalisedRect?
    @State private var pinchStartRect: NormalisedRect?
    @State private var precisionStartRect: NormalisedRect?

    @State private var isPinching: Bool = false
    @State private var isPrecisionDragActive: Bool = false

    @State private var isApplying: Bool = false

    @State private var straightenDegrees: Double = 0
    @State private var straightenDenseGridOpacity: Double = 0
    @State private var straightenInteractionToken: Int = 0
    @GestureState private var isStraightenHolding: Bool = false
    @State private var isStraightenEditing: Bool = false
    @State private var lastStraightenDegrees: Double = 0

    @State private var loadErrorMessage: String = ""
    @State private var didPushFocus: Bool = false
    @State private var focusSnapshot: EditorFocusSnapshot?

    #if DEBUG
    @State private var debugOverlayEnabled: Bool = false
    @State private var isDetecting: Bool = false
    @State private var debugDetection: SmartPhotoDebugDetection?
    @State private var debugStatusMessage: String = ""
    #endif

    init(
        family: EditingFamily,
        masterFileName: String,
        targetPixels: PixelSize,
        initialCropRect: NormalisedRect,
        initialStraightenDegrees: Double = 0,
        initialRotationQuarterTurns _: Int = 0,
        autoCropRect: NormalisedRect? = nil,
        filterSpec: PhotoFilterSpec? = nil,
        focus: Binding<EditorFocusSnapshot>? = nil,
        onResetToAuto: (() async -> Void)? = nil,
        onApply: @escaping (NormalisedRect, Double, Int) async -> Void
    ) {
        self.family = family
        self.masterFileName = masterFileName
        self.targetPixels = targetPixels.normalised()
        self.initialCropRect = initialCropRect.normalised()
        self.initialStraightenDegrees = Self.normalisedStraightenDegrees(initialStraightenDegrees)
        self.autoCropRect = autoCropRect?.normalised()
        self.filterSpec = filterSpec
        self.focus = focus
        self.onResetToAuto = onResetToAuto
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            if !loadErrorMessage.isEmpty {
                ContentUnavailableView("Missing image", systemImage: "exclamationmark.triangle", description: Text(loadErrorMessage))
                    .padding(.horizontal, 16)
            } else if let masterImage {
                cropCanvas(masterImage: previewImage ?? masterImage)
                    .safeAreaInset(edge: .bottom) {
                        let img = previewImage ?? masterImage
                        let px = SmartPhotoCropMath.pixelSize(of: img)
                        let masterPixelSize = PixelSize(width: px.width, height: px.height).normalised()
                        let masterAspect = SmartPhotoCropMath.safeAspect(width: masterPixelSize.width, height: masterPixelSize.height)
                        let targetAspect = SmartPhotoCropMath.safeAspect(width: targetPixels.width, height: targetPixels.height)
                        let normalisedRectAspect = targetAspect / masterAspect
                        cropControls(
                            masterPixels: masterPixelSize,
                            rectAspect: normalisedRectAspect
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
            } else {
                ProgressView()
                    .padding(.horizontal, 16)
            }
        }
        .navigationTitle("Fix framing (\(family.label))")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pushFocusIfNeeded() }
        .onDisappear { restoreFocusIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isApplying)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyAndDismissIfPossible() }
                    .disabled(isApplying || masterImage == nil || previewRotationQuarterTurns != 0)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Reset") {
                    cropIntentRect = initialCropRect.normalised()
                    cropRect = cropIntentRect
                    straightenDegrees = initialStraightenDegrees
                    previewRotationQuarterTurns = 0
                    previewImage = nil
                    applyStraightenConstraintFromIntent()
                }
                .disabled(isApplying || masterImage == nil)
                if autoCropRect != nil {
                    Button("Reset to Auto") { resetToAutoAndDismissIfPossible() }
                        .disabled(isApplying)
                }
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Debug overlay", isOn: $debugOverlayEnabled)
                    Button("Re-run detection") { runDebugDetection(force: true) }
                        .disabled(masterImage == nil || isApplying || isDetecting)
                    if isDetecting {
                        Text("Detecting…")
                    } else if !debugStatusMessage.isEmpty {
                        Text(debugStatusMessage)
                    } else if debugOverlayEnabled, let d = debugDetection {
                        Text("Chosen: \(d.chosenKind.label)")
                    }
                } label: {
                    Image(systemName: debugOverlayEnabled ? "ladybug.fill" : "ladybug")
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(masterImage == nil)
            }
            #endif
        }
        .task {
            if masterImage != nil || !loadErrorMessage.isEmpty { return }
            loadMasterImage()
        }
        .onChange(of: straightenDegrees) { straightenInteractionToken &+= 1; applyStraightenConstraintFromIntent() }
        .onChange(of: isStraightenHolding) { straightenInteractionToken &+= 1 }
        .task(id: straightenInteractionToken) { @MainActor in
            guard straightenInteractionToken > 0 else { return }
            straightenDenseGridOpacity = 1
            while isStraightenHolding && !Task.isCancelled { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled && !isStraightenHolding else { return }
            withAnimation(.easeOut(duration: 0.25)) { straightenDenseGridOpacity = 0 }
        }
        #if DEBUG
        .task(id: debugOverlayEnabled) {
            if debugOverlayEnabled {
                runDebugDetection(force: false)
            } else {
                debugStatusMessage = ""
            }
        }
        #endif
        .onAppear {
            cropIntentRect = initialCropRect.normalised()
            cropRect = cropIntentRect
            straightenDegrees = initialStraightenDegrees
            lastStraightenDegrees = initialStraightenDegrees
        }
    }

    private func loadMasterImage() {
        let img = AppGroup.loadUIImage(fileName: masterFileName)
        if let img {
            masterImage = img
            previewRotationQuarterTurns = 0
            previewImage = nil
            loadErrorMessage = ""
            applyStraightenConstraintFromIntent()
            return
        }
        loadErrorMessage = "Smart master image was not found on disk."
    }

    private func applyAndDismissIfPossible() {
        guard !isApplying else { return }
        guard masterImage != nil else { return }
        guard previewRotationQuarterTurns == 0 else { return }

        isApplying = true
        let rectToApply = cropRect.normalised()

        Task {
            let degreesToApply = Self.normalisedStraightenDegrees(straightenDegrees)
            await onApply(rectToApply, degreesToApply, 0)
            await MainActor.run {
                isApplying = false
                dismiss()
            }
        }
    }

    private func resetToAutoAndDismissIfPossible() {
        guard !isApplying else { return }
        guard let auto = autoCropRect?.normalised() else { return }

        if let onResetToAuto {
            isApplying = true
            Task {
                await onResetToAuto()
                await MainActor.run {
                    isApplying = false
                    dismiss()
                }
            }
            return
        }

        cropIntentRect = auto
        cropRect = auto

        previewRotationQuarterTurns = 0
        previewImage = nil
        applyStraightenConstraintFromIntent()

        Task { @MainActor in dismiss() }
    }

    private func pushFocusIfNeeded() {
        guard let focus else { return }
        guard !didPushFocus else { return }
        focusSnapshot = focus.wrappedValue
        didPushFocus = true
        focus.wrappedValue = .singleNonAlbumElement(id: "smartPhotoCrop")
    }

    private func restoreFocusIfNeeded() {
        guard didPushFocus else { return }
        guard let focus else { return }
        defer {
            didPushFocus = false
            focusSnapshot = nil
        }
        guard focus.wrappedValue.focus == .element(id: "smartPhotoCrop") else { return }
        guard let snap = focusSnapshot else { return }
        focus.wrappedValue = snap
    }

    private static func normalisedStraightenDegrees(_ degrees: Double) -> Double {
        let d = degrees.clamped(to: -45...45)
        if abs(d) < 0.0001 { return 0 }
        return d
    }

    private func applyStraightenConstraintFromIntent() {
        guard let img = previewImage ?? masterImage else { return }
        let px = SmartPhotoCropMath.pixelSize(of: img)
        let imageAspect = SmartPhotoCropMath.safeAspect(width: px.width, height: px.height)
        let targetAspect = SmartPhotoCropMath.safeAspect(width: targetPixels.width, height: targetPixels.height)
        let rectAspect = targetAspect / imageAspect
        cropRect = SmartPhotoCropMath.straightenConstrainedRect(cropIntentRect.normalised(), rectAspect: rectAspect, imageAspect: imageAspect, straightenDegrees: straightenDegrees)
    }

    #if DEBUG
    private func runDebugDetection(force: Bool) {
        guard debugOverlayEnabled else { return }
        guard !isApplying else { return }
        guard !isDetecting else { return }
        guard masterImage != nil else { return }

        if debugDetection != nil && !force {
            return
        }

        guard let masterData = AppGroup.readImageData(fileName: masterFileName) else {
            debugDetection = nil
            debugStatusMessage = "Master file missing."
            return
        }

        isDetecting = true
        debugStatusMessage = "Detecting…"

        Task.detached(priority: .userInitiated) {
            let detection = SmartPhotoDebugDetector.detect(masterData: masterData)
            await MainActor.run {
                isDetecting = false
                guard debugOverlayEnabled else {
                    debugDetection = nil
                    debugStatusMessage = ""
                    return
                }
                debugDetection = detection
                debugStatusMessage = (detection == nil) ? "No detections." : ""
            }
        }
    }
    #endif

    @ViewBuilder
    private func cropCanvas(masterImage: UIImage) -> some View {
        GeometryReader { geo in
            let masterPixelSize = SmartPhotoCropMath.pixelSize(of: masterImage)
            let masterAspect = SmartPhotoCropMath.safeAspect(width: masterPixelSize.width, height: masterPixelSize.height)
            let targetAspect = SmartPhotoCropMath.safeAspect(width: targetPixels.width, height: targetPixels.height)
            let normalisedRectAspect = targetAspect / masterAspect
            let displayRect = SmartPhotoCropMath.aspectFitRect(container: geo.size, imageAspect: masterAspect)
            let cropFrame = CGRect(
                x: displayRect.minX + CGFloat(cropRect.x) * displayRect.width,
                y: displayRect.minY + CGFloat(cropRect.y) * displayRect.height,
                width: CGFloat(cropRect.width) * displayRect.width,
                height: CGFloat(cropRect.height) * displayRect.height
            )
            let contentRect = CGRect(origin: .zero, size: displayRect.size)
            let showGrid = isStraightenEditing || straightenDenseGridOpacity > 0.001 || abs(straightenDegrees) > 0.01

            ZStack {
                ZStack {
                    Image(uiImage: masterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayRect.width, height: displayRect.height)

                    #if DEBUG
                    if debugOverlayEnabled, previewRotationQuarterTurns == 0, let debugDetection {
                        SmartPhotoDebugOverlayView(
                            displayRect: contentRect,
                            detection: debugDetection
                        )
                    }
                    #endif
                }
                .rotationEffect(.degrees(straightenDegrees))
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .clipped()

                Path { p in
                    p.addRect(displayRect)
                    p.addRect(cropFrame)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                if showGrid {
                    Group {
                        StraightenGridOverlay(rect: displayRect, divisions: 3)
                            .opacity(abs(straightenDegrees) > 0.01 && !isStraightenEditing ? 1.0 : 0.0)
                        StraightenGridOverlay(rect: displayRect, divisions: 10)
                            .opacity(straightenDenseGridOpacity)
                        CropThirdsGridOverlay(frame: cropFrame, divisions: 3)
                    }
                    .opacity((isStraightenEditing || abs(straightenDegrees) > 0.01) ? 1.0 : straightenDenseGridOpacity)
                    .allowsHitTesting(false)
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .shadow(radius: 1.5)

                let dragGesture = DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isApplying else { return }
                        if isPinching { return }
                        if dragStartRect == nil { dragStartRect = cropRect }
                        let start = dragStartRect ?? cropRect
                        let dx = Double(value.translation.width / displayRect.width)
                        let dy = Double(value.translation.height / displayRect.height)
                        let proposed = NormalisedRect(
                            x: start.x + dx,
                            y: start.y + dy,
                            width: start.width,
                            height: start.height
                        )
                        cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: normalisedRectAspect)
                    }
                    .onEnded { _ in
                        dragStartRect = nil
                        cropIntentRect = cropRect.normalised()
                    }

                let pinchGesture = MagnificationGesture()
                    .onChanged { value in
                        guard !isApplying else { return }
                        if !isPinching {
                            isPinching = true
                            pinchStartRect = cropRect
                        }
                        let start = pinchStartRect ?? cropRect
                        let scale = Double(value)
                        let factor = 1.0 / max(0.0001, scale)
                        let w = SmartPhotoCropMath.clampWidth(start.width * factor, rectAspect: normalisedRectAspect)
                        let h = w / normalisedRectAspect
                        let cx = start.x + (start.width / 2.0)
                        let cy = start.y + (start.height / 2.0)
                        let proposed = NormalisedRect(x: cx - (w / 2.0), y: cy - (h / 2.0), width: w, height: h)
                        cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: normalisedRectAspect)
                    }
                    .onEnded { _ in
                        isPinching = false
                        pinchStartRect = nil
                        cropIntentRect = cropRect.normalised()
                    }

                    #if os(macOS)
                    let precisionGesture = DragGesture(minimumDistance: 0)
                        .modifiers(.command)
                        .onChanged { value in
                            guard !isApplying else { return }
                            if precisionStartRect == nil { precisionStartRect = cropRect }
                            isPrecisionDragActive = true
                            let start = precisionStartRect ?? cropRect
                            let dx = Double(value.translation.width / displayRect.width) * 0.35
                            let dy = Double(value.translation.height / displayRect.height) * 0.35
                            let proposed = NormalisedRect(
                                x: start.x + dx,
                                y: start.y + dy,
                                width: start.width,
                                height: start.height
                            )
                            cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: normalisedRectAspect)
                        }
                        .onEnded { _ in
                            precisionStartRect = nil
                            isPrecisionDragActive = false
                            cropIntentRect = cropRect.normalised()
                        }
                    #endif


                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(pinchGesture)
                #if os(macOS)
                    .simultaneousGesture(precisionGesture)
                #endif

                if isPrecisionDragActive {
                    Text("Precision move")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func cropControls(
        masterPixels: PixelSize,
        rectAspect: Double
    ) -> some View {
        VStack(spacing: 12) {
            rotateControls(masterPixels: masterPixels, rectAspect: rectAspect)
            straightenControls()
        }
    }

    private func rotateControls(
        masterPixels: PixelSize,
        rectAspect: Double
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                rotatePreview(deltaQuarterTurns: -1, rectAspect: rectAspect, masterPixels: masterPixels)
            } label: {
                Label("Rotate left", systemImage: "rotate.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isApplying || masterImage == nil)

            Button {
                rotatePreview(deltaQuarterTurns: 1, rectAspect: rectAspect, masterPixels: masterPixels)
            } label: {
                Label("Rotate right", systemImage: "rotate.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isApplying || masterImage == nil)

            Spacer(minLength: 0)

            Button {
                toggleZoom(anchor: CGPoint(x: 0.5, y: 0.5), rectAspect: rectAspect)
            } label: {
                Text("Zoom")
                    .frame(minWidth: 72, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isApplying || masterImage == nil)
        }
    }

    private func rotatePreview(
        deltaQuarterTurns: Int,
        rectAspect: Double,
        masterPixels: PixelSize
    ) {
        guard !isApplying else { return }
        guard let masterImage else { return }

        let from = previewRotationQuarterTurns
        let to = SmartPhotoCropRotationPreview.normalisedQuarterTurns(from + deltaQuarterTurns)

        let baseRect = cropRect.normalised()
        let remappedRect = SmartPhotoCropRotationPreview.remapCropRect(
            baseRect,
            fromQuarterTurns: from,
            toQuarterTurns: to,
            targetRectAspect: rectAspect
        )

        let imageAspect: Double = {
            let w = Double(masterPixels.width)
            let h = Double(masterPixels.height)
            if to % 2 == 0 { return SmartPhotoCropMath.safeAspect(width: masterPixels.width, height: masterPixels.height) }
            return SmartPhotoCropMath.safeAspect(width: Int(h), height: Int(w))
        }()

        let constrainedRect = SmartPhotoCropMath.straightenConstrainedRect(
            remappedRect,
            rectAspect: rectAspect,
            imageAspect: imageAspect,
            straightenDegrees: straightenDegrees
        )

        cropIntentRect = constrainedRect.normalised()
        cropRect = cropIntentRect

        previewRotationQuarterTurns = to
        previewImage = (to == 0) ? nil : SmartPhotoCropRotationPreview.rotatedPreviewImage(masterImage, quarterTurns: to)
        dragStartRect = nil; pinchStartRect = nil; precisionStartRect = nil
        isPinching = false; isPrecisionDragActive = false
    }

    private func toggleZoom(anchor: CGPoint, rectAspect: Double) {
        guard !isApplying else { return }
        cropRect = SmartPhotoCropMath.toggleZoomRect(current: cropRect, rectAspect: rectAspect, anchor: anchor)
        cropIntentRect = cropRect.normalised()
    }

    private func straightenControls() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Straighten")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(straightenDegrees.rounded()))°")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $straightenDegrees, in: -45...45, step: 1)
                .disabled(isApplying || masterImage == nil)

            HStack(spacing: 10) {
                Button {
                    isStraightenEditing = true
                    straightenDegrees = 0
                    lastStraightenDegrees = 0
                    straightenInteractionToken &+= 1
                } label: {
                    Text("Zero")
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || masterImage == nil)

                Button {
                    isStraightenEditing = true
                    let snapped = Double(Int(straightenDegrees.rounded()))
                    straightenDegrees = snapped
                    lastStraightenDegrees = snapped
                    straightenInteractionToken &+= 1
                } label: {
                    Text("Snap")
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || masterImage == nil)

                Spacer(minLength: 0)

                Button {
                    isStraightenEditing = true
                    let d = lastStraightenDegrees
                    let reset = d == 0 ? initialStraightenDegrees : 0
                    straightenDegrees = reset
                    lastStraightenDegrees = reset
                    straightenInteractionToken &+= 1
                } label: {
                    Text("Toggle")
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isApplying || masterImage == nil)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .updating($isStraightenHolding) { value, state, _ in
                            state = value
                        }
                )
            }
        }
        .onChange(of: straightenDegrees) { _, newValue in
            let snapped = Double(Int(newValue.rounded()))
            if abs(newValue - snapped) < 0.0001 {
                lastStraightenDegrees = snapped
            }
        }
        .onChange(of: isStraightenHolding) { _, holding in
            if holding {
                isStraightenEditing = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !isStraightenHolding {
                        isStraightenEditing = false
                    }
                }
            }
        }
    }

    private struct StraightenGridOverlay: View {
        let rect: CGRect
        let divisions: Int

        var body: some View {
            Path { p in
                guard divisions >= 2 else { return }
                for i in 1..<divisions {
                    let t = CGFloat(i) / CGFloat(divisions)

                    let x = rect.minX + t * rect.width
                    p.move(to: CGPoint(x: x, y: rect.minY))
                    p.addLine(to: CGPoint(x: x, y: rect.maxY))

                    let y = rect.minY + t * rect.height
                    p.move(to: CGPoint(x: rect.minX, y: y))
                    p.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 1)
        }
    }

    private struct CropThirdsGridOverlay: View {
        let frame: CGRect
        let divisions: Int

        var body: some View {
            Path { p in
                guard divisions >= 2 else { return }
                for i in 1..<divisions {
                    let t = CGFloat(i) / CGFloat(divisions)

                    let x = frame.minX + t * frame.width
                    p.move(to: CGPoint(x: x, y: frame.minY))
                    p.addLine(to: CGPoint(x: x, y: frame.maxY))

                    let y = frame.minY + t * frame.height
                    p.move(to: CGPoint(x: frame.minX, y: y))
                    p.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 1)
        }
    }
}
