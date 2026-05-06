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
          String(localized: "Custom Widgets"),
          value: configStore.active.customMenubar.customWidgets.keys.sorted().titleText
        )

        LabeledContent(
          String(localized: "Background Opacity"),
          value: String(format: "%.2f", configStore.active.customMenubar.backgroundOpacity)
        )

        LabeledContent(
          String(localized: "Horizontal Padding"),
          value: String(format: "%.0f", configStore.active.customMenubar.horizontalPadding)
        )

        Text(
          String(
            localized:
              "Custom menubar options are configured in config.toml under [custom_menubar], and custom widget definitions live under [custom_widgets.<name>]."
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

private extension Array where Element == String {
  var titleText: String {
    guard !isEmpty else {
      return String(localized: "None")
    }

    let names = map { widgetName in
      widgetName
    }

    return names.joined(separator: ", ")
  }
}

#Preview {
  CustomMenubarSettingsView()
    .environment(ConfigStore())
}
