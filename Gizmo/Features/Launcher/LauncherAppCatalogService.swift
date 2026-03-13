import Foundation
import Observation

@Observable
@MainActor
final class LauncherAppCatalogService {
  private enum Storage {
    static let cacheKey = "launcher.installedApps.v1"
  }

  private struct RankedApplication {
    let target: LauncherApplicationTarget
    let rootPriority: Int
  }

  private let userDefaults: UserDefaults
  private let scanRoots: [URL]
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  private var isRefreshing = false
  private var hasPendingRefresh = false

  private(set) var applications: [LauncherApplicationTarget]
  var onApplicationsDidChange: (([LauncherApplicationTarget]) -> Void)?

  init(
    userDefaults: UserDefaults = .standard,
    scanRoots: [URL]? = nil
  ) {
    self.userDefaults = userDefaults
    self.scanRoots = scanRoots ?? Self.defaultScanRoots()
    self.applications = []
    self.applications = loadCachedApplications()
  }

  func refreshInBackground() {
    guard !isRefreshing else {
      hasPendingRefresh = true
      return
    }

    isRefreshing = true
    let roots = scanRoots

    Task { [weak self] in
      let discoveredApplications = await Task.detached(priority: .utility) {
        Self.discoverApplications(scanRoots: roots)
      }.value

      self?.applyRefreshResult(discoveredApplications)
    }
  }

  private func applyRefreshResult(_ discoveredApplications: [LauncherApplicationTarget]) {
    isRefreshing = false

    if discoveredApplications != applications {
      applications = discoveredApplications
      persistApplications()
      onApplicationsDidChange?(applications)
    }

    if hasPendingRefresh {
      hasPendingRefresh = false
      refreshInBackground()
    }
  }

  private func loadCachedApplications() -> [LauncherApplicationTarget] {
    guard let data = userDefaults.data(forKey: Storage.cacheKey) else {
      return []
    }

    do {
      return try decoder.decode([LauncherApplicationTarget].self, from: data)
    } catch {
      userDefaults.removeObject(forKey: Storage.cacheKey)
      return []
    }
  }

  private func persistApplications() {
    do {
      let data = try encoder.encode(applications)
      userDefaults.set(data, forKey: Storage.cacheKey)
    } catch {
      assertionFailure("Failed to persist launcher app catalog: \(error)")
    }
  }

  private nonisolated static func defaultScanRoots() -> [URL] {
    let homeApplications = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)

    return [
      homeApplications,
      URL(filePath: "/Applications", directoryHint: .isDirectory),
      URL(filePath: "/System/Applications", directoryHint: .isDirectory),
    ]
  }

  private nonisolated static func discoverApplications(
    scanRoots: [URL]
  ) -> [LauncherApplicationTarget] {
    var dedupedApplications: [String: RankedApplication] = [:]

    for (rootPriority, rootURL) in scanRoots.enumerated() {
      guard FileManager.default.fileExists(atPath: rootURL.path()) else {
        continue
      }

      for candidateURL in applicationCandidateURLs(in: rootURL) {
        let target = makeApplicationTarget(at: candidateURL)
        let dedupeKey = target.bundleIdentifier?.lowercased() ?? candidateURL.path().lowercased()

        if let existing = dedupedApplications[dedupeKey] {
          if shouldReplace(existing: existing, withRootPriority: rootPriority, candidateURL: candidateURL)
          {
            dedupedApplications[dedupeKey] = RankedApplication(
              target: target,
              rootPriority: rootPriority
            )
          }
          continue
        }

        dedupedApplications[dedupeKey] = RankedApplication(
          target: target,
          rootPriority: rootPriority
        )
      }
    }

    return dedupedApplications.values
      .map(\.target)
      .sorted { lhs, rhs in
        let primary = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if primary != .orderedSame {
          return primary == .orderedAscending
        }

        return lhs.bundleURL.path().localizedStandardCompare(rhs.bundleURL.path()) == .orderedAscending
      }
  }

  private nonisolated static func applicationCandidateURLs(in rootURL: URL) -> [URL] {
    var candidateURLs: [URL] = []
    var seenPaths: Set<String> = []

    func appendCandidate(_ candidateURL: URL) {
      guard candidateURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
        return
      }

      let standardizedURL = candidateURL.standardizedFileURL
      guard seenPaths.insert(standardizedURL.path).inserted else {
        return
      }

      candidateURLs.append(standardizedURL)
    }

    if let enumerator = FileManager.default.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants],
      errorHandler: { _, _ in true }
    ) {
      for case let candidateURL as URL in enumerator {
        appendCandidate(candidateURL)
      }
    }

    for candidateURL in topLevelApplicationSymlinks(in: rootURL) {
      appendCandidate(candidateURL)
    }

    return candidateURLs
  }

  private nonisolated static func topLevelApplicationSymlinks(in rootURL: URL) -> [URL] {
    guard
      let childURLs = try? FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: []
      )
    else {
      return []
    }

    return childURLs.filter { childURL in
      guard childURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
        return false
      }

      let resourceValues = try? childURL.resourceValues(forKeys: [.isSymbolicLinkKey])
      return resourceValues?.isSymbolicLink == true
    }
  }

  private nonisolated static func shouldReplace(
    existing: RankedApplication,
    withRootPriority candidateRootPriority: Int,
    candidateURL: URL
  ) -> Bool {
    if candidateRootPriority != existing.rootPriority {
      return candidateRootPriority < existing.rootPriority
    }

    return candidateURL.path().localizedStandardCompare(existing.target.bundleURL.path()) == .orderedAscending
  }

  private nonisolated static func makeApplicationTarget(
    at appURL: URL
  ) -> LauncherApplicationTarget {
    let bundle = Bundle(url: appURL)
    let bundleIdentifier = normalizedBundleIdentifier(from: bundle)

    return LauncherApplicationTarget(
      stableID: stableID(forBundleIdentifier: bundleIdentifier, bundleURL: appURL),
      displayName: displayName(from: bundle, fallbackURL: appURL),
      bundleIdentifier: bundleIdentifier,
      bundleURL: appURL
    )
  }

  private nonisolated static func normalizedBundleIdentifier(from bundle: Bundle?) -> String? {
    guard let bundleIdentifier = bundle?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
      !bundleIdentifier.isEmpty
    else {
      return nil
    }

    return bundleIdentifier
  }

  private nonisolated static func displayName(from bundle: Bundle?, fallbackURL: URL) -> String {
    let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let bundleName = bundle?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String

    let candidates = [displayName, bundleName, fallbackURL.deletingPathExtension().lastPathComponent]

    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty {
        return trimmed
      }
    }

    return fallbackURL.lastPathComponent
  }

  private nonisolated static func stableID(
    forBundleIdentifier bundleIdentifier: String?,
    bundleURL: URL
  ) -> String {
    let rawIdentifier = bundleIdentifier?.lowercased() ?? bundleURL.path().lowercased()

    return Data(rawIdentifier.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
