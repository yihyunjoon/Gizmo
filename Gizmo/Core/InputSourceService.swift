import Carbon
import Foundation

@MainActor
enum InputSourceService {
  private static let preferredEnglishInputSourceIDs = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
  ]

  private static var cachedEnglishInputSource: TISInputSource?

  static func preloadEnglishInputSource() {
    _ = englishInputSource()
  }

  static func switchToEnglishInputSource() -> String? {
    guard let currentInputSource = currentInputSource() else { return nil }
    guard let currentInputSourceID = inputSourceID(for: currentInputSource) else { return nil }
    guard let englishInputSource = englishInputSource() else { return nil }
    guard let englishInputSourceID = inputSourceID(for: englishInputSource) else { return nil }
    guard currentInputSourceID != englishInputSourceID else { return nil }

    let status = TISSelectInputSource(englishInputSource)
    guard status == noErr else { return nil }

    return currentInputSourceID
  }

  static func selectInputSource(withID inputSourceID: String) {
    guard let inputSource = inputSource(withID: inputSourceID) else { return }
    _ = TISSelectInputSource(inputSource)
  }

  private static func currentInputSource() -> TISInputSource? {
    TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  }

  private static func englishInputSource() -> TISInputSource? {
    if let cachedEnglishInputSource {
      return cachedEnglishInputSource
    }

    for inputSourceID in preferredEnglishInputSourceIDs {
      if let inputSource = inputSource(withID: inputSourceID) {
        cachedEnglishInputSource = inputSource
        return inputSource
      }
    }

    cachedEnglishInputSource = firstASCIICapableKeyboardLayout()
    return cachedEnglishInputSource
  }

  private static func inputSource(withID inputSourceID: String) -> TISInputSource? {
    let filter: NSDictionary = [
      kTISPropertyInputSourceID as String: inputSourceID
    ]
    let inputSources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
    guard let inputSource = inputSources.firstObject else { return nil }
    return (inputSource as! TISInputSource)
  }

  private static func firstASCIICapableKeyboardLayout() -> TISInputSource? {
    let filter: NSDictionary = [
      kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout!
    ]
    let inputSources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray

    for inputSource in inputSources {
      let source = inputSource as! TISInputSource
      guard isASCIICapable(source) else { continue }
      return source
    }

    return nil
  }

  private static func inputSourceID(for inputSource: TISInputSource) -> String? {
    guard let idPointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
      return nil
    }

    return Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
  }

  private static func isASCIICapable(_ inputSource: TISInputSource) -> Bool {
    guard
      let boolPointer = TISGetInputSourceProperty(
        inputSource,
        kTISPropertyInputSourceIsASCIICapable
      )
    else {
      return false
    }

    let value = Unmanaged<CFBoolean>.fromOpaque(boolPointer).takeUnretainedValue()
    return value == kCFBooleanTrue
  }
}
