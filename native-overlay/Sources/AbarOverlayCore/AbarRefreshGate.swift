public struct AbarRefreshGate: Equatable {
    private var isInFlight = false

    public init() {}

    public mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    public mutating func finish() {
        isInFlight = false
    }
}
