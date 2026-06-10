//
//  CloudFolder.swift
//  CatchlightCore
//
//  Abstraction over the user's chosen cloud folder. The sync engine is
//  cloud-AGNOSTIC: it only knows how to list, read, write, and delete named files.
//  The iOS app provides the real implementation over the Files API
//  (`UIDocumentPickerViewController` for selection, security-scoped bookmarks +
//  `FileManager` for ongoing access — see Catchlight/Sync/FileCloudFolder.swift).
//  The in-memory implementation here lets the entire sync engine be tested with no
//  file system and no network (Phase 5 brief §12 "Mock the file system").
//
//  Per Encryption Architecture §11.3 the folder contains only:
//    catchlight-account-metadata.json   (plaintext: salt, creation date, schema)
//    catchlight-manifest.json           (HMAC-signed index)
//    {uuid}.clk                         (encrypted Take blobs)
//    catchlight-device-request-*.json   (transient handshake files)
//

import Foundation

public protocol CloudFolder: AnyObject {
    func listFiles() throws -> [String]
    func read(_ name: String) throws -> Data?
    func write(_ data: Data, to name: String) throws
    /// Atomic write: write to a temp name then rename, so a crash never leaves a
    /// partially written manifest (Phase 5 brief §7.4 step 5).
    func writeAtomically(_ data: Data, to name: String) throws
    func delete(_ name: String) throws
    /// Secure delete: overwrite with random bytes of equal length, then remove
    /// (Encryption Architecture §6 step 13, Phase 5 brief §7.7).
    func secureDelete(_ name: String) throws
}

public extension CloudFolder {
    func clkFiles() throws -> [String] { try listFiles().filter { $0.hasSuffix(".clk") } }

    // NOTE (2026-06-10): there is deliberately NO default implementation of
    // `writeAtomically`. The previous default wrote a `.tmp` file and then did a
    // SECOND full non-atomic write to the real name — it never renamed, so a
    // crash mid-write left exactly the torn manifest the method exists to
    // prevent, and any conformer silently inherited that bug while tests
    // validated semantics production didn't have. Every conformer must provide
    // real atomicity for its medium (temp-write + rename on file systems;
    // trivial single assignment in memory).

    func secureDelete(_ name: String) throws {
        if let existing = try read(name) {
            let randomReplacement = SecureRandom.bytes(existing.count)
            try write(randomReplacement, to: name)
        }
        try delete(name)
    }
}

/// In-memory `CloudFolder` for tests. A dictionary standing in for the folder.
public final class InMemoryCloudFolder: CloudFolder {
    public private(set) var files: [String: Data] = [:]
    /// Records secure-delete overwrites so tests can assert files were scrubbed
    /// before deletion (Phase 5 brief §12.5).
    public private(set) var secureDeleteOverwroteBytes: [String: Int] = [:]

    public init() {}

    public func listFiles() throws -> [String] { Array(files.keys).sorted() }
    public func read(_ name: String) throws -> Data? { files[name] }
    public func write(_ data: Data, to name: String) throws { files[name] = data }
    /// A dictionary assignment is inherently atomic for this medium.
    public func writeAtomically(_ data: Data, to name: String) throws { files[name] = data }
    public func delete(_ name: String) throws { files[name] = nil }

    public func secureDelete(_ name: String) throws {
        if let existing = files[name] {
            let replacement = SecureRandom.bytes(existing.count)
            files[name] = replacement
            secureDeleteOverwroteBytes[name] = replacement.count
        }
        files[name] = nil
    }
}
