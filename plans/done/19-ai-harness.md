# AI Harness Memory And Voice Cleanup

> Completed. This plan was narrowed to semantic-memory wiring, provider memory write proposals, live voice audio hardening, and focused tests. Those slices are now supported in local code.

## 1. Wire Real Semantic Memory Retrieval

Original gap: `SemanticRunMemoryRetriever` existed, but the live pointer-prompt path called it with no records. Retrieval needed to search actual run/target memory and feed the selected results into planner or command context.

Implemented:

- load target-scoped records from `TargetMemoryJSONLStore` or the active run memory before command/planner calls
- pass real records to `SemanticRunMemoryRetriever.retrieve`
- include selected memory ids and summaries in `RunContextPackage` or provider prompt context
- keep retrieval bounded by record count, prompt characters, scope, target id, and minimum relevance
- record retrieval metadata on the command/planner trace

Done:

- a command or planner call can retrieve non-empty target memories from local storage
- retrieved memory is visible in the assembled model context without sending full memory logs
- tests cover target scoping, prompt budget limits, and empty-memory fallback

## 2. Integrate Provider Memory Write Proposals

Original gap: `ProviderDecodedMemoryProposalHandler` could decode proposals and apply deterministic approval, but live provider flows did not request, decode, approve, or persist model-proposed memory writes.

Implemented:

- extend provider planner output to include optional memory write proposals
- keep planner hints valid even when memory proposals are absent or rejected
- run decoded proposals through `RunMemoryApprover`
- persist approved target memories through `TargetMemoryJSONLStore`
- attach proposal, approval, rejection, and persistence counts to model trace metadata
- reject proposals that lack source links, retention, target/run/user scope requirements, or safe content

Done:

- provider-backed planner calls can return memory proposals alongside validated hints
- approved target memories are persisted and later retrievable
- rejected proposals are traceable without being stored
- tests cover accepted proposals, rejected proposals, malformed proposal payloads, and no-proposal outputs

## 3. Harden Live Voice Transcription Audio

Original gap: pointer-prompt voice capture fed `LocalVoiceTranscriptionAdapter` and `ProcessBackedParakeetTranscriptionRuntime`, but the captured audio format could differ from the Parakeet runtime expectation.

Original risk:

- microphone capture emits `pcm_f32le`
- device sample rate may not be 16 kHz
- Parakeet registry metadata expects 16 kHz mono `.wav` or `.flac`
- the sidecar writes received bytes to a temp file based on the provided format, so unsupported raw PCM can fail or decode incorrectly

Implemented:

- convert pointer-prompt audio to a supported Parakeet input format before transcription
- normalize to mono 16 kHz where required
- prefer a small local conversion utility with explicit metadata over implicit sidecar assumptions
- surface clear failure metadata when conversion or transcription is unavailable
- keep transcript text flowing through the normal validated task-intent path

Done:

- live pointer-prompt voice input sends Parakeet-compatible audio
- tests cover PCM input conversion metadata, empty audio fallback, runtime unavailable fallback, and successful transcript-to-command flow

## 4. Verification

Completed checks:

1. `swift test --filter AIHarnessAdapterTests`
2. `swift test --filter RunMemoryStoreTests`
3. `swift test`
