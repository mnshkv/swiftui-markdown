// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "swift-marked",
    platforms: [.iOS("26.0"), .macOS("14.0")],
    products: [
        .library(name: "MarkdownAST", targets: ["MarkdownAST"]),
        .library(name: "MarkdownTextEngine", targets: ["MarkdownTextEngine"]),
    ],
    targets: [
        .target(name: "MarkdownAST"),
        .testTarget(name: "MarkdownASTTests", dependencies: ["MarkdownAST"],
                    resources: [.copy("Fixtures/commonmark-spec.json")]),
        .target(name: "MarkdownTextEngine"),
        .testTarget(name: "MarkdownTextEngineTests", dependencies: ["MarkdownTextEngine"]),
    ]
)
