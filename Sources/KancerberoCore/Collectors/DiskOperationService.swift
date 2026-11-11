import Foundation
import DiskArbitration
import IOKit

public struct KBDiskOperationError: LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private final class DiskCallback {
    let continuation: CheckedContinuation<Void, Error>
    let session: DASession
    let disk: DADisk
    init(_ continuation: CheckedContinuation<Void, Error>, session: DASession, disk: DADisk) {
        self.continuation = continuation; self.session = session; self.disk = disk
    }
}

private func diskFailureReason(_ status: DAReturn) -> String {
    switch status {
    case DAReturn(truncatingIfNeeded: kDAReturnBusy): return "The volume is in use."
    case DAReturn(truncatingIfNeeded: kDAReturnExclusiveAccess): return "The device is held for exclusive access."
    case DAReturn(truncatingIfNeeded: kDAReturnNotPrivileged): return "Insufficient privileges to perform this action."
    case DAReturn(truncatingIfNeeded: kDAReturnNotPermitted): return "The system does not permit this action."
    case DAReturn(truncatingIfNeeded: kDAReturnNotFound): return "The device is no longer available."
    case DAReturn(truncatingIfNeeded: kDAReturnNotMounted): return "The volume is no longer mounted."
    case DAReturn(truncatingIfNeeded: kDAReturnNotReady): return "The device is not ready."
    case DAReturn(truncatingIfNeeded: kDAReturnNotWritable): return "The device is not writable."
    case DAReturn(truncatingIfNeeded: kDAReturnUnsupported): return "The device does not support this action."
    default: return "Disk Arbitration refused the operation (status \(status))."
    }
}

private let diskOperationCallback: DADiskMountCallback = { _, dissenter, context in
    guard let context else { return }
    let pending = Unmanaged<DiskCallback>.fromOpaque(context).takeRetainedValue()
    DASessionSetDispatchQueue(pending.session, nil)
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        let provided = DADissenterGetStatusString(dissenter).map { $0 as String }
        let reason = provided?.isEmpty == false ? provided! : diskFailureReason(status)
        pending.continuation.resume(throwing: KBDiskOperationError(message: reason))
    } else {
        pending.continuation.resume()
    }
}

public struct DiskOperationService: KBDiskOperationExecuting {
    public init() {}

    public static func ejectDisks(in inventory: KBDiskInventorySnapshot) -> [String: String] {
        guard let session = DASessionCreate(nil) else { return [:] }
        var result: [String: String] = [:]
        let physicalIDs = Set(inventory.items.filter { $0.kind == .physicalDisk }.map(\.id))
        for item in inventory.allItems {
            guard let disk = DADiskCreateFromBSDName(nil, session, item.id) else { continue }
            // APFS's whole disk may be synthetic. Traverse all IOService
            // parents to resolve physical stores, rejecting multi-disk stores.
            let stores = physicalStores(for: disk).intersection(physicalIDs)
            guard stores.count == 1, let id = stores.first,
                  inventory.items.filter({ $0.id == id && $0.item(withID: item.id) != nil }).count == 1,
                  let physical = DADiskCreateFromBSDName(nil, session, id),
                  let whole = DADiskCopyWholeDisk(physical), let name = DADiskGetBSDName(whole),
                  String(cString: name) == id,
                  let description = DADiskCopyDescription(whole) as? [String: Any],
                  description[kDADiskDescriptionMediaEjectableKey as String] as? Bool == true else { continue }
            result[item.id] = id
        }
        return result
    }

    private static func physicalStores(for disk: DADisk) -> Set<String> {
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { return [] }
        defer { IOObjectRelease(media) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var names: Set<String> = []
        func read(_ entry: io_registry_entry_t) {
            if let name = IORegistryEntryCreateCFProperty(entry, "BSD Name" as CFString,
                nil, 0)?.takeRetainedValue() as? String {
                names.insert(name)
            }
        }
        read(media)
        while true {
            let parent = IOIteratorNext(iterator)
            if parent == 0 { break }
            read(parent)
            IOObjectRelease(parent)
        }
        guard IOIteratorIsValid(iterator) != 0 else { return [] }
        return names
    }

    public func execute(_ step: KBDiskOperationStep) async throws {
        if step.network {
            try await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/umount")
                process.arguments = [step.device]
                let pipe = Pipe()
                process.standardError = pipe
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let reason = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    throw KBDiskOperationError(message: reason.isEmpty
                        ? "umount failed (exit status \(process.terminationStatus))." : reason)
                }
            }.value
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let session = DASessionCreate(nil),
                  let disk = DADiskCreateFromBSDName(nil, session, step.device) else {
                continuation.resume(throwing: KBDiskOperationError(message: "The device is no longer available."))
                return
            }
            DASessionSetDispatchQueue(session, DispatchQueue.global(qos: .utility))
            let pending = DiskCallback(continuation, session: session, disk: disk)
            let context = Unmanaged.passRetained(pending).toOpaque()
            switch step.action {
            case .mount: DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault), diskOperationCallback, context)
            case .unmount:
                let description = DADiskCopyDescription(disk) as? [String: Any]
                let whole = description?[kDADiskDescriptionMediaWholeKey as String] as? Bool == true
                DADiskUnmount(disk, DADiskUnmountOptions(whole ? kDADiskUnmountOptionWhole : kDADiskUnmountOptionDefault), diskOperationCallback, context)
            case .eject: DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), diskOperationCallback, context)
            }
        }
    }
}
