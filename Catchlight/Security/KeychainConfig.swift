//
//  KeychainConfig.swift
//  Catchlight (iOS app target)
//
//  Single source of truth for the Keychain access group shared by
//  MasterKeyKeychain, MnemonicKeychain, PINService, and any future extension.
//  Previously this literal was duplicated across several files (and two views),
//  which risked silent divergence if the development team ever changes.
//
//  Must EXACTLY match the resolved entitlement string in the signed binary:
//  `$(AppIdentifierPrefix)com.considus.catchlight` resolves at build time to
//  `<TEAM_ID>.com.considus.catchlight`. That substitution happens only for
//  plist/entitlements files, never in Swift source, so the resolved literal is
//  hardcoded here. Team prefix YTPP9HU9F9 = Mark Stradling (project.yml
//  DEVELOPMENT_TEAM). If the team changes, update this constant AND project.yml.
//

import Foundation

public enum KeychainConfig {
    /// Resolved keychain access group for all Catchlight secret items.
    public static let accessGroup = "YTPP9HU9F9.com.considus.catchlight"

    /// Keychain service name shared by all Catchlight secret items.
    public static let service = "com.considus.catchlight"
}
