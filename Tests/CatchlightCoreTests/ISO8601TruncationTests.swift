//
//  ISO8601TruncationTests.swift
//  CatchlightCoreTests — 2026-07-01 mid-point review remediation
//
//  Pins the two properties the whole "truncate everywhere" defence rests on:
//
//    1. IDEMPOTENCY — truncating an already-truncated Date returns it unchanged.
//       Every synced model re-truncates in `didSet`/decode, so a non-idempotent
//       truncation silently shifts stored values on re-assignment.
//    2. WIRE FIXED POINT — a truncated Date survives the canonical
//       string→parse→truncate round trip byte-identically. This is what makes a
//       no-op sync resolve to `.noChange` instead of a phantom conflict.
//
//  The previous floor-based truncation (`.rounded(.down)`) violated BOTH in
//  specific floating-point binades — empirically ~20% of timestamps in the
//  2038–2039 band and most pre-1970 dates — while contemporary dates happened
//  to be safe, which is why the defect stayed invisible. The ranges below
//  deliberately sweep the failing binades so a regression to floor (or any
//  other non-fixed-point arithmetic) fails loudly.
//

import XCTest
@testable import CatchlightCore

final class ISO8601TruncationTests: XCTestCase {

    /// Deterministic sample of epoch seconds: strided coarse sweep 1960→2050
    /// plus a fine sweep of the 2038–2039 binade boundary that broke floor.
    private static let sampleSeconds: [Double] = {
        var samples: [Double] = []
        // Coarse: 1960 → 2050 in ~11.6-day prime steps.
        samples.append(contentsOf: stride(from: -315_619_200.0, to: 2_524_608_000.0, by: 1_000_003.0))
        // Fine: the 2038–2039 band (t*1000 approaching 2^41), ~2.2-hour prime steps.
        samples.append(contentsOf: stride(from: 2_145_000_000.0, to: 2_200_000_000.0, by: 7_919.0))
        return samples
    }()

    /// Sub-second fractions chosen to land on awkward Double representations.
    private static let fractions: [Double] = [
        0.0, 0.001, 0.4995, 0.686_123_456, 0.999_999_9, 0.123_456_789, 0.000_499_9
    ]

    func testTruncation_isIdempotent_acrossBinades() {
        for base in Self.sampleSeconds {
            for frac in Self.fractions {
                let d = Date(timeIntervalSince1970: base + frac)
                let once = ISO8601.truncateToMilliseconds(d)
                let twice = ISO8601.truncateToMilliseconds(once)
                XCTAssertEqual(
                    twice, once,
                    "re-truncating \(d.timeIntervalSince1970) moved it "
                    + "(\(once.timeIntervalSince1970) → \(twice.timeIntervalSince1970))"
                )
            }
        }
    }

    func testTruncation_isFixedPointOfWireCodec() {
        for base in Self.sampleSeconds {
            for frac in Self.fractions {
                let truncated = ISO8601.truncateToMilliseconds(Date(timeIntervalSince1970: base + frac))
                let wire = ISO8601.string(from: truncated)
                guard let parsed = ISO8601.date(from: wire) else {
                    XCTFail("canonical string failed to parse: \(wire)")
                    continue
                }
                let reloaded = ISO8601.truncateToMilliseconds(parsed)
                XCTAssertEqual(
                    reloaded, truncated,
                    "wire round trip drifted for \(wire): "
                    + "\(truncated.timeIntervalSince1970) → \(reloaded.timeIntervalSince1970)"
                )
            }
        }
    }

    /// The exact failure class floor exhibited: the 2038–2039 band, where
    /// `floor(x*1000)/1000` re-truncated 1 ms backwards for ~20% of values.
    /// Kept as a separate named test so a regression points straight here.
    func testTruncation_2038Band_doesNotWalkBackwards() {
        for base in stride(from: 2_150_000_000.0, to: 2_199_000_000.0, by: 997.0) {
            let d = Date(timeIntervalSince1970: base + 0.686)
            let once = ISO8601.truncateToMilliseconds(d)
            XCTAssertEqual(ISO8601.truncateToMilliseconds(once), once)
        }
    }
}
