//
//  WidgetWeaverDeepLinkHost.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI

enum WidgetWeaverDeepLink: String, Identifiable {
    case noiseMachine

    var id: String { rawValue }

    static func from(url: URL) -> WidgetWeaverDeepLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "widgetweaver" else { return nil }

        let host = (url.host ?? "").lowercased()
        switch host {
        case "noisemachine", "noise", "noise-machine":
            return .noiseMachine
        default:
            return nil
        }
    }
}

struct WidgetWeaverDeepLinkHost<Content: View>: View {
    private let content: Content

    @State private var activeDeepLink: WidgetWeaverDeepLink?
    @StateObject private var noiseMachinePresentationTracker = NoiseMachinePresentationTracker()

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.noiseMachinePresentationTracker, noiseMachinePresentationTracker)
            .onOpenURL { url in
                guard let link = WidgetWeaverDeepLink.from(url: url) else { return }

                switch link {
                case .noiseMachine:
                    if noiseMachinePresentationTracker.isVisible {
                        return
                    }
                }

                activeDeepLink = link
            }
            .sheet(item: $activeDeepLink) { link in
                switch link {
                case .noiseMachine:
                    NavigationStack {
                        NoiseMachineView()
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close") {
                                        activeDeepLink = nil
                                    }
                                }
                            }
                    }
                }
            }
    }
}
