//
//  GameControllerManager.swift
//  SmartCane
//
//  Reads a Nintendo Switch Joy-Con (or any MFi controller) paired via
//  iOS Settings.  Left stick X axis overrides autonomous steering.
//  Joystick centered → autonomous mode resumes.
//

import Foundation
import Combine
import GameController

@MainActor
class GameControllerManager: ObservableObject {
    /// nil = no override (autonomous), -1…+1 = manual steering
    @Published var overrideSteer: Float? = nil
    @Published var isConnected: Bool = false

    private let deadzone: Float = 0.15

    init() {
        // Pick up controllers already connected before launch
        if let controller = GCController.controllers().first {
            configureController(controller)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees we're on the main thread;
            // re-read the controllers list to avoid sending non-Sendable objects
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
            print("[GameController] Disconnected")
        }
    }

    private func configureController(_ controller: GCController) {
        isConnected = true
        print("[GameController] Connected: \(controller.vendorName ?? "Unknown")")

        guard let gamepad = controller.extendedGamepad else {
            print("[GameController] No extended gamepad profile — trying micro gamepad")
            // Joy-Con in single mode may present as microGamepad
            configureMicroGamepad(controller)
            return
        }

        gamepad.leftThumbstick.xAxis.valueChangedHandler = { [weak self] _, value in
            Task { @MainActor in
                self?.handleStickInput(value)
            }
        }
    }

    private func configureMicroGamepad(_ controller: GCController) {
        guard let micro = controller.microGamepad else {
            print("[GameController] No gamepad profile available")
            return
        }
        micro.dpad.xAxis.valueChangedHandler = { [weak self] _, value in
            Task { @MainActor in
                self?.handleStickInput(value)
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
