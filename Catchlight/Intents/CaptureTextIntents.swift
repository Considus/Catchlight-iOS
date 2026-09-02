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
//  These two intents declare `[.background, .foreground(.deferred)]`. If the system permits
//  the front, `perform()` asks for it and the app opens. If the phone is locked, the system
//  refuses, the intent stays in the background, and the text goes to the queue. The Take
//  appears at the next unlock and Siri asks for no unlock.
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
/// THE FAILURE IS SWALLOWED ON PURPOSE. Apple throws when the app cannot come to the front,
/// and a locked phone is exactly that case, so the throw is expected rather than exceptional.
/// The words are in the queue before this line runs. Only the instant save and the reveal are
/// lost, and the next unlock does both. Letting the error out would make Siri report a
/// failure for a Take that is safe on disk, which is a worse lie than a missing pulse.
///
/// DO NOT DELETE THE CALL TO GET A SILENT CAPTURE. `.foreground(.deferred)` moves the app to
/// the front at the END of `perform()` by itself when no transition method runs. The call
/// below is what makes the transition explicit and unconfirmed. To stop the app coming
/// forward at all, take `.foreground(.deferred)` out of `supportedModes` — and accept that
/// an unlocked capture then loses its instant save and its pulse.
private extension AppIntent {
    @MainActor
    func queueDictatedCapture(text: String, isObie: Bool) async {
        CaptureRouting.enqueueShared(.init(text: text, isObie: isObie))
        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try? await continueInForeground(alwaysConfirm: false)
        }
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
    /// `.foreground(.deferred)` lets an unlocked phone still open the app and save at once.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.deferred)] }

    /// NON-OPTIONAL, and that is the entire point of this type. App Intents requests a value
    /// for a required parameter, which is what makes `requestValueDialog` fire.
    @Parameter(
        title: "Take",
        description: "What to capture.",
        requestValueDialog: "What's your Take?"
    )
    var text: String

    /// Audit 2026-08, S2: one readable sentence in Shortcuts instead of a title
    /// plus a detached parameter row.
    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text)")
    }

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
    static var supportedModes: IntentModes { [.background, .foreground(.deferred)] }

    @Parameter(
        title: "Obie",
        description: "What to capture as your Obie.",
        requestValueDialog: "What's your Obie?"
    )
    var text: String

    /// Audit 2026-08, S2 — see CaptureTakeIntent.
    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) as your Obie")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await queueDictatedCapture(text: text, isObie: true)
        return .result()
    }
}
