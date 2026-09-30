// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "whodis",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "whodis", targets: ["whodis"]),
    ],
    targets: [
        // Pure Foundation: matching, parsing, formatting. No Apple-only frameworks, so it's unit-testable anywhere.
        .target(name: "WhodisCore"),

        // The CLI: reads chat.db (read-only) and writes through Contacts.framework.
        .executableTarget(
            name: "whodis",
            dependencies: ["WhodisCore"],
            linkerSettings: [
                // Embed Info.plist so macOS has a Contacts usage description for the permission prompt.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Supporting/Info.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),

        .testTarget(name: "WhodisCoreTests", dependencies: ["WhodisCore"]),
    ]
)
