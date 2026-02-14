//
//  VoiceManager.swift
//  SmartCane
//
//  Voice input (Speech Recognition) and output (AVSpeechSynthesizer)
//

import Foundation
import AVFoundation
import Speech
import Combine

class VoiceManager: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    @Published var isListening = false
    private var isAudioSessionConfigured = false

    override init() {
        super.init()

        // Request speech recognition permissions (async to avoid blocking)
        DispatchQueue.global(qos: .background).async {
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    print("[Voice] Speech recognition authorized")
                case .denied:
                    print("[Voice] Speech recognition denied")
                case .restricted:
                    print("[Voice] Speech recognition restricted")
                case .notDetermined:
                    print("[Voice] Speech recognition not determined")
                @unknown default:
                    print("[Voice] Speech recognition unknown status")
                }
            }
        }

        // Audio session will be configured lazily on first use
        print("[Voice] Initialized (audio session deferred)")
    }

    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionConfigured = true
            print("[Voice] Audio session configured")
        } catch {
            print("[Voice] Failed to configure audio session: \(error)")
            print("[Voice] Continuing without audio session configuration")
            // Don't crash - allow app to continue without voice
        }
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String, priority: Bool = false) {
        // Configure audio session on first use (lazy initialization)
        configureAudioSession()

        if priority {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5  // Slightly slower for clarity
        utterance.volume = 1.0

        print("[Voice] Speaking: \(text)")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Speech-to-Text

    func startListening(completion: @escaping (String) -> Void) {
        guard !isListening else { return }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print("[Voice] Heard: \(transcription)")

                isFinal = result.isFinal

                if isFinal {
                    completion(transcription)
                }
            }

            if error != nil || isFinal {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                self?.isListening = false
            }
        }

        // Configure audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
            print("[Voice] Started listening...")
        } catch {
            print("[Voice] Error starting audio engine: \(error)")
        }
    }

    func stopListening() {
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        isListening = false
        print("[Voice] Stopped listening")
    }

    // MARK: - Command Processing (Phase 3)

    func processVoiceCommand(_ command: String) {
        let lowercased = command.lowercased()

        if lowercased.contains("navigate to") || lowercased.contains("take me to") {
            // Extract destination
            let destination = lowercased
                .replacingOccurrences(of: "navigate to", with: "")
                .replacingOccurrences(of: "take me to", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            speak("Navigating to \(destination)")
            // TODO: Integrate with GPS navigation (Phase 3)

        } else if lowercased.contains("stop") {
            speak("Stopping navigation")
            // TODO: Stop navigation

        } else if lowercased.contains("resume") {
            speak("Resuming navigation")
            // TODO: Resume navigation

        } else {
            speak("Command not recognized")
        }
    }
}
