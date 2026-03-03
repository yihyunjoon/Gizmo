import SwiftUI

struct WindowManagerView: View {
  @Environment(ConfigStore.self) private var configStore
  @Environment(AccessibilityPermissionService.self)
  private var accessibilityPermissionService
  @Environment(WindowManagerService.self)
  private var windowManagerService

  @State private var lastError: WindowManagerError?
  @State private var lastSucceededAction: WindowTileAction?

  var body: some View {
    Form {
      Section {
        LabeledContent(
          String(localized: "Status"),
          value: accessibilityPermissionService.isGranted
            ? String(localized: "Permission Granted")
            : String(localized: "Permission Required")
        )

        HStack(spacing: 8) {
          Button(String(localized: "Grant Access")) {
            accessibilityPermissionService.requestPermissionPrompt()
          }
          .buttonStyle(.borderedProminent)

          Button(String(localized: "Open System Settings")) {
            accessibilityPermissionService.openSystemSettings()
          }
          .buttonStyle(.bordered)
        }
      } header: {
        Text(String(localized: "Accessibility Permission"))
      }

      Section {
        Button(String(localized: "Tile left half")) {
          execute(.leftHalf)
        }

        Button(String(localized: "Tile right half")) {
          execute(.rightHalf)
        }

        Button(String(localized: "Place center")) {
          execute(.placeCenter)
        }

        if let lastError {
          Text(lastError.localizedDescription)
            .foregroundStyle(.red)
            .font(.footnote)
        } else if let lastSucceededAction {
          Text("Executed: \(lastSucceededAction.commandTitle)")
          .foregroundStyle(.secondary)
          .font(.footnote)
        }
      } header: {
        Text(String(localized: "Test Commands"))
      }

      Section {
        LabeledContent(
          String(localized: "Inner Horizontal"),
          value: String(format: "%.0f", configStore.active.gaps.inner.horizontal)
        )
        LabeledContent(
          String(localized: "Inner Vertical"),
          value: String(format: "%.0f", configStore.active.gaps.inner.vertical)
        )
        LabeledContent(
          String(localized: "Outer Left"),
          value: String(format: "%.0f", configStore.active.gaps.outer.left)
        )
        LabeledContent(
          String(localized: "Outer Top"),
          value: String(format: "%.0f", configStore.active.gaps.outer.top)
        )
        LabeledContent(
          String(localized: "Outer Right"),
          value: String(format: "%.0f", configStore.active.gaps.outer.right)
        )
        LabeledContent(
          String(localized: "Outer Bottom"),
          value: String(format: "%.0f", configStore.active.gaps.outer.bottom)
        )

        Text(
          String(
            localized:
              "Window gaps are configured in config.toml under [gaps]."
          )
        )
        .foregroundStyle(.secondary)
        .font(.footnote)
      } header: {
        Text(String(localized: "Window Gaps"))
      }
    }
    .formStyle(.grouped)
    .onAppear {
      accessibilityPermissionService.refresh()
    }
  }

  private func execute(_ action: WindowTileAction) {
    switch windowManagerService.execute(action) {
    case .success:
      lastError = nil
      lastSucceededAction = action
    case .failure(let error):
      lastSucceededAction = nil
      lastError = error
    }
  }
}

#Preview {
  WindowManagerView()
    .environment(ConfigStore())
    .environment(AccessibilityPermissionService())
    .environment(
      WindowManagerService(permissionService: AccessibilityPermissionService())
    )
}
