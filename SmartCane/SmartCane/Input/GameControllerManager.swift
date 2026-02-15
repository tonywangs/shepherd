//
//  GameControllerManager.swift
//  SmartCane
//
//  Reads a Nintendo Switch Joy-Con (or any MFi controller) paired via
//  iOS Settings.  Left stick X axis overrides autonomous steering.
//  Any button = emergency kill. Joystick centered → autonomous mode resumes.
//

import Foundation
import Combine
import GameController

@MainActor
class GameControllerManager: ObservableObject {
    /// nil = no override (autonomous), -1…+1 = manual steering
    @Published var overrideSteer: Float? = nil
    /// true = emergency stop, forces motor to 0
    @Published var killMotor: Bool = false
    @Published var isConnected: Bool = false

    private let deadzone: Float = 0.15

    init() {
        if let controller = GCController.controllers().first {
            configureController(controller)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let controller = GCController.controllers().last else { return }
                self.configureController(controller)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isConnected = false
            self.overrideSteer = nil
            self.killMotor = false
            print("[GameController] Disconnected")
        }
    }

    private func configureController(_ controller: GCController) {
        isConnected = true
        print("[GameController] Connected: \(controller.vendorName ?? "Unknown")")

        // Log available profiles
        if controller.extendedGamepad != nil { print("[GameController] Profile: extendedGamepad") }
        if controller.microGamepad != nil { print("[GameController] Profile: microGamepad") }

        // --- Stick input: use Y axis (Joy-Con held sideways, so physical left/right = Y axis) ---
        if let gamepad = controller.extendedGamepad {
            gamepad.leftThumbstick.yAxis.valueChangedHandler = { [weak self] _, value in
                Task { @MainActor in self?.handleStickInput(value) }
            }
        } else if let micro = controller.microGamepad {
            micro.dpad.yAxis.valueChangedHandler = { [weak self] _, value in
                Task { @MainActor in self?.handleStickInput(value) }
            }
        }

        // --- Kill button: attach to EVERY button via physicalInputProfile ---
        // This covers face buttons, shoulder buttons, triggers, SL/SR — regardless of profile
        let profile = controller.physicalInputProfile
        let buttonNames = profile.buttons.keys.sorted()
        print("[GameController] Available buttons: \(buttonNames)")

        for (name, button) in profile.buttons {
            // Skip directional inputs — those are for steering, not kill
            if name.contains("Direction") { continue }

            button.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    if pressed {
                        print("[GameController] KILL pressed: \(name)")
                    }
                    self?.killMotor = pressed
                    if pressed { self?.overrideSteer = 0 }
                }
            }
        }
    }

    private func handleStickInput(_ value: Float) {
        if abs(value) > deadzone {
            overrideSteer = value
        } else {
            overrideSteer = nil
        }
    }
}
