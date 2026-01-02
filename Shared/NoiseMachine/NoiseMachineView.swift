//
//  NoiseMachineView.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import SwiftUI

struct NoiseMachineView: View {
    @StateObject private var model = NoiseMachineViewModel()
    @StateObject private var logModel = NoiseMachineDebugLogModel()
    @State private var expandedEQ: Set<Int> = []

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
            logModel.start()
            model.onAppear()
        }
        .onDisappear {
            logModel.stop()
        }
    }

    private var masterSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    model.togglePlayPause()
                } label: {
                    Label(model.state.wasPlaying ? "Pause" : "Play", systemImage: model.state.wasPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            WWFloatSliderRow(
                title: "Master volume",
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

            diagnosticsSection
        } header: {
            Text("Master")
        } footer: {
            Text("If enabled, playback resumes automatically after a force-quit and relaunch.")
        }
    }

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
                    model.resetToDefaults()
                } label: {
                    Label("Reset mix", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

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

    private func slotSection(index: Int) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.state.slots[index].enabled },
                set: { model.setSlotEnabled(index, enabled: $0) }
            )) {
                Text("Enabled")
            }

            WWFloatSliderRow(
                title: "Volume",
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
                        value: Binding(
                            get: { model.state.slots[index].eq.lowGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, low: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing {
                                model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true)
                            }
                        }
                    )

                    WWFloatSliderRow(
                        title: "Mid",
                        value: Binding(
                            get: { model.state.slots[index].eq.midGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, mid: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing {
                                model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true)
                            }
                        }
                    )

                    WWFloatSliderRow(
                        title: "High",
                        value: Binding(
                            get: { model.state.slots[index].eq.highGainDB },
                            set: { model.setSlotEQ(index, eq: updatedEQ(index: index, high: $0), commit: false) }
                        ),
                        range: -12...12,
                        valueText: { dbString($0) },
                        onEditingChanged: { editing in
                            if !editing {
                                model.setSlotEQ(index, eq: model.state.slots[index].eq, commit: true)
                            }
                        }
                    )
                }
                .padding(.vertical, 4)
            } label: {
                Text("EQ")
            }
        } header: {
            Text("Layer \(index + 1)")
        } footer: {
            Text("Colour blends white → pink → brown. Sliders are smoothed to avoid zipper noise.")
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
        if hz >= 1000 {
            return String(format: "%.1f kHz", Double(hz / 1000))
        }
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
        }
        .padding(.vertical, 4)
    }
}

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
