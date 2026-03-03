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

  @Environment(ConfigStore.self) private var configStore
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
          String(localized: "Hide Strategy"),
          value: configStore.active.workspace.hideStrategy.rawValue
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
        Text(String(localized: "Only windows moved via workspace commands become managed windows."))
        Text(String(localized: "Unmanaged windows stay visible across all workspaces."))
        Text(String(localized: "Managed windows in inactive workspaces are hidden by moving them off-screen."))
      } header: {
        Text(String(localized: "How Gizmo Workspace Works"))
      }

      Section {
        if snapshot.managedWindowKeys.isEmpty {
          Text(String(localized: "No managed windows yet."))
            .foregroundStyle(.secondary)
        } else {
          ForEach(snapshot.managedWindowKeys, id: \.self) { windowKey in
            managedWindowRow(
              windowKey: windowKey,
              isHidden: snapshot.hiddenWindowKeys.contains(windowKey)
            )
          }
        }
      } header: {
        Text(String(localized: "Managed Windows"))
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

  @ViewBuilder
  private func managedWindowRow(
    windowKey: WindowKey,
    isHidden: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(windowDisplayName(for: windowKey))
          .font(.system(size: 13, weight: .medium))

        if isHidden {
          Text(String(localized: "Hidden"))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.16))
            .clipShape(Capsule())
        } else {
          Text(String(localized: "Visible"))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green.opacity(0.16))
            .clipShape(Capsule())
        }
      }

      if let windowNumber = windowNumber(from: windowKey),
        let catalogEntry = windowCatalog[windowNumber]
      {
        Text(windowMetaText(for: catalogEntry))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("id: \(windowKey)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
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

  private func windowMetaText(for entry: WindowCatalogEntry) -> String {
    let frame = entry.frame
    let frameText = String(
      format: "frame: %.0f, %.0f %.0fx%.0f",
      frame.minX,
      frame.minY,
      frame.width,
      frame.height
    )
    let visibilityText = entry.isOnscreen
      ? String(localized: "onscreen")
      : String(localized: "offscreen")

    return "\(frameText) · \(visibilityText)"
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
