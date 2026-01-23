//
//  WidgetWeaverRemindersTemplateView+Placeholder.swift
//  WidgetWeaver
//
//  Created by . . on 1/23/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverRemindersTemplateView {
    func remindersPlaceholder() -> some View {
        let titles: [String] = [
            "Buy milk",
            "Reply to email",
            "Book dentist",
        ]

        let guidance: String = {
            if context == .widget {
                return "Tap the widget to open Reminders settings."
            }
            return "Open WidgetWeaver to enable Reminders access and refresh."
        }()

        let maxRows: Int = {
            switch family {
            case .systemSmall:
                return 1
            case .systemMedium:
                return 2
            case .systemLarge:
                return 3
            case .systemExtraLarge:
                return 4
            case .accessoryRectangular:
                return 1
            default:
                return 2
            }
        }()

        let blockSpacing: CGFloat = {
            switch family {
            case .systemSmall, .systemMedium:
                return 8
            default:
                return 10
            }
        }()

        let rowSpacing: CGFloat = (family == .systemSmall) ? 6 : 8

        let visibleTitles = Array(titles.prefix(maxRows))

        return VStack(alignment: layout.alignment.alignment, spacing: blockSpacing) {
            modeHeader(title: "Reminders", progress: nil, showProgressBadge: false)

            if family == .systemMedium {
                Text("No snapshot yet.")
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(visibleTitles, id: \.self) { title in
                            placeholderReminderRowCompact(title: title)
                        }
                    }
                    .opacity(0.85)

                    Text(guidance)
                        .font(style.secondaryTextStyle.font(fallback: .caption2))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
                }
            } else {
                Text("No snapshot yet.\n\(guidance)")
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                    .lineLimit(family == .systemSmall ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)

                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(visibleTitles, id: \.self) { title in
                        placeholderReminderRow(title: title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
                .opacity(0.85)
            }
        }
    }

    private func placeholderReminderRowCompact(title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent)
                .opacity(0.9)

            Text(title)
                .font(style.secondaryTextStyle.font(fallback: .caption))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func placeholderReminderRow(title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent)
                .opacity(0.9)

            Text(title)
                .font(style.secondaryTextStyle.font(fallback: .caption))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}
