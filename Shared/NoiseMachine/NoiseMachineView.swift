//
//  NoiseMachineView.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI

struct NoiseMachineView: View {
    @StateObject private var model = NoiseMachineViewModel()

    #if DEBUG
    @StateObject private var logModel = NoiseMachineDebugLogModel()
    #endif

    @State private var expandedEQ: Set<Int> = []

    @Environment(\.noiseMachinePresentationTracker) private var presentationTracker

    var body: some View {
        List {
            masterSection

            ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                slotSection(index: idx)
            }
        }
        .navigationTitle("Noise Machine")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            presentationTracker?.setVisible(true)
            #if DEBUG
            logModel.start()
            #endif
            model.onAppear()
        }
        .onDisappear {
            presentationTracker?.setVisible(false)
            #if DEBUG
            logModel.stop()
            #endif
            model.onDisappear()
        }
    }

    private var masterSection: some View {
        Section {
            Button {
                model.togglePlayPause()
            } label: {
                NoiseMachineActionButtonLabel(
                    title: model.state.wasPlaying ? "Pause" : "Play",
                    systemImage: model.state.wasPlaying ? "pause.fill" : "play.fill",
                    variant: .prominent
                )
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(model.state.wasPlaying ? "Pause noise" : "Play noise")
            .accessibilityHint("Toggles Noise Machine playback.")

            HStack(spacing: 12) {
                Button {
                    model.resetToDefaults()
                } label: {
                    NoiseMachineActionButtonLabel(
                        title: "Reset",
                        systemImage: "arrow.counterclockwise",
                        variant: .normal
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset to defaults")
                .accessibilityHint("Resets all layers, filters, and EQ to defaults.")

                Menu {
                    ForEach(NoiseMixPreset.allCases) { preset in
                        Button {
                            model.applyPreset(preset)
                        } label: {
                            Text(preset.title)
                        }
                    }
                } label: {
                    NoiseMachineActionButtonLabel(
                        title: "Presets",
                        systemImage: "sparkles",
                        variant: .normal
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Applies a built-in mix without changing the play/pause state.")
            }

            WWFloatSliderRow(
                title: "Master volume",
                accessibilityLabel: "Master volume",
                value: Binding(
                    get: { model.state.masterVolume },
                    set: { model.setMasterVolume($0, commit: false) }
                ),
                range: 0...1,
                valueText: { String(format: "%.0f%%", Double($0 * 100)) },
                onEditingChanged: { editing in
                    if !editing { model.setMasterVolume(model.state.masterVolume, commit: true) }
                }
            )

            Toggle(isOn: Binding(
                get: { model.resumeOnLaunch },
                set: { model.setResumeOnLaunch($0) }
            )) {
                Text("Resume on launch")
            }

            #if DEBUG
            diagnosticsSection
            #endif
        } header: {
            Text("Master")
        } footer: {
            Text("Reset sets all layers, filters, and EQ back to defaults. Playback stops; press Play to start again.")
        }
    }

    private enum NoiseMachineActionButtonVariant {
        case prominent
        case normal
    }

    private struct NoiseMachineActionButtonLabel: View {
        let title: String
        let systemImage: String
        let variant: NoiseMachineActionButtonVariant

        var body: some View {
            HStack(spacing: 10) {
                if variant == .prominent {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.tint)
                }

                if variant == .prominent {
                    Text(title)
                        .foregroundStyle(.white)
                } else {
                    Text(title)
                        .foregroundStyle(.tint)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
    }

    #if DEBUG
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.top, 4)

            Text("Diagnostics")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    model.refreshFromController()
                    Task { await model.refreshAudioStatus() }
                    logModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    model.dumpAudioStatus()
                } label: {
                    Label("Dump status", systemImage: "doc.plaintext")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    logModel.clear()
                } label: {
                    Label("Clear log", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                ShareLink(item: logModel.exportText) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button {
                    model.rebuildEngine()
                } label: {
                    Label("Rebuild engine", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
            }

            if !model.audioStatus.isEmpty {
                ScrollView {
                    Text(model.audioStatus)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            if !logModel.entries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(logModel.entries.suffix(80)) { entry in
                            Text(logModel.format(entry))
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.level == .error ? Color.red : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                Text("No log entries yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    #endif

    private func slotSection(index: Int) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.state.slots[index].enabled },
                set: { model.setSlotEnabled(index, enabled: $0) }
            )) {
                Text("Enabled")
            }
            .accessibilityLabel("Layer \(index + 1) enabled")

            WWFloatSliderRow(
                title: "Volume",
                accessibilityLabel: "Layer \(index + 1) volume",
                value: Binding(
                    get: { model.state.slots[index].volume },
                    set: { model.setSlotVolume(index, volume: $0, commit: false) }
                ),
                range: 0...1,
                valueText: { String(format: "%.0f%%", Double($0 * 100)) },
                onEditingChanged: { editing in
                    if !editing { model.setSlotVolume(index, volume: model.state.slots[index].volume, commit: true) }
                }
            )

            WWFloatSliderRow(
                title: "Colour",
                accessibilityLabel: "Layer \(index + 1) colour",
                value: Binding(
                    get: { model.state.slots[index].colour },
                    set: { model.setSlotColour(index, colour: $0, commit: false) }
                ),
                range: 0...2,
                valueText: { colourLabel($0) },
                onEditingChanged: { editing in
                    if !editing { model.setSlotColour(index, colour: model.state.slots[index].colour, commit: true) }
                }
            )

            WWFloatSliderRow(
                title: "Low cut",
                accessibilityLabel: "Layer \(index + 1) low cut",
                value: Binding(
                    get: { model.state.slots[index].lowCutHz },
                    set: { model.setSlotLowCut(index, hz: $0, commit: false) }
                ),
                range: 10...2000,
                valueText: { hzString($0) },
                onEditingChanged: { editing in
                    if !editing { model.setSlotLowCut(index, hz: model.state.slots[index].lowCutHz, commit: true) }
                }
            )

            WWFloatSliderRow(
                title: "High cut",
                accessibilityLabel: "Layer \(index + 1) high cut",
                value: Binding(
                    get: { model.state.slots[index].highCutHz },
                    set: { model.setSlotHighCut(index, hz: $0, commit: false) }
                ),
                range: 500...20000,
                valueText: { hzString($0) },
                onEditingChanged: { editing in
                    if !editing { model.setSlotHighCut(index, hz: model.state.slots[index].highCutHz, commit: true) }
                }
            )

            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedEQ.contains(index) },
                    set: { newValue in
                        if newValue {
                            expandedEQ.insert(index)
                        } else {
                            expandedEQ.remove(index)
                        }
                    }
                )
            ) {
                VStack(spacing: 12) {
                    WWFloatSliderRow(
                        title: "Low",
                        accessibilityLabel: "Layer \(index + 1) EQ low",
                        value: Binding(
                            get: { model.state.slots[index].eq.lowGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, low: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing { model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true) }
                        }
                    )

                    WWFloatSliderRow(
                        title: "Mid",
                        accessibilityLabel: "Layer \(index + 1) EQ mid",
                        value: Binding(
                            get: { model.state.slots[index].eq.midGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, mid: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing { model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true) }
                        }
                    )

                    WWFloatSliderRow(
                        title: "High",
                        accessibilityLabel: "Layer \(index + 1) EQ high",
                        value: Binding(
                            get: { model.state.slots[index].eq.highGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, high: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing { model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true) }
                        }
                    )
                }
                .padding(.vertical, 4)
            } label: {
                Text("EQ")
            }
            .accessibilityLabel("Layer \(index + 1) EQ")
            .accessibilityHint("Shows three band equaliser controls.")
        } header: {
            Text("Layer \(index + 1)")
        } footer: {
            Text("Colour blends white → pink → brown.")
        }
    }

    private func colourLabel(_ value: Float) -> String {
        if value < 0.25 { return "White" }
        if value < 0.75 { return "White → Pink" }
        if value < 1.25 { return "Pink" }
        if value < 1.75 { return "Pink → Brown" }
        return "Brown"
    }

    private func hzString(_ hz: Float) -> String {
        if hz >= 1000 { return String(format: "%.1f kHz", Double(hz / 1000)) }
        return String(format: "%.0f Hz", Double(hz))
    }

    private func dbString(_ db: Float) -> String {
        if abs(db) < 0.05 { return "0 dB" }
        return String(format: "%.1f dB", Double(db))
    }

    private func updatedEQ(index: Int, low: Float? = nil, mid: Float? = nil, high: Float? = nil) -> EQState {
        var eq = model.state.slots[index].eq
        if let low { eq.lowGainDB = low }
        if let mid { eq.midGainDB = mid }
        if let high { eq.highGainDB = high }
        return eq
    }
}

private struct WWFloatSliderRow: View {
    let title: String
    let accessibilityLabel: String
    let value: Binding<Float>
    let range: ClosedRange<Float>
    let valueText: (Float) -> String
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                Text(valueText(value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityValue(Text(valueText(value.wrappedValue)))
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
@MainActor
private final class NoiseMachineDebugLogModel: ObservableObject {
    @Published private(set) var entries: [NoiseMachineLogEntry] = []

    private var timer: Timer?

    var exportText: String {
        entries.map { format($0, includeOrigin: true) }.joined(separator: "\n")
    }

    func start() {
        refresh()
        timer?.invalidate()

        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        entries = NoiseMachineDebugLogStore.shared.load()
    }

    func clear() {
        NoiseMachineDebugLogStore.shared.clear()
        entries = []
    }

    func format(_ entry: NoiseMachineLogEntry, includeOrigin: Bool = false) -> String {
        let date = ISO8601DateFormatter().string(from: entry.timestamp)
        if includeOrigin {
            return "\(date) [\(entry.level.rawValue.uppercased())] [\(entry.origin)] \(entry.message)"
        }
        return "\(date) [\(entry.level.rawValue.uppercased())] \(entry.message)"
    }
}
#endif

final class NoiseMachinePresentationTracker: ObservableObject {
    @Published private(set) var isVisible: Bool = false

    func setVisible(_ visible: Bool) {
        if isVisible != visible {
            isVisible = visible
        }
    }
}

private struct NoiseMachinePresentationTrackerKey: EnvironmentKey {
    static var defaultValue: NoiseMachinePresentationTracker? { nil }
}

extension EnvironmentValues {
    var noiseMachinePresentationTracker: NoiseMachinePresentationTracker? {
        get { self[NoiseMachinePresentationTrackerKey.self] }
        set { self[NoiseMachinePresentationTrackerKey.self] = newValue }
    }
}
