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

    private var state: NoiseMixState {
        // Force `body` to depend on the Darwin notification tick. When a tap triggers an App Intent
        // in a different process (app/intents), the widget cannot rely on `@AppStorage` change
        // propagation, so this is a cheap cross-process "poke" to re-read the App Group value.
        _ = liveState.tick

        let loaded = NoiseMixStore.shared.loadLastMix().sanitised()

        // If the App Group value is unavailable (first render / race), fall back to the timeline entry.
        if loaded == .default, entry.state != .default {
            return entry.state.sanitised()
        }

        return loaded
    }

    private var slots: [NoiseSlotState] {
        let s = state
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

        // Intentionally no .widgetURL here.
        // With interactive controls, widgetURL can sometimes steal taps and make buttons feel flaky.
    }

    private var header: some View {
        HStack(spacing: 10) {
            if state.wasPlaying {
                Button(intent: PauseNoiseIntent()) {
                    Image(systemName: "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(intent: PlayNoiseIntent()) {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(intent: StopNoiseIntent()) {
                Image(systemName: "stop.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Noise")
                    .font(.headline)
                Text(state.wasPlaying ? "Playing" : "Paused")
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
