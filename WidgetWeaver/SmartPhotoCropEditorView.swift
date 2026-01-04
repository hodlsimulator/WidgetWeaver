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
    let onApply: (NormalisedRect) async -> Void

    @State private var masterImage: UIImage?
    @State private var cropRect: NormalisedRect
    @State private var isApplying: Bool = false
    @State private var loadErrorMessage: String = ""

    @State private var dragStartRect: NormalisedRect?
    @State private var pinchStartRect: NormalisedRect?

    @Environment(\.dismiss) private var dismiss

    init(
        family: EditingFamily,
        masterFileName: String,
        targetPixels: PixelSize,
        initialCropRect: NormalisedRect,
        onApply: @escaping (NormalisedRect) async -> Void
    ) {
        self.family = family
        self.masterFileName = masterFileName
        self.targetPixels = targetPixels.normalised()
        self.initialCropRect = initialCropRect.normalised()
        self.onApply = onApply

        _cropRect = State(initialValue: initialCropRect.normalised())
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
        .navigationTitle("Fix framing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isApplying)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") { applyAndDismissIfPossible() }
                    .disabled(isApplying || masterImage == nil)
            }

            ToolbarItem(placement: .bottomBar) {
                Button("Reset") { cropRect = initialCropRect.normalised() }
                    .disabled(isApplying || masterImage == nil)
            }
        }
        .task {
            if masterImage != nil || !loadErrorMessage.isEmpty { return }
            loadMasterImage()
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
            await onApply(rectToApply)
            await MainActor.run {
                isApplying = false
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func cropCanvas(masterImage: UIImage) -> some View {
        GeometryReader { geo in
            let masterPixelSize = pixelSize(of: masterImage)
            let masterAspect = safeAspect(width: masterPixelSize.width, height: masterPixelSize.height)

            let targetAspect = safeAspect(width: targetPixels.width, height: targetPixels.height)
            let normalisedRectAspect = targetAspect / masterAspect

            let displayRect = aspectFitRect(container: geo.size, imageAspect: masterAspect)

            let cropFrame = CGRect(
                x: displayRect.minX + CGFloat(cropRect.x) * displayRect.width,
                y: displayRect.minY + CGFloat(cropRect.y) * displayRect.height,
                width: CGFloat(cropRect.width) * displayRect.width,
                height: CGFloat(cropRect.height) * displayRect.height
            )

            ZStack {
                Image(uiImage: masterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                Path { p in
                    p.addRect(displayRect)
                    p.addRect(cropFrame)
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .shadow(radius: 1.5)

                Rectangle()
                    .fill(.clear)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isApplying else { return }
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

                                cropRect = clampRect(proposed, rectAspect: normalisedRectAspect)
                            }
                            .onEnded { _ in
                                dragStartRect = nil
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard !isApplying else { return }
                                if pinchStartRect == nil { pinchStartRect = cropRect }
                                guard let start = pinchStartRect else { return }

                                let scale = max(0.2, min(5.0, Double(value)))
                                let proposedWidth = start.width / scale

                                let centerX = start.x + (start.width / 2.0)
                                let centerY = start.y + (start.height / 2.0)

                                let w = clampWidth(proposedWidth, rectAspect: normalisedRectAspect)
                                let h = w / max(0.0001, normalisedRectAspect)

                                let proposed = NormalisedRect(
                                    x: centerX - (w / 2.0),
                                    y: centerY - (h / 2.0),
                                    width: w,
                                    height: h
                                )

                                cropRect = clampRect(proposed, rectAspect: normalisedRectAspect)
                            }
                            .onEnded { _ in
                                pinchStartRect = nil
                            }
                    )

                VStack(spacing: 8) {
                    Text("\(family.label) • \(targetPixels.width)×\(targetPixels.height) px")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))

                    Text("Drag to move. Pinch to zoom.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
            }
        }
    }

    private func pixelSize(of image: UIImage) -> PixelSize {
        if let cg = image.cgImage {
            return PixelSize(width: cg.width, height: cg.height).normalised()
        }

        let w = Int((image.size.width * image.scale).rounded())
        let h = Int((image.size.height * image.scale).rounded())
        return PixelSize(width: max(1, w), height: max(1, h)).normalised()
    }

    private func safeAspect(width: Int, height: Int) -> Double {
        let w = max(1, width)
        let h = max(1, height)
        return Double(w) / Double(h)
    }

    private func aspectFitRect(container: CGSize, imageAspect: Double) -> CGRect {
        let cw = max(1.0, container.width)
        let ch = max(1.0, container.height)
        let containerAspect = Double(cw / ch)

        let w: CGFloat
        let h: CGFloat

        if containerAspect > imageAspect {
            h = ch
            w = CGFloat(Double(ch) * imageAspect)
        } else {
            w = cw
            h = CGFloat(Double(cw) / imageAspect)
        }

        let x = (cw - w) / 2.0
        let y = (ch - h) / 2.0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func clampWidth(_ proposedWidth: Double, rectAspect: Double) -> Double {
        let a = max(0.0001, rectAspect)
        let maxWidth = min(1.0, a)
        let minWidth = min(maxWidth, 0.08)

        return min(maxWidth, max(minWidth, proposedWidth))
    }

    private func clampRect(_ rect: NormalisedRect, rectAspect: Double) -> NormalisedRect {
        let a = max(0.0001, rectAspect)

        let w = clampWidth(rect.width, rectAspect: a)
        let h = w / a

        var x = rect.x
        var y = rect.y

        x = min(max(0.0, x), 1.0 - w)
        y = min(max(0.0, y), 1.0 - h)

        return NormalisedRect(x: x, y: y, width: w, height: h).normalised()
    }
}
