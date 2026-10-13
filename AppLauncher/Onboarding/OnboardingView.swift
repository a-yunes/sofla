import SwiftUI

struct OnboardingView: View {
    @Bindable var setup: OnboardingModel
    let launcher: LauncherModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == setup.step ? .primary : .tertiary)
                        .frame(width: 28, height: 4)
                }
            }
            .accessibilityLabel("Setup step \(setup.step.rawValue + 1) of 3")
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title).font(.system(size: 32, weight: .semibold))
                Text(subtitle).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            content.frame(maxWidth: .infinity, minHeight: 130)
            if let error = setup.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("onboarding.error")
            }
            Spacer(minLength: 0)
            HStack {
                if setup.step != .welcome {
                    Button("Back") {
                        setup.step = setup.step == .startup ? .shortcut : .welcome
                    }
                    .accessibilityIdentifier("onboarding.back")
                }
                Spacer()
                Button(setup.step == .startup ? "Open Sofla" : "Continue") {
                    switch setup.step {
                    case .welcome: setup.step = .shortcut
                    case .shortcut: setup.step = .startup
                    case .startup:
                        if setup.finish() { finish() }
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(setup.step == .startup && !setup.canFinish)
                .accessibilityIdentifier("onboarding.continue")
            }
        }
        .padding(40).frame(width: 540, height: 560)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            setup.refresh()
        }
    }

    private var title: String {
        switch setup.step {
        case .welcome: "A little closer."
        case .shortcut: "One shortcut away."
        case .startup: "Ready when you are."
        }
    }

    private var subtitle: String {
        switch setup.step {
        case .welcome: "Welcome to Sofla. A quiet home for your apps,\nwith room to make it yours."
        case .shortcut: "Choose how you open Sofla.\nYou can change this anytime in Settings."
        case .startup:
            "Choose whether Sofla opens when you log in.\nIt stays hidden until you need it."
        }
    }

    @ViewBuilder private var content: some View {
        switch setup.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Label("Your apps. Your folders. Your favorites.", systemImage: "square.grid.3x3")
                Label("No account. No analytics. Works offline.", systemImage: "lock.shield")
                Label(
                    "No privacy permissions needed to launch apps.", systemImage: "checkmark.seal")
            }
            .font(.callout)
        case .shortcut:
            VStack(spacing: 20) {
                ShortcutRecorder(shortcut: launcher.preferences.shortcut) { value in
                    let accepted = launcher.updateShortcut(value)
                    if accepted { launcher.message = nil }
                    setup.error =
                        accepted ? nil : "That shortcut is in use. Try a different combination."
                    return accepted
                }
                .accessibilityIdentifier("onboarding.shortcut")
                Text(launcher.message ?? "Or open Sofla from Applications or the Dock.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Optional. Your other keyboard shortcuts stay as they are.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .startup:
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { setup.wantsLogin }, set: { setup.setLogin($0) }
                    )
                )
                .toggleStyle(.switch).accessibilityIdentifier("onboarding.login")
                Text("Optional. Change this anytime in Sofla Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                if setup.wantsLogin {
                    if setup.login.status == .enabled {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).accessibilityIdentifier(
                                "onboarding.loginEnabled")
                    } else {
                        Text(
                            setup.login.status == .notFound
                                ? "Move Sofla to Applications, reopen it, and try again."
                                : "Allow Sofla in System Settings → General → Login Items & Extensions."
                        )
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open System Settings") { setup.login.openSystemSettings() }
                                .accessibilityIdentifier("onboarding.loginApproval")
                            Button("Check again") { setup.refresh() }
                                .accessibilityIdentifier("onboarding.recheck")
                        }
                        if setup.login.status != .requiresApproval {
                            Button("Try enabling again") { setup.setLogin(true) }
                                .accessibilityIdentifier("onboarding.retryLogin")
                        }
                        Button("Continue without Open at Login") { setup.setLogin(false) }
                            .accessibilityIdentifier("onboarding.skipLogin")
                    }
                }
            }
            .padding(20).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
