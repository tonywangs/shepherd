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

        // 1. Check speech recognition is available and authorized
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[Voice] Speech recognizer unavailable")
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("[Voice] Speech recognition not authorized (status: \(SFSpeechRecognizer.authorizationStatus().rawValue))")
            return
        }

        // 2. Configure audio session for recording
        configureAudioSession()

        // 3. Clean up any previous session
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // 4. Set up audio engine and validate format
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("[Voice] Invalid audio format (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)) — mic may be unavailable")
            return
        }

        // 5. Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // 6. Install audio tap FIRST (before recognition task, so audio is flowing)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // 7. Start audio engine BEFORE recognition task
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[Voice] Failed to start audio engine: \(error)")
            inputNode.removeTap(onBus: 0)
            return
        }

        // 8. Store references now that setup succeeded
        self.audioEngine = engine
        self.recognitionRequest = request
        isListening = true
        print("[Voice] Started listening...")

        // 9. Start recognition task LAST (audio is already flowing)
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result = result, result.isFinal {
                let transcription = result.bestTranscription.formattedString
                print("[Voice] Final: \(transcription)")
                completion(transcription)
            }

            if error != nil || (result?.isFinal == true) {
                engine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                DispatchQueue.main.async {
                    self.isListening = false
                }
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        print("[Voice] Stopped listening")
    }

    // MARK: - Navigation Speech

    func speakNavigation(_ text: String, priority: Bool = false) {
        speak(text, priority: priority)
    }

    // MARK: - Command Processing

    func processVoiceCommand(_ command: String, navigationManager: NavigationManager? = nil) {
        let lowercased = command.lowercased()

        if lowercased.contains("navigate to") || lowercased.contains("take me to") {
            let destination = lowercased
                .replacingOccurrences(of: "navigate to", with: "")
                .replacingOccurrences(of: "take me to", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let nav = navigationManager, !destination.isEmpty {
                nav.startNavigation(to: destination)
            } else {
                speak("Navigating to \(destination)")
            }

        } else if lowercased.contains("stop nav") || lowercased.contains("stop navigation") {
            if let nav = navigationManager, nav.state.isActive {
                nav.stopNavigation()
            } else {
                speak("No active navigation to stop")
            }

        } else if lowercased.contains("stop") {
            speak("Stopping")

        } else if lowercased.contains("resume") {
            speak("Resuming")

        } else {
            speak("Command not recognized")
        }
    }
}
