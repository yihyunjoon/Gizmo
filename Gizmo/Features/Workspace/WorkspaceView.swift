import CoreGraphics
import Combine
import SwiftUI

struct WorkspaceView: View {
  private struct WindowCatalogEntry: Equatable {
    let windowNumber: Int
    let ownerName: String
    let title: String
    let frame: CGRect
    let isOnscreen: Bool
    let layer: Int
  }

  @Environment(AccessibilityPermissionService.self)
  private var accessibilityPermissionService
  @Environment(VirtualWorkspaceService.self)
  private var workspaceService

  @State private var windowCatalog: [Int: WindowCatalogEntry] = [:]

  private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var snapshot: VirtualWorkspaceDebugSnapshot {
    workspaceService.debugSnapshot()
  }

  var body: some View {
    Form {
      Section {
        LabeledContent(
          String(localized: "Workspace Enabled"),
          value: snapshot.state.enabled
            ? String(localized: "Enabled")
            : String(localized: "Disabled")
        )
        LabeledContent(
          String(localized: "Active Workspace"),
          value: snapshot.state.activeWorkspaceName
        )
        LabeledContent(
          String(localized: "Previous Workspace"),
          value: snapshot.state.previousWorkspaceName ?? "-"
        )
        LabeledContent(
          String(localized: "Managed Window Count"),
          value: "\(snapshot.managedWindowKeys.count)"
        )
        LabeledContent(
          String(localized: "Hidden Managed Windows"),
          value: "\(snapshot.hiddenWindowKeys.count)"
        )

        if !accessibilityPermissionService.isGranted {
          Text(String(localized: "Accessibility permission is required for accurate window tracking."))
            .font(.footnote)
            .foregroundStyle(.red)
        }

        Button(String(localized: "Refresh Window Snapshot")) {
          refreshWindowCatalog()
        }
        .buttonStyle(.bordered)
      } header: {
        Text(String(localized: "Workspace Status"))
      }

      Section {
        ForEach(snapshot.state.workspaceNames, id: \.self) { workspaceName in
          let keys = snapshot.workspaceWindows[workspaceName, default: []]
          VStack(alignment: .leading, spacing: 6) {
            Text("\(workspaceName) (\(keys.count))")
              .font(.system(size: 13, weight: .semibold, design: .rounded))

            if keys.isEmpty {
              Text(String(localized: "No managed windows in this workspace."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
              ForEach(keys, id: \.self) { windowKey in
                Text(windowDisplayName(for: windowKey))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(.vertical, 2)
        }
      } header: {
        Text(String(localized: "Workspace Mapping"))
      }
    }
    .formStyle(.grouped)
    .onAppear {
      accessibilityPermissionService.refresh()
      refreshWindowCatalog()
    }
    .onReceive(refreshTimer) { _ in
      refreshWindowCatalog()
    }
  }

  private func refreshWindowCatalog() {
    let options: CGWindowListOption = [.excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
      windowCatalog = [:]
      return
    }

    var mapped: [Int: WindowCatalogEntry] = [:]

    for window in windows {
      let layer = intValue(for: "kCGWindowLayer", in: window)
      guard layer == 0 else { continue }

      let windowNumber = intValue(for: "kCGWindowNumber", in: window)
      guard windowNumber > 0 else { continue }

      let ownerName = stringValue(for: "kCGWindowOwnerName", in: window)
      let title = stringValue(for: "kCGWindowName", in: window)
      let frame = frameValue(from: window["kCGWindowBounds"] as? [String: Any] ?? [:])
      let isOnscreen = intValue(for: "kCGWindowIsOnscreen", in: window) == 1

      mapped[windowNumber] = WindowCatalogEntry(
        windowNumber: windowNumber,
        ownerName: ownerName.isEmpty ? String(localized: "Unknown App") : ownerName,
        title: title,
        frame: frame,
        isOnscreen: isOnscreen,
        layer: layer
      )
    }

    windowCatalog = mapped
  }

  private func windowDisplayName(for windowKey: WindowKey) -> String {
    guard let windowNumber = windowNumber(from: windowKey),
      let catalogEntry = windowCatalog[windowNumber]
    else {
      if let debugName = snapshot.windowDisplayNames[windowKey] {
        return debugName
      }
      return String(localized: "Unknown Window")
    }

    if !catalogEntry.title.isEmpty {
      return "\(catalogEntry.ownerName) - \(catalogEntry.title)"
    }

    return "\(catalogEntry.ownerName) (#\(catalogEntry.windowNumber))"
  }

  private func windowNumber(from windowKey: WindowKey) -> Int? {
    guard windowKey.hasPrefix("axwn:") else { return nil }
    return Int(windowKey.dropFirst("axwn:".count))
  }

  private func intValue(for key: String, in dict: [String: Any]) -> Int {
    if let value = dict[key] as? Int { return value }
    if let value = dict[key] as? NSNumber { return value.intValue }
    return 0
  }

  private func stringValue(for key: String, in dict: [String: Any]) -> String {
    dict[key] as? String ?? ""
  }

  private func frameValue(from bounds: [String: Any]) -> CGRect {
    let x = doubleValue(for: "X", in: bounds)
    let y = doubleValue(for: "Y", in: bounds)
    let width = doubleValue(for: "Width", in: bounds)
    let height = doubleValue(for: "Height", in: bounds)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func doubleValue(for key: String, in dict: [String: Any]) -> Double {
    if let value = dict[key] as? Double { return value }
    if let value = dict[key] as? NSNumber { return value.doubleValue }
    return 0
  }
}

#Preview {
  WorkspaceView()
    .environment(ConfigStore())
    .environment(AccessibilityPermissionService())
    .environment(
      VirtualWorkspaceService(
        permissionService: AccessibilityPermissionService(),
        initialConfig: .default
      )
    )
}
