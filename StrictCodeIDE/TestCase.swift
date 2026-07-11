import Foundation

/// A student-defined test: input to feed the program via stdin, and the
/// output they expect back.
struct TestCase: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var input: String
    var expectedOutput: String
}

/// The result of running one TestCase against the current code.
struct TestCaseResult: Identifiable {
    let id = UUID()
    let testCase: TestCase
    let actualOutput: String
    let passed: Bool
}
