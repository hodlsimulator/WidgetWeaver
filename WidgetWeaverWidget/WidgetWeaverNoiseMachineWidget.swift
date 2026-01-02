//
//  WidgetWeaverNoiseMachineWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 01/02/26.
//

import WidgetKit
import SwiftUI

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
            Entry(date: Date(), state: NoiseMixState.default)
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let state = NoiseMixStore.shared.loadLastMix()
            completion(Entry(date: Date(), state: state))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let state = NoiseMixStore.shared.loadLastMix()
            let entry = Entry(date: Date(), state: state)
            completion(Timeline(entries: [entry], policy: .never))
        }
    }
}

private struct NoiseMachineWidgetView: View {
    let entry: WidgetWeaverNoiseMachineWidget.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(intent: TogglePlayPauseIntent()) {
                    Label(entry.state.wasPlaying ? "Pause" : "Play",
                          systemImage: entry.state.wasPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)

                Button(intent: StopNoiseIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Noise")
                        .font(.headline)
                    Text(entry.state.wasPlaying ? "Playing" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                    let enabled = entry.state.slots[idx].enabled
                    Button(intent: ToggleSlotIntent(layerIndex: idx + 1)) {
                        Text("\(idx + 1)")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(enabled ? .borderedProminent : .bordered)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
    }
}
