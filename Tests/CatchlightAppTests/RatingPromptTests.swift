//
//  RatingPromptTests.swift
//  CatchlightAppTests
//
//  When the app asks for an App Store rating (owner 2026-10-06): only after a finished
//  checklist or a seventh day of writing, never in the first three days, never in the
//  read-only lapse, and at most once per version and per 120 days.
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

private final class QuietCenter: NotificationScheduling {
    func add(_ request: UNNotificationRequest) {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}

@MainActor
final class RatingPromptTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    /// 2026-10-06 12:00 London, plus `days` days.
    private func day(_ days: Int, hour: Int = 12) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour))!
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    private func checklist(_ ticked: [Bool], createdAt: Date = Date()) -> Take {
        Take(createdAt: createdAt, blocks: ticked.enumerated().map { .checkItem("item \($0.offset)", isComplete: $0.element) })
    }

    // MARK: - Moments

    func testFinishingAThreeItemChecklist_isAMoment() {
        let before = checklist([true, true, false])
        var after = before
        after.setAllItemsComplete(true)
        XCTAssertEqual(RatingPrompt.moment(previous: before, updated: after, allCreatedAt: [],
                                           firstLaunch: day(0), calendar: calendar), .checklistFinished)
    }

    func testFinishingATwoItemChecklist_isNotAMoment() {
        let before = checklist([true, false])
        var after = before
        after.setAllItemsComplete(true)
        XCTAssertNil(RatingPrompt.moment(previous: before, updated: after, allCreatedAt: [],
                                         firstLaunch: day(0), calendar: calendar))
    }

    func testSavingAnAlreadyFinishedChecklist_isNotAMoment() {
        let done = checklist([true, true, true])
        XCTAssertNil(RatingPrompt.moment(previous: done, updated: done, allCreatedAt: [],
                                         firstLaunch: day(0), calendar: calendar))
    }

    func testANewTakeOnTheSeventhWritingDay_isAMoment() {
        let dates = (0..<7).map { day($0 * 2) }   // seven different days, not consecutive
        XCTAssertEqual(RatingPrompt.moment(previous: nil, updated: Take(), allCreatedAt: dates,
                                           firstLaunch: day(0), calendar: calendar), .writingHabit)
    }

    func testANewTakeOnTheSixthWritingDay_isNotAMoment() {
        let dates = (0..<6).map { day($0) } + [day(5, hour: 20)]   // two on one day
        XCTAssertNil(RatingPrompt.moment(previous: nil, updated: Take(), allCreatedAt: dates,
                                         firstLaunch: day(0), calendar: calendar))
    }

    func testTakesFromBeforeTheFirstLaunch_doNotCountAsWritingDays() {
        let imported = (1...10).map { day(-$0) }
        XCTAssertEqual(RatingPrompt.writingDays(imported + [day(0)], since: day(0, hour: 18),
                                                calendar: calendar), 1)
    }

    func testEditingAnExistingTake_isNotAWritingMoment() {
        let take = Take(blocks: [.textLine("a")])
        var edited = take
        edited.blocks = [.textLine("ab")]
        let dates = (0..<10).map { day($0) }
        XCTAssertNil(RatingPrompt.moment(previous: take, updated: edited, allCreatedAt: dates,
                                         firstLaunch: day(0), calendar: calendar))
    }

    // MARK: - Whether to ask

    private func ask(now: Date, lastAsked: Date? = nil, lastVersion: String? = nil,
                     version: String = "1.0", entitled: Bool = true) -> Bool {
        RatingPrompt.shouldAsk(now: now, firstLaunch: day(0), lastAsked: lastAsked,
                               lastAskedVersion: lastVersion, currentVersion: version,
                               isEntitled: entitled, calendar: calendar)
    }

    func testNeverInTheFirstThreeDays() {
        XCTAssertFalse(ask(now: day(0)))
        XCTAssertFalse(ask(now: day(2)))
        XCTAssertTrue(ask(now: day(3)))
    }

    func testNeverInTheReadOnlyLapse() {
        XCTAssertFalse(ask(now: day(10), entitled: false))
    }

    func testOncePerVersion() {
        XCTAssertFalse(ask(now: day(300), lastAsked: day(5), lastVersion: "1.0", version: "1.0"))
        XCTAssertTrue(ask(now: day(300), lastAsked: day(5), lastVersion: "1.0", version: "1.1"))
    }

    func testAtLeast120DaysApart_evenAcrossVersions() {
        XCTAssertFalse(ask(now: day(124), lastAsked: day(5), lastVersion: "1.0", version: "1.1"))
        XCTAssertTrue(ask(now: day(125), lastAsked: day(5), lastVersion: "1.0", version: "1.1"))
    }

    // MARK: - The timeline notices the moment

    private func makeVM(_ takes: [Take], firstLaunch: Date) throws -> DailiesViewModel {
        let store = InMemoryTakeStore()
        for t in takes { try store.upsert(t) }
        let defaults = UserDefaults(suiteName: "RatingPromptTests-\(UUID())")!
        defaults.set(firstLaunch, forKey: "catchlight.rating.firstLaunch")
        return DailiesViewModel(store: store, reminders: ReminderScheduler(center: QuietCenter()),
                                ratingLedger: RatingPromptLedger(defaults: defaults))
    }

    func testTickingTheLastItemInTheEditor_leavesAMomentPending() throws {
        let take = checklist([true, true, false])
        let vm = try makeVM([take], firstLaunch: Date())
        var edited = take
        edited.setAllItemsComplete(true)

        vm.save(edited)

        XCTAssertEqual(vm.pendingRatingMoment, .checklistFinished)
        vm.clearRatingMoment()
        XCTAssertNil(vm.pendingRatingMoment)
    }

    func testSwipingAChecklistDone_leavesAMomentPending() throws {
        let take = checklist([false, false, false])
        let vm = try makeVM([take], firstLaunch: Date())

        vm.toggleDone(take)

        XCTAssertEqual(vm.pendingRatingMoment, .checklistFinished)
    }

    func testUndoingTheFinish_withdrawsTheMoment() throws {
        let take = checklist([false, false, false])
        let vm = try makeVM([take], firstLaunch: Date())

        vm.toggleDone(take)
        vm.toggleDone(vm.takes.first { $0.id == take.id }!)

        XCTAssertNil(vm.pendingRatingMoment)
    }

    func testAnOrdinaryEdit_leavesNothingPending() throws {
        let take = Take(blocks: [.textLine("a")])
        let vm = try makeVM([take], firstLaunch: Date())
        var edited = take
        edited.blocks = [.textLine("ab")]

        vm.save(edited)

        XCTAssertNil(vm.pendingRatingMoment)
    }
}
#endif
