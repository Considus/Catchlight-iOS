//
//  JailbreakDetector.swift
//  Catchlight (iOS app target)
//
//  Basic jailbreak detection (Encryption Architecture §14, Phase 5 brief §5.11).
//
//  On detection the app shows a PERSISTENT, NON-BLOCKING warning. It does NOT
//  prevent use — this is a transparency obligation, not a gating mechanism. A
//  jailbroken device weakens the Keychain/Secure Enclave protections the app's
//  security relies on, and the user deserves to know.
//

import Foundation

public enum JailbreakDetector {

    public static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false   // never flag the Simulator
        #else
        let paths = ["/Applications/Cydia.app", "/usr/bin/ssh",
                     "/private/var/lib/apt", "/usr/sbin/sshd"]
        if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        if canWriteOutsideSandbox() { return true }
        return false
        #endif
    }

    /// Attempts to write outside the app sandbox; success indicates a jailbreak.
    private static func canWriteOutsideSandbox() -> Bool {
        let probe = "/private/catchlight-jb-probe.txt"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
    }

    public static let warningMessage =
        "Catchlight's security depends on iOS's built-in protections. This device " +
        "appears to have been modified, which may reduce those protections. Your " +
        "data may be at greater risk than on an unmodified device."
}
