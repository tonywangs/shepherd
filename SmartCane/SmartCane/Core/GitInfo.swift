//
//  GitInfo.swift
//  SmartCane
//
//  Simple helper to read local git repository information
//

import Foundation

struct GitInfo {
    static func getCurrentBranch() -> String {
        return runGitCommand(["rev-parse", "--abbrev-ref", "HEAD"]) ?? "unknown"
    }

    static func getLastCommitInfo() -> String {
        return runGitCommand(["log", "-1", "--format=%h - %cr", "--date=relative"]) ?? "no commits"
    }

    static func getLastCommitDate() -> String {
        return runGitCommand(["log", "-1", "--format=%cd", "--date=short"]) ?? "unknown"
    }

    private static func runGitCommand(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        // Set working directory to project root (3 levels up from SmartCane app bundle)
        if let bundlePath = Bundle.main.bundlePath as String? {
            let projectPath = (bundlePath as NSString)
                .deletingLastPathComponent
                .deletingLastPathComponent
                .deletingLastPathComponent
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        }

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("[GitInfo] Failed to run git command: \(error)")
        }

        return nil
    }
}
