import Foundation
import Testing

/// Waits for a condition rather than a clock: polls every few milliseconds until `condition`
/// holds, however long the machine takes (the simulator's one JavaScript thread is shared by
/// every test in the process). A test that never gets there is stopped by its `.timeLimit`.
func waitUntil(isolation: isolated (any Actor)? = #isolation, _ condition: () -> Bool) async throws {
    while !condition() {
        try await Task.sleep(for: .milliseconds(5))
    }
}

extension TimeLimitTrait.Duration {
    /// For a test that waits on simulations: a hang fails it long before the run's own limit.
    static let simulationWait = TimeLimitTrait.Duration.minutes(10)
}

/// Opt-in benchmarks (`TAVERN_BENCHMARKS=1 scripts/test.sh`, or `scripts/benchmark.sh`): timings
/// on the captured games, which depend on the machine and on what else runs, so they aren't
/// part of the regular suite.
enum Benchmarks {
    static var enabled: Bool { ProcessInfo.processInfo.environment["TAVERN_BENCHMARKS"] == "1" }
}
