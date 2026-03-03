import CoreGraphics
import XCTest
@testable import Gizmo

final class WindowManagerLayoutCalculatorTests: XCTestCase {
  func testApplyOuterGapsAddsOnTopOfCustomBarAdjustedFrame() {
    let baseVisibleAfterCustomBar = CGRect(x: 0, y: 20, width: 200, height: 120)
    let outer = WindowManagerOuterGaps(
      left: 10,
      top: 10,
      right: 10,
      bottom: 40
    )

    let adjusted = WindowManagerLayoutCalculator.applyOuterGaps(
      to: baseVisibleAfterCustomBar,
      outerGaps: outer
    )

    XCTAssertEqual(adjusted.minY, 60)
    XCTAssertEqual(adjusted.height, 70)
  }

  func testLeftAndRightHalfRespectInnerHorizontalGap() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 100, height: 80)

    let left = WindowManagerLayoutCalculator.targetFrame(
      for: .leftHalf,
      in: visibleFrame,
      innerHorizontalGap: 4
    )
    let right = WindowManagerLayoutCalculator.targetFrame(
      for: .rightHalf,
      in: visibleFrame,
      innerHorizontalGap: 4
    )

    XCTAssertEqual(left.width, 48)
    XCTAssertEqual(right.width, 48)
    XCTAssertEqual(right.minX - left.maxX, 4)
  }

  func testExcessiveOuterGapsCanProduceInvalidFrame() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 50, height: 50)
    let outer = WindowManagerOuterGaps(
      left: 30,
      top: 30,
      right: 20,
      bottom: 20
    )

    let adjusted = WindowManagerLayoutCalculator.applyOuterGaps(
      to: visibleFrame,
      outerGaps: outer
    )

    XCTAssertLessThan(adjusted.width, 1)
    XCTAssertLessThan(adjusted.height, 1)
  }
}
