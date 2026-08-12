//
//  CaptureTextIntents.swift
//  Catchlight — App Intents (owner 2026-08-11)
//
//  The DICTATION half of capture: "say the trigger, Siri asks what to capture, you speak it".
//
//  WHY THESE EXIST, AND WHY SPLITTING WAS THE ONLY FIX.
//  `NewTakeIntent` / `NewObieIntent` tried to serve two surfaces at once by declaring an
//  OPTIONAL text parameter. That cannot work, because the two surfaces want opposite things:
//
//    • the iOS-18 Control, the Action button and the launcher widgets must run with NO text,
//      so the parameter has to be optional;
//    • Siri must be ASKED for the text, and App Intents only requests a value for a parameter
//      the intent actually requires — an optional one is simply left nil, and its
//      `requestValueDialog` ("What's the Take?") never fires.
//
//  So the documented behaviour never happened: Siri opened a blank editor without asking.
//  Predicted from the parameter's optionality on 2026-08-11 and confirmed on device the same
//  day (owner: "blank editor without asking"). One parameter cannot be both required and
//  optional, so the intent had to become two.
//
//  THE SPLIT: the launcher intents keep their names and their surfaces (Controls, widgets,
//  Action button) and no longer carry text at all. These two carry a REQUIRED text parameter
//  and own every Siri phrase — talking to Siri means you have something to say, and if you
//  wanted a blank editor you would have tapped the widget.
//
//  Both funnel into the SAME `CaptureRouting` hand-off the app drains, so nothing downstream
//  knows or cares which surface it came from. Changing intent shape is free right now and
//  would break user-built shortcuts later; nothing is shipped.
//

import AppIntents
import CatchlightCore

/// Dictate a Take. The Siri phrases in `CatchlightAppShortcuts` point here.
struct CaptureTakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a Take"
    static var description = IntentDescription(
        "Capture a new Take from text you speak or type.",
        categoryName: "Capture"
    )

    /// Capture still happens IN the app: the encrypted store needs the master key, which only
    /// materialises in the foreground, unlocked app. The text is resolved BEFORE this runs, so
    /// Siri asks first and the app opens with the words already in hand.
    static var openAppWhenRun: Bool = true

    /// NON-OPTIONAL, and that is the entire point of this type. App Intents requests a value
    /// for a required parameter, which is what makes `requestValueDialog` fire.
    @Parameter(
        title: "Take",
        description: "What to capture.",
        requestValueDialog: "What's your Take?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRouting.setPending(.init(mode: .text, text: text))
        return .result()
    }
}

/// Dictate an Obie — the same, pre-flagged as the Obie. The store's single-Obie upsert demotes
/// the previous one on save.
struct CaptureObieIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture an Obie"
    static var description = IntentDescription(
        "Capture a new Take as your Obie, from text you speak or type.",
        categoryName: "Capture"
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Obie",
        description: "What to capture as your Obie.",
        requestValueDialog: "What's your Obie?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRouting.setPending(.init(mode: .obie, text: text))
        return .result()
    }
}
