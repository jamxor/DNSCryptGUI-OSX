import Foundation

enum ShellError: LocalizedError {
    case nonZeroExit(Int32, String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let out): return "Exit \(code): \(out)"
        case .launchFailed(let s): return "Launch failed: \(s)"
        }
    }
}

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var combined: String { stdout + stderr }
    var ok: Bool { exitCode == 0 }
}

/// Runs *non-privileged* shell commands. Anything that needs root goes
/// through HelperClient over XPC instead.
enum PrivilegedShell {

    @discardableResult
    static func run(_ path: String, _ args: [String], env: [String: String]? = nil) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                if let env { p.environment = env }
                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError  = errPipe
                do { try p.run() }
                catch {
                    cont.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                    return
                }
                p.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: ShellResult(exitCode: p.terminationStatus, stdout: out, stderr: err))
            }
        }
    }

    /// Locate an executable in the standard PATH locations expected on macOS.
    static func which(_ binary: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(binary)",
            "/opt/homebrew/sbin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/usr/local/sbin/\(binary)",
            "/usr/bin/\(binary)",
            "/bin/\(binary)",
            "/usr/sbin/\(binary)",
            "/sbin/\(binary)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
