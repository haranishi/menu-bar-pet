import Darwin

struct TestCase: Sendable {
    let name: String
    let body: @Sendable () throws -> Void
}

struct AssertionFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func require(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "assertion failed"
) throws {
    guard condition() else { throw AssertionFailure(message: message()) }
}

let tests = petMotionTests + petStateMachineTests + aiUsageTests + aiUsageReviewTests
    + menuBarReadoutTests + rustIntegrationTests + runnerGaitTests
guard tests.count == 74 else {
    print("FAIL: expected 74 tests, found \(tests.count)")
    exit(EXIT_FAILURE)
}
var passed = 0

for (index, test) in tests.enumerated() {
    do {
        try test.body()
        passed += 1
        print("PASS [\(index + 1)/\(tests.count)]: \(test.name)")
    } catch {
        print("FAIL [\(index + 1)/\(tests.count)]: \(test.name) — \(error)")
    }
}

let failed = tests.count - passed
print("RESULT: \(passed)/\(tests.count) passed, \(failed) failed")
exit(failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
