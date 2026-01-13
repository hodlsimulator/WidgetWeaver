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
        ZStack {
            if entry.image == nil {
                placeholderContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            backgroundLayer
        }
        .widgetURL(URL(string: "widgetweaver://pawpulse")!)
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
        Image(systemName: "pawprint")
            .font(.title2)
            .foregroundStyle(.secondary)
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
