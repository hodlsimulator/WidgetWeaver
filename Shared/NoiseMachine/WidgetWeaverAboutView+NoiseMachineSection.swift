//
//  WidgetWeaverAboutView+NoiseMachineSection.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import SwiftUI

#if !APP_EXTENSION

extension WidgetWeaverAboutView {
    var noiseMachineSection: some View {
        Section {
            NavigationLink {
                NoiseMachineView()
            } label: {
                WidgetWeaverAboutCard(accent: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Noise Machine")
                                    .font(.headline)

                                Text("4-layer procedural noise mixer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Label("Open", systemImage: "waveform")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text("Mix white/pink/brown noise layers with per-layer filters + EQ. Playback state is shared with an interactive widget.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        WidgetWeaverAboutBulletList(items: [
                            "4 simultaneous layers, each with volume + colour.",
                            "Low cut / high cut per layer.",
                            "Simple 3-band EQ per layer.",
                            "Instant resume on relaunch (optional).",
                            "Home Screen widget controls play/pause, stop, layer toggles, and resume-on-launch."
                        ])
                    }
                }
            }
            .buttonStyle(.plain)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Audio", systemImage: "speaker.wave.2.fill", accent: .purple)
        } footer: {
            Text("Add the Noise Machine widget from the Home Screen widget gallery to control playback without opening the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#endif
