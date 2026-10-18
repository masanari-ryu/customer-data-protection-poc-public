import Foundation

// A small dependency-free runner for CLT installations that do not include XCTest.
// It evaluates real assertions, prints only test names/locations, and exits nonzero
// on any failure. It never generates Secure Enclave keys or accepts authentication.
@MainActor
enum TestState {
    static var failures: [String] = []
    static var assertions = 0

    static func evaluate(_ condition: Bool, file: StaticString, line: UInt) {
        assertions += 1
        if !condition { failures.append("\(file):\(line)") }
    }
}

@MainActor
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    TestState.evaluate(actual == expected, file: file, line: line)
}

@MainActor
func checkNotEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    TestState.evaluate(actual != expected, file: file, line: line)
}

@MainActor
func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    TestState.evaluate(value, file: file, line: line)
}

@MainActor
func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    TestState.evaluate(!value, file: file, line: line)
}

@MainActor
func expectThrows<T>(_ expression: @autoclosure () throws -> T,
                     file: StaticString = #filePath, line: UInt = #line,
                     inspect: (Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        TestState.evaluate(false, file: file, line: line)
    } catch {
        TestState.evaluate(true, file: file, line: line)
        inspect(error)
    }
}

@MainActor
func expectNoThrow<T>(_ expression: @autoclosure () throws -> T,
                      file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        TestState.evaluate(true, file: file, line: line)
    } catch { TestState.evaluate(false, file: file, line: line) }
}

enum SelfTestError: Error { case missingValue }

@MainActor
func requireValue<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        TestState.evaluate(false, file: file, line: line)
        throw SelfTestError.missingValue
    }
    return value
}

@main
@MainActor
struct SelfTestRunner {
    static func main() {
        let suite = EnvelopeTests()
        let cases: [(String, () throws -> Void)] = [
            ("canonical-byte-layout", suite.testCanonicalByteLayoutHasIndependentExpectedBytes),
            ("purposes-and-u64-boundaries", suite.testBothPurposesRoundTripAndUInt64Boundaries),
            ("every-truncated-length", suite.testEveryTruncatedLengthIsRejected),
            ("trailing-data", suite.testTrailingDataIsRejected),
            ("unknown-version-purpose", suite.testUnknownVersionAndPurposeAreRejected),
            ("purpose-confusion-both-directions", suite.testBothDirectionsOfPurposeConfusionAreRejected),
            ("vault-epoch-mismatch", suite.testOtherVaultAndEpochAreRejected),
            ("secret-length", suite.testWrongSecretLengthCannotBeEncoded),
            ("digest-context-binding", suite.testDigestIsPurposeSeparatedAndContextBound),
            ("sha256-known-vector", suite.testFingerprintUsesKnownSHA256Vector),
            ("restart-fingerprint-mismatch", suite.testRestartComparisonRejectsChangedAndMissingRoles),
            ("report-boundary", suite.testReportContainsNoProbeSecretAndNoAcceptanceClaim),
            ("cancellation-before-key-access", suite.testInvalidatedOperationCannotStartKeyAccess),
            ("cancel-failure-separation", suite.testCancellationAndFailureAreSeparateOutcomes)
        ]
        var passed = 0
        for (name, run) in cases {
            let before = TestState.failures.count
            do { try run() }
            catch { TestState.failures.append("\(name): unexpected error (values suppressed)") }
            if TestState.failures.count == before {
                passed += 1
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
            }
        }
        print("\(passed)/\(cases.count) test cases passed; \(TestState.assertions) assertions; hardware acceptance 0/23")
        for location in TestState.failures { print("Failure at \(location)") }
        exit(TestState.failures.isEmpty ? 0 : 1)
    }
}
