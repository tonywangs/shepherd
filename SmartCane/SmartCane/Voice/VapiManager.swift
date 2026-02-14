//
//  VapiManager.swift
//  SmartCane
//
//  Wraps the Vapi iOS SDK for voice assistant integration.
//  Handles call lifecycle, live sensor injection via controlUrl,
//  and urgent spoken alerts.
//

import Foundation
import Combine
import Vapi

class VapiManager: ObservableObject {
    // MARK: - Published State

    @Published var isCallActive = false
    @Published var isMuted = false
    @Published var lastTranscript: String?
    @Published var callError: String?

    // MARK: - Private

    private var vapi: Vapi?
    private var callId: String?
    private var controlUrl: String?
    private var cancellables = Set<AnyCancellable>()

    // Vapi assistant configuration
    private let assistantId = "2c5e8893-65df-4bea-987f-84ea6a0f236f"

    // controlUrl base (Vapi's WebRTC control endpoint)
    private let controlUrlBase = "https://aws-us-west-2-production1-phone-call-websocket.vapi.ai"

    // Rate limiting for sensor updates
    private var lastSensorUpdateTime: Date = .distantPast
    private let sensorUpdateInterval: TimeInterval = 5.0  // seconds

    // Rate limiting for urgent alerts
    private var lastUrgentAlertTime: Date = .distantPast
    private let urgentAlertCooldown: TimeInterval = 3.0  // seconds

    // Shared URLSession for controlUrl requests
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    // MARK: - Initialization

    init(publicKey: String) {
        self.vapi = Vapi(publicKey: publicKey)
        subscribeToEvents()
        print("[Vapi] Manager initialized")
    }

    // MARK: - Call Lifecycle

    func startCall() {
        guard !isCallActive else {
            print("[Vapi] Call already active")
            return
        }

        callError = nil

        Task {
            do {
                guard let vapi = vapi else { return }

                print("[Vapi] Starting call with assistant: \(assistantId)")
                let response = try await vapi.start(assistantId: assistantId)

                // Store call ID and construct controlUrl
                self.callId = response.id
                self.controlUrl = "\(controlUrlBase)/\(response.id)/control"

                await MainActor.run {
                    self.isCallActive = true
                }

                print("[Vapi] Call started - ID: \(response.id)")
                print("[Vapi] controlUrl: \(self.controlUrl ?? "nil")")
            } catch {
                print("[Vapi] Failed to start call: \(error)")
                await MainActor.run {
                    self.callError = error.localizedDescription
                    self.isCallActive = false
                }
            }
        }
    }

    func stopCall() {
        guard isCallActive else { return }

        print("[Vapi] Stopping call")
        vapi?.stop()

        callId = nil
        controlUrl = nil
        isCallActive = false
        lastTranscript = nil
    }

    func toggleMute() {
        Task {
            do {
                let newMuteState = !isMuted
                try await vapi?.setMuted(newMuteState)
                await MainActor.run {
                    self.isMuted = newMuteState
                }
                print("[Vapi] Mute: \(newMuteState)")
            } catch {
                print("[Vapi] Mute toggle failed: \(error)")
            }
        }
    }

    // MARK: - Sensor Data Injection

    /// Send a compact sensor summary to the assistant as a system message.
    /// Throttled to one update per sensorUpdateInterval seconds.
    /// triggerResponseEnabled = false so the assistant doesn't speak after every update.
    func sendSensorUpdate(_ summary: String) {
        guard isCallActive, controlUrl != nil else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSensorUpdateTime) >= sensorUpdateInterval else { return }
        lastSensorUpdateTime = now

        let body: [String: Any] = [
            "type": "add-message",
            "message": [
                "role": "system",
                "content": summary
            ],
            "triggerResponseEnabled": false
        ]

        Task {
            await postToControlUrl(body)
        }

        print("[Vapi] Sensor update sent: \(summary)")
    }

    /// Send an urgent spoken alert that the assistant will immediately speak aloud.
    /// Cooldown prevents spamming.
    func sendUrgentAlert(_ message: String) {
        guard isCallActive, controlUrl != nil else { return }

        let now = Date()
        guard now.timeIntervalSince(lastUrgentAlertTime) >= urgentAlertCooldown else { return }
        lastUrgentAlertTime = now

        let body: [String: Any] = [
            "type": "say",
            "content": message,
            "endCallAfterSpoken": false
        ]

        Task {
            await postToControlUrl(body)
        }

        print("[Vapi] URGENT alert: \(message)")
    }

    /// Send a sensor update AND trigger the assistant to respond.
    /// Use sparingly - for important state changes the user should hear about.
    func sendSensorUpdateWithResponse(_ summary: String) {
        guard isCallActive, controlUrl != nil else { return }

        let body: [String: Any] = [
            "type": "add-message",
            "message": [
                "role": "system",
                "content": summary
            ],
            "triggerResponseEnabled": true
        ]

        Task {
            await postToControlUrl(body)
        }

        print("[Vapi] Sensor update (with response): \(summary)")
    }

    // MARK: - controlUrl HTTP

    private func postToControlUrl(_ body: [String: Any]) async {
        guard let controlUrl = controlUrl,
              let url = URL(string: controlUrl) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await urlSession.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                print("[Vapi] controlUrl POST failed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[Vapi] controlUrl POST error: \(error.localizedDescription)")
        }
    }

    // MARK: - Event Subscriptions

    private func subscribeToEvents() {
        guard let vapi = vapi else { return }

        vapi.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleEvent(_ event: Vapi.Event) {
        switch event {
        case .callDidStart:
            print("[Vapi] Event: Call started")
            isCallActive = true

        case .callDidEnd:
            print("[Vapi] Event: Call ended")
            isCallActive = false
            callId = nil
            controlUrl = nil

        case .transcript(let transcript):
            print("[Vapi] Transcript: \(transcript)")
            lastTranscript = "\(transcript)"

        case .error(let error):
            print("[Vapi] Error: \(error)")
            callError = error.localizedDescription

        default:
            break
        }
    }
}
