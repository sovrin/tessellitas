//
//  WindowWorker.swift
//  tessellitas
//

@preconcurrency import ApplicationServices
import Foundation

/// Applies frames to one window off the main thread.
///
/// Every Accessibility call is a synchronous round trip to the other app, and some apps take tens of
/// milliseconds to answer. One worker per window lets windows animate in parallel, and keeps a slow app
/// from stalling the others or the main thread. Frames coalesce: if the app falls behind, it skips
/// straight to the newest frame instead of replaying old ones.
nonisolated final class WindowWorker: @unchecked Sendable {
    private struct Frame {
        let rect: CGRect
        let exact: Bool
    }

    private let window: AXUIElement
    private let condition = NSCondition()
    private var pending: Frame?
    private var running = false
    private var applied: CGRect   // only touched by the drain loop, which never overlaps itself

    init(window: AXUIElement, start: CGRect) {
        self.window = window
        applied = start
    }

    /// `exact` uses the slower, more robust size-position-size sequence, for the final frame.
    func submit(_ rect: CGRect, exact: Bool) {
        condition.lock()
        pending = Frame(rect: rect, exact: exact)
        let needsStart = !running
        running = true
        condition.unlock()
        if needsStart {
            DispatchQueue.global(qos: .userInteractive).async { [self] in drain() }
        }
    }

    /// Blocks until every submitted frame has been applied.
    func waitUntilIdle() {
        condition.lock()
        while running { condition.wait() }
        condition.unlock()
    }

    private func drain() {
        while true {
            condition.lock()
            guard let next = pending else {
                running = false
                condition.broadcast()
                condition.unlock()
                return
            }
            pending = nil
            condition.unlock()

            if next.exact {
                window.setFrame(next.rect)
            } else {
                window.setFrameQuickly(from: applied, to: next.rect)
            }
            applied = next.rect
        }
    }
}
