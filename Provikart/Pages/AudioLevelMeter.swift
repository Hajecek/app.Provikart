//
//  AudioLevelMeter.swift
//  Provikart
//
//  Měření úrovně mikrofonu a rozpoznávání řeči (přepis do textu).
//

import AVFoundation
import Combine
import Speech
import SwiftUI

final class AudioLevelMeter: ObservableObject {
    static let barCount = 32

    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.15, count: barCount)
    @Published private(set) var isRunning = false
    @Published var permissionDenied = false

    private let engine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var tapInstalled = false
    private let levelSmoothing: Float = 0.3
    private var smoothedLevel: Float = 0

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionCompletion: ((String?) -> Void)?
    private var audioFormat: AVAudioFormat?

    init() {
        self.inputNode = engine.inputNode
    }

    func start() {
        guard !isRunning else { return }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    self?.requestSpeechAndStart()
                } else {
                    self?.permissionDenied = true
                }
            }
        }
    }

    private func requestSpeechAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.startEngine()
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

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
            return
        }
        audioFormat = format

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        tapInstalled = true

        startSpeechRecognition()

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            removeTap()
        }
    }

    private func startSpeechRecognition() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "cs-CZ")), recognizer.isAvailable else {
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result, result.isFinal {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.recognitionCompletion?(text.isEmpty ? nil : text)
                    self.recognitionCompletion = nil
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
                return
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.recognitionCompletion?(nil)
                    self.recognitionCompletion = nil
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            }
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

        recognitionRequest?.append(buffer)
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
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionCompletion = nil
        engine.stop()
        removeTap()
        isRunning = false
        levels = Array(repeating: 0.15, count: Self.barCount)
    }

    /// Zastaví nahrávání a po dokončení rozpoznávání zavolá completion s přepsaným textem (nebo nil).
    func stopWithRecognitionResult(completion: @escaping (String?) -> Void) {
        guard isRunning else {
            completion(nil)
            return
        }
        recognitionCompletion = completion
        recognitionRequest?.endAudio()
        engine.stop()
        removeTap()
        tapInstalled = false
        isRunning = false
        levels = Array(repeating: 0.15, count: Self.barCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, let comp = self.recognitionCompletion else { return }
            comp(nil)
            self.recognitionCompletion = nil
            self.recognitionRequest = nil
            self.recognitionTask = nil
        }
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
