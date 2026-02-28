import SwiftUI

struct WindowManagerView: View {
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
    .environment(AccessibilityPermissionService())
    .environment(
      WindowManagerService(permissionService: AccessibilityPermissionService())
    )
}
