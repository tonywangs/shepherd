//
//  SmartCaneApp.swift
//  SmartCane
//
//  Hackathon MVP - Lateral Steering Smart Cane
//

import SwiftUI

@main
struct SmartCaneApp: App {
    @StateObject private var espBluetooth = ESPBluetoothManager()
    @StateObject private var caneController = SmartCaneController()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(espBluetooth: espBluetooth, caneController: caneController)
                    .tabItem {
                        Label("Navigation", systemImage: "location.fill")
                    }

                BluetoothPairingView(ble: espBluetooth, controller: caneController)
                    .tabItem {
                        Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                    }
            }
            .onAppear {
                // Initialize after views are ready
                caneController.initialize(espBluetooth: espBluetooth)
            }
        }
    }
}
