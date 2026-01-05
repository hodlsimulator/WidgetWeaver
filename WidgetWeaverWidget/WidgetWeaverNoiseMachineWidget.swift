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
        .supportedFamilies([.systemSmall, .systemMedium])
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

    init(entry: WidgetWeaverNoiseMachineWidget.Entry) {
        self.entry = entry
        _renderedState = State(initialValue: entry.state.sanitised())
    }

    private var displayState: NoiseMixState {
        var s = renderedState
        if let optimisticWasPlaying {
            s.wasPlaying = optimisticWasPlaying
        }
        return s
    }

    private func refreshFromStore() {
        renderedState = NoiseMixStore.shared.loadLastMix().sanitised()
    }

    private func scheduleOptimisticReconcile(desiredWasPlaying: Bool, token: UInt64) {
        Task { @MainActor in
            // Poll with backoff so the first tap after a cold start can still feel instant, even if
            // the App Intent takes a few seconds to start and persist the new state.
            let delays: [UInt64] = [
                150_000_000,
                300_000_000,
                600_000_000,
                1_000_000_000,
                1_600_000_000,
                2_400_000_000,
                3_200_000_000,
            ]

            for ns in delays {
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
        VStack(alignment: .leading, spacing: 12) {
            header
            layers(slots: slots)
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
        }
    }

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
        }
    }

    @ViewBuilder
    private func layers(slots: [NoiseSlotState]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                let slot = slots.indices.contains(idx) ? slots[idx] : .default
                layerButton(index: idx, isEnabled: slot.enabled)
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
        } else {
            Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                Text("\(index + 1)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
        }
    }
}
