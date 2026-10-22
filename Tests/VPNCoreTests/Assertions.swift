import Testing

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
func checkNil<T>(_ actual: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == nil, sourceLocation: sourceLocation)
}
func checkTrue(_ actual: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual, sourceLocation: sourceLocation)
}
func checkFalse(_ actual: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!actual, sourceLocation: sourceLocation)
}
func checkThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        _ = try expression()
        Issue.record("Expected rejection", sourceLocation: sourceLocation)
    } catch {}
}
