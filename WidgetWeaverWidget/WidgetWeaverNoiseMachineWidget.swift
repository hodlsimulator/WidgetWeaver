//
//  WidgetWeaverNoiseMachineWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 01/02/26.
//

import Foundation
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

private struct NoiseMachineWidgetView: View {
    let entry: WidgetWeaverNoiseMachineWidget.Entry

    private var state: NoiseMixState {
        // Interactive widgets are often re-rendered without a fresh timeline entry.
        // Read the App Group-backed state at render time so the play/pause button reflects
        // changes immediately after a tap.
        NoiseMixStore.shared.loadLastMix()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 8) {
                layerButton(index: 0)
                layerButton(index: 1)
                layerButton(index: 2)
                layerButton(index: 3)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
        .widgetURL(URL(string: "widgetweaver://noiseMachine"))
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
    private func layerButton(index: Int) -> some View {
        let enabled = state.slots.indices.contains(index) ? state.slots[index].enabled : false

        if enabled {
            Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                Text("\\(index + 1)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(intent: ToggleSlotIntent(layerIndex: index + 1)) {
                Text("\\(index + 1)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
        }
    }
}
