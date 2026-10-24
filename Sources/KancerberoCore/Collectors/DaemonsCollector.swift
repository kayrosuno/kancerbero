import Darwin
import Foundation

/// Enumerates launchd jobs for one domain.
///
/// Status comes from `launch_msg("GetJobs")` when the caller's launchd domain
/// matches (user GUI domain in the app, system domain in the root daemon).
/// Otherwise it falls back to `launchctl print <domain>`. Metadata comes from
/// the standard LaunchDaemons/LaunchAgents plists, and the disabled flag from
/// `launchctl print-disabled`.
public final class DaemonsCollector: @unchecked Sendable {
    public let domain: KBDaemonDomain
    public let uid: UInt32

    public init(domain: KBDaemonDomain, uid: UInt32 = getuid()) {
        self.domain = domain
        self.uid = uid
    }

    public func snapshot() -> KBDaemonSnapshot {
        var errors: [String] = []
        var statuses: [String: StatusEntry] = [:]
        var source = "plist"

        if usesLaunchdMessage() {
            do {
                for job in try LaunchdQuery.jobs() {
                    statuses[job.label] = StatusEntry(
                        pid: job.pid > 0 ? job.pid : nil,
                        lastExitStatus: job.lastExitStatus >= 0 ? job.lastExitStatus : nil,
                        statusToken: statusToken(for: job),
                        program: job.program,
                        arguments: job.arguments,
                        onDemand: job.onDemand
                    )
                }
                source = "launch_msg"
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if statuses.isEmpty {
            let printed = LaunchctlRunner.printServices(domain: domain)
            if printed.ok {
                for entry in LaunchctlRunner.parseServices(printed.stdout) {
                    statuses[entry.label] = StatusEntry(
                        pid: entry.pid,
                        lastExitStatus: Int32(entry.statusToken),
                        statusToken: entry.statusToken,
                        program: "",
                        arguments: "",
                        onDemand: false
                    )
                }
                source = "launchctl print"
            } else {
                errors.append(printed.stderr.isEmpty
                              ? "launchctl print \(domain.domainString) failed"
                              : printed.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let disabledResult = LaunchctlRunner.printDisabled(domain: domain)
        let disabled: Set<String>
        if disabledResult.ok {
            disabled = LaunchctlRunner.parseDisabled(disabledResult.stdout)
        } else {
            disabled = []
            if !disabledResult.stderr.isEmpty {
                errors.append(disabledResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let metadata = loadPlistMetadata()
        let labels = Set(metadata.keys).union(statuses.keys)
        var services: [KBDaemonService] = []
        services.reserveCapacity(labels.count)

        for label in labels.sorted() {
            let meta = metadata[label]
            let status = statuses[label]
            let isDisabled = disabled.contains(label) || (meta?.disabled ?? false)
            let program: String
            if let meta, !meta.program.isEmpty {
                program = meta.program
            } else if let meta,
                      let first = meta.arguments.split(separator: " ").first {
                program = String(first)
            } else {
                program = status?.program ?? ""
            }
            services.append(KBDaemonService(
                label: label,
                domain: domain,
                uid: domain == .system ? nil : uid,
                pid: status?.pid,
                lastExitStatus: status?.lastExitStatus,
                statusToken: status?.statusToken ?? "",
                isLoaded: status != nil,
                isDisabled: isDisabled,
                program: program,
                arguments: meta?.arguments ?? status?.arguments ?? "",
                plistPath: meta?.path ?? "",
                runAtLoad: meta?.runAtLoad ?? false,
                keepAlive: meta?.keepAlive ?? false,
                startInterval: meta?.startInterval,
                workingDirectory: meta?.workingDirectory ?? "",
                environment: meta?.environment ?? [:],
                onDemand: status?.onDemand ?? false
            ))
        }

        return KBDaemonSnapshot(
            services: services,
            error: errors.isEmpty ? nil : errors.joined(separator: "; "),
            source: source
        )
    }

    // MARK: - Private

    private struct StatusEntry {
        var pid: Int32?
        var lastExitStatus: Int32?
        var statusToken: String
        var program: String
        var arguments: String
        var onDemand: Bool
    }

    private struct PlistMeta {
        var path: String
        var program: String
        var arguments: String
        var runAtLoad: Bool
        var keepAlive: Bool
        var startInterval: Int?
        var workingDirectory: String
        var environment: [String: String]
        var disabled: Bool
    }

    private func usesLaunchdMessage() -> Bool {
        switch domain {
        case .system:
            return geteuid() == 0
        case .gui:
            return geteuid() != 0
        case .user:
            return false
        }
    }

    private func statusToken(for job: KBRawLaunchdJob) -> String {
        if job.pid > 0 { return "running" }
        if job.lastExitStatus >= 0 { return String(job.lastExitStatus) }
        return "-"
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var metadataCache: [String: (Date, [String: PlistMeta])] = [:]

    private func loadPlistMetadata() -> [String: PlistMeta] {
        let key = domain.plistDirectories.joined(separator: "|")
        Self.cacheLock.lock()
        if let entry = Self.metadataCache[key],
           Date().timeIntervalSince(entry.0) < 30 {
            let cached = entry.1
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        let fresh = parsePlistMetadata()
        Self.cacheLock.lock()
        Self.metadataCache[key] = (Date(), fresh)
        Self.cacheLock.unlock()
        return fresh
    }

    private func parsePlistMetadata() -> [String: PlistMeta] {
        var result: [String: PlistMeta] = [:]
        let fileManager = FileManager.default
        for directory in domain.plistDirectories {
            guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for file in files where file.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(file)
                guard let data = fileManager.contents(atPath: path),
                      let object = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil),
                      let plist = object as? [String: Any] else {
                    continue
                }
                let label = (plist["Label"] as? String)
                    ?? (file as NSString).deletingPathExtension

                let keepAlive: Bool
                if let value = plist["KeepAlive"] as? Bool {
                    keepAlive = value
                } else if plist["KeepAlive"] is [String: Any] {
                    keepAlive = true
                } else {
                    keepAlive = false
                }

                let environment = (plist["EnvironmentVariables"] as? [String: Any])?
                    .compactMapValues { $0 as? String } ?? [:]
                let startInterval = (plist["StartInterval"] as? NSNumber)?.intValue

                result[label] = PlistMeta(
                    path: path,
                    program: plist["Program"] as? String ?? "",
                    arguments: (plist["ProgramArguments"] as? [String])?
                        .joined(separator: " ") ?? "",
                    runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                    keepAlive: keepAlive,
                    startInterval: startInterval,
                    workingDirectory: plist["WorkingDirectory"] as? String ?? "",
                    environment: environment,
                    disabled: plist["Disabled"] as? Bool ?? false
                )
            }
        }
        return result
    }
}
