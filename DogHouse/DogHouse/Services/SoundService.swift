//
//  SoundService.swift
//  DogHouse
//
//  Synthesized sound effects using AVAudioEngine tone generation.
//  No external audio files required.
//

@preconcurrency import AVFoundation
import SwiftUI
import Combine
import OSLog

final class SoundService: ObservableObject {
    static let shared = SoundService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "soundEnabled")
        }
    }

    /// Engines that are still playing, held until their buffer finishes.
    ///
    /// This used to be a single `audioEngine` property that each new sound
    /// overwrote. Two sounds close together therefore dropped the last reference
    /// to an engine that was still running, and releasing a running AVAudioEngine
    /// is a hard crash inside CoreAudio rather than a no-op.
    private var activeEngines: [ObjectIdentifier: AVAudioEngine] = [:]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        configureAudioSession()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Sound Effects

    func playSendToDoghouse() {
        guard isEnabled else { return }
        // Dramatic descending tone sequence
        playToneSequence(frequencies: [880, 660, 440, 330], durations: [0.1, 0.1, 0.15, 0.25], volume: 0.4)
    }

    func playRelease() {
        guard isEnabled else { return }
        // Happy ascending celebration tone
        playToneSequence(frequencies: [330, 440, 550, 660, 880], durations: [0.08, 0.08, 0.08, 0.1, 0.2], volume: 0.35)
    }

    func playItemUnlock() {
        guard isEnabled else { return }
        // Quick sparkle sound
        playToneSequence(frequencies: [1200, 1400, 1600], durations: [0.06, 0.06, 0.12], volume: 0.25)
    }

    func playVoteResult() {
        guard isEnabled else { return }
        // Notification chime
        playToneSequence(frequencies: [660, 880, 660], durations: [0.1, 0.15, 0.1], volume: 0.3)
    }

    func playButtonTap() {
        guard isEnabled else { return }
        // Subtle click
        playToneSequence(frequencies: [800], durations: [0.03], volume: 0.15)
    }

    func playImmunityGranted() {
        guard isEnabled else { return }
        // Shield activation sound — rising shimmer
        playToneSequence(frequencies: [440, 660, 880, 1100], durations: [0.08, 0.08, 0.1, 0.15], volume: 0.3)
    }

    // MARK: - Tone Synthesis

    private func playToneSequence(frequencies: [Double], durations: [Double], volume: Float) {
        Task.detached(priority: .userInitiated) {
            let sampleRate: Double = 44100
            var allSamples: [Float] = []

            for (index, freq) in frequencies.enumerated() {
                let duration = durations[index]
                let sampleCount = Int(sampleRate * duration)

                for i in 0..<sampleCount {
                    let t = Double(i) / sampleRate
                    let envelope = Self.envelope(t: t, duration: duration)
                    let sample = Float(sin(2.0 * Double.pi * freq * t) * envelope) * volume
                    allSamples.append(sample)
                }
            }

            await self.playBuffer(samples: allSamples, sampleRate: sampleRate)
        }
    }

    /// Smooth attack/decay envelope to avoid clicks
    private nonisolated static func envelope(t: Double, duration: Double) -> Double {
        let attack = 0.005
        let release = min(0.05, duration * 0.3)

        if t < attack {
            return t / attack
        } else if t > duration - release {
            return (duration - t) / release
        }
        return 1.0
    }

    @MainActor
    private func playBuffer(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = samples[i]
            }
        }

        do {
            try engine.start()
            player.play()

            // Each engine keeps its own entry until its buffer finishes, so a
            // second sound starting mid-playback can no longer deallocate the
            // first one out from under CoreAudio.
            let key = ObjectIdentifier(engine)
            activeEngines[key] = engine

            player.scheduleBuffer(buffer) {
                Task { @MainActor [weak self] in
                    engine.stop()
                    self?.activeEngines[key] = nil
                }
            }
        } catch {
            Logger.data.error("Sound playback failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
