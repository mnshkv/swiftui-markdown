import CoreGraphics

public struct TextStyle: Equatable, Sendable {
    public var fontSize: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var isStrikethrough: Bool
    public var isMonospace: Bool
    public var color: CGColor
    public init(fontSize: CGFloat, isBold: Bool = false, isItalic: Bool = false,
                isStrikethrough: Bool = false, isMonospace: Bool = false, color: CGColor) {
        self.fontSize = fontSize; self.isBold = isBold; self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough; self.isMonospace = isMonospace; self.color = color
    }
}

public struct LinkPayload: Equatable, Sendable { public var token: String; public init(_ token: String) { self.token = token } }

public struct ImageAttachment: Equatable, Sendable {
    public var source: String; public var intrinsicSize: CGSize; public var alt: String
    public init(source: String, intrinsicSize: CGSize, alt: String) {
        self.source = source; self.intrinsicSize = intrinsicSize; self.alt = alt
    }
}

public indirect enum InlineRun: Equatable, Sendable {
    case text(String, TextStyle)
    case link(runs: [InlineRun], payload: LinkPayload)
    case inlineImage(ImageAttachment)
    case lineBreak(hard: Bool)
}
