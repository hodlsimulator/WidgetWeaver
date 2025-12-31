//
//  ContentView+SharePackage.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {

    // MARK: - Share package (Transferable)

    struct WidgetWeaverSharePackage: Transferable {
        let fileName: String
        let data: Data

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .json) { package in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(package.fileName)
                try package.data.write(to: url, options: [.atomic])
                return SentTransferredFile(url)
            } importing: { received in
                let data = try Data(contentsOf: received.file)
                return WidgetWeaverSharePackage(fileName: received.file.lastPathComponent, data: data)
            }
        }

        static var importableTypes: [UTType] {
            [.json, .data]
        }

        static func suggestedFileName(prefix: String, suffix: String) -> String {
            let safePrefix = sanitise(prefix)
            let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            return "\(safePrefix)-\(suffix)-\(date).json"
        }

        private static func sanitise(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = trimmed.isEmpty ? "WidgetWeaver" : trimmed

            var out = ""
            out.reserveCapacity(min(fallback.count, 64))

            for ch in fallback {
                if ch.isLetter || ch.isNumber {
                    out.append(ch)
                } else if ch == " " || ch == "-" || ch == "_" {
                    out.append("-")
                } else {
                    out.append("-")
                }

                if out.count >= 64 { break }
            }

            while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
            out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

            return out.isEmpty ? "WidgetWeaver" : out
        }
    }
}
