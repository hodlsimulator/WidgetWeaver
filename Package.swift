// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WidgetWeaverEditorTooling",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WidgetWeaverEditorTooling",
            targets: ["WidgetWeaverEditorTooling"]
        )
    ],
    targets: [
        .target(
            name: "WidgetWeaverEditorTooling",
            path: ".",
            sources: [
                "Shared/WidgetSpec+Layout.swift",
                "WidgetWeaver/EditorFocusModel.swift",
                "WidgetWeaver/EditorPhotoLibraryAccess.swift",
                "WidgetWeaver/EditorSelectionDescriptor.swift",
                "WidgetWeaver/EditorToolEligibility.swift",
                "WidgetWeaver/EditorToolFocusGating.swift",
                "WidgetWeaver/EditorToolTeardown.swift",
                "WidgetWeaver/EditorTooling.swift"
            ],
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "WidgetWeaverTests",
            dependencies: ["WidgetWeaverEditorTooling"],
            path: "WidgetWeaverTests"
        )
    ]
)
