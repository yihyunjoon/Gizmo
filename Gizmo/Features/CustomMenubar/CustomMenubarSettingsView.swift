import SwiftUI

struct CustomMenubarSettingsView: View {
  @Environment(ConfigStore.self) private var configStore

  var body: some View {
    Form {
      Section {
        LabeledContent(
          String(localized: "Enabled"),
          value: configStore.active.customMenubar.enabled
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
        )

        LabeledContent(
          String(localized: "Border"),
          value: configStore.active.customMenubar.border
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
        )

        LabeledContent(
          String(localized: "Display Scope"),
          value: String(localized: "Primary Display")
        )

        LabeledContent(
          String(localized: "Position"),
          value: configStore.active.customMenubar.position.titleText
        )

        LabeledContent(
          String(localized: "Height"),
          value: String(format: "%.0f", configStore.active.customMenubar.height)
        )

        LabeledContent(
          String(localized: "Widgets"),
          value: configStore.active.customMenubar.widgets.titleText
        )

        LabeledContent(
          String(localized: "Background Opacity"),
          value: String(format: "%.2f", configStore.active.customMenubar.backgroundOpacity)
        )

        LabeledContent(
          String(localized: "Horizontal Padding"),
          value: String(format: "%.0f", configStore.active.customMenubar.horizontalPadding)
        )

        LabeledContent(
          String(localized: "Clock 24H"),
          value: configStore.active.customMenubar.clock24h
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
        )

        Text(
          String(
            localized:
              "Custom menubar options are configured in config.toml under [custom_menubar]."
          )
        )
        .foregroundStyle(.secondary)
        .font(.footnote)
      } header: {
        Text(String(localized: "Custom Menubar"))
      }
    }
    .formStyle(.grouped)
  }
}

private extension CustomMenubarPosition {
  var titleText: String {
    switch self {
    case .top:
      return String(localized: "Top")
    case .bottom:
      return String(localized: "Bottom")
    }
  }
}

private extension Array where Element == CustomMenubarWidget {
  var titleText: String {
    let names = map { widget in
      switch widget {
      case .clock:
        return String(localized: "Clock")
      case .frontApp:
        return String(localized: "Front App")
      }
    }

    return names.joined(separator: ", ")
  }
}

#Preview {
  CustomMenubarSettingsView()
    .environment(ConfigStore())
}
