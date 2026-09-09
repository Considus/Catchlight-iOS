//
//  AddPulseFrameProbeTests.swift
//  CatchlightUITests
//
//  V40, fifth characterisation (§15ap). The surviving surface is ONE control: the
//  Add button, intermittently, twice in the owner's session. Storyboard, Sequence,
//  Search and the hint were each reached repeatedly and never jumped.
//
//  🚨 THE EARLIER ELIMINATION REFUTED THE WRONG PROPOSITION. `runPulseCycle`'s
//  comment records the pulse as "MEASURED AND ELIMINATED" because the suspicion was
//  that `addPulsesDone < 2` was not holding and the pulse ran FOREVER. The bench
//  logged done=0,1,2 and stopped, and that was read as exoneration.
//
//  But the cap holding means the pulse fires EXACTLY TWICE — and the owner got
//  EXACTLY TWO jumps out of Add Take. The observation taken as clearing the pulse is
//  the same number as the fault. What was never measured is the thing the comment
//  itself names: whether the pulse "moves a focused control's frame under the
//  cursor".
//
//  `.scaleEffect(addPulseScale)` takes the button 1.0 -> 1.18 -> 1.0, twice. This
//  campaign has already measured that `.offset` DOES move an accessibility frame
//  (TooltipFrameProbeTests). Whether `.scaleEffect` does is the open question, and
//  it is answerable here: sample the frame across the pulse window.
//
//  Frame movement alone is not proof that VoiceOver re-anchors — the bench has no
//  cursor. It establishes whether the precondition exists at all.
//

import XCTest

final class AddPulseFrameProbeTests: XCTestCase {

    func testAddButtonAccessibilityFrameDuringPulse() {
        let app = XCUIApplication()
        // Step 1 mounts the hint, which is what arms the pulse.
        // `--a11y-diag` forces recording without VoiceOver, so the PULSE notes land in
        // the log and the sampling window can be PROVEN to overlap the pulse. Sampling a
        // window the pulse had already left would read exactly like "the frame never
        // moves" — the failure this investigation keeps producing.
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1", "--a11y-diag",
                               // Hold the pulse until the probe is sampling. Without this
                               // the window opens a second AFTER the pulse has finished.
                               "--uitesting-pulse-delay", "4"]
        app.launch()

        let add = app.buttons["add-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "Dock did not load")

        // The cycle is 0.45s up + 0.45s down, twice — about 1.8s from mount. Sample
        // past it. Re-query each time: a held reference pinned a stale snapshot on
        // this runtime (the same trap A11yStateUITests records for the Important value).
        var frames: [CGRect] = []
        let started = Date()
        let deadline = started.addingTimeInterval(9)    // spans the delayed pulse
        while Date() < deadline {
            frames.append(app.buttons["add-button"].firstMatch.frame)
        }
        print("PULSE window opened \(started.timeIntervalSince1970) closed \(Date().timeIntervalSince1970)")

        let widths = Set(frames.map { ($0.width * 100).rounded() / 100 })
        print("PULSE samples=\(frames.count) distinct widths=\(widths.sorted())")
        print("PULSE first=\(frames.first.map(String.init(describing:)) ?? "-") "
              + "widest=\(frames.max(by: { $0.width < $1.width }).map(String.init(describing:)) ?? "-")")

        // The load-bearing question. If the accessibility frame never changes, the
        // pulse is purely visual and cannot move anything under a cursor — the
        // elimination stands, on the right proposition this time. If it DOES change,
        // the precondition the comment names is real and was never tested.
        XCTAssertEqual(widths.count, 1,
                       "The Add button's ACCESSIBILITY frame changes during the pulse: "
                       + "widths \(widths.sorted()). `.scaleEffect` moves the frame, so a "
                       + "VoiceOver cursor resting on this control has its target resized "
                       + "twice underneath it — the precondition §15ai named and never measured.")
    }
}
