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
    let focus: Binding<EditorFocusSnapshot>?
    let onResetToAuto: (() async -> Void)?
    let onApply: (NormalisedRect, Double, Int) async -> Void

    @State private var masterImage: UIImage?
    @State private var cropRect: NormalisedRect
    @State private var straightenDegrees: Double
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

    // Debug overlay (Batch E)
    @AppStorage("widgetweaver.smartphoto.debugOverlay.enabled")
    private var debugOverlayEnabled: Bool = false

    @State private var debugDetection: SmartPhotoDebugDetection?
    @State private var isDetecting: Bool = false
    @State private var debugStatusMessage: String = ""

    @Environment(\.dismiss) private var dismiss

    init(
        family: EditingFamily,
        masterFileName: String,
        targetPixels: PixelSize,
        initialCropRect: NormalisedRect,
        initialStraightenDegrees: Double = 0,
        initialRotationQuarterTurns _: Int = 0,
        autoCropRect: NormalisedRect? = nil,
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
        self.focus = focus
        self.onResetToAuto = onResetToAuto
        self.onApply = onApply

        _cropRect = State(initialValue: initialCropRect.normalised())
        _straightenDegrees = State(initialValue: Self.normalisedStraightenDegrees(initialStraightenDegrees))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let masterImage {
                cropCanvas(masterImage: masterImage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            } else if !loadErrorMessage.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    Text(loadErrorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
            if isApplying {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Applying crop…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let masterImage {
                let masterPixelSize = SmartPhotoCropMath.pixelSize(of: masterImage)
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
        }
        .navigationTitle("Fix framing (\(family.label))")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pushFocusIfNeeded()
        }
        .onDisappear {
            restoreFocusIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isApplying)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyAndDismissIfPossible() }
                    .disabled(isApplying || masterImage == nil)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Reset") {
                    cropRect = initialCropRect.normalised()
                    straightenDegrees = initialStraightenDegrees
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
                    Button("Re-run detection") {
                        runDebugDetection(force: true)
                    }
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
        .task(id: debugOverlayEnabled) {
            if debugOverlayEnabled {
                runDebugDetection(force: false)
            } else {
                debugStatusMessage = ""
            }
        }
    }

    private func loadMasterImage() {
        let img = AppGroup.loadUIImage(fileName: masterFileName)
        if let img {
            masterImage = img
            loadErrorMessage = ""
            return
        }
        loadErrorMessage = "Smart master image was not found on disk."
    }

    private func applyAndDismissIfPossible() {
        guard !isApplying else { return }
        guard masterImage != nil else { return }
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
        cropRect = auto
        straightenDegrees = 0
    }

    private func pushFocusIfNeeded() {
        guard let focus else { return }
        if previousFocusSnapshot == nil {
            previousFocusSnapshot = focus.wrappedValue
        }
        focus.wrappedValue = .singleNonAlbumElement(id: "smartPhotoCrop")
    }

    private func restoreFocusIfNeeded() {
        guard let focus else { return }
        guard let previous = previousFocusSnapshot else { return }
        defer { previousFocusSnapshot = nil }
        if focus.wrappedValue.focus == .element(id: "smartPhotoCrop") {
            focus.wrappedValue = previous
        }
    }

    private func runDebugDetection(force: Bool) {
        guard debugOverlayEnabled else { return }
        guard !isDetecting else { return }
        if debugDetection != nil, !force { return }

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
            let showGrid = isStraightenEditing || abs(straightenDegrees) > 0.01

            ZStack {
                ZStack {
                    Image(uiImage: masterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayRect.width, height: displayRect.height)

                    if debugOverlayEnabled, let debugDetection {
                        SmartPhotoDebugOverlayView(
                            displayRect: contentRect,
                            detection: debugDetection
                        )
                    }
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
                    StraightenGridOverlay(rect: displayRect, divisions: isStraightenEditing ? 10 : 3)
                        .allowsHitTesting(false)
                }

                if showGrid {
                    CropThirdsGridOverlay(frame: cropFrame, divisions: 3)
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
                        if isPrecisionDragActive { return }
                        if isPinching { return }

                        if dragStartRect == nil { dragStartRect = cropRect }
                        guard let start = dragStartRect else { return }

                        let dx = Double(value.translation.width / max(1.0, displayRect.width))
                        let dy = Double(value.translation.height / max(1.0, displayRect.height))

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
                    }

                let precisionGesture = LongPressGesture(minimumDuration: 0.25, maximumDistance: 12)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard !isApplying else { return }
                        if isPinching { return }

                        switch value {
                        case .first(true):
                            break

                        case .second(true, nil):
                            if !isPrecisionDragActive {
                                isPrecisionDragActive = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                            if precisionStartRect == nil { precisionStartRect = cropRect }

                        case .second(true, let drag?):
                            if !isPrecisionDragActive {
                                isPrecisionDragActive = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                            if precisionStartRect == nil { precisionStartRect = cropRect }
                            guard let start = precisionStartRect else { return }

                            let precisionFactor = 0.05
                            let dx = Double(drag.translation.width / max(1.0, displayRect.width)) * precisionFactor
                            let dy = Double(drag.translation.height / max(1.0, displayRect.height)) * precisionFactor

                            let proposed = NormalisedRect(
                                x: start.x + dx,
                                y: start.y + dy,
                                width: start.width,
                                height: start.height
                            )

                            cropRect = SmartPhotoCropMath.pixelSnappedRect(
                                proposed,
                                masterPixels: masterPixelSize,
                                rectAspect: normalisedRectAspect
                            )

                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        precisionStartRect = nil
                        isPrecisionDragActive = false
                    }

                let magnifyGesture = MagnificationGesture()
                    .onChanged { value in
                        guard !isApplying else { return }
                        if isPrecisionDragActive { return }

                        if !isPinching {
                            isPinching = true
                            dragStartRect = nil
                        }

                        if pinchStartRect == nil { pinchStartRect = cropRect }
                        guard let start = pinchStartRect else { return }

                        let scale = max(0.2, min(5.0, Double(value)))
                        let proposedWidth = start.width * scale

                        let centerX = start.x + (start.width / 2.0)
                        let centerY = start.y + (start.height / 2.0)

                        let w = SmartPhotoCropMath.clampWidth(proposedWidth, rectAspect: normalisedRectAspect)
                        let h = w / max(0.0001, normalisedRectAspect)

                        let proposed = NormalisedRect(
                            x: centerX - (w / 2.0),
                            y: centerY - (h / 2.0),
                            width: w,
                            height: h
                        )

                        cropRect = SmartPhotoCropMath.clampRect(proposed, rectAspect: normalisedRectAspect)
                    }
                    .onEnded { _ in
                        pinchStartRect = nil
                        isPinching = false
                    }

                let doubleTapGesture = SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard !isApplying else { return }

                        let anchor = CGPoint(
                            x: value.location.x / max(1.0, displayRect.width),
                            y: value.location.y / max(1.0, displayRect.height)
                        )

                        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                            cropRect = SmartPhotoCropMath.toggleZoomRect(
                                current: cropRect,
                                rectAspect: normalisedRectAspect,
                                anchor: anchor
                            )
                        }
                    }

                Rectangle()
                    .fill(.clear)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(precisionGesture)
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(doubleTapGesture)

                if debugOverlayEnabled {
                    SmartPhotoDebugHUDView(
                        isDetecting: isDetecting,
                        status: debugStatusMessage,
                        detection: debugDetection
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 10)
                }
            }
        }
    }

    private static func normalisedStraightenDegrees(_ degrees: Double) -> Double {
        let clamped = degrees.clamped(to: -45...45)
        if abs(clamped) < 0.0001 { return 0 }
        return clamped
    }

    private func cropControls(masterPixels: PixelSize, rectAspect: Double) -> some View {
        let zoomStepPixels = max(1, nudgeStepPixels * 10)

        func nudge(dxPixels: Int, dyPixels: Int) {
            guard !isApplying else { return }

            let stepX = Double(dxPixels) / Double(max(1, masterPixels.width))
            let stepY = Double(dyPixels) / Double(max(1, masterPixels.height))

            let proposed = NormalisedRect(
                x: cropRect.x + stepX,
                y: cropRect.y + stepY,
                width: cropRect.width,
                height: cropRect.height
            )

            cropRect = SmartPhotoCropMath.pixelSnappedRect(
                proposed,
                masterPixels: masterPixels,
                rectAspect: rectAspect
            )
        }

        func zoom(deltaPixels: Int) {
            guard !isApplying else { return }

            let deltaW = Double(deltaPixels) / Double(max(1, masterPixels.width))
            let proposedWidth = cropRect.width + deltaW

            let centerX = cropRect.x + (cropRect.width / 2.0)
            let centerY = cropRect.y + (cropRect.height / 2.0)

            let w = SmartPhotoCropMath.clampWidth(proposedWidth, rectAspect: rectAspect)
            let h = w / max(0.0001, rectAspect)

            let proposed = NormalisedRect(
                x: centerX - (w / 2.0),
                y: centerY - (h / 2.0),
                width: w,
                height: h
            )

            cropRect = SmartPhotoCropMath.pixelSnappedRect(
                proposed,
                masterPixels: masterPixels,
                rectAspect: rectAspect
            )
        }

        func recenter() {
            guard !isApplying else { return }

            let w = cropRect.width
            let h = cropRect.height

            let proposed = NormalisedRect(
                x: 0.5 - (w / 2.0),
                y: 0.5 - (h / 2.0),
                width: w,
                height: h
            )

            cropRect = SmartPhotoCropMath.pixelSnappedRect(
                proposed,
                masterPixels: masterPixels,
                rectAspect: rectAspect
            )
        }

        return VStack(spacing: 10) {
            Text("\(family.label) • \(targetPixels.width)×\(targetPixels.height) px")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))

            HStack(spacing: 10) {
                Text("Straighten")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Slider(
                    value: $straightenDegrees,
                    in: -15...15,
                    step: 0.1,
                    onEditingChanged: { editing in
                        isStraightenEditing = editing
                    }
                )
                .disabled(isApplying)

                Text("\(straightenDegrees, specifier: "%+.1f")°")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 58, alignment: .trailing)

                Button {
                    guard !isApplying else { return }
                    straightenDegrees = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 4)
                .accessibilityLabel("Reset straighten")
            }

            HStack(spacing: 10) {
                Text("Nudge")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Picker("Step", selection: $nudgeStepPixels) {
                    Text("1 px").tag(1)
                    Text("5 px").tag(5)
                    Text("10 px").tag(10)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220).environment(\.colorScheme, .dark)

                Spacer(minLength: 8)

                Button {
                    zoom(deltaPixels: zoomStepPixels)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
                .disabled(isApplying)
                .accessibilityLabel("Zoom out")

                Button {
                    zoom(deltaPixels: -zoomStepPixels)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
                .disabled(isApplying)
                .accessibilityLabel("Zoom in")
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    nudgeButton(systemName: "arrow.up") {
                        nudge(dxPixels: 0, dyPixels: -nudgeStepPixels)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    nudgeButton(systemName: "arrow.left") {
                        nudge(dxPixels: -nudgeStepPixels, dyPixels: 0)
                    }

                    nudgeButton(systemName: "dot.scope") {
                        recenter()
                    }
                    .accessibilityLabel("Centre")

                    nudgeButton(systemName: "arrow.right") {
                        nudge(dxPixels: nudgeStepPixels, dyPixels: 0)
                    }
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    nudgeButton(systemName: "arrow.down") {
                        nudge(dxPixels: 0, dyPixels: nudgeStepPixels)
                    }
                    Spacer(minLength: 0)
                }
            }

            Text("Drag to move. Pinch to zoom. Double-tap to zoom. Press and hold, then drag for fine moves.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func nudgeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 34)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.85))
        .disabled(isApplying)
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
