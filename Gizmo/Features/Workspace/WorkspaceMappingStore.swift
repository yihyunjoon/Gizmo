import CoreGraphics
import Foundation

struct PersistedWindowFrame: Codable, Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  init(rect: CGRect) {
    self.init(
      x: rect.origin.x,
      y: rect.origin.y,
      width: rect.width,
      height: rect.height
    )
  }

  var rect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
}

struct WorkspaceMappingSnapshot: Codable, Equatable {
  static let currentVersion = 2

  var version: Int
  var activeWorkspaceNamesByDisplay: [String: String]
  var workspaceWindows: [String: [WindowKey]]
  var savedFrames: [WindowKey: PersistedWindowFrame]

  private enum CodingKeys: String, CodingKey {
    case version
    case activeWorkspaceName
    case activeWorkspaceNamesByDisplay
    case workspaceWindows
    case savedFrames
  }

  init(
    version: Int = currentVersion,
    activeWorkspaceNamesByDisplay: [String: String] = [:],
    workspaceWindows: [String: [WindowKey]],
    savedFrames: [WindowKey: PersistedWindowFrame] = [:]
  ) {
    self.version = version
    self.activeWorkspaceNamesByDisplay = activeWorkspaceNamesByDisplay
    self.workspaceWindows = workspaceWindows
    self.savedFrames = savedFrames
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    workspaceWindows = try container.decode(
      [String: [WindowKey]].self,
      forKey: .workspaceWindows
    )
    savedFrames = try container.decodeIfPresent(
      [WindowKey: PersistedWindowFrame].self,
      forKey: .savedFrames
    ) ?? [:]

    if version == 1 {
      let primaryActiveWorkspaceName = try container.decodeIfPresent(
        String.self,
        forKey: .activeWorkspaceName
      )
      activeWorkspaceNamesByDisplay = primaryActiveWorkspaceName.map {
        [WorkspaceDisplayRole.primary.rawValue: $0]
      } ?? [:]
      version = Self.currentVersion
      return
    }

    activeWorkspaceNamesByDisplay = try container.decodeIfPresent(
      [String: String].self,
      forKey: .activeWorkspaceNamesByDisplay
    ) ?? [:]
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(activeWorkspaceNamesByDisplay, forKey: .activeWorkspaceNamesByDisplay)
    try container.encode(workspaceWindows, forKey: .workspaceWindows)
    try container.encode(savedFrames, forKey: .savedFrames)
  }
}

protocol WorkspaceMappingStore {
  func load() -> WorkspaceMappingSnapshot?
  func save(_ snapshot: WorkspaceMappingSnapshot)
}

final class FileWorkspaceMappingStore: WorkspaceMappingStore {
  private let fileManager: FileManager
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    fileURL: URL? = nil,
    fileManager: FileManager = .default,
    pathResolver: ConfigPathResolver = ConfigPathResolver()
  ) {
    self.fileManager = fileManager
    self.fileURL = fileURL ?? pathResolver.resolveWorkspaceMappingURL()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder = encoder
    self.decoder = JSONDecoder()
  }

  func load() -> WorkspaceMappingSnapshot? {
    guard fileManager.fileExists(atPath: fileURL.path()) else {
      return nil
    }

    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }

    guard
      let snapshot = try? decoder.decode(
        WorkspaceMappingSnapshot.self,
        from: data
      )
    else {
      return nil
    }

    guard snapshot.version == WorkspaceMappingSnapshot.currentVersion else {
      return nil
    }

    return snapshot
  }

  func save(_ snapshot: WorkspaceMappingSnapshot) {
    do {
      let parentDirectoryURL = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(
        at: parentDirectoryURL,
        withIntermediateDirectories: true
      )

      let data = try encoder.encode(snapshot)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      assertionFailure("Failed to persist workspace mapping: \(error)")
    }
  }
}
