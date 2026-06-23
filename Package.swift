// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "swiftui-markdown",
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
