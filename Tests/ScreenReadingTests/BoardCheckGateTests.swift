import Testing

@testable import ScreenReading

@Suite("Board check gate")
struct BoardCheckGateTests {
    private func begin(_ gate: inout BoardCheckGate, enabled: Bool = true, granted: Bool = true) -> Bool {
        gate.begin(isEnabled: enabled, permissionGranted: granted)
    }

    @Test("Starts once per game")
    func startsOnce() {
        var gate = BoardCheckGate()
        let first = begin(&gate)
        let second = begin(&gate)
        #expect(first)
        #expect(!second)
    }

    @Test("Does not start while off or without permission")
    func needsEnabledAndPermission() {
        var gate = BoardCheckGate()
        let off = begin(&gate, enabled: false)
        let denied = begin(&gate, granted: false)
        let ready = begin(&gate)
        #expect(!off)
        #expect(!denied)
        #expect(ready)
    }

    @Test("Turning the reader off and on again restarts the check")
    func restartsAfterStop() {
        var gate = BoardCheckGate()
        let first = begin(&gate)
        gate.stop()
        let restarted = begin(&gate)
        #expect(first)
        #expect(restarted)
    }

    @Test("A new game gets its own check")
    func resetStartsNewGame() {
        var gate = BoardCheckGate()
        _ = begin(&gate)
        gate.reset()
        let again = begin(&gate)
        #expect(again)
    }
}
