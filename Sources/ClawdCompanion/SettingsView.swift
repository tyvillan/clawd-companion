import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    /// Observed so the notification row can report a denial instead of the
    /// toggle sitting on while nothing ever appears.
    @ObservedObject var alerter: CompletionAlerter

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $settings.scaleMultiplier, in: Settings.scaleRange)
                        Text(String(format: "%.2f\u{00d7}", settings.scaleMultiplier))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Text("Relative to the size measured from your Dock. Applies immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Movement") {
                LabeledContent("Walk speed") {
                    HStack {
                        Slider(value: $settings.walkSpeed, in: Settings.walkSpeedRange)
                        Text("\(Int(settings.walkSpeed)) pt/s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                Toggle("Wander between Dock icons when idle", isOn: $settings.idleWanderEnabled)
                Toggle("Walk to the app a tool is using", isOn: $settings.walkToTargetEnabled)
                Toggle("Walk home when VS Code regains focus", isOn: $settings.walkHomeEnabled)
            }

            Section("Full-screen peek") {
                Toggle("Peek up to signal a finished response", isOn: $settings.peekEnabled)
                LabeledContent("Hold for") {
                    HStack {
                        Slider(value: $settings.peekDuration, in: Settings.peekDurationRange)
                        Text(String(format: "%.1fs", settings.peekDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!settings.peekEnabled)
                Text("Only applies while another app is in full screen, where the Dock is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Text("When a response finishes, or a prompt needs your attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Play a sound", isOn: $settings.soundEnabled)
                LabeledContent("Sound") {
                    HStack {
                        Picker("", selection: $settings.soundName) {
                            ForEach(Settings.availableSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        Button("Preview") { CompletionAlerter.preview(sound: settings.soundName) }
                    }
                }
                .disabled(!settings.soundEnabled)
                Toggle("Show a notification", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled { alerter.requestNotificationAuthorizationIfNeeded() }
                    }
                if settings.notificationsEnabled, alerter.notificationsAuthorized == false {
                    Text(
                        "macOS is blocking notifications for Clawd. Turn them on in "
                            + "System Settings \u{203a} Notifications \u{203a} ClawdCompanion."
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        // Deliberately no minHeight: pinning one taller than the window made
        // the hosting view overflow and clip the last section instead of
        // letting the Form scroll inside the window.
    }
}
