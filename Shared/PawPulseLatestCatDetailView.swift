//
//  PawPulseLatestCatDetailView.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import SwiftUI
import UIKit

@MainActor
struct PawPulseLatestCatDetailView: View {
    @State private var item: PawPulseLatestItem? = PawPulseCache.loadLatestItem()
    @State private var image: UIImage? = PawPulseCache.loadUIImage()
    @State private var statusMessage: String = ""
    @State private var isRefreshing: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                imageBlock

                metaBlock

                messageBlock

                actionsBlock

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .navigationTitle("Latest Cat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") {
                    PawPulseSettingsView()
                }
            }
        }
        .task {
            await refreshIfPossible(force: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sourceTitle)
                .font(.headline)

            Text(postedTimeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var imageBlock: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)

                    VStack(spacing: 10) {
                        Image(systemName: "pawprint")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No cached image yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let postID = item?.postID, !postID.isEmpty {
                LabeledContent("Post ID") {
                    Text(postID)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let url = URL(string: item?.permalinkURL ?? "") {
                LabeledContent("Permalink") {
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caption")
                .font(.headline)

            Text(item?.message?.trimmingCharacters(in: .whitespacesAndNewlines).fallbackDash ?? "—")
                .font(.body)
        }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await refreshIfPossible(force: true) }
            } label: {
                if isRefreshing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Refreshing…")
                    }
                } else {
                    Text("Refresh now")
                }
            }
            .disabled(isRefreshing)

            if let urlString = item?.permalinkURL, let url = URL(string: urlString), !urlString.isEmpty {
                Link("Open original post", destination: url)
            }

            if PawPulseSettingsStore.resolvedBaseURL() == nil {
                Text("Feed not configured. Open Settings to set the base URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private var sourceTitle: String {
        let display = PawPulseSettingsStore.loadDisplayName()
        let name = (item?.pageName ?? item?.source ?? display).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "PawPulse" : name
    }

    private var postedTimeText: String {
        if let d = item?.createdDate {
            return "Posted " + d.formatted(date: .abbreviated, time: .shortened)
        }
        if let raw = item?.createdTime, !raw.isEmpty {
            return "Posted " + raw
        }
        return "Posted time unavailable"
    }

    private func refreshIfPossible(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await PawPulseEngine.shared.updateIfNeeded(force: force)
        statusMessage = result.statusMessage

        item = PawPulseCache.loadLatestItem()
        image = PawPulseCache.loadUIImage()

        PawPulseBackgroundTasks.scheduleNextEarliest(minutesFromNow: 30)
    }
}

private extension String {
    var fallbackDash: String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }
}
