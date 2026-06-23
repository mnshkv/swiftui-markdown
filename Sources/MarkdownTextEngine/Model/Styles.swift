import CoreGraphics

public enum TextAlignment: Equatable, Sendable { case leading, center, trailing, justified }

public struct ParagraphStyle: Equatable, Sendable {
    public var alignment: TextAlignment
    public var lineSpacing: CGFloat
    public var spacingBefore: CGFloat
    public var spacingAfter: CGFloat
    public var leadingIndent: CGFloat
    public init(alignment: TextAlignment = .leading, lineSpacing: CGFloat = 0,
                spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 8, leadingIndent: CGFloat = 0) {
        self.alignment = alignment; self.lineSpacing = lineSpacing
        self.spacingBefore = spacingBefore; self.spacingAfter = spacingAfter
        self.leadingIndent = leadingIndent
    }
    public static let body = ParagraphStyle()
}

public struct RuleStyle: Equatable, Sendable {
    public var thickness: CGFloat; public var color: CGColor
    public init(thickness: CGFloat = 1, color: CGColor) { self.thickness = thickness; self.color = color }
}
