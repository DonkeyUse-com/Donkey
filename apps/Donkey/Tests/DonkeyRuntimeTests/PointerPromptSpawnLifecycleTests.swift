import DonkeyContracts
import Testing

@Suite
struct PointerPromptSpawnLifecycleTests {
    @Test
    func inputFreezeTracksEditingAndDirtyDrafts() {
        #expect(
            PointerPromptSpawnLifecycle.freezesMovement(
                inputState: .editing,
                draftText: ""
            )
        )
        #expect(
            PointerPromptSpawnLifecycle.freezesMovement(
                inputState: .collapsed,
                draftText: "  clarify this  "
            )
        )
        #expect(
            !PointerPromptSpawnLifecycle.freezesMovement(
                inputState: .collapsed,
                draftText: "   \n"
            )
        )
    }

    @Test
    func followUpSubmissionRoutesToSameTask() throws {
        let state = PointerPromptSpawnState(
            id: "spawn-1",
            taskID: "task-1",
            commandText: "open music",
            label: "Waiting for detail",
            accentIndex: 3,
            phase: .holding
        )

        let submission = try #require(
            PointerPromptSpawnLifecycle.followUpSubmission(
                from: state,
                text: "  play the next song  "
            )
        )

        #expect(submission.spawnID == "spawn-1")
        #expect(submission.taskID == "task-1")
        #expect(submission.text == "play the next song")
    }

    @Test
    func followUpSubmissionRequiresTaskAndText() {
        let state = PointerPromptSpawnState(
            id: "spawn-1",
            taskID: nil,
            commandText: "answer this",
            label: "Answering",
            accentIndex: 0,
            phase: .holding
        )

        #expect(
            PointerPromptSpawnLifecycle.followUpSubmission(
                from: state,
                text: "more detail"
            ) == nil
        )

        let taskedState = PointerPromptSpawnState(
            id: "spawn-2",
            taskID: "task-2",
            commandText: "open notes",
            label: "Waiting",
            accentIndex: 1,
            phase: .holding
        )

        #expect(
            PointerPromptSpawnLifecycle.followUpSubmission(
                from: taskedState,
                text: " \n "
            ) == nil
        )
    }
}
