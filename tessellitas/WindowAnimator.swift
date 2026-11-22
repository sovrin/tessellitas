//
//  WindowAnimator.swift
//  tessellitas
//

@preconcurrency import ApplicationServices
import AppKit
import QuartzCore

/// The Accessibility API has no animation, so we drive the windows' frames ourselves.
///
/// The main thread only keeps the clock and works out each window's frame; the actual (slow)
/// Accessibility calls happen on per-window workers. Progress is time-based, so a slow app just
/// gets fewer intermediate frames, never a longer animation.
@MainActor
final class WindowAnimator {
    struct Move {
        let window: AXUIElement
        let from: CGRect
        let to: CGRect
    }

    private var timer: Timer?
    private var workers: [WindowWorker] = []
    private var finalFrames: [CGRect] = []

    /// Cuts a running animation short, puts its windows on their final frames and waits until
    /// they're there, so the next command reads accurate frames and starts from where windows are headed.
    func finish() {
        if let timer {
            timer.invalidate()
            self.timer = nil
            for (worker, frame) in zip(workers, finalFrames) { worker.submit(frame, exact: true) }
        }
        workers.forEach { $0.waitUntilIdle() }
        workers = []
        finalFrames = []
    }

    func animate(_ window: AXUIElement, from: CGRect, to: CGRect, duration: TimeInterval) {
        animate([Move(window: window, from: from, to: to)], duration: duration)
    }

    /// Animates several windows together, on one clock, so a resized row stays flush while it moves.
    func animate(_ moves: [Move], duration: TimeInterval) {
        finish()
        let moves = moves.filter { $0.from != $0.to }
        guard duration > 0, !moves.isEmpty else {
            moves.forEach { $0.window.setFrame($0.to) }
            return
        }

        let workers = moves.map { WindowWorker(window: $0.window, start: $0.from) }
        self.workers = workers
        finalFrames = moves.map(\.to)

        let start = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let progress = min(1, (CACurrentMediaTime() - start) / duration)
                if progress >= 1 {
                    timer.invalidate()
                    self?.timer = nil
                    for (worker, move) in zip(workers, moves) { worker.submit(move.to, exact: true) }
                } else {
                    let eased = 1 - pow(1 - progress, 3)   // ease-out cubic
                    for (worker, move) in zip(workers, moves) {
                        worker.submit(Self.interpolate(move.from, move.to, eased), exact: false)
                    }
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { (x + (y - x) * t).rounded() }
        return CGRect(x: lerp(a.minX, b.minX), y: lerp(a.minY, b.minY),
                      width: lerp(a.width, b.width), height: lerp(a.height, b.height))
    }
}
