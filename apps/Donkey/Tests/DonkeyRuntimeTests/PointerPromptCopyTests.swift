import DonkeyAI
import DonkeyContracts
import Testing

@Suite
struct PointerPromptCopyTests {
    @Test
    func defaultPromptCopyIsSharedAcrossPromptSurfaces() {
        #expect(PointerPromptState.productionDefault.promptText == PointerPromptCopy.defaultPromptPlaceholder)
        #expect(AIHarnessBoundary().snapshot().suggestedPromptText == PointerPromptCopy.defaultPromptPlaceholder)
    }

    @Test
    func placeholderCopyDoesNotBecomeTaskDisplayText() {
        #expect(!PointerPromptCopy.isTaskDisplayText(PointerPromptCopy.defaultPromptPlaceholder))
        #expect(!PointerPromptCopy.isTaskDisplayText("  \(PointerPromptCopy.defaultPromptPlaceholder)  "))
        #expect(PointerPromptCopy.isTaskDisplayText("Open Safari"))
    }
}
