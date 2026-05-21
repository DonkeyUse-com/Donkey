import CoreGraphics
import DonkeyContracts
import Testing

@Suite
struct PointerPromptSpawnGeometryTests {
    @Test
    func fallbackPointSitsBelowNotchAndClampsInsideScreen() {
        let point = PointerPromptSpawnGeometry.fallbackPoint(
            screenSize: CGSize(width: 1200, height: 800),
            notchBottomY: 32
        )

        #expect(point.x == 600)
        #expect(point.y == 282)

        let shortScreenPoint = PointerPromptSpawnGeometry.fallbackPoint(
            screenSize: CGSize(width: 360, height: 260),
            notchBottomY: 40
        )

        #expect(shortScreenPoint.x == 180)
        #expect(shortScreenPoint.y == 224)
    }

    @Test
    func clampedPointRespectsMinimumInset() {
        let point = PointerPromptSpawnGeometry.clampedPoint(
            CGPoint(x: -20, y: 1000),
            in: CGSize(width: 500, height: 400),
            inset: 40
        )

        #expect(point.x == 40)
        #expect(point.y == 360)
    }

    @Test
    func cueAngleUsesTopLeftCoordinateSpace() {
        #expect(
            PointerPromptSpawnGeometry.angleDegrees(
                from: CGPoint(x: 100, y: 100),
                to: CGPoint(x: 100, y: 200)
            ) == 90
        )
        #expect(
            PointerPromptSpawnGeometry.angleDegrees(
                from: CGPoint(x: 100, y: 100),
                to: CGPoint(x: 0, y: 100)
            ) == 180
        )
    }

    @Test
    func labelTypingIdentityChangesWhenLabelChanges() {
        let first = PointerPromptSpawnGeometry.labelTypingIdentity(
            spawnID: "spawn-1",
            label: "Routing task"
        )
        let second = PointerPromptSpawnGeometry.labelTypingIdentity(
            spawnID: "spawn-1",
            label: "Opening Music"
        )

        #expect(first != second)
        #expect(
            first == PointerPromptSpawnGeometry.labelTypingIdentity(
                spawnID: "spawn-1",
                label: "Routing task"
            )
        )
    }
}
