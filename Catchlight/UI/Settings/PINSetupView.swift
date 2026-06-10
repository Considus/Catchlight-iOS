//
//  PINSetupView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → Security → PIN / biometrics.
//
//  Flow depends on whether a PIN is already set (queried from PINService via
//  the keychain — see SettingsViewModel.hasPIN):
//
//    No PIN yet:           create (6 digits)  →  confirm (6 digits)  →  saved
//    PIN already set:      menu — Change PIN  |  Remove PIN
//    Change:               verify current     →  create new          →  confirm new
//    Remove:               verify current     →  cleared (also turns off biometrics)
//
//  Biometrics: once a PIN is set, a toggle becomes available. Enabling calls
//  LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics); if
//  unsupported (Simulator, denied, no enrolled Face/Touch ID) the toggle stays
//  disabled with an explanatory line. PIN is ALWAYS the fallback.
//

import SwiftUI
import LocalAuthentication

@MainActor
struct PINSetupView: View {

    enum Mode { case create, manage }

    private enum Step: Equatable {
        case menu                 // mode == .manage with PIN set
        case createNew            // first entry while creating/changing
        case confirmNew(String)   // re-enter to confirm (carries the pending PIN)
        case verifyCurrent(Next)  // gate before change / remove
        case done

        enum Next: Equatable { case change, remove }
    }

    @Environment(\.dismiss) private var dismiss

    /// Re-evaluated every time the view appears so the parent's state stays in sync.
    var onDidChangePINState: () -> Void

    @State private var step: Step
    @State private var errorText: String?
    @State private var entryResetId = UUID()
    @State private var biometricsEnabled: Bool = BiometricsPreference.isEnabled
    @State private var biometricsAvailability: BiometricsAvailability = .check()
    @Environment(\.scenePhase) private var scenePhase

    private let pinService = PINService()

    init(initialMode: Mode, onDidChangePINState: @escaping () -> Void) {
        self.onDidChangePINState = onDidChangePINState
        switch initialMode {
        case .create:
            _step = State(initialValue: .createNew)
        case .manage:
            _step = State(initialValue: .menu)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.ckTextObie)
                    }
                }
                .background(Color.ckBackground.ignoresSafeArea())
        }
        .presentationDragIndicator(.visible)
        // Re-probe biometric availability when the user returns from Settings
        // (e.g. after enrolling Face ID as the footer suggests) — the @State
        // initialiser only ran once, so the toggle stayed disabled until the
        // sheet was reopened.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { biometricsAvailability = .check() }
        }
    }

    private var title: String {
        switch step {
        case .menu: return "PIN & Biometrics"
        case .createNew, .confirmNew: return "Set a PIN"
        case .verifyCurrent: return "Enter current PIN"
        case .done: return "PIN & Biometrics"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .menu:
            menu
        case .createNew:
            entry(
                title: "Create a 6-digit PIN",
                subtitle: "You'll be asked for this PIN when the app locks."
            ) { pin in
                if let reason = PINPolicy.rejectionReason(for: pin) {
                    errorText = reason
                    entryResetId = UUID()
                    return
                }
                errorText = nil
                step = .confirmNew(pin)
                entryResetId = UUID()
            }
        case .confirmNew(let pending):
            entry(
                title: "Confirm your PIN",
                subtitle: "Re-enter the same 6 digits."
            ) { pin in
                guard pin == pending else {
                    errorText = "Those didn't match — start again."
                    step = .createNew
                    entryResetId = UUID()
                    return
                }
                do {
                    try pinService.setPIN(pin)
                    errorText = nil
                    step = .done
                    onDidChangePINState()
                } catch {
                    errorText = "Couldn't save the PIN. Try again."
                    step = .createNew
                    entryResetId = UUID()
                }
            }
        case .verifyCurrent(let next):
            entry(
                title: "Enter your current PIN",
                subtitle: "Verify the current PIN to continue."
            ) { pin in
                do {
                    if try pinService.verify(pin) {
                        errorText = nil
                        switch next {
                        case .change:
                            step = .createNew
                        case .remove:
                            pinService.reset()
                            BiometricsPreference.isEnabled = false
                            biometricsEnabled = false
                            step = .done
                            onDidChangePINState()
                        }
                        entryResetId = UUID()
                    } else {
                        errorText = "Incorrect PIN. Try again."
                        entryResetId = UUID()
                    }
                } catch {
                    errorText = "Couldn't verify the PIN. Try again."
                    entryResetId = UUID()
                }
            }
        case .done:
            doneScreen
        }
    }

    private func entry(title: String, subtitle: String, onSubmit: @escaping (String) -> Void) -> some View {
        PINEntryView(title: title, subtitle: subtitle, onSubmit: onSubmit, errorText: errorText)
            .id(entryResetId)
    }

    // MARK: - Manage menu

    private var menu: some View {
        List {
            Section("PIN") {
                Button {
                    errorText = nil
                    step = .verifyCurrent(.change)
                } label: {
                    SettingsRow(icon: "arrow.triangle.2.circlepath", label: "Change PIN", chevron: true)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    errorText = nil
                    step = .verifyCurrent(.remove)
                } label: {
                    SettingsRow(icon: "trash", label: "Remove PIN", chevron: true)
                }
                .buttonStyle(.plain)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { biometricsEnabled && biometricsAvailability.isAvailable },
                    set: { newValue in
                        guard biometricsAvailability.isAvailable else { return }
                        BiometricsPreference.isEnabled = newValue
                        biometricsEnabled = newValue
                    }
                )) {
                    Label(biometricsAvailability.label,
                          systemImage: biometricsAvailability.symbol)
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                }
                .tint(Color.ckEmber)
                .disabled(!biometricsAvailability.isAvailable)
                .listRowBackground(Color.ckSurface)
            } header: {
                Text("Biometrics")
            } footer: {
                Text(biometricsAvailability.footer)
                    .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ckTextSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ckBackground)
    }

    private var doneScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.ckEmber)
            Text("PIN saved")
                .font(CatchlightFont.ui(.regular, size: 20, relativeTo: .title3))
                .foregroundStyle(Color.ckTextPrimary)
            Text("You'll use it to unlock Catchlight on this device.")
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.ckEmber)
                .padding(.top, 8)
            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
    }
}

// MARK: - Biometrics availability + persisted toggle

struct BiometricsAvailability {
    let isAvailable: Bool
    let label: String
    let symbol: String
    let footer: String

    static func check() -> BiometricsAvailability {
        let ctx = LAContext()
        var error: NSError?
        let can = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        let (label, symbol): (String, String)
        switch ctx.biometryType {
        case .faceID:  (label, symbol) = ("Use Face ID", "faceid")
        case .touchID: (label, symbol) = ("Use Touch ID", "touchid")
        case .opticID: (label, symbol) = ("Use Optic ID", "opticid")
        case .none:    (label, symbol) = ("Biometrics", "lock.shield")
        @unknown default: (label, symbol) = ("Biometrics", "lock.shield")
        }

        let footer: String
        if can {
            footer = "Biometrics unlock the app faster. Your PIN is always available as a fallback."
        } else if error?.code == LAError.biometryNotEnrolled.rawValue {
            footer = "No biometrics enrolled on this device — set up Face ID or Touch ID in iOS Settings to enable."
        } else if error?.code == LAError.biometryNotAvailable.rawValue {
            footer = "Biometrics aren't available on this device."
        } else {
            footer = "Biometrics aren't available right now."
        }

        return BiometricsAvailability(isAvailable: can, label: label, symbol: symbol, footer: footer)
    }
}

/// Persisted biometrics-enabled flag. Convenience unlock only — does NOT affect
/// the PIN itself, which is always required as a fallback.
enum BiometricsPreference {
    private static let key = "catchlight.pin.biometricsEnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
