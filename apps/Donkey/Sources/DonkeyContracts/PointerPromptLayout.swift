import CoreGraphics

public enum PointerPromptLayout {
    public static let contentSize = CGSize(width: 448, height: 166)
    public static let stageHorizontalPadding: CGFloat = 8
    public static let stageVerticalPadding: CGFloat = 10
    public static let pointerSlotSize = CGSize(width: 58, height: 68)
    public static let pointerVisualSize = CGSize(width: 24, height: 24)
    public static let pointerTipUnitPoint = CGPoint(x: 0.16914, y: 0.05641)
    public static let pointerStrokeWidth: CGFloat = 1.6
    public static let pointerDistanceFromCursor: CGFloat = 48
    public static let pointerDiagonalComponent = pointerDistanceFromCursor / CGFloat(2).squareRoot()
    public static let pointerComposerSpacing: CGFloat = 16
    public static let composerSize = CGSize(width: 350, height: 142)
    public static let composerCornerRadius: CGFloat = 12
    public static let composerDragBorderThickness: CGFloat = 14
    public static let closeButtonSize: CGFloat = 20
    public static let closeButtonInset: CGFloat = 12
}
