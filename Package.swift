// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "swiftui-markdown",
    products: [.library(name: "MarkdownAST", targets: ["MarkdownAST"])],
    targets: [
        .target(name: "MarkdownAST"),
        .testTarget(name: "MarkdownASTTests", dependencies: ["MarkdownAST"]),
    ]
)