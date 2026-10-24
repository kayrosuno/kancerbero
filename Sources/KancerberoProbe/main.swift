import Darwin
import Foundation
import KancerberoCore

private func write(_ text: String, to handle: FileHandle = .standardOutput) {
    if let data = text.data(using: .utf8) {
        handle.write(data)
    }
}

private func fail(_ message: String) -> Never {
    write("error: \(message)\n", to: .standardError)
    exit(1)
}

private func formatBytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
}

private func printVersion() {
    write("kancerbero probe \(KBVersion.current) (core \(KBVersion.coreVersion), schema \(KBVersion.schema))\n")
}

private func printSymbols() {
    let availability = NStatCollector.availability()
    write("NetworkStatistics: \(availability.available ? "available" : "unavailable")\n")
    if !availability.available {
        write("  reason: \(availability.message)\n")
    }
    var privcheck: Int32 = -1
    let rc = kb_sysctl_int("net.statistics_privcheck", &privcheck)
    write("net.statistics_privcheck: \(rc == 0 ? String(privcheck) : "unreadable")\n")
    write("euid: \(geteuid()) root: \(geteuid() == 0 ? "yes" : "no")\n")
}

private func printProcesses(limit: Int) {
    do {
        let items = try ProcessCollector.snapshot()
        write("processes: \(items.count) (showing \(min(limit, items.count)))\n")
        for item in items.sorted(by: { $0.pid < $1.pid }).prefix(limit) {
            let path = item.path.isEmpty ? "-" : item.path
            write(String(format: "%7d %7d uid=%-5u %-24@ %@\n",
                         item.pid, item.ppid, item.uid,
                         item.name as NSString, path as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func printInterfaces() {
    do {
        let items = try InterfaceCollector.snapshot()
        write("interfaces: \(items.count)\n")
        for item in items.sorted(by: { $0.index < $1.index }) {
            let state = item.isUp ? (item.isRunning ? "up" : "up,not-running") : "down"
            write(String(format: "%-8@ idx=%-3u %-14@ %-16@ rx=%-12@ tx=%-12@ mtu=%u\n",
                         item.name as NSString, item.index, state as NSString,
                         item.kind.displayName as NSString,
                         formatBytes(item.counters.rxBytes) as NSString,
                         formatBytes(item.counters.txBytes) as NSString,
                         item.mtu))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private struct Aggregate {
    var name: String = ""
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var connections: Int = 0
}

private func printSockets(pid: Int32) {
    do {
        let sockets = try SocketCollector.snapshot(pid: pid)
        write("sockets: \(sockets.count) (pid \(pid))\n")
        for item in sockets {
            write(String(format: "  fd=%-4d %-6@ %-22@ -> %-22@ %@\n",
                         item.fd,
                         item.connectionProtocol.displayName as NSString,
                         item.local.display as NSString,
                         item.remote.display as NSString,
                         item.stateName as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func printFiles(pid: Int32) {
    do {
        let files = try OpenFileCollector.snapshot(pid: pid)
        write("open files: \(files.count) (pid \(pid))\n")
        for item in files.prefix(60) {
            write(String(format: "  fd=%-4d %-14@ %10llu  %@\n",
                         item.fd, item.typeName as NSString,
                         item.size, item.path as NSString))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

private func printSources() {
    let collector = NStatCollector()
    do {
        try collector.start()
    } catch {
        fail(error.localizedDescription)
    }
    defer { collector.stop() }
    Thread.sleep(forTimeInterval: 1.5)
    _ = collector.poll(timeoutMilliseconds: 800)
    let sources = collector.snapshot()
    write("sources: \(sources.count)\n")
    for source in sources.sorted(by: { ($0.pid, $0.local.display) < ($1.pid, $1.local.display) }) {
        write(String(format: "id=%-5llu pid=%-7d %-12@ %-5@ %-22@ -> %-22@ %-11@ uuid=%@ if=%@\n",
                     source.sourceID,
                     source.pid,
                     (source.processName.isEmpty ? "?" : source.processName) as NSString,
                     source.provider as NSString,
                     source.local.display as NSString,
                     source.remote.display as NSString,
                     source.tcpState as NSString,
                     (source.uuid.isEmpty ? "-" : source.uuid) as NSString,
                     source.interfaceName as NSString))
    }
}

private func printNStat(seconds: Int) {
    let collector = NStatCollector()
    do {
        try collector.start()
    } catch {
        fail(error.localizedDescription)
    }
    defer { collector.stop() }

    write("nstat: sampling \(seconds)s (1s interval)\n")
    for second in 0..<seconds {
        Thread.sleep(forTimeInterval: 1.0)
        let pollStart = Date()
        let ok = collector.poll(timeoutMilliseconds: 400)
        let elapsed = Date().timeIntervalSince(pollStart)
        let sources = collector.snapshot()

        var byPID: [Int32: Aggregate] = [:]
        for source in sources {
            let pid = source.epid != 0 ? source.epid : source.pid
            var aggregate = byPID[pid] ?? Aggregate(name: source.processName, rx: 0, tx: 0, connections: 0)
            if aggregate.name.isEmpty && !source.processName.isEmpty {
                aggregate.name = source.processName
            }
            aggregate.rx &+= source.counters.rxBytes
            aggregate.tx &+= source.counters.txBytes
            aggregate.connections += 1
            byPID[pid] = aggregate
        }

        write(String(format: "t=%ds poll=%@ %.0fms sources=%d processes=%d\n",
                     second + 1, ok ? "ok" : "partial", elapsed * 1000, sources.count, byPID.count))
        let top = byPID.sorted { ($0.value.rx + $0.value.tx) > ($1.value.rx + $1.value.tx) }.prefix(8)
        for (pid, aggregate) in top {
            write(String(format: "  %-24@ pid=%-7d conns=%-3d rx=%-12@ tx=%-12@\n",
                         (aggregate.name.isEmpty ? "?" : aggregate.name) as NSString,
                         pid, aggregate.connections,
                         formatBytes(aggregate.rx) as NSString,
                         formatBytes(aggregate.tx) as NSString))
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "all"
let remainder = Array(arguments.dropFirst())

func integerOption(_ name: String, default defaultValue: Int) -> Int {
    guard let index = remainder.firstIndex(of: name), index + 1 < remainder.count,
          let value = Int(remainder[index + 1]) else {
        return defaultValue
    }
    return value
}

switch command {
case "version":
    printVersion()
case "symbols":
    printSymbols()
case "procs":
    printProcesses(limit: integerOption("--limit", default: 20))
case "ifaces":
    printInterfaces()
case "sockets":
    guard let pid = Int32(remainder.first ?? "") else {
        fail("usage: KancerberoProbe sockets <pid>")
    }
    printSockets(pid: pid)
case "files":
    guard let pid = Int32(remainder.first ?? "") else {
        fail("usage: KancerberoProbe files <pid>")
    }
    printFiles(pid: pid)
case "sources":
    printSources()
case "nstat":
    printNStat(seconds: integerOption("--seconds", default: 5))
case "all":
    printVersion()
    printSymbols()
    printProcesses(limit: integerOption("--limit", default: 10))
    printInterfaces()
    printNStat(seconds: integerOption("--seconds", default: 3))
default:
    fail("unknown command '\(command)'. Use: version|symbols|procs|ifaces|sockets <pid>|files <pid>|nstat|all")
}
