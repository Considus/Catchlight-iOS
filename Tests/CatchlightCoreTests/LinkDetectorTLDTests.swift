//
//  LinkDetectorTLDTests.swift
//  CatchlightCoreTests
//
//  The IANA TLD list and the casing gate (owner, 2026-09-12).
//
//  🚨 These exist because the hand-curated 53-TLD set failed in the field and
//  nothing in the suite noticed. The owner pasted a real reference list of 51
//  sites into a Take; three did not link. The fixtures below ARE that list, so
//  a regression is measured against what he actually types rather than against
//  cases we invented.
//

import XCTest
@testable import CatchlightCore

final class LinkDetectorTLDTests: XCTestCase {

    private func links(_ text: String) -> [String] {
        LinkDetector.detect(in: text).map { String(text[$0.range]) }
    }

    private func linksWholeString(_ text: String) -> Bool {
        links(text) == [text]
    }

    // MARK: - The reported fault

    /// The three that failed on device. All are gTLDs created after 2013, which
    /// `NSDataDetector` does not know and the old curated set did not list.
    func testTheThreeThatFailedInTheOwnersListNowLink() {
        for site in ["cleanup.pictures", "radio.garden", "apinex.bond"] {
            XCTAssertTrue(linksWholeString(site), "\(site) must link")
        }
    }

    /// 🚨 The regression guard that matters most. These three linked ONLY because
    /// of the old curated list — Apple's detector misses `.app` and `.sh` — so a
    /// mistake in replacing that list would silently break working links.
    func testDomainsThatDependOnOurListStillLink() {
        for site in ["squoosh.app", "consensus.app", "carbon.now.sh"] {
            XCTAssertTrue(linksWholeString(site), "\(site) must still link")
        }
    }

    /// The owner's full reference list, every entry, in one assertion.
    func testEveryEntryInTheOwnersReferenceListLinks() {
        let sites = [
            "unpaywall.org", "openlibrary.org", "doaj.org", "alternativeto.net",
            "justwatch.com", "archive.org", "gutenberg.org", "openstax.org",
            "openculture.com", "wolframalpha.com", "photopea.com", "squoosh.app",
            "remove.bg", "cleanup.pictures", "unscreen.com", "carbon.now.sh",
            "ray.so", "shots.so", "smartmockups.com", "haveibeenpwned.com",
            "virustotal.com", "privnote.com", "temp-mail.org", "file.io",
            "archive.ph", "similarsites.com", "radio.garden", "everynoise.com",
            "tunefind.com", "musicforprogramming.net", "mynoise.net",
            "coffitivity.com", "elicit.org", "consensus.app", "connectedpapers.com",
            "semanticscholar.org", "scispace.com", "summarize.tech", "phind.com",
            "regex101.com", "codebeautify.org", "jsonformatter.org",
            "explainshell.com", "raindrop.io", "downdetector.com", "tineye.com",
            "fast.com", "smallpdf.com", "ilovepdf.com", "10minutemail.com",
            "apinex.bond",
        ]
        let failures = sites.filter { !linksWholeString($0) }
        XCTAssertTrue(failures.isEmpty, "these did not link: \(failures)")
    }

    // MARK: - Gate (a): filename lookalikes

    /// ⚠️ The dangerous direction. Adopting 1,434 TLDs wholesale would turn
    /// ordinary filenames into links, which is worse than a missing link because
    /// it fires on text the user never meant as a URL.
    func testFilenameLookalikeTLDsAreNeverLinked() {
        for name in ["readme.md", "notes.md", "archive.zip", "clip.mov", "Thing.java"] {
            XCTAssertEqual(links(name), [], "\(name) must stay inert")
        }
    }

    /// The other half of that decision, recorded so it is not "tidied" later:
    /// these three are file extensions too and are KEPT, being real domains.
    func testExtensionLookalikesThatAreRealDomainsAreKept() {
        for tld in ["app", "ai", "sh"] {
            XCTAssertTrue(TLDList.all.contains(tld), ".\(tld) must remain linkable")
        }
    }

    func testExcludedTLDsAreAbsentFromTheGeneratedList() {
        for tld in ["md", "zip", "mov", "java"] {
            XCTAssertFalse(TLDList.all.contains(tld), ".\(tld) must be excluded")
        }
    }

    // MARK: - Gate (b): casing

    /// 🚨 The prose bug. A missing space after a full stop is a common typo, and
    /// `.it` and `.no` are Italy and Norway, so "home.It" was becoming a link
    /// inside ordinary sentences.
    func testMissingSpaceAfterAFullStopDoesNotLink() {
        XCTAssertEqual(links("I went home.It was late"), [])
        XCTAssertEqual(links("Call Bob.No answer"), [])
        XCTAssertEqual(links("Finished.Invoice tomorrow"), [])
    }

    /// iOS auto-capitalises the first letter when a URL starts a line, so this
    /// shape is common and must keep working.
    func testAutoCapitalisedFirstLetterStillLinks() {
        XCTAssertTrue(linksWholeString("Considus.app"))
        XCTAssertTrue(linksWholeString("Squoosh.app"))
    }

    /// The deliberate exception: an all-caps domain is someone shouting a URL.
    func testAllCapsDomainStillLinks() {
        XCTAssertTrue(linksWholeString("SQUOOSH.APP"))
        XCTAssertTrue(linksWholeString("CATCHLIGHT.APP"))
    }

    func testCasingGateInIsolation() {
        XCTAssertTrue(LinkDetector.casingAllowsLink(match: "considus.com", tld: "com"))
        XCTAssertTrue(LinkDetector.casingAllowsLink(match: "Considus.app", tld: "app"))
        XCTAssertTrue(LinkDetector.casingAllowsLink(match: "SQUOOSH.APP", tld: "APP"))
        XCTAssertFalse(LinkDetector.casingAllowsLink(match: "home.It", tld: "It"))
        XCTAssertFalse(LinkDetector.casingAllowsLink(match: "Bob.No", tld: "No"))
    }

    // MARK: - The list itself

    func testGeneratedListIsPlausiblyComplete() {
        XCTAssertGreaterThan(TLDList.all.count, 1_000,
                             "a truncated list would silently stop linking most domains")
        XCTAssertFalse(TLDList.all.contains("wibble"))
        XCTAssertFalse(TLDList.all.contains(""))
    }

    /// Everything in the list is lower case, which gate (b) relies on: the
    /// lookup lowercases the matched TLD and expects to find it as written.
    func testGeneratedListIsAllLowercase() {
        let wrong = TLDList.all.filter { $0 != $0.lowercased() }
        XCTAssertTrue(wrong.isEmpty, "non-lowercase entries: \(wrong)")
    }

    func testVersionStampIsPresentAndPlausible() {
        XCTAssertEqual(TLDList.ianaVersion.count, 10,
                       "IANA stamps versions as YYYYMMDDNN")
        XCTAssertTrue(TLDList.ianaVersion.allSatisfy(\.isNumber))
    }

    // MARK: - Unchanged behaviour

    func testSchemedAndEmailBehaviourIsUnchanged() {
        XCTAssertEqual(links("see https://considus.com/x now"), ["https://considus.com/x"])
        XCTAssertEqual(LinkDetector.detect(in: "bob@example.com").first?.url.scheme, "mailto")
        XCTAssertEqual(links("Mr.Smith called"), [])
        XCTAssertEqual(links("e.g. later"), [])
    }
}
