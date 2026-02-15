//
//  ClaudeAssistant.swift
//  SmartCane
//
//  Talks to the Anthropic Messages API with tool use for navigation commands.
//  Replaces Vapi — all voice I/O handled by VoiceManager.
//

import Foundation

enum AssistantAction {
    case navigateTo(destination: String)
    case stopNavigation
}

struct AssistantResponse {
    let text: String
    let action: AssistantAction?
}

class ClaudeAssistant {
    private let apiKey: String
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private var conversationHistory: [[String: Any]] = []

    private let systemPrompt = """
        You are a concise voice assistant for a smart cane that helps visually impaired users navigate. \
        Keep responses to 1-2 short sentences — they will be spoken aloud. \
        You receive sensor data about nearby obstacles (left/center/right distances) and navigation state. \
        Use the navigate_to tool when the user wants to go somewhere. \
        Use the stop_navigation tool when they want to stop navigating. \
        For general questions about surroundings, interpret the sensor data naturally.
        """

    private let tools: [[String: Any]] = [
        [
            "name": "navigate_to",
            "description": "Start GPS navigation to a destination address or place name",
            "input_schema": [
                "type": "object",
                "properties": [
                    "destination": [
                        "type": "string",
                        "description": "The destination address or place name"
                    ]
                ],
                "required": ["destination"]
            ]
        ],
        [
            "name": "stop_navigation",
            "description": "Stop the current GPS navigation",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
        ]
    ]

    init(apiKey: String) {
        self.apiKey = apiKey
        print("[ClaudeAssistant] Initialized with model: \(model)")
    }

    func sendMessage(
        _ text: String,
        sensorContext: String?,
        navState: String?,
        completion: @escaping (AssistantResponse?) -> Void
    ) {
        // Build user message with context
        var userContent = text
        if let sensor = sensorContext {
            userContent += "\n[Sensor data: \(sensor)]"
        }
        if let nav = navState {
            userContent += "\n[Navigation: \(nav)]"
        }

        conversationHistory.append(["role": "user", "content": userContent])

        // Keep history manageable (last 10 turns)
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": conversationHistory,
            "tools": tools
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            print("[ClaudeAssistant] Failed to serialize request")
            completion(nil)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("[ClaudeAssistant] Network error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else {
                print("[ClaudeAssistant] Failed to parse response")
                completion(nil)
                return
            }

            var spokenText = ""
            var action: AssistantAction?

            for block in content {
                let blockType = block["type"] as? String

                if blockType == "text", let text = block["text"] as? String {
                    spokenText = text
                }

                if blockType == "tool_use",
                   let name = block["name"] as? String,
                   let input = block["input"] as? [String: Any] {
                    switch name {
                    case "navigate_to":
                        if let dest = input["destination"] as? String {
                            action = .navigateTo(destination: dest)
                        }
                    case "stop_navigation":
                        action = .stopNavigation
                    default:
                        break
                    }
                }
            }

            // Add assistant response to history
            self?.conversationHistory.append(["role": "assistant", "content": spokenText])

            // If Claude used a tool but didn't provide text, generate a default
            if spokenText.isEmpty {
                switch action {
                case .navigateTo(let dest):
                    spokenText = "Starting navigation to \(dest)."
                case .stopNavigation:
                    spokenText = "Navigation stopped."
                case .none:
                    spokenText = "I'm not sure how to help with that."
                }
            }

            completion(AssistantResponse(text: spokenText, action: action))
        }.resume()
    }

    func clearHistory() {
        conversationHistory.removeAll()
    }
}
