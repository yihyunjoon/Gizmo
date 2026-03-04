import SwiftUI

struct LauncherView: View {
  @Environment(ConfigStore.self) private var configStore

  var body: some View {
    Form {
      Section {
        LabeledContent(
          String(localized: "Launcher Hot Key"),
          value: configStore.active.launcher.globalHotkey.descriptionText
        )

        Text(
          String(
            localized:
              "Set the launcher hot key in config.toml and press Reload Config."
          )
        )
        .foregroundStyle(.secondary)
        .font(.footnote)
      } header: {
        Text(String(localized: "Global Shortcut"))
      }

      Section {
        LabeledContent(
          String(localized: "Launcher Display"),
          value: configStore.active.launcher.display.titleText
        )

        Text(
          String(
            localized:
              "Choose which display should show the launcher when the global shortcut is pressed."
          )
        )
        .foregroundStyle(.secondary)
        .font(.footnote)
      } header: {
        Text(String(localized: "Display Placement"))
      }

      Section {
        LabeledContent(
          String(localized: "Force English Input Source"),
          value: configStore.active.launcher.forceEnglishInputSource
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
        )

        Text(
          String(
            localized:
              "When enabled, launcher input uses an English keyboard layout while the launcher is open."
          )
        )
        .foregroundStyle(.secondary)
        .font(.footnote)
      } header: {
        Text(String(localized: "Input Source"))
      }
    }
    .formStyle(.grouped)
  }
}

private extension LauncherDisplay {
  var titleText: String {
    switch self {
    case .primary:
      return String(localized: "Primary Display")
    case .mouse:
      return String(localized: "Display With Mouse")
    case .activeWindow:
      return String(localized: "Active Display")
    }
  }
}

#Preview {
  LauncherView()
    .environment(ConfigStore())
}
