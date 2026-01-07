//
//  SmartPhotoImportButton.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import SwiftUI

struct SmartPhotoImportButton: View {

    var currentFamily: EditingFamily?

    var body: some View {
        Button {
            // Placeholder: Smart Photo import flow can be wired here.
        } label: {
            Label(
                currentFamily.map { "Import smart photos (\($0.label))" } ?? "Import smart photos",
                systemImage: "photo.on.rectangle.angled"
            )
        }
        .buttonStyle(.borderedProminent)
    }
}
