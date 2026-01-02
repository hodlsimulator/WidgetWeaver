//
//  WidgetWeaverAboutView+NoiseMachineSection.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import SwiftUI

extension WidgetWeaverAboutView {
    
    var noiseMachineSection: some View {
        Section {
            NavigationLink {
                NoiseMachineView()
            } label: {
                WidgetWeaverAboutCard(accent: .purple) {
                    WidgetWeaverAboutCardTitle(
                        "Noise Machine",
                        systemImage: "waveform"
                    )
                    
                    Text("A Sleep Machine-style procedural noise mixer with 4 layers and a controller widget.")
                        .foregroundStyle(.secondary)
                    
                    WidgetWeaverAboutBulletList {
                        WidgetWeaverAboutBullet("4 simultaneous noise layers (white → pink → brown)")
                        WidgetWeaverAboutBullet("Per-layer low/high cut + 3‑band EQ")
                        WidgetWeaverAboutBullet("Instant resume after force-quit (optional)")
                        WidgetWeaverAboutBullet("Home Screen widget controls play/pause + toggles")
                    }
                }
            }
            .buttonStyle(.plain)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Audio", systemImage: "speaker.wave.2.fill", accent: .purple)
        } footer: {
            Text("Add the Noise Machine widget from the Home Screen widget gallery to control playback without opening the app.")
        }
    }
}
