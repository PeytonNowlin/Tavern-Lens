import Foundation

/// Runs the latest of a stream of jobs, the way the recruit-phase odds preview and the advisor
/// both need: a new job waits `debounce` for the state to settle and replaces the one pending or
/// running (cancelled at once, its results dropped from then on); the running job's results are
/// delivered in order, the final one last, at most one partial per `refreshInterval`.
///
/// While the previous job's result is still on screen (`submit(_:replacing: true)`), the new job's
/// results are held back until one `isReady` (or the final one), so the numbers don't flicker.
///
/// Results carry a generation (the job) and a step (monotonic within the job): a result of an
/// older job, one older than a result already delivered, or a partial arriving after the final one
/// is dropped. Partials may be emitted from any thread; each hops to the main actor on its own.
@MainActor
final class LatestRunner<Output: Sendable> {
    /// Hands a job's partial results to the runner. Sendable, so a simulator's progress callback
    /// can call it from its own thread.
    final class Emitter: @unchecked Sendable {
        private let lock = NSLock()
        private var step = 0
        private let hop: @Sendable (Output, Int) -> Void
        private let direct: @MainActor (Output, Int) -> Void

        fileprivate init(hop: @escaping @Sendable (Output, Int) -> Void, direct: @escaping @MainActor (Output, Int) -> Void) {
            self.hop = hop
            self.direct = direct
        }

        fileprivate func nextStep() -> Int {
            lock.withLock {
                step += 1
                return step
            }
        }

        /// A partial result, from any thread: it reaches the main actor on its own hop.
        func callAsFunction(_ output: Output) {
            hop(output, nextStep())
        }

        /// A partial result, delivered at once (the job runs on the main actor).
        @MainActor
        func onMain(_ output: Output) {
            direct(output, nextStep())
        }
    }

    typealias Job = @MainActor (_ emit: Emitter) async throws -> Output

    let debounce: Duration
    let refreshInterval: Duration
    /// Called on the main actor with each result let through, and whether it's the final one.
    var onResult: ((Output, _ isFinal: Bool) -> Void)?
    /// Called on the main actor when the current job throws (other than by being cancelled).
    var onFailure: ((any Error) -> Void)?

    private let isReady: (Output) -> Bool
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?
    /// Of the current generation: the latest step delivered, and whether the final one was.
    private var lastStep = 0
    private var finished = false
    private var awaitingReplacement = false
    private var lastDelivered: ContinuousClock.Instant?

    /// - Parameter isReady: whether a partial result may replace the previous job's on screen.
    init(debounce: Duration, refreshInterval: Duration, isReady: @escaping (Output) -> Bool = { _ in true }) {
        self.debounce = debounce
        self.refreshInterval = refreshInterval
        self.isReady = isReady
    }

    /// Replaces whatever is pending or running with `job`, which starts after the debounce.
    /// - Parameter replacing: the previous job's result is on screen; hold the new one's back
    ///   until it's ready.
    func submit(replacing: Bool, _ job: @escaping Job) {
        stop()
        awaitingReplacement = replacing
        let token = generation
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.start(job, token: token)
        }
    }

    /// Cancels the pending and running jobs; nothing more of theirs is delivered.
    func stop() {
        generation += 1
        pending?.cancel()
        pending = nil
        running?.cancel()
        running = nil
        lastStep = 0
        finished = false
        awaitingReplacement = false
        lastDelivered = nil
    }

    private func start(_ job: @escaping Job, token: Int) {
        guard token == generation else { return }
        let emitter = Emitter(
            hop: { [weak self] output, step in
                Task { @MainActor in self?.receive(output, step: step, isFinal: false, token: token) }
            },
            direct: { [weak self] output, step in self?.receive(output, step: step, isFinal: false, token: token) }
        )
        running = Task { [weak self] in
            do {
                let output = try await job(emitter)
                self?.receive(output, step: emitter.nextStep(), isFinal: true, token: token)
            } catch is CancellationError {
                // A newer job replaced this one.
            } catch {
                guard let self, token == self.generation else { return }
                self.finished = true
                self.onFailure?(error)
            }
        }
    }

    private func receive(_ output: Output, step: Int, isFinal: Bool, token: Int) {
        guard token == generation, !finished, step > lastStep else { return }
        if !isFinal {
            if awaitingReplacement, !isReady(output) { return }
            let now = ContinuousClock.now
            if !awaitingReplacement, let lastDelivered, now - lastDelivered < refreshInterval { return }
            lastDelivered = now
        }
        lastStep = step
        finished = isFinal
        awaitingReplacement = false
        onResult?(output, isFinal)
    }
}
