import Foundation
import XCTest

// A real app bundle supplies the identity required by UNUserNotificationCenter.
// Load the existing SwiftPM XCTest bundle; do not duplicate its test inventory.
guard CommandLine.arguments.count == 2,
      let bundle = Bundle(path: CommandLine.arguments[1]) else {
    fatalError("Expected the path to the macOS XCTest bundle")
}
try bundle.loadAndReturnError()
let suite = XCTestSuite.default
suite.run()
guard let result = suite.testRun else {
    fatalError("XCTest did not produce a result")
}
print("Native test host: \(result.executionCount) tests, \(result.totalFailureCount) failures, \(result.skipCount) skips")
exit(result.executionCount > 0 && result.totalFailureCount == 0 && result.skipCount == 0 ? 0 : 1)
