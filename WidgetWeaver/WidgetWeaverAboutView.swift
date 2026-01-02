//
//  WidgetWeaverAboutView.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

//
//  WidgetWeaverAboutView.swift
//  WidgetWeaver
//
//  Created by Conor Nolan on 29/12/2024.
//

import SwiftUI
import WidgetKit

struct WidgetWeaverAboutView: View {
    @Environment(\.openURL) private var openURL
    
    @ObservedObject var proManager: WidgetWeaverProManager
    
    var forceUseWeatherMockData: Bool
    var resetAllWidgetWeaverData: (() -> Void)?
    var notificationAccessAction: (() -> Void)?
    var notificationDiagnosticsAction: (() -> Void)?
    var requestProAction: (() -> Void)?
    
    private var isProEnabled: Bool { proManager.isProEnabled }
    
    var body: some View {
        aboutList
            .background(Color(uiColor: .systemBackground))
            .task {
                WidgetWeaverWidgetRefresh.kickWidgetCacheWarmUp()
            }
            .task {
                let widgetCenter = WidgetCenter.shared
                let currentConfigs = await widgetCenter.currentConfigurations()
                let currentKinds = Set(currentConfigs.map(\.kind))
                
                WidgetWeaverWidgetDebug.configuredKinds = currentKinds
            }
            .navigationTitle("Explore")
    }
    
    var aboutList: some View {
        List {
            aboutHeaderSection
            
            featuredWeatherSection
            featuredLiveIndicatorSection
            featuredStepsSection
            featuredNextUpSection
            featuredVariableSection
            featuredVariableLocationSection
            featuredDynamicTypeSection
            featuredCountdownSection
            featuredGridSection
            featuredLargeTitleSection
            featuredStyledTextSection
            featuredSymbolsSection
            featuredButtonsSection
            
            capabilitiesSection
            interactiveButtonsSection
            noiseMachineSection
            variablesSection
            aiSection
            privacySection
            
            sharingSection
            proSection
            diagnosticsSection
            supportSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Sharing

extension WidgetWeaverAboutView {
    
    var sharingSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .blue) {
                WidgetWeaverAboutCardTitle(
                    "Share as a Widget",
                    systemImage: "square.and.arrow.up"
                )
                
                Text("Share your widget designs with others. They can load them into WidgetWeaver instantly.")
                    .foregroundStyle(.secondary)
                
                WidgetWeaverAboutBulletList {
                    WidgetWeaverAboutBullet(
                        "Use the Share button in the editor"
                    )
                    
                    WidgetWeaverAboutBullet(
                        "Generates a compact WidgetWeaver URL"
                    )
                    
                    WidgetWeaverAboutBullet(
                        "Recipients can import with one tap"
                    )
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Sharing", systemImage: "square.and.arrow.up", accent: .blue)
        } footer: {
            Text("Shared widgets can include most styling and data features, and can optionally include interactive elements depending on the widget type.")
        }
    }
}

// MARK: - Pro

extension WidgetWeaverAboutView {
    
    var proSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .indigo) {
                WidgetWeaverAboutCardTitle(
                    "WidgetWeaver Pro",
                    systemImage: "sparkles"
                )
                
                Text("Unlock additional templates, design tools, and faster iteration workflows.")
                    .foregroundStyle(.secondary)
                
                WidgetWeaverAboutBulletList {
                    WidgetWeaverAboutBullet(
                        "Extra widget templates"
                    )
                    
                    WidgetWeaverAboutBullet(
                        "Premium styling options"
                    )
                    
                    WidgetWeaverAboutBullet(
                        "More design flexibility"
                    )
                }
                
                if isProEnabled {
                    WidgetWeaverAboutBadgeRow(
                        title: "Pro enabled",
                        systemImage: "checkmark.seal.fill",
                        accent: .green
                    )
                    .padding(.top, 8)
                } else {
                    Button {
                        requestProAction?()
                    } label: {
                        Label("Upgrade to Pro", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Pro", systemImage: "sparkles", accent: .indigo)
        } footer: {
            Text("Pro features are optional. The free version is fully usable for building and running widgets.")
        }
    }
}

// MARK: - Diagnostics

extension WidgetWeaverAboutView {
    
    var diagnosticsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                WidgetWeaverAboutCardTitle(
                    "Diagnostics",
                    systemImage: "stethoscope"
                )
                
                Text("Tools for checking widget refresh behaviour, notification access, and debugging templates.")
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 10) {
                    if let notificationAccessAction {
                        Button {
                            notificationAccessAction()
                        } label: {
                            Label("Check Notification Access", systemImage: "bell.badge")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let notificationDiagnosticsAction {
                        Button {
                            notificationDiagnosticsAction()
                        } label: {
                            Label("Notification Diagnostics", systemImage: "ladybug")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let resetAllWidgetWeaverData {
                        Button(role: .destructive) {
                            resetAllWidgetWeaverData()
                        } label: {
                            Label("Reset All WidgetWeaver Data", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 10)
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Diagnostics", systemImage: "stethoscope", accent: .orange)
        } footer: {
            Text("Resetting data deletes local designs and cached assets. Widgets may take a moment to repopulate afterwards.")
        }
    }
}
