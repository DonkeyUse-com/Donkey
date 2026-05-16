import DonkeyContracts
@testable import DonkeyRuntime
import Foundation
import Testing

@Suite
struct MacWindowResolverTests {
    @Test
    func windowCandidateMetadataRoundTripsThroughJSON() throws {
        let candidate = MacWindowTargetCandidate(
            windowID: 42,
            processID: 9001,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            title: "Project Notes",
            bounds: WindowTargetBounds(x: 10, y: 20, width: 300, height: 400),
            isVisible: true,
            isOnScreen: true,
            isFrontmost: true,
            isFocused: true,
            isIPhoneMirroring: false,
            safetyAssessment: WindowTargetSafetyAssessment(
                status: .allowed,
                summary: "No sensitive surface indicators detected"
            )
        )

        let data = try JSONEncoder().encode(candidate)
        let decoded = try JSONDecoder().decode(
            MacWindowTargetCandidate.self,
            from: data
        )

        #expect(decoded == candidate)
        #expect(decoded.bounds == WindowTargetBounds(x: 10, y: 20, width: 300, height: 400))
    }

    @Test
    func explicitWindowSelectionUsesRequestedWindowID() throws {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(windowID: 1, processID: 100, appName: "Terminal"),
                    fixtureWindow(windowID: 2, processID: 200, appName: "Safari")
                ],
                frontmostProcessID: 100
            )
        )

        let selected = try resolver.selectTarget(
            MacWindowSelectionRequest(windowID: 2)
        )

        #expect(selected.windowID == 2)
        #expect(selected.appName == "Safari")
    }

    @Test
    func focusedWindowSelectionFallsBackToFrontmostCandidate() throws {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(windowID: 1, processID: 100, appName: "Terminal"),
                    fixtureWindow(windowID: 2, processID: 200, appName: "Safari"),
                    fixtureWindow(windowID: 3, processID: 200, appName: "Safari", title: "Background Tab")
                ],
                frontmostProcessID: 200
            )
        )

        let candidates = resolver.enumerateCandidates()
        let selected = try resolver.selectTarget()

        #expect(selected.windowID == 2)
        #expect(candidates.first(where: { $0.windowID == 2 })?.isFocused == true)
        #expect(candidates.first(where: { $0.windowID == 3 })?.isFocused == false)
    }

    @Test
    func focusedWindowIdentifierWinsWhenProvided() throws {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(windowID: 1, processID: 100, appName: "Terminal"),
                    fixtureWindow(windowID: 2, processID: 200, appName: "Safari"),
                    fixtureWindow(windowID: 3, processID: 200, appName: "Safari", title: "Focused Tab")
                ],
                frontmostProcessID: 200,
                focusedWindowID: 3
            )
        )

        let selected = try resolver.selectTarget()

        #expect(selected.windowID == 3)
        #expect(selected.isFocused)
        #expect(selected.isFrontmost)
    }

    @Test
    func missingExplicitWindowSelectionFailsDeterministically() {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(windowID: 1, processID: 100, appName: "Terminal")
                ],
                frontmostProcessID: 100
            )
        )

        do {
            _ = try resolver.selectTarget(MacWindowSelectionRequest(windowID: 999))
            Issue.record("Expected missing window selection to fail")
        } catch MacWindowResolverError.windowNotFound(let windowID) {
            #expect(windowID == 999)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func iPhoneMirroringIsNormalVisibleCandidateWithHint() {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(
                        windowID: 7,
                        processID: 700,
                        appName: "iPhone Mirroring",
                        bundleIdentifier: "com.apple.ScreenContinuity",
                        title: "David's iPhone"
                    )
                ],
                frontmostProcessID: 700
            )
        )

        let candidates = resolver.enumerateCandidates()

        #expect(candidates.map(\.windowID) == [7])
        #expect(candidates.first?.isIPhoneMirroring == true)
        #expect(candidates.first?.safetyAssessment.status == .allowed)
    }

    @Test
    func safetyClassificationMarksSensitiveAndUnknownSurfaces() {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(
                        windowID: 1,
                        processID: 100,
                        appName: "Notes",
                        bundleIdentifier: "com.apple.Notes",
                        title: "Shopping List"
                    ),
                    fixtureWindow(
                        windowID: 2,
                        processID: 200,
                        appName: "Safari",
                        title: "Password Sign In"
                    ),
                    fixtureWindow(
                        windowID: 3,
                        processID: 300,
                        appName: "Safari",
                        title: "Checkout Payment"
                    ),
                    fixtureWindow(
                        windowID: 4,
                        processID: 400,
                        appName: "System Settings",
                        bundleIdentifier: "com.apple.systempreferences",
                        title: "Privacy & Security Accessibility Permission"
                    ),
                    fixtureWindow(windowID: 5, processID: 500)
                ],
                frontmostProcessID: 100
            )
        )

        let candidates = Dictionary(
            uniqueKeysWithValues: resolver.enumerateCandidates().map {
                ($0.windowID, $0.safetyAssessment)
            }
        )

        #expect(candidates[1]?.status == .allowed)
        #expect(candidates[2]?.status == .blocked)
        #expect(candidates[2]?.reasons.contains(.loginSurface) == true)
        #expect(candidates[2]?.reasons.contains(.passwordSurface) == true)
        #expect(candidates[3]?.status == .blocked)
        #expect(candidates[3]?.reasons.contains(.paymentSurface) == true)
        #expect(candidates[4]?.status == .blocked)
        #expect(candidates[4]?.reasons.contains(.systemSurface) == true)
        #expect(candidates[4]?.reasons.contains(.permissionSurface) == true)
        #expect(candidates[5]?.status == .reviewRequired)
        #expect(candidates[5]?.reasons == [.unknownSurface])
    }

    @Test
    func enumerationFiltersNonVisibleWindows() {
        let resolver = MacWindowResolver(
            provider: FixtureWindowProvider(
                windows: [
                    fixtureWindow(windowID: 1, processID: 100, appName: "Visible"),
                    fixtureWindow(windowID: 2, processID: 200, appName: "Transparent", alpha: 0),
                    fixtureWindow(windowID: 3, processID: 300, appName: "Desktop", layer: 1),
                    fixtureWindow(windowID: 4, processID: 400, appName: "Offscreen", isOnScreen: false),
                    fixtureWindow(
                        windowID: 5,
                        processID: 500,
                        appName: "Zero Size",
                        bounds: WindowTargetBounds(x: 0, y: 0, width: 0, height: 100)
                    )
                ],
                frontmostProcessID: 100
            )
        )

        #expect(resolver.enumerateCandidates().map(\.windowID) == [1])
    }

    private func fixtureWindow(
        windowID: UInt32,
        processID: Int32,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        title: String? = nil,
        bounds: WindowTargetBounds = WindowTargetBounds(
            x: 0,
            y: 0,
            width: 100,
            height: 100
        ),
        alpha: Double = 1,
        layer: Int = 0,
        isOnScreen: Bool = true
    ) -> MacWindowProviderWindow {
        MacWindowProviderWindow(
            windowID: windowID,
            processID: processID,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            bounds: bounds,
            alpha: alpha,
            layer: layer,
            isOnScreen: isOnScreen
        )
    }
}

private struct FixtureWindowProvider: MacWindowMetadataProviding {
    var fixtureWindows: [MacWindowProviderWindow]
    var frontmostProcessID: Int32?
    var focusedWindowID: UInt32?

    init(
        windows: [MacWindowProviderWindow],
        frontmostProcessID: Int32? = nil,
        focusedWindowID: UInt32? = nil
    ) {
        self.fixtureWindows = windows
        self.frontmostProcessID = frontmostProcessID
        self.focusedWindowID = focusedWindowID
    }

    func windows() -> [MacWindowProviderWindow] {
        fixtureWindows
    }

    func frontmostProcessIdentifier() -> Int32? {
        frontmostProcessID
    }

    func focusedWindowIdentifier() -> UInt32? {
        focusedWindowID
    }
}
