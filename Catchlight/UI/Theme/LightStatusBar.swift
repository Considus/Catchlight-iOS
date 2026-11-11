//
//  LightStatusBar.swift
//  Catchlight
//
//  The colour field behind Welcome and the closing screen is dark in every Scene in both
//  appearances, but SwiftUI picks the status bar icons from the appearance, so in the light
//  appearance they were dark on dark. `lightStatusBar(_:)` asks for light icons while such a
//  screen is up, without touching the colour scheme (the field tokens depend on it).
//
//  SwiftUI has no status bar style of its own, so the window's root view controller gets a
//  subclass that answers `preferredStatusBarStyle` from the screens currently on display. The
//  answer is light only when at least one screen asks for it and none asks for the normal
//  style, so the splash (normal style) wins over the Welcome screen beneath it.
//

import SwiftUI
import UIKit
import ObjectiveC
import CatchlightCore

@MainActor
enum LightStatusBar {
    /// What each screen on display asked for, by the probe that reports it.
    private static var requests: [ObjectIdentifier: Bool] = [:]

    fileprivate static var isLight = false
    private static var loggedKept = false

    fileprivate static func set(_ wantsLight: Bool?, for probe: UIViewController) {
        let key = ObjectIdentifier(probe)
        if let wantsLight { requests[key] = wantsLight } else { requests[key] = nil }
        let light = !requests.isEmpty && requests.values.allSatisfy { $0 }
        guard let root = probe.view.window?.rootViewController ?? rootViewController() else { return }
        let install = install(on: root)
        if install == .refused {
            // Not ours to change: make sure our getter, if it is still in the chain, answers normally.
            if isLight { isLight = false; root.setNeedsStatusBarAppearanceUpdate() }
            return
        }
        // A newly installed class must be asked again, whether or not the flag flipped.
        if light != isLight || install == .installed {
            isLight = light
            root.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    }

    private static let prefix = "CKLightStatusBar_"

    enum Install { case installed, already, refused }

    static func install(on root: UIViewController) -> Install {
        // `type(of:)` and `-class` hide a runtime subclass, so read the real class pointer.
        guard let actual = object_getClass(root) else { return .refused }
        let base: AnyClass = type(of: root)
        // Ours may sit under a class another observer (KVO) added later, so look down the chain.
        var cls: AnyClass? = actual
        while let current = cls, current !== base {
            if NSStringFromClass(current).hasPrefix(prefix) { return .already }
            cls = class_getSuperclass(current)
        }
        // Another observer (KVO) swapped the class before us: changing it again would
        // fight over the same pointer, so leave the style alone.
        if actual !== base {
            if !loggedKept {
                loggedKept = true
                DiagnosticsLog.shared.record(.statusBarStyleKept)
            }
            return .refused
        }
        let baseName = NSStringFromClass(base)
        let name = prefix + baseName
        if let existing = NSClassFromString(name) { object_setClass(root, existing); return .installed }
        guard let subclass = objc_allocateClassPair(base, name, 0) else { return .refused }
        let selector = #selector(getter: UIViewController.preferredStatusBarStyle)
        guard let imp = class_getMethodImplementation(base, selector) else { return .refused }
        typealias Original = @convention(c) (AnyObject, Selector) -> Int
        let original = unsafeBitCast(imp, to: Original.self)
        let answer: @convention(block) (AnyObject) -> Int = { object in
            // UIKit asks for the status bar style on the main thread.
            MainActor.assumeIsolated {
                LightStatusBar.isLight ? UIStatusBarStyle.lightContent.rawValue : original(object, selector)
            }
        }
        class_addMethod(subclass, selector, imp_implementationWithBlock(answer), "q@:")
        objc_registerClassPair(subclass)
        object_setClass(root, subclass)
        return .installed
    }
}

private final class LightStatusBarProbe: UIViewController {
    var wantsLight = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        report()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        LightStatusBar.set(nil, for: self)
    }
    func report() {
        guard viewIfLoaded?.window != nil else { return }
        LightStatusBar.set(wantsLight, for: self)
    }
}

private struct LightStatusBarRequest: UIViewControllerRepresentable {
    let wantsLight: Bool
    func makeUIViewController(context: Context) -> UIViewController {
        let probe = LightStatusBarProbe()
        probe.wantsLight = wantsLight
        return probe
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let probe = controller as? LightStatusBarProbe else { return }
        probe.wantsLight = wantsLight
        probe.report()
    }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        if let probe = controller as? LightStatusBarProbe { LightStatusBar.set(nil, for: probe) }
    }
}

extension View {
    /// Light status bar icons while this screen is up when `wantsLight`, the normal style
    /// otherwise. A screen that asks for the normal style outranks one that asks for light.
    func lightStatusBar(_ wantsLight: Bool) -> some View {
        background(LightStatusBarRequest(wantsLight: wantsLight).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
