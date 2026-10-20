// Daisy — runs external conversion commands with a timeout and captured output.
import Foundation

struct ToolResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
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

    /// Runs a command synchronously on the given queue; returns captured output.
    static func run(
        _ launchPath: String,
        arguments: [String],
        timeout: TimeInterval,
        on queue: DispatchQueue = .global(qos: .userInitiated)
    ) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let sem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sem.signal() }

        do {
            try process.run()
        } catch {
            return ToolResult(exitCode: -1, stdout: "", stderr: ToolError.launchFailed(launchPath).localizedDescription)
        }

        // Drain pipes on background queues so blocked readers cannot deadlock us.
        var outData = Data(), errData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global().async { outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data(); drain.leave() }
        drain.enter()
        DispatchQueue.global().async { errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data(); drain.leave() }
        let drainSem = DispatchSemaphore(value: 0)
        drain.notify(queue: .global()) { drainSem.signal() }

        let deadline = DispatchTime.now() + timeout
        if sem.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = sem.wait(timeout: .now() + 10)
            return ToolResult(exitCode: -1, stdout: "", stderr: ToolError.timedOut(launchPath).localizedDescription)
        }
        _ = drainSem.wait(timeout: .now() + 10)

        return ToolResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData ?? Data(), encoding: .utf8) ?? "",
            stderr: String(data: errData ?? Data(), encoding: .utf8) ?? ""
        )
    }
}
