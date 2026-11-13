//
//  SiteClipFlows.swift
//  CatchlightSiteClips
//
//  The three phone flows recorded for catchlight.app, paced like a person. NOT part of the
//  Catchlight scheme: `scripts/site-clips/record.sh` runs them from the CatchlightSiteClips
//  scheme while it records the simulator screen. Each flow logs where and when it taps
//  (`<clip>.taps.json` in $CLIP_OUT_DIR) so the recorder can draw the tap dot at encode time,
//  leaving the app and the recording untouched.
//

import XCTest

/// Logs each tap's place (points, window coordinates) and wall-clock time.
final class TapLog {
    struct Tap: Codable { let t: Double; let x: Double; let y: Double }
    private(set) var taps: [Tap] = []
    private(set) var begin = 0.0
    private(set) var end = 0.0

    static var now: Double { Date().timeIntervalSince1970 }

    func start() { begin = Self.now }
    func finish() { end = Self.now }

    /// Find `element` and return its centre. Resolving an element costs a second or two of
    /// accessibility work, so a flow looks first, waits out its beat, then taps the point:
    /// the beat on screen is then the beat the flow means.
    func target(_ element: XCUIElement, file: StaticString = #file, line: UInt = #line) -> CGPoint {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Clip flow: element not found", file: file, line: line)
        let f = element.frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Tap `element` at its centre and log it.
    func tap(_ element: XCUIElement, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Clip flow: element not found", file: file, line: line)
        let f = element.frame
        log(f.midX, f.midY)
        element.tap()
    }

    /// Tap a point (window coordinates) and log it.
    func tap(_ app: XCUIApplication, x: CGFloat, y: CGFloat) {
        log(x, y)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    private func log(_ x: CGFloat, _ y: CGFloat) {
        taps.append(Tap(t: Self.now, x: Double(x), y: Double(y)))
    }

    func write(clip: String, app: XCUIApplication) throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_OUT_DIR"] else { return }
        let size = app.windows.firstMatch.frame.size
        let json: [String: Any] = [
            "clip": clip, "begin": begin, "end": end,
            "screenWidth": size.width, "screenHeight": size.height,
            "taps": taps.map { ["t": $0.t, "x": $0.x, "y": $0.y] },
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(clip).taps.json"))
    }
}

/// One tap of a flow: where it lands, found on screen in the scouting pass, and the beat
/// before it in the recorded pass.
private struct Step {
    let name: String
    /// Seconds from the previous tap: the screen's reaction plus about 0.8 s of looking.
    let beat: Double
    let find: (XCUIApplication) -> CGPoint
}

final class SiteClipFlows: XCTestCase {

    private let log = TapLog()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launch on the demo Takes in the Cobalt Scene, Daylight or Night (`$CLIP_APPEARANCE`),
    /// with every animation at its real speed. Returns once the timeline shows.
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        let mode = ProcessInfo.processInfo.environment["CLIP_APPEARANCE"] ?? "daylight"
        app.launchArguments = ["--uitesting", "--uitesting-demo",
                               "-catchlight.focusRowTimeScale", "1",
                               "-appearanceMode", mode, "-catchlight.creationStamp", "off"]
        app.launch()
        XCTAssertTrue(anyElement(in: app, id: "take-iris").waitForExistence(timeout: 15), "No Take on the timeline")
        return app
    }

    /// Tell the recorder script the app is up and still (`ready`), then wait for it to say the
    /// screen recording has started (`go`), so the video opens on a still Dailies, not the launch.
    /// Without `$CLIP_OUT_DIR` (a manual run) there is nothing to wait for.
    private func waitForRecorder() {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_OUT_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        FileManager.default.createFile(atPath: base.appendingPathComponent("ready").path, contents: Data())
        let go = base.appendingPathComponent("go").path
        let deadline = Date().addingTimeInterval(90)
        while !FileManager.default.fileExists(atPath: go), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: go), "The recorder never started")
    }

    /// Wait until 1.5 s before the next minute that is a multiple of five. The reminder's default
    /// time is fixed when the Focus row opens, about 3.2 s after the recorder's go.
    private func waitForNearestFive() {
        let cal = Calendar.current
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let next = cal.nextDate(after: now, matching: DateComponents(minute: (minute / 5 + 1) * 5 % 60, second: 0),
                                matchingPolicy: .nextTime) ?? now
        let wait = next.addingTimeInterval(-1.5).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    /// Run a flow twice. The scouting pass finds each tap's place, which costs a second or two
    /// of accessibility lookup per tap and would make the pacing the runner's, not a person's;
    /// it also proves every step is reachable. The recorded pass relaunches and only taps the
    /// found points, on the beats given, so the pacing is the flow's own.
    ///
    /// `onTheFives` holds the recorded pass until the clock is a few seconds before a minute
    /// that is a multiple of five, for a clip whose Take shows the default reminder time (the
    /// minute the editor opens): it then reads 07:40, not an arbitrary 07:36.
    private func flow(_ clip: String, hold: Double, onTheFives: Bool = false, steps: [Step]) throws {
        var points: [CGPoint] = []
        let scout = launchDemo()
        for step in steps {
            let p = step.find(scout)
            points.append(p)
            scout.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).tap()
            Thread.sleep(forTimeInterval: 1.5)   // let the screen settle before the next lookup
        }
        scout.terminate()

        let app = launchDemo()
        if onTheFives { waitForNearestFive() }
        waitForRecorder()
        Thread.sleep(forTimeInterval: 1.6)   // still Dailies before the first tap; the encoder trims to the first change
        log.start()
        // Each tap is due on a running schedule, and never sooner than its beat after the call
        // before it: a tap the runner is slow to return from (a sheet, the keyboard) pushes the
        // next one back instead of squeezing it. The runner takes about 0.15 s to deliver a tap,
        // so each call starts that much early.
        let began = Date()
        var due = 0.0
        var previousCall = began
        for (step, p) in zip(steps, points) {
            due += step.beat
            let fire = max(began.addingTimeInterval(due - 0.15), previousCall.addingTimeInterval(step.beat - 0.15))
            let wait = fire.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            previousCall = Date()
            log.tap(app, x: p.x, y: p.y)
        }
        Thread.sleep(forTimeInterval: hold)
        log.finish()
        try log.write(clip: clip, app: app)
    }

    // MARK: Finding where to tap

    private func irisOf(row: Int) -> (XCUIApplication) -> CGPoint {
        { app in
            let e = app.descendants(matching: .any).matching(identifier: "take-iris").element(boundBy: row)
            XCTAssertTrue(e.waitForExistence(timeout: 10), "No Iris on row \(row)")
            return CGPoint(x: e.frame.midX, y: e.frame.midY)
        }
    }

    private func centre(ofID id: String) -> (XCUIApplication) -> CGPoint {
        { app in
            let e = anyElement(in: app, id: id)
            XCTAssertTrue(e.waitForExistence(timeout: 10), "\(id) not found")
            return CGPoint(x: e.frame.midX, y: e.frame.midY)
        }
    }

    private func centre(ofButton label: String) -> (XCUIApplication) -> CGPoint {
        { app in
            let e = app.buttons[label]
            XCTAssertTrue(e.waitForExistence(timeout: 10), "\(label) button not found")
            return CGPoint(x: e.frame.midX, y: e.frame.midY)
        }
    }

    /// The centre of the Take card whose text starts with `prefix`.
    private func rowCentre(startingWith prefix: String) -> (XCUIApplication) -> CGPoint {
        { app in
            let e = takeRow(in: app, withLabelStarting: prefix)
            XCTAssertTrue(e.waitForExistence(timeout: 10), "No Take starting \(prefix)")
            return CGPoint(x: e.frame.midX, y: e.frame.midY)
        }
    }

    /// A tap on the dimmed Dailies low on the screen, well away from the top card, which closes
    /// the open Focus row.
    private var dimLow: (XCUIApplication) -> CGPoint {
        { app in
            let dim = anyElement(in: app, id: "focus-row-dim")
            XCTAssertTrue(dim.waitForExistence(timeout: 10), "The Focus row is not open")
            return CGPoint(x: dim.frame.minX + dim.frame.width * 0.85, y: dim.frame.minY + dim.frame.height * 0.62)
        }
    }

    /// A tap on the dimmed Dailies above the open Focus row, which closes it.
    private var dimAbove: (XCUIApplication) -> CGPoint {
        { app in
            let dim = anyElement(in: app, id: "focus-row-dim")
            XCTAssertTrue(dim.waitForExistence(timeout: 10), "The Focus row is not open")
            return CGPoint(x: dim.frame.midX, y: dim.frame.minY + dim.frame.height * 0.08)
        }
    }

    // MARK: The three clips

    /// Clip 1: tap a Take's Iris, the Focus row opens, Task then Reminder are chosen, the row
    /// closes and the Take shows both. The Take is the two-line note "Idea from the walk", the first card.
    func testClip1_shapingATake() throws {
        try flow("shaping-a-take", hold: 2.0, onTheFives: true, steps: [
            Step(name: "iris", beat: 0, find: irisOf(row: 0)),
            Step(name: "task", beat: 1.4, find: centre(ofID: "focus-row-mark-task")),
            Step(name: "remind", beat: 1.3, find: centre(ofID: "focus-row-mark-remind")),
            Step(name: "done", beat: 1.6, find: centre(ofButton: "Done")),
            Step(name: "close", beat: 1.4, find: dimAbove),
        ])
    }

    /// Clip 2: from the Focus row tap Reminder, the editor opens on Time, a time is picked and
    /// saved, the Take shows it. The Take is "Water the studio plants", the third card.
    func testClip2_settingAReminder() throws {
        try flow("setting-a-reminder", hold: 1.8, steps: [
            Step(name: "iris", beat: 0, find: irisOf(row: 2)),
            Step(name: "remind", beat: 1.3, find: centre(ofID: "focus-row-mark-remind")),
            Step(name: "quickset", beat: 1.4, find: centre(ofID: "reminder-quickset")),
            Step(name: "tomorrow", beat: 1.1, find: centre(ofButton: "Tomorrow")),
            Step(name: "done", beat: 1.2, find: centre(ofButton: "Done")),
            Step(name: "close", beat: 1.3, find: dimAbove),
        ])
    }

    /// Clip 3: tap Sequence, the choices open above the toolbar, Tasks is picked, the
    /// timeline narrows.
    func testClip3_sequence() throws {
        try flow("sequence", hold: 2.0, steps: [
            Step(name: "sequence", beat: 0, find: centre(ofButton: "sequence-tab")),
            Step(name: "tasks", beat: 1.5, find: centre(ofButton: "filter-tasks")),
        ])
    }

    // MARK: Slow-pace drafts of Shaping a Take (Art Director, 13 Nov): 1.5 s of still screen,
    // each dot 0.4 s before its press (the encoder), 1.4 s on each result, 3 s on the end.

    /// B2, in the editor: open the Take, tap the editor's Iris, tap Task, close the row.
    func testClip1B2_shapingATakeInTheEditor() throws {
        try flow("shaping-a-take-B2", hold: 3.6, steps: [
            Step(name: "open", beat: 0, find: rowCentre(startingWith: "Idea from the walk")),
            Step(name: "iris", beat: 2.6, find: centre(ofID: "editor-shape")),
            Step(name: "task", beat: 2.6, find: centre(ofID: "focus-row-mark-task")),
            Step(name: "close", beat: 2.5, find: dimLow),
        ])
    }
}
