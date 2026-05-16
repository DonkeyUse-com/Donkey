import AVFoundation
import DonkeyContracts
import Foundation

@MainActor
final class MicrophoneWaveformMeter {
    private let engine = AVAudioEngine()
    private let barCount = PointerPromptState.defaultVoiceWaveformLevels.count
    private var levels = PointerPromptState.defaultVoiceWaveformLevels
    private var isRunning = false
    private var isStarting = false

    var onLevelsChanged: (([Double]) -> Void)?

    func start() {
        guard !isRunning, !isStarting else { return }

        isStarting = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] isGranted in
            Task { @MainActor in
                guard self?.isStarting == true else { return }

                guard isGranted else {
                    self?.isStarting = false
                    self?.publishSilence()
                    return
                }

                self?.startEngine()
            }
        }
    }

    func stop() {
        guard isRunning || isStarting else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        isStarting = false
        publishSilence()
    }

    private func startEngine() {
        guard !isRunning else {
            isStarting = false
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        levels = PointerPromptState.defaultVoiceWaveformLevels
        publishLevels()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 512,
            format: format,
            block: Self.makeTapBlock(meter: self)
        )

        engine.prepare()

        do {
            try engine.start()
            isRunning = true
            isStarting = false
        } catch {
            inputNode.removeTap(onBus: 0)
            isRunning = false
            isStarting = false
            publishSilence()
        }
    }

    private func append(_ level: Double) {
        levels.append(level)
        if levels.count > barCount {
            levels.removeFirst(levels.count - barCount)
        }

        publishLevels()
    }

    private func publishSilence() {
        levels = Array(repeating: 0.08, count: barCount)
        publishLevels()
    }

    private func publishLevels() {
        onLevelsChanged?(levels)
    }

    nonisolated private static func makeTapBlock(meter: MicrophoneWaveformMeter) -> AVAudioNodeTapBlock {
        { [weak meter] buffer, _ in
            let level = Self.normalizedLevel(from: buffer)

            Task { @MainActor in
                meter?.append(level)
            }
        }
    }

    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for frame in 0..<frameCount {
                let sample = samples[frame]
                sumOfSquares += sample * sample
            }

            sampleCount += frameCount
        }

        guard sampleCount > 0 else { return 0 }

        let rms = sqrt(sumOfSquares / Float(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = (Double(decibels) + 55) / 45

        return min(max(normalized, 0), 1)
    }
}
