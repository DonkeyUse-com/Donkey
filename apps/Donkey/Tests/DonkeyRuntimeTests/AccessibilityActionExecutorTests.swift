import CoreGraphics
@testable import DonkeyRuntime
import DonkeyContracts
import Foundation
import Testing

@Suite
struct AccessibilityActionExecutorTests {
    @Test
    func clickPointIsTheCenterOfTheControlFrame() {
        let frame = WindowTargetBounds(x: 100, y: 200, width: 80, height: 40)
        let point = AccessibilityActionExecutor.clickPoint(for: frame)
        #expect(point.x == 140)
        #expect(point.y == 220)
    }
}
