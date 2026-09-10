import SwiftUI

/// The Settings section: sidetone level, auto-pause/auto-answer toggles, an editable device
/// name, and a read-only multipoint status row. Each live control is wired directly to a
/// `BoseController` intent (debounced internally by the controller); multipoint is
/// display-only because its write path is unreliable on-device.
public struct SettingsSection: View {
    public var controller: BoseController

    @Environment(\.colorScheme) private var scheme

    /// Local draft for the device-name field; seeded from `state.name` on appear so typing
    /// doesn't fight a live-reflected binding, and only committed via the Save button.
    @State private var nameDraft: String = ""

    public init(controller: BoseController) {
        self.controller = controller
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                sidetoneCard
                togglesCard
                nameCard
                multipointCard

                if let lastError = controller.state.lastError {
                    Text(lastError)
                        .font(DT.body(11))
                        .foregroundStyle(DT.muted(scheme))
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            nameDraft = controller.state.name ?? ""
        }
    }

    // MARK: - Sidetone

    /// Label -> BMAP level. BoseKit encodes sidetone as 0=off, 1=high, 2=medium, 3=low, so
    /// the UI's natural Off/Low/Medium/High ordering does NOT match the raw level order.
    private let sidetoneOptions: [(title: String, level: Int)] = [
        ("Off", 0),
        ("Low", 3),
        ("Medium", 2),
        ("High", 1),
    ]

    private var sidetoneCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sidetone")
                    .font(DT.body(12))
                    .foregroundStyle(DT.muted(scheme))

                HStack(spacing: 8) {
                    ForEach(sidetoneOptions, id: \.title) { option in
                        ModeChip(
                            title: option.title,
                            active: controller.state.sidetone == option.level
                        ) {
                            controller.setSidetone(option.level)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toggles

    private var togglesCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                toggleRow(
                    title: "Auto-pause on removal",
                    isOn: Binding(
                        get: { controller.state.autoPause ?? false },
                        set: { controller.setAutoPause($0) }
                    )
                )

                Divider()

                toggleRow(
                    title: "Auto-answer calls",
                    isOn: Binding(
                        get: { controller.state.autoAnswer ?? false },
                        set: { controller.setAutoAnswer($0) }
                    )
                )
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(DT.body(13))
                .foregroundStyle(DT.text(scheme))
            Spacer()
            HushToggle(isOn: isOn)
        }
    }

    // MARK: - Device name

    private var nameCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Device name")
                    .font(DT.body(12))
                    .foregroundStyle(DT.muted(scheme))

                HStack(spacing: 12) {
                    TextField("Device name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(DT.body(13))
                        .foregroundStyle(DT.text(scheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DT.ink(scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DT.hairline(scheme), lineWidth: 1)
                        )
                        .onSubmit { save() }

                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(DT.body(13))
                            .foregroundStyle(hasPendingNameChange ? DT.accent(scheme) : DT.text(scheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(hasPendingNameChange ? DT.accent(scheme).opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(hasPendingNameChange ? DT.accent(scheme) : DT.hairline(scheme), lineWidth: 1)
                            )
                            .opacity(hasPendingNameChange ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasPendingNameChange)
                }
            }
        }
        .frame(maxWidth: 420)
    }

    /// Save only lights up champagne (DT.accent) — the active/pending-change state — when
    /// the draft differs from the device's current name and isn't blank/whitespace-only.
    private var hasPendingNameChange: Bool {
        nameDraft != controller.state.name && !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        nameDraft = trimmed
        controller.setName(trimmed)
    }

    // MARK: - Multipoint (read-only)

    private var multipointCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Multipoint")
                        .font(DT.body(13))
                        .foregroundStyle(DT.text(scheme))
                    Spacer()
                    Text(multipointText)
                        .font(DT.body(13))
                        .foregroundStyle(DT.muted(scheme))
                }

                Text("Changes apply on the device.")
                    .font(DT.body(11))
                    .foregroundStyle(DT.muted(scheme))
            }
        }
    }

    private var multipointText: String {
        guard let multipoint = controller.state.multipoint else { return "—" }
        return multipoint ? "On" : "Off"
    }
}

#Preview {
    SettingsSection(controller: BoseController(makeProvider: {
        struct Unavailable: Error {}
        throw Unavailable()
    }))
}
