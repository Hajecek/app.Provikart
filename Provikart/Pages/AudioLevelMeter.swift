//
//  AudioLevelMeter.swift
//  Provikart
//
//  Měření úrovně mikrofonu pro vizualizaci vln při nahrávání.
//

import AVFoundation
import Combine
import SwiftUI

final class AudioLevelMeter: ObservableObject {
    /// Počet sloupců vizualizace (0...1 normalizované výšky).
    static let barCount = 32

    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.15, count: barCount)
    @Published private(set) var isRunning = false
    @Published var permissionDenied = false

    private let engine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var tapInstalled = false
    private let levelSmoothing: Float = 0.3
    private var smoothedLevel: Float = 0

    init() {
        self.inputNode = engine.inputNode
    }

    func start() {
        guard !isRunning else { return }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self?.startEngine()
                } else {
                    self?.permissionDenied = true
                }
            }
        }
    }

    private func startEngine() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return
        }

        // Použij platný formát – outputFormat(forBus:) může mít sample rate 0 před startem enginu.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        tapInstalled = true

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            removeTap()
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channel = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            sum += channel[i] * channel[i]
        }
        let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
        let normalized = min(1.0, rms * 8)
        self.smoothedLevel = self.levelSmoothing * normalized + (1 - self.levelSmoothing) * self.smoothedLevel

        DispatchQueue.main.async {
            self.pushLevel(CGFloat(self.smoothedLevel))
        }
    }

    private func pushLevel(_ level: CGFloat) {
        let value = max(0.12, min(1.0, level))
        var next = levels
        for i in 0..<(Self.barCount - 1) {
            next[i] = next[i + 1]
        }
        next[Self.barCount - 1] = value
        levels = next
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        removeTap()
        isRunning = false
        levels = Array(repeating: 0.15, count: Self.barCount)
    }

    private func removeTap() {
        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    deinit {
        stop()
    }
}
