//
//  NavigationView.swift
//  SmartCane
//
//  Navigation input sheet and HUD overlay for GPS turn-by-turn guidance
//

import SwiftUI

// MARK: - Navigation Input Sheet

struct NavigationInputSheet: View {
    @ObservedObject var navigationManager: NavigationManager
    @Binding var isPresented: Bool
    var voiceManager: VoiceManager?
    @State private var destination: String = ""
    @State private var isListeningForDest: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.cyan)

                    Text("Where to?")
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)

                    Text("Enter or speak a destination")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)

                HStack(spacing: 8) {
                    TextField("e.g. Tresidder Union, Stanford", text: $destination)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .focused($isTextFieldFocused)
                        .submitLabel(.go)
                        .onSubmit { startNavigation() }

                    Button(action: toggleVoiceInput) {
                        Image(systemName: isListeningForDest ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundColor(isListeningForDest ? .green : .cyan)
                            .frame(width: 50, height: 50)
                            .background(isListeningForDest ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(12)
                    }
                }

                Button(action: startNavigation) {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                        Text("Navigate")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(destination.isEmpty ? Color.gray : Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(destination.isEmpty)

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear { isTextFieldFocused = true }
    }

    private func startNavigation() {
        guard !destination.isEmpty else { return }
        print("[NavigationSheet] Navigate tapped with destination: '\(destination)'")
        navigationManager.startNavigation(to: destination)
        isPresented = false
    }

    private func toggleVoiceInput() {
        if isListeningForDest {
            voiceManager?.stopListening()
            isListeningForDest = false
        } else {
            isTextFieldFocused = false
            isListeningForDest = true
            voiceManager?.startListening { [self] text in
                DispatchQueue.main.async {
                    self.destination = text
                    self.isListeningForDest = false
                }
            }
        }
    }
}

// MARK: - Navigation HUD

struct NavigationHUD: View {
    @ObservedObject var navigationManager: NavigationManager

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                // State-dependent content
                switch navigationManager.state {
                case .planning:
                    planningView

                case .navigating:
                    navigatingView

                case .arriving:
                    arrivingView

                case .arrived:
                    arrivedView

                case .error(let message):
                    errorView(message)

                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(hudBorderColor, lineWidth: 2)
                    )
            )
            .shadow(color: hudBorderColor.opacity(0.3), radius: 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Sub-views

    private var planningView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
            Text("Planning route...")
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
        }
    }

    private var navigatingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current instruction
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: maneuverIcon)
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(navigationManager.currentGuidance?.currentInstruction ?? "Continue")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 16) {
                        Label(formatDistance(navigationManager.distanceToNextManeuver), systemImage: "arrow.turn.up.right")
                            .font(.caption)
                            .foregroundColor(.cyan)

                        Label(formatDistance(navigationManager.distanceToDestination), systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                stopButton
            }

            // Infrastructure warnings
            if let guidance = navigationManager.currentGuidance,
               !guidance.nearbyInfrastructure.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(Set(guidance.nearbyInfrastructure.map(\.type.rawValue))), id: \.self) { type in
                        Label(type.capitalized, systemImage: infrastructureIcon(for: type))
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.3))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var arrivingView: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading) {
                Text("Approaching destination")
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                Text("\(Int(navigationManager.distanceToDestination))m remaining")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Spacer()
            stopButton
        }
    }

    private var arrivedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            Text("You have arrived!")
                .font(.subheadline)
                .bold()
                .foregroundColor(.green)
            Spacer()
            Button("Done") {
                navigationManager.stopNavigation()
            }
            .font(.caption)
            .bold()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.3))
            .foregroundColor(.green)
            .cornerRadius(8)
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") {
                navigationManager.stopNavigation()
            }
            .font(.caption)
            .bold()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.3))
            .foregroundColor(.red)
            .cornerRadius(8)
        }
    }

    private var stopButton: some View {
        Button {
            navigationManager.stopNavigation()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(.red.opacity(0.8))
        }
    }

    // MARK: - Helpers

    private var hudBorderColor: Color {
        switch navigationManager.state {
        case .navigating: return .cyan
        case .arriving: return .green
        case .arrived: return .green
        case .error: return .red
        default: return .gray
        }
    }

    private var maneuverIcon: String {
        guard let route = navigationManager.currentRoute,
              navigationManager.currentStepIndex < route.steps.count else {
            return "arrow.up"
        }
        let maneuver = route.steps[navigationManager.currentStepIndex].maneuver
        switch maneuver {
        case .turnLeft, .turnSharpLeft: return "arrow.turn.up.left"
        case .turnRight, .turnSharpRight: return "arrow.turn.up.right"
        case .turnSlightLeft: return "arrow.up.left"
        case .turnSlightRight: return "arrow.up.right"
        case .uturnLeft, .uturnRight: return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }

    private func infrastructureIcon(for type: String) -> String {
        switch type {
        case "crosswalk": return "figure.walk"
        case "trafficSignal": return "light.beacon.max"
        case "stopSign": return "hand.raised.fill"
        default: return "exclamationmark.triangle"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters))m"
    }
}
