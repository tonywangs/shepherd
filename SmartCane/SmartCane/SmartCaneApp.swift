//
//  SmartCaneApp.swift
//  SmartCane
//
//  Hackathon MVP - Lateral Steering Smart Cane
//

import SwiftUI

@main
struct SmartCaneApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("Navigation", systemImage: "location.fill")
                    }

                BluetoothPairingView()
                    .tabItem {
                        Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                    }
            }
        }
    }
}
