//
//  WidgetWeaverPawPulseLatestCatWidget.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

struct WidgetWeaverPawPulseLatestCatEntry: TimelineEntry {
    let date: Date
    let item: PawPulseLatestItem?
    let image: UIImage?
}

struct WidgetWeaverPawPulseLatestCatProvider: TimelineProvider {
    typealias Entry = WidgetWeaverPawPulseLatestCatEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), item: PawPulseLatestItem.sample(), image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview {
            completion(Entry(date: Date(), item: PawPulseLatestItem.sample(), image: nil))
            return
        }

        let item = PawPulseCache.loadLatestItem()
        let image = PawPulseCache.loadWidgetImage(maxPixel: maxPixel(for: context.family))
        completion(Entry(date: Date(), item: item, image: image))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let refreshIntervalSeconds: TimeInterval = 60.0 * 30.0
        let count = 14

        let item = PawPulseCache.loadLatestItem()
        let image = PawPulseCache.loadWidgetImage(maxPixel: maxPixel(for: context.family))

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = now.addingTimeInterval(TimeInterval(i) * refreshIntervalSeconds)
            entries.append(Entry(date: d, item: item, image: image))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func maxPixel(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 900
        case .systemMedium:
            return 1200
        case .systemLarge:
            return 1600
        default:
            return 1200
        }
    }
}

struct WidgetWeaverPawPulseLatestCatView: View {
    let entry: WidgetWeaverPawPulseLatestCatEntry

    var body: some View {
        foreground
            .containerBackground(for: .widget) {
                backgroundLayer
            }
            .widgetURL(URL(string: "widgetweaver://pawpulse")!)
    }

    // Foreground content only (no manual background here).
    private var foreground: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.image == nil {
                placeholderContent
            }

            overlay
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let image = entry.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Rectangle()
                .fill(.thinMaterial)
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(placeholderText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderText: String {
        if entry.item == nil {
            return "Open the app to set a PawPulse feed."
        }
        return "Updating…"
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitleText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var titleText: String {
        let name = (entry.item?.pageName ?? entry.item?.source ?? PawPulseSettingsStore.loadDisplayName())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "PawPulse" : name
    }

    private var subtitleText: String {
        if let d = entry.item?.createdDate {
            return "Posted " + d.formatted(date: .abbreviated, time: .shortened)
        }
        if let raw = entry.item?.createdTime?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return "Posted " + raw
        }
        return "Latest cat"
    }
}

struct WidgetWeaverPawPulseLatestCatWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.pawPulseLatestCat

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverPawPulseLatestCatProvider()) { entry in
            WidgetWeaverPawPulseLatestCatView(entry: entry)
                .id(entry.date)
        }
        .configurationDisplayName("Latest Cat (PawPulse)")
        .description("Shows the latest cached adoption post photo from your PawPulse feed.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    WidgetWeaverPawPulseLatestCatWidget()
} timeline: {
    WidgetWeaverPawPulseLatestCatEntry(date: Date(), item: PawPulseLatestItem.sample(), image: nil)
}
