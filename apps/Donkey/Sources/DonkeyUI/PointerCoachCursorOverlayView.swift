import DonkeyContracts
import SwiftUI

@MainActor
public final class PointerCoachCursorOverlayViewModel: ObservableObject {
    public let request: PointerCoachCursorGuideRequest
    public private(set) var screenSize: CGSize
    @Published public private(set) var viewportOrigin: CGPoint = .zero
    @Published public private(set) var viewportSize: CGSize = .zero
    @Published public private(set) var startedAt = Date()
    @Published public private(set) var now = Date()

    public init(
        request: PointerCoachCursorGuideRequest,
        screenSize: CGSize
    ) {
        self.request = request
        self.screenSize = screenSize
    }

    public var animationFrame: CoachCursorAnimationFrame {
        animationFrame(size: screenSize)
    }

    public var visualFrame: CGRect {
        visualFrame(for: animationFrame)
    }

    public func start(at date: Date = Date()) {
        startedAt = date
        now = date
    }

    public func update(now: Date, screenSize: CGSize? = nil) {
        self.now = now
        if let screenSize {
            self.screenSize = screenSize
        }
    }

    public func updateViewport(origin: CGPoint, size: CGSize) {
        viewportOrigin = origin
        viewportSize = size
    }

    public func renderPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - viewportOrigin.x,
            y: point.y - viewportOrigin.y
        )
    }

    public func labelPosition(for cursorPosition: CGPoint) -> CGPoint {
        let prefersLeft = cursorPosition.x > screenSize.width - 340
        let prefersAbove = cursorPosition.y > screenSize.height - 120
        return CGPoint(
            x: cursorPosition.x + (prefersLeft ? -156 : 156),
            y: cursorPosition.y + (prefersAbove ? -54 : 54)
        )
    }

    private func visualFrame(for frame: CoachCursorAnimationFrame) -> CGRect {
        var bounds = CGRect(
            x: frame.position.x - 30,
            y: frame.position.y - 30,
            width: 60,
            height: 60
        )
        if !frame.visibleLabel.isEmpty {
            let labelCenter = labelPosition(for: frame.position)
            bounds = bounds.union(CGRect(
                x: labelCenter.x - 160,
                y: labelCenter.y - 42,
                width: 320,
                height: 84
            ))
        }
        return bounds.insetBy(dx: -8, dy: -8)
    }

    private func animationFrame(size: CGSize) -> CoachCursorAnimationFrame {
        guard !request.steps.isEmpty else {
            return CoachCursorAnimationFrame(
                position: point(request.origin, in: size),
                angle: 0,
                visibleLabel: "",
                isHolding: false
            )
        }

        var elapsed = now.timeIntervalSince(startedAt)
        var origin = point(request.origin, in: size)
        for step in request.steps {
            let target = point(step.target, in: size)
            if elapsed <= step.travelDuration {
                let progress = eased(elapsed / step.travelDuration)
                let position = curvedPoint(from: origin, to: target, progress: progress)
                return CoachCursorAnimationFrame(
                    position: position,
                    angle: angle(from: origin, to: target),
                    visibleLabel: "",
                    isHolding: false
                )
            }

            elapsed -= step.travelDuration
            if elapsed <= step.holdDuration {
                let typeProgress = min(1, elapsed / min(step.holdDuration, max(0.6, Double(step.label.count) * 0.035)))
                let wobble = sin(elapsed * 8) * 1.8
                return CoachCursorAnimationFrame(
                    position: CGPoint(x: target.x + wobble, y: target.y),
                    angle: angle(from: origin, to: target),
                    visibleLabel: typedText(step.label, progress: typeProgress),
                    isHolding: true,
                    haloScale: 1 + 0.14 * sin(elapsed * 3.2),
                    haloOpacity: 0.24 + 0.18 * cos(elapsed * 3.2),
                    labelOpacity: min(1, elapsed / 0.18)
                )
            }

            elapsed -= step.holdDuration
            origin = target
        }

        let finalStep = request.steps[request.steps.count - 1]
        return CoachCursorAnimationFrame(
            position: point(finalStep.target, in: size),
            angle: 0,
            visibleLabel: finalStep.label,
            isHolding: true,
            labelOpacity: 1
        )
    }

    private func point(_ normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(normalizedPoint.x, 0.04), 0.96) * max(1, size.width),
            y: min(max(normalizedPoint.y, 0.06), 0.94) * max(1, size.height)
        )
    }

    private func curvedPoint(
        from origin: CGPoint,
        to target: CGPoint,
        progress: Double
    ) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = max(1, hypot(dx, dy))
        let curve = min(80, length * 0.35)
        let control = CGPoint(
            x: (origin.x + target.x) / 2 + (-dy / length) * curve,
            y: (origin.y + target.y) / 2 + (dx / length) * curve
        )
        let t = CGFloat(progress)
        let inv = 1 - t
        return CGPoint(
            x: inv * inv * origin.x + 2 * inv * t * control.x + t * t * target.x,
            y: inv * inv * origin.y + 2 * inv * t * control.y + t * t * target.y
        )
    }

    private func typedText(_ text: String, progress: Double) -> String {
        guard progress < 1 else { return text }

        let count = max(1, Int(Double(text.count) * progress))
        let endIndex = text.index(text.startIndex, offsetBy: min(count, text.count))
        return String(text[..<endIndex])
    }

    private func angle(from origin: CGPoint, to target: CGPoint) -> Double {
        atan2(target.y - origin.y, target.x - origin.x) * 180 / .pi
    }

    private func eased(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}

public struct PointerCoachCursorOverlayView: View {
    @ObservedObject private var viewModel: PointerCoachCursorOverlayViewModel

    public init(viewModel: PointerCoachCursorOverlayViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let frame = viewModel.animationFrame

        ZStack(alignment: .topLeading) {
            if frame.isHolding {
                Circle()
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .scaleEffect(frame.haloScale)
                    .opacity(frame.haloOpacity)
                    .position(viewModel.renderPoint(frame.position))
            }

            cursor(angle: frame.angle)
                .position(viewModel.renderPoint(frame.position))

            if !frame.visibleLabel.isEmpty {
                label(text: frame.visibleLabel, accent: frame.accent)
                    .position(viewModel.renderPoint(viewModel.labelPosition(for: frame.position)))
                    .opacity(frame.labelOpacity)
            }
        }
    }

    private func cursor(angle: Double) -> some View {
        PointerCoachCursorShape()
            .fill(Color.white)
            .overlay {
                PointerCoachCursorShape()
                    .stroke(Color(red: 0.34, green: 0.95, blue: 1.0), lineWidth: 1.4)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 2)
            .frame(width: 26, height: 26)
            .rotationEffect(.degrees(angle + 50))
    }

    private func label(text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 280, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.32), radius: 8, x: 0, y: 4)
    }

}

public struct CoachCursorAnimationFrame {
    var position: CGPoint
    var angle: Double
    var visibleLabel: String
    var isHolding: Bool
    var haloScale: Double = 1
    var haloOpacity: Double = 0.35
    var labelOpacity: Double = 0
    var accent: Color = Color(red: 0.34, green: 0.28, blue: 0.95)
}

private struct PointerCoachCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: svgPoint(x: 83.086, y: 5.6406, width: w, height: h))
        path.addLine(to: svgPoint(x: 10.453, y: 34.6836, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 11.13269, y: 51.0276, width: w, height: h),
            control1: svgPoint(x: 2.8514, y: 37.7227, width: w, height: h),
            control2: svgPoint(x: 3.3085, y: 48.6326, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 35.69469, y: 58.5471, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 41.44859, y: 64.301, width: w, height: h),
            control1: svgPoint(x: 38.44859, y: 59.39085, width: w, height: h),
            control2: svgPoint(x: 40.60489, y: 61.5471, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 48.96809, y: 88.863, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 65.31209, y: 89.54269, width: w, height: h),
            control1: svgPoint(x: 51.36649, y: 96.6911, width: w, height: h),
            control2: svgPoint(x: 62.27309, y: 97.1442, width: w, height: h)
        )
        path.addLine(to: svgPoint(x: 94.35509, y: 16.90969, width: w, height: h))
        path.addCurve(
            to: svgPoint(x: 83.08209, y: 5.63669, width: w, height: h),
            control1: svgPoint(x: 97.18709, y: 9.83159, width: w, height: h),
            control2: svgPoint(x: 90.15979, y: 2.80769, width: w, height: h)
        )
        path.closeSubpath()

        return path
    }

    private func svgPoint(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(
            x: (100 - x) / 100 * width,
            y: y / 100 * height
        )
    }
}
