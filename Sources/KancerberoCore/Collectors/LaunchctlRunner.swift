import Darwin
import Foundation

public struct LaunchctlResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public var ok: Bool {
        guard status == 0, !timedOut else { return false }
        let lower = stderr.lowercased()
        if lower.contains("bad request") || lower.contains("could not find") {
            return false
        }
        return true
    }
}

public struct LaunchctlServiceStatus: Sendable {
    public var label: String
    public var pid: Int32?
    public var statusToken: String
}

public enum LaunchctlRunner {
    /// Runs `launchctl` with stdout/stderr redirected to temporary files.
    /// Pipes are deliberately avoided: a started service can inherit the
    /// pipe descriptors, which would keep the pipe open and hang reads.
    public static func run(_ arguments: [String], timeout: TimeInterval = 5) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let fileManager = FileManager.default
        let identifier = UUID().uuidString
        let stdoutURL = fileManager.temporaryDirectory
            .appendingPathComponent("kancerbero-launchctl-\(identifier).out")
        let stderrURL = fileManager.temporaryDirectory
            .appendingPathComponent("kancerbero-launchctl-\(identifier).err")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
              let stderrHandle = try? FileHandle(forWritingTo: stderrURL) else {
            return LaunchctlResult(status: -1, stdout: "", stderr: "cannot open output files",
                                   timedOut: false)
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        do {
            try process.run()
        } catch {
            return LaunchctlResult(status: -1, stdout: "", stderr: error.localizedDescription,
                                   timedOut: false)
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        var timedOut = false
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 0.5)
            }
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()
        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

        return LaunchctlResult(
            status: timedOut ? -1 : process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            timedOut: timedOut
        )
    }

    // MARK: - Queries

    public static func printServices(domain: KBDaemonDomain) -> LaunchctlResult {
        run(["print", domain.domainString])
    }

    public static func printDisabled(domain: KBDaemonDomain) -> LaunchctlResult {
        run(["print-disabled", domain.domainString])
    }

    public static func list() -> LaunchctlResult {
        run(["list"])
    }

    public static func action(_ request: KBDaemonActionRequest) -> LaunchctlResult {
        guard isValidLabel(request.label) else {
            return LaunchctlResult(status: -1, stdout: "", stderr: "invalid label",
                                   timedOut: false)
        }

        // `launchctl kickstart -k` can block while the old instance is being
        // torn down. LaunchControl performs stop/start separately, so do the
        // same here.
        if request.action == .restart {
            let target = "\(request.domain.domainString)/\(request.label)"
            _ = run(["kill", "SIGTERM", target], timeout: 5)
            usleep(500_000)
            return run(["kickstart", target], timeout: 10)
        }

        guard let arguments = actionArguments(request) else {
            return LaunchctlResult(status: -1, stdout: "", stderr: "invalid action arguments",
                                   timedOut: false)
        }
        let result = run(arguments, timeout: request.action == .start ? 10 : 5)
        if request.action == .stop,
           result.stderr.lowercased().contains("no process to signal") {
            return LaunchctlResult(status: 0, stdout: result.stdout,
                                   stderr: result.stderr, timedOut: false)
        }
        return result
    }

    public static func actionArguments(_ request: KBDaemonActionRequest) -> [String]? {
        let domain = request.domain.domainString
        let target = "\(domain)/\(request.label)"
        switch request.action {
        case .start:
            return ["kickstart", target]
        case .restart:
            return nil // handled as stop + start in action(_:)
        case .stop:
            return ["kill", "SIGTERM", target]
        case .enable:
            return ["enable", target]
        case .disable:
            return ["disable", target]
        case .load:
            guard let plist = request.plistPath, !plist.isEmpty else { return nil }
            return ["bootstrap", domain, plist]
        case .unload:
            return ["bootout", target]
        }
    }

    // MARK: - Parsers

    /// Parses the `services = { PID STATUS LABEL ... }` block from
    /// `launchctl print <domain>`.
    public static func parseServices(_ output: String) -> [LaunchctlServiceStatus] {
        var result: [LaunchctlServiceStatus] = []
        var inside = false
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inside {
                if line.hasPrefix("services = {") {
                    inside = true
                }
                continue
            }
            if line == "}" {
                inside = false
                continue
            }
            let parts = line.split(maxSplits: 2,
                                   omittingEmptySubsequences: true,
                                   whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 3, let pid = Int32(parts[0]) else { continue }
            let label = String(parts[2])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(LaunchctlServiceStatus(
                label: label,
                pid: pid > 0 ? pid : nil,
                statusToken: String(parts[1])
            ))
        }
        return result
    }

    /// Parses `launchctl print-disabled <domain>` into disabled labels.
    public static func parseDisabled(_ output: String) -> Set<String> {
        var result = Set<String>()
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "=>") else { continue }
            let left = line[..<range.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
            let right = line[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            if right == "disabled" {
                result.insert(left)
            }
        }
        return result
    }

    /// Parses the tab-separated output of `launchctl list`.
    public static func parseList(_ output: String) -> [LaunchctlServiceStatus] {
        var result: [LaunchctlServiceStatus] = []
        for rawLine in output.split(separator: "\n") {
            let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let pidText = String(fields[0])
            if pidText == "PID" { continue }
            let pid = Int32(pidText)
            result.append(LaunchctlServiceStatus(
                label: String(fields[2]),
                pid: pid,
                statusToken: String(fields[1])
            ))
        }
        return result
    }

    public static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 512 else { return false }
        return label.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}
