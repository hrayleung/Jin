actor UpdateLaunchCheckGate {
    static let shared = UpdateLaunchCheckGate()

    private var hasRun = false

    func claim() -> Bool {
        guard !hasRun else { return false }
        hasRun = true
        return true
    }
}
