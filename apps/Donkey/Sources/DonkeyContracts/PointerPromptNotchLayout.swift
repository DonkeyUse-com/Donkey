import CoreGraphics

public struct PointerPromptNotchLayout: Equatable, Sendable {
    public var voidHeight: CGFloat
    public var contentHorizontalInset: CGFloat
    public var visibleHeight: CGFloat
    public var cornerRadius: CGFloat

    public init(
        voidHeight: CGFloat,
        contentHorizontalInset: CGFloat,
        visibleHeight: CGFloat,
        cornerRadius: CGFloat
    ) {
        self.voidHeight = voidHeight
        self.contentHorizontalInset = contentHorizontalInset
        self.visibleHeight = visibleHeight
        self.cornerRadius = cornerRadius
    }
}
