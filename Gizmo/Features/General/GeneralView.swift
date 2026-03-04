import SwiftUI

struct GeneralView: View {
  @Environment(ConfigStore.self) private var configStore

  var body: some View {
    Form {
      Section {
        LabeledContent(String(localized: "Path"), value: configStore.configURL.path())
          .lineLimit(2)

        HStack(spacing: 8) {
          Button(String(localized: "Open Config")) {
            configStore.openConfigFile()
          }
          .buttonStyle(.bordered)

          Button(String(localized: "Reveal Config")) {
            configStore.revealConfigFile()
          }
          .buttonStyle(.bordered)

          Button(String(localized: "Reload Config")) {
            _ = configStore.reload()
          }
          .buttonStyle(.borderedProminent)
        }

        if let error = configStore.lastLoadError {
          Text(error)
            .foregroundStyle(.red)
            .font(.footnote)
            .textSelection(.enabled)
        }
      } header: {
        Text(String(localized: "Config File"))
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  GeneralView()
    .environment(ConfigStore())
}
