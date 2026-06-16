//
//  SeedTakesTests.swift
//  CatchlightCoreTests
//
//  Seed Takes onboarding data (UX Session Decisions §12).
//

import XCTest
@testable import CatchlightCore

final class SeedTakesTests: XCTestCase {
    func testFiveSeedTakes() {
        XCTAssertEqual(SeedTakes.make().count, 5)
    }

    func testAllFlaggedSeeded() {
        XCTAssertTrue(SeedTakes.make().allSatisfy { $0.isSeeded })
    }

    func testQuadrantCoverage() {
        let s = SeedTakes.make()
        XCTAssertTrue(s[0].isNote)
        XCTAssertTrue(s[1].isTask)
        XCTAssertNotNil(s[2].timeReminder)
        XCTAssertTrue(s[3].isObie)
    }

    func testExactlyOneObie() {
        XCTAssertEqual(SeedTakes.make().filter { $0.isObie }.count, 1)
    }

    func testChronologicalOrder() {
        // Ascending: Note (oldest) → Delete (newest). Under the default TakeSort
        // ("Oldest first") this is also the top→bottom on-screen order.
        let s = SeedTakes.make()
        XCTAssertTrue(zip(s, s.dropFirst()).allSatisfy { $0.createdAt <= $1.createdAt })
    }

    func testSeedTakesRoundTrip() throws {
        for seed in SeedTakes.make() {
            let decoded = try PlatformJSON.decode(Take.self, from: try PlatformJSON.encode(seed))
            XCTAssertEqual(decoded, seed)
        }
    }
}
