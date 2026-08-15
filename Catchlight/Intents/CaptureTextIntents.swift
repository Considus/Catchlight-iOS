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

//  ---------------------------------------------------------------------------------------
//  SUPPORTED MODES (2026-08-15). Apple deprecated `openAppWhenRun`. `supportedModes` replaces
//  it, and the replacement is the reason for this change, not the deprecation.
//
//  An intent with `openAppWhenRun = true` always brings the app to the front. The system
//  therefore demands Face ID on a locked phone. No authentication policy changes this. The
//  owner dictated a Take to Siri on a locked phone and had to unlock first. That is the fault
//  this change corrects.
//
//  These two intents declare `[.background, .foreground(.dynamic)]`. On an unlocked phone
//  `perform()` asks for the front, the app opens, and the Take saves at once. On a locked
//  phone it asks for nothing: the intent stays in the background, the text goes to the queue,
//  and the Take appears at the next unlock. Siri asks for no unlock either way.
//
//  WHAT THE DEVICE TAUGHT US, IN TWO ROUNDS (owner, iOS 26.6, locked phone). Round one used
//  `.deferred` and a confirmed transition: no Face ID, but Siri showed "You'll need to
//  continue in the app". Round two turned the confirmation off: the prompt went, and Face ID
//  came back. Those two results together say one thing. ANY move to the front on a locked
//  phone costs an unlock, and the confirmation prompt was only hiding that cost behind a
//  button. So the fix is not a softer transition. The fix is to not ask for the front while
//  the phone is locked, which is what the guard in `queueDictatedCapture` does.
//
//  BOTH DECLARATIONS STAY. The app floor is iOS 18.0 (D-039) and `supportedModes` is iOS 26.
//  One type holds both: the new property sits behind `@available(iOS 26.0, *)`, and each
//  system reads the property it knows. iOS 18 keeps today's behaviour, so a locked phone
//  still demands Face ID there. The owner accepts this.
//
//  `authenticationPolicy` keeps its default, `.alwaysAllowed`. Do not set it.
//
//  THE QUEUE, NOT THE PENDING SLOT. These two intents write straight to
//  `CaptureRouting.enqueueShared`. They wrote `CaptureRouting.setPending` before, and the app
//  turned the text into a shared item inside `drainPendingCapture`.
//
//  The pending slot holds ONE capture and the last write wins. That was safe while the intent
//  always opened the app, because the app drained the slot at once. A background intent does
//  not open the app, so two dictations on a locked phone can queue together and the slot
//  loses the first one. The shared queue keeps both, holds them while the phone is locked,
//  and commits them at the next unlock.
//
//  The app needs no change for this. `drainSharedCaptures` already runs on every activation
//  and on every unlock, and `drainPendingCapture` sent text down this same path before.
//  ---------------------------------------------------------------------------------------
//

import AppIntents
import CatchlightCore
import UIKit

/// Queue dictated text, then ask for the front only if the system permits it.
///
/// THE INTENT NEVER WRITES THE ENCRYPTED STORE, and a background mode does not change that.
/// The master key is `.userPresence`-gated and only materialises in the foreground, unlocked
/// app, so a capture can only ever be QUEUED here and committed by the app later. That wall
/// is the reason the share extension queues too. A background run is therefore not a new
/// risk: it uses the path that already existed for exactly this problem.
///
/// The order matters. The queue write happens first, so the words are safe before anything
/// tries to bring the app forward. On iOS 18 the availability test fails, this method stops
/// after the queue write, and `openAppWhenRun` opens the app exactly as it did before.
///
/// THE CONFIRMATION IS OFF ON PURPOSE (owner-reported 2026-08-15). `continueInForeground`
/// confirms by DEFAULT — `alwaysConfirm` is `true` unless you say otherwise. On a locked
/// phone that default put a "You'll need to continue in the app" prompt, with a Cancel
/// button, in front of the owner. That trades the Face ID chore for a different chore and
/// misses the point of the change. Apple's rule for `false`: the system does not ask again
/// if it recently asked the person for a value. Siri ALWAYS asks these two intents for their
/// text, because the parameter is required, so that condition holds on every run.
///
/// THE FAILURE IS SWALLOWED ON PURPOSE. Apple throws when the app cannot come to the front.
/// The words are in the queue before this line runs, so the capture already succeeded and
/// only the instant save and the reveal are lost, both of which the next unlock does. Letting
/// the error out would make Siri report a failure for a Take that is safe on disk.
///
/// `isProtectedDataAvailable` IS THE GATE, and it is not merely a lock test. It answers the
/// question that actually matters here: can the app read protected data yet? If it cannot,
/// the store is unreadable, so bringing the app to the front saves nothing and only costs the
/// owner a Face ID. The app commits the queued Take at the next unlock instead.
///
/// `.dynamic` IS LOAD-BEARING, and `.deferred` must not come back. `.deferred` brings the app
/// to the front by itself at the end of `perform()` when no transition method runs, which
/// puts a Face ID in front of a locked capture no matter what this guard does. `.dynamic`
/// stays in the background until the code asks.
private extension AppIntent {
    @MainActor
    func queueDictatedCapture(text: String, isObie: Bool) async {
        CaptureRouting.enqueueShared(.init(text: text, isObie: isObie))
        guard #available(iOS 26.0, *),
              systemContext.currentMode.canContinueInForeground,
              UIApplication.shared.isProtectedDataAvailable else { return }
        try? await continueInForeground(alwaysConfirm: false)
    }
}

/// Dictate a Take. The Siri phrases in `CatchlightAppShortcuts` point here.
struct CaptureTakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a Take"
    static var description = IntentDescription(
        "Capture a new Take from text you speak or type.",
        categoryName: "Capture"
    )

    /// iOS 18 reads this. iOS 26 reads `supportedModes` below instead.
    static var openAppWhenRun: Bool = true

    /// iOS 26 reads this. `.background` lets a locked phone capture with no unlock.
    /// `.foreground(.dynamic)` lets an unlocked phone still open the app and save at once.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

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
        await queueDictatedCapture(text: text, isObie: false)
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

    /// iOS 18 reads this. iOS 26 reads `supportedModes` below instead.
    static var openAppWhenRun: Bool = true

    /// iOS 26 reads this. See `CaptureTakeIntent` for why both declarations stay.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(
        title: "Obie",
        description: "What to capture as your Obie.",
        requestValueDialog: "What's your Obie?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        await queueDictatedCapture(text: text, isObie: true)
        return .result()
    }
}
