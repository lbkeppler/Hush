import SwiftUI

/// Top-level navigation destinations in the main window's sidebar.
enum Section: String, CaseIterable, Identifiable {
    case now
    case sound
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .sound: "Sound"
        case .settings: "Settings"
        }
    }

    var systemIcon: String {
        switch self {
        case .now: "moon.stars.fill"
        case .sound: "slider.horizontal.3"
        case .settings: "gearshape.fill"
        }
    }
}

/// The full Hush window: a device-summary + navigation sidebar on the left, and a detail
/// area on the right that switches per selected `Section`. `.now` (modes), `.sound` (EQ),
/// and `.settings` (sidetone/toggles/name/multipoint) are all fully implemented here.
/// "Quiet instrument" styling via `DT` tokens, theme-aware through `colorScheme`.
public struct MainWindow: View {
    public var controller: BoseController
    @State private var section: Section = .now

    @Environment(\.colorScheme) private var scheme

    public init(controller: BoseController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)
                .background(DT.surface(scheme))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DT.ink(scheme))
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceSummary
                .padding(20)

            Divider()
                .padding(.horizontal, 20)

            navList
                .padding(.top, 12)

            Spacer(minLength: 0)

            Divider()

            connectionFooter
                .padding(16)
        }
    }

    private var deviceSummary: some View {
        HStack(spacing: 12) {
            if let battery = controller.state.battery {
                BatteryArc(percent: battery)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.state.name ?? "Hush")
                    .font(DT.display(16))
                    .foregroundStyle(DT.text(scheme))
                    .lineLimit(1)

                if let firmware = controller.state.firmware {
                    Text("Firmware \(firmware)")
                        .font(DT.body(11))
                        .foregroundStyle(DT.muted(scheme))
                        .lineLimit(1)
                }
            }
        }
    }

    private var navList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                navRow(item)
            }
        }
        .padding(.horizontal, 12)
    }

    private func navRow(_ item: Section) -> some View {
        let active = section == item
        return Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? DT.accent(scheme) : .clear)
                    .frame(width: 3, height: 18)

                Image(systemName: item.systemIcon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)

                Text(item.title)
                    .font(DT.body(13))

                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? DT.accent(scheme) : DT.text(scheme))
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? DT.accent(scheme).opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(DT.body(12))
                .foregroundStyle(DT.muted(scheme))
                .lineLimit(1)

            if case .error = controller.state.status {
                Spacer(minLength: 8)
                Button {
                    Task { await controller.start() }
                } label: {
                    Text("Retry")
                        .font(DT.body(12))
                        .foregroundStyle(DT.text(scheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectionColor: Color {
        switch controller.state.status {
        case .connected: DT.accent(scheme)
        case .connecting: DT.muted(scheme)
        case .disconnected, .error: DT.muted(scheme).opacity(0.4)
        }
    }

    private var statusText: String {
        switch controller.state.status {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Disconnected"
        case .error(let message): message
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .now:
            ModesSection(controller: controller)
        case .sound:
            SoundSection(controller: controller)
        case .settings:
            SettingsSection(controller: controller)
        }
    }
}

#Preview {
    MainWindow(controller: BoseController(makeProvider: {
        struct Unavailable: Error {}
        throw Unavailable()
    }))
}
