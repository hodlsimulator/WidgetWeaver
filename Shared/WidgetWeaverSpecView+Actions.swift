//
//  WidgetWeaverSpecView+Actions.swift
//  WidgetWeaver
//
//  Created by . . on 1/16/26.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import AppIntents

extension WidgetWeaverSpecView {
    // MARK: - Quick Actions (interactive widget buttons)

    func actionBarIfNeeded(spec: WidgetSpec, accent: Color) -> some View {
        Group {
            if WidgetWeaverEntitlements.isProUnlocked,
               let bar = spec.actionBar,
               !bar.actions.isEmpty {
                actionBar(bar: bar, accent: accent)
                    .allowsHitTesting(context == .widget)
                    .opacity(context == .widget ? 1.0 : 0.85)
            }
        }
    }

    private func actionBar(bar: WidgetActionBarSpec, accent: Color) -> some View {
        HStack(spacing: 10) {
            ForEach(bar.actions) { action in
                widgetActionButton(action: action, barStyle: bar.style, accent: accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func widgetActionButton(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        switch action.kind {
        case .incrementVariable:
            Button(intent: WidgetWeaverIncrementVariableIntent(key: action.variableKey, amount: action.incrementAmount)) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)

        case .setVariableToNow:
            Button(intent: WidgetWeaverSetVariableToNowIntent(key: action.variableKey, format: mapNowFormat(action.nowFormat))) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func mapNowFormat(_ token: WidgetNowFormatToken) -> WidgetWeaverNowValueFormat {
        switch token {
        case .iso8601:
            return .iso8601
        case .unixSeconds:
            return .unixSeconds
        case .unixMilliseconds:
            return .unixMilliseconds
        case .dateOnly:
            return .dateOnly
        case .timeOnly:
            return .timeOnly
        }
    }

    private func actionButtonLabel(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let backgroundOpacity: Double = (barStyle == .prominent) ? 0.20 : 0.12
        let borderOpacity: Double = (barStyle == .prominent) ? 0.30 : 0.16
        let minHeight: CGFloat = 44

        return HStack(spacing: 8) {
            if let systemImage = action.systemImage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !systemImage.isEmpty {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(action.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 12)
        .background { shape.fill(accent.opacity(backgroundOpacity)) }
        .overlay { shape.strokeBorder(accent.opacity(borderOpacity), lineWidth: 1) }
        .contentShape(shape)
    }

}
