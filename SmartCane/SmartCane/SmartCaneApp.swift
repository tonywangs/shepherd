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

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(espBluetooth: espBluetooth)
                    .tabItem {
                        Label("Navigation", systemImage: "location.fill")
                    }

                BluetoothPairingView(ble: espBluetooth)
                    .tabItem {
                        Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                    }
            }
        }
    }
}
