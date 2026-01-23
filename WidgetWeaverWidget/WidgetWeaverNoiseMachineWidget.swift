//
//  WidgetWeaverNoiseMachineWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 01/02/26.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct WidgetWeaverNoiseMachineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWeaverWidgetKinds.noiseMachine, provider: Provider()) { entry in
            NoiseMachineWidgetView(entry: entry)
        }
        .configurationDisplayName("Noise Machine")
        .description("Control the Noise Machine without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var state: NoiseMixState
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: Date(), state: .default)
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date(), state: NoiseMixStore.shared.loadLastMix()))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let entry = Entry(date: Date(), state: NoiseMixStore.shared.loadLastMix())
            completion(Timeline(entries: [entry], policy: .never))
        }
    }
}

@MainActor
private final class NoiseMachineWidgetLiveState: ObservableObject {
    @Published var tick: UInt64 = 0
    private var token: DarwinNotificationToken?

    init() {
        token = DarwinNotificationToken(name: AppGroupDarwinNotifications.noiseMachineStateDidChange) { [weak self] in
            guard let self else { return }
            self.tick &+= 1
        }
    }
}

private struct NoiseMachineWidgetView: View {
    let entry: WidgetWeaverNoiseMachineWidget.Entry

    @Environment(\.widgetFamily) private var family
    @StateObject private var liveState = NoiseMachineWidgetLiveState()

    /// Keep a lightweight, in-memory copy of the last-known state.
    ///
    /// Reading and decoding the App Group blob during every render can make the first interaction
    /// after a cold start feel unresponsive.
    @State private var renderedState: NoiseMixState

    /// WidgetKit timeline reloads (and cross-process notifications) are not guaranteed to update
    /// immediately. This provides an optimistic UI flip so the play/pause button and status text
    /// change instantly on tap, then reconcile back to the persisted App Group state.
    @State private var optimisticWasPlaying: Bool? = nil
    @State private var optimisticToken: UInt64 = 0

    @State private var optimisticResumeOnLaunchEnabled: Bool? = nil
    @State private var optimisticResumeToken: UInt64 = 0

    @State private var resumeOnLaunchEnabled: Bool

    init(entry: WidgetWeaverNoiseMachineWidget.Entry) {
        self.entry = entry
        _renderedState = State(initialValue: entry.state.sanitised())
        _resumeOnLaunchEnabled = State(initialValue: NoiseMixStore.shared.isResumeOnLaunchEnabled())
    }

    private var displayState: NoiseMixState {
        var s = renderedState
        if let optimisticWasPlaying {
            s.wasPlaying = optimisticWasPlaying
        }
        return s
    }

    private var displayResumeOnLaunchEnabled: Bool {
        optimisticResumeOnLaunchEnabled ?? resumeOnLaunchEnabled
    }

    private func refreshFromStore() {
        renderedState = NoiseMixStore.shared.loadLastMix().sanitised()
        resumeOnLaunchEnabled = NoiseMixStore.shared.isResumeOnLaunchEnabled()
    }

    private static let optimisticReconcileDelays: [UInt64] = [
        150_000_000,
        300_000_000,
        600_000_000,
        1_000_000_000,
        1_600_000_000,
        2_400_000_000,
        3_200_000_000
    ]

    private func scheduleOptimisticReconcile(desiredWasPlaying: Bool, token: UInt64) {
        Task { @MainActor in
            // Poll with backoff so the first tap after a cold start can still feel instant, even if
            // the App Intent takes a few seconds to start and persist the new state.

            for ns in Self.optimisticReconcileDelays {
                try? await Task.sleep(nanoseconds: ns)
                if optimisticToken != token { return }

                refreshFromStore()

                if renderedState.wasPlaying == desiredWasPlaying {
                    optimisticWasPlaying = nil
                    return
                }
            }

            if optimisticToken == token {
                optimisticWasPlaying = nil
                refreshFromStore()
            }
        }
    }

    private func setOptimisticWasPlaying(_ playing: Bool) {
        optimisticToken &+= 1
        let token = optimisticToken

        optimisticWasPlaying = playing

        // Update the local snapshot immediately so a redraw doesn't need to hit UserDefaults.
        renderedState.wasPlaying = playing
        renderedState.updatedAt = Date()

        scheduleOptimisticReconcile(desiredWasPlaying: playing, token: token)
    }

    private func scheduleResumeOptimisticReconcile(desiredEnabled: Bool, token: UInt64) {
        Task { @MainActor in
            for ns in Self.optimisticReconcileDelays {
                try? await Task.sleep(nanoseconds: ns)
                if optimisticResumeToken != token { return }

                refreshFromStore()

                if resumeOnLaunchEnabled == desiredEnabled {
                    optimisticResumeOnLaunchEnabled = nil
                    return
                }
            }

            if optimisticResumeToken == token {
                optimisticResumeOnLaunchEnabled = nil
                refreshFromStore()
            }
        }
    }

    private func setOptimisticResumeOnLaunchEnabled(_ enabled: Bool) {
        optimisticResumeToken &+= 1
        let token = optimisticResumeToken

        optimisticResumeOnLaunchEnabled = enabled
        resumeOnLaunchEnabled = enabled

        scheduleResumeOptimisticReconcile(desiredEnabled: enabled, token: token)
    }

    private var slots: [NoiseSlotState] {
        let s = displayState

        if s.slots.count == NoiseMixState.slotCount {
            return s.slots
        }

        return (0..<NoiseMixState.slotCount).map { idx in
            s.slots.indices.contains(idx) ? s.slots[idx] : .default
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                largeLayout(slots: slots)
            default:
                compactLayout(slots: slots)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
        .widgetURL(URL(string: "widgetweaver://noisemachine")!)
        .task {
            refreshFromStore()
        }
        .onChange(of: liveState.tick) { _, _ in
            // A confirmed cross-process update should win over optimistic UI.
            refreshFromStore()
            optimisticWasPlaying = nil
            optimisticResumeOnLaunchEnabled = nil
        }
    }

    // MARK: - Layouts

    private func compactLayout(slots: [NoiseSlotState]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            layerRow(slots: slots)
        }
    }

    private func largeLayout(slots: [NoiseSlotState]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            masterVolumeRow
            layerGrid(slots: slots)
            footer
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        let isPlaying = displayState.wasPlaying

        return HStack(spacing: 10) {
            if isPlaying {
                Button(intent: PauseNoiseIntent()) {
                    Image(systemName: "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Pause noise machine")
                .simultaneousGesture(TapGesture().onEnded {
                    setOptimisticWasPlaying(false)
                })
            } else {
                Button(intent: PlayNoiseIntent()) {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Play noise machine")
                .simultaneousGesture(TapGesture().onEnded {
                    setOptimisticWasPlaying(true)
                })
            }

            Button(intent: StopNoiseIntent()) {
                Image(systemName: "stop.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop noise machine")
            .simultaneousGesture(TapGesture().onEnded {
                setOptimisticWasPlaying(false)
            })

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Noise")
                    .font(.headline)
                Text(isPlaying ? "Playing" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleResumeOnLaunchIntent()) {
                Text(displayResumeOnLaunchEnabled ? "Resume: On" : "Resume: Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Resume on launch")
            .accessibilityValue(displayResumeOnLaunchEnabled ? "On" : "Off")
            .simultaneousGesture(TapGesture().onEnded {
                setOptimisticResumeOnLaunchEnabled(!displayResumeOnLaunchEnabled)
            })

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("Updated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayState.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Volume

    private var masterVolumeRow: some View {
        let pct = percentageString(displayState.masterVolume)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Master")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(pct)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(clamped01(displayState.masterVolume)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Master volume")
        .accessibilityValue(pct)
    }

    // MARK: - Layers

    @ViewBuilder
    private func layerRow(slots: [NoiseSlotState]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                let slot = slots.indices.contains(idx) ? slots[idx] : .default
                layerButton(index: idx, isEnabled: slot.enabled)
            }
        }
    }

    private func layerGrid(slots: [NoiseSlotState]) -> some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                let slot = slots.indices.contains(idx) ? slots[idx] : .default
                layerTile(index: idx, slot: slot)
            }
        }
    }

    @ViewBuilder
    private func layerButton(index: Int, isEnabled: Bool) -> some View {
        if isEnabled {
            Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                Text("\(index + 1)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Layer \(index + 1)")
            .accessibilityValue("On")
        } else {
            Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                Text("\(index + 1)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Layer \(index + 1)")
            .accessibilityValue("Off")
        }
    }

    private func layerTile(index: Int, slot: NoiseSlotState) -> some View {
        let isEnabled = slot.enabled
        let pct = percentageString(slot.volume)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            if isEnabled {
                Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                    HStack(spacing: 8) {
                        Text("Layer \(index + 1)")
                            .font(.caption.weight(.semibold))

                        Spacer(minLength: 0)

                        Text("On")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Layer \(index + 1)")
                .accessibilityValue("On")
            } else {
                Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                    HStack(spacing: 8) {
                        Text("Layer \(index + 1)")
                            .font(.caption.weight(.semibold))

                        Spacer(minLength: 0)

                        Text("Off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Layer \(index + 1)")
                .accessibilityValue("Off")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Volume")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(pct)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(clamped01(slot.volume)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Layer \(index + 1) volume")
            .accessibilityValue(pct)
        }
        .padding(10)
        .background(.quaternary, in: shape)
    }

    // MARK: - Formatting

    private func clamped01(_ v: Float) -> Float {
        min(1, max(0, v))
    }

    private func percentageString(_ v: Float) -> String {
        let pct = Int((clamped01(v) * 100).rounded())
        return "\(pct)%"
    }
}
