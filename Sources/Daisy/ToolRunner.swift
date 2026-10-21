// Daisy — runs external conversion commands with a timeout and captured output.
import Foundation
import Darwin

struct ToolResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Lock-guarded accumulator shared between a pipe's readability handler and the drain step.
private final class OutputBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    /// Lossy UTF-8 decoding so partially invalid output still reaches the caller.
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

enum ToolRunner {
    enum ToolError: LocalizedError {
        case launchFailed(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let path): return "Could not launch \(path). Install it with Homebrew or set its path in Daisy's settings."
            case .timedOut(let path): return "\(path) exceeded the conversion timeout."
            }
        }
    }

    /// Runs a command synchronously; returns captured stdout/stderr and exit code.
    static func run(
        _ launchPath: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval = 300
    ) -> ToolResult {
        guard !launchPath.isEmpty, FileManager.default.isExecutableFile(atPath: launchPath) else {
            return ToolResult(exitCode: -1, stdout: "", stderr: ToolError.launchFailed(launchPath).localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        process.environment = env

        let stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return ToolResult(exitCode: -1, stdout: "", stderr: ToolError.launchFailed(launchPath).localizedDescription)
        }

        let outBuffer = OutputBuffer(), errBuffer = OutputBuffer()
        let outputDone = DispatchGroup()
        attachReader(stdoutPipe, into: outBuffer, finished: outputDone)
        attachReader(stderrPipe, into: errBuffer, finished: outputDone)

        var timedOut = false
        if exited.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
            timedOut = true
            let pid = process.processIdentifier
            // Snapshot before signalling: once a parent dies, its children re-parent to launchd and leave the walk.
            var victims = descendants(of: pid)
            for victim in victims {
                kill(victim, SIGTERM)
            }
            process.terminate()
            let childGone = exited.wait(timeout: .now() + 2) == .success
            if !childGone {
                // Child still alive: pick up anything it spawned during the grace period.
                let current = descendants(of: pid)
                victims = current + victims.filter { !current.contains($0) }
            }
            for victim in victims {
                kill(victim, SIGKILL)
            }
            if !childGone {
                kill(pid, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }

        // One deadline for both pipes, measured from process exit.
        drain(outputDone, deadline: .now() + 0.3, pipes: [stdoutPipe, stderrPipe])

        if timedOut {
            return ToolResult(
                exitCode: -1,
                stdout: outBuffer.text,
                stderr: ToolError.timedOut(launchPath).localizedDescription
            )
        }
        return ToolResult(
            exitCode: process.terminationStatus,
            stdout: outBuffer.text,
            stderr: errBuffer.text
        )
    }

    /// Collects pipe output as it arrives so the buffer survives even if the drain gives up.
    /// `finished` is left exactly once, when the pipe reaches EOF.
    private static func attachReader(_ pipe: Pipe, into buffer: OutputBuffer, finished: DispatchGroup) {
        finished.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                finished.leave()
            } else {
                buffer.append(chunk)
            }
        }
    }

    /// Waits until both pipes reach EOF or `deadline` passes, then stops reading. Output already
    /// received is kept, so a grandchild still holding a pipe open cannot stall the caller past it.
    private static func drain(_ finished: DispatchGroup, deadline: DispatchTime, pipes: [Pipe]) {
        _ = finished.wait(timeout: deadline)
        for pipe in pipes {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    /// Live descendants of `root`, deepest first. `root` itself is excluded.
    private static func descendants(of root: pid_t) -> [pid_t] {
        var order: [pid_t] = [root]
        var seen: Set<pid_t> = [root]
        var index = 0
        while index < order.count {
            for child in childPids(of: order[index]) where seen.insert(child).inserted {
                order.append(child)
            }
            index += 1
        }
        return Array(order.dropFirst().reversed())
    }

    /// Direct children of `parent` via libproc. `proc_listchildpids` returns a PID count.
    private static func childPids(of parent: pid_t) -> [pid_t] {
        var capacity = 64
        while true {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = buffer.withUnsafeMutableBytes {
                proc_listchildpids(parent, $0.baseAddress, Int32($0.count))
            }
            guard count > 0 else { return [] }
            if Int(count) < capacity { return Array(buffer.prefix(Int(count))) }
            capacity *= 2 // buffer may be full; retry larger
        }
    }
}
