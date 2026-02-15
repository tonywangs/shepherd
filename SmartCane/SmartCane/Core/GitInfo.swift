//
//  GitInfo.swift
//  SmartCane
//
//  Simple helper to read git repository information
//  Note: Process API is macOS-only, so we provide build-time info instead
//

import Foundation

struct GitInfo {
    // These are set at build time - on iOS we can't run shell commands
    // In a real app, these would be populated by a build script

    static func getCurrentBranch() -> String {
        // TODO: Could be populated by Xcode build phase script
        return "feature/terrain-detection-cityscapes"
    }

    static func getLastCommitInfo() -> String {
        // TODO: Could be populated by Xcode build phase script
        return "b0eb5da - Terrain detection"
    }

    static func getLastCommitDate() -> String {
        return "2026-02-14"
    }
}
