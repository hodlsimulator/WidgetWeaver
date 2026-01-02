//
//  WidgetWeaverNoiseMachineWidget.swift
//  WidgetWeaverWidgetExtension
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI
import WidgetKit

struct NoiseMachineEntry: TimelineEntry {
    let date: Date
    let state: NoiseMixState
}

struct NoiseMachineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoiseMachineEntry {
        NoiseMachineEntry(date: Date(), state: .default())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NoiseMachineEntry) -> Void) {
        let state = NoiseMixStore.shared.loadLastMix()
        completion(NoiseMachineEntry(date: Date(), state: state))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NoiseMachineEntry>) -> Void) {
        let state = NoiseMixStore.shared.loadLastMix()
        let entry = NoiseMachineEntry(date: Date(), state: state)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct WidgetWeaverNoiseMachineWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.noiseMachine
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoiseMachineProvider()) { entry in
            NoiseMachineWidgetView(state: entry.state)
        }
        .configurationDisplayName("Noise Machine")
        .description("Play/pause and toggle Noise Machine layers.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NoiseMachineWidgetView: View {
    let state: NoiseMixState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Noise Machine")
                        .font(.headline)
                    Text(state.wasPlaying ? "Playing" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(intent: TogglePlayPauseIntent()) {
                    Image(systemName: state.wasPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<NoiseMixState.slotCount, id: \.self) { idx in
                    HStack {
                        Text("L\(idx + 1)")
                            .font(.caption)
                            .frame(width: 22, alignment: .leading)
                        
                        Spacer()
                        
                        let enabled = state.slots.indices.contains(idx) ? state.slots[idx].enabled : false
                        Button(intent: ToggleSlotIntent(layerIndex: idx + 1)) {
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .opacity(state.wasPlaying ? 1.0 : 0.85)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            HStack {
                Button(intent: StopNoiseIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
    }
}
