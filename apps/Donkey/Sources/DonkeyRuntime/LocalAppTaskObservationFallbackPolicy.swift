import DonkeyContracts
import Foundation

public enum LocalAppTaskObservationFallbackPolicy {
    public static func shouldUseScreenshotUnderstanding(
        definition: LocalAppTaskDefinition,
        accessibilityObservation: LocalAppTaskObservation,
        verificationKey: String
    ) -> Bool {
        guard definition.observationStrategies.contains(.screenshotForLocalModel) else {
            return false
        }

        if accessibilityObservation.visibleText[verificationKey]?.isEmpty == false {
            return false
        }

        return definition.workflowSteps.contains { step in
            guard step.role == .focusControl,
                  let controlID = step.metadata["controlID"]
            else {
                return false
            }

            return accessibilityObservation.availableControls[controlID] != true
        } || accessibilityObservation.visibleText.isEmpty
    }
}
