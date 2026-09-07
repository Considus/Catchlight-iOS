//
//  PhraseProbe.swift — TEMPORARY DIAGNOSTIC, DO NOT SHIP
//
//  Established: the phrase IS present (authenticated read returned 12 words), but
//  MnemonicKeychain.exists() reports absent. exists() uses
//  kSecUseAuthenticationUISkip and treats anything but errSecSuccess /
//  errSecInteractionNotAllowed as missing; this device answers errSecItemNotFound
//  (-25300) when it cannot evaluate an access control without UI.
//
//  This probe asks ONLY the question that remains: which existence check sees the
//  item WITHOUT prompting? 0 or -25308 = sees it. -25300 = blind.
//
import Foundation
import Security

enum PhraseProbe {
    static func run() -> String {
        let cfg = MnemonicKeychain.configuration
        let ident: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     cfg.service,
            kSecAttrAccount as String:     cfg.account,
            kSecAttrAccessGroup as String: cfg.accessGroup,
            kSecMatchLimit as String:      kSecMatchLimitOne
        ]
        func st(_ q: [String: Any]) -> Int32 { SecItemCopyMatching(q as CFDictionary, nil) }

        var a = ident; a[kSecReturnAttributes as String] = true
        var b = ident; b[kSecReturnAttributes as String] = true
        b[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        return "A=\(st(a)) B=\(st(b)) C=\(st(ident)) OLD=\(MnemonicKeychain.exists())"
    }
}
