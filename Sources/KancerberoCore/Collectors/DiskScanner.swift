import Darwin
import Foundation

/// Directory-size scanner built on `getattrlistbulk`, the same mechanism Disk
/// Inspector uses. One C call per directory keeps cancellation responsive and
/// avoids crossing the Swift/C boundary once per entry.
public enum DiskScanner {
    private enum EntryFlag {
        static let directory: UInt32 = 1 << 0
        static let symlink: UInt32 = 1 << 1
        static let mountPoint: UInt32 = 1 << 2
    }

    private static let vdir: UInt32 = 2
    private static let vlnk: UInt32 = 5

    private static let packageSuffixes: [String] = [
        ".app", ".appex", ".bundle", ".plugin", ".kext", ".framework",
        ".pkg", ".webplugin", ".wdgt", ".fs", ".downloads", ".photoslibrary",
        ".dictionary", ".xcodeproj", ".playground", ".docset", ".prefpane",
        ".qlgenerator", ".mdimporter", ".saver"
    ]

    private struct Frame {
        let name: String
        let path: String
        let depth: Int
        let isPackage: Bool
        let isHidden: Bool
        let isMountPoint: Bool

        var allocated: UInt64
        var logical: UInt64 = 0
        var fileCount: Int = 0
        var folderCount: Int = 0
        var accessDenied: Bool = false
        var truncated: Bool = false
        var listed: Bool = false
        var children: [KBDiskNode] = []
        var pending: [Frame] = []
    }

    private struct LargestFiles {
        let limit: Int
        let includeHidden: Bool
        private(set) var items: [KBDiskFile] = []

        mutating func consider(_ file: KBDiskFile) {
            guard limit > 0 else { return }
            guard includeHidden || !file.isHidden else { return }
            if items.count >= limit {
                guard let last = items.last,
                      file.allocatedBytes > last.allocatedBytes else { return }
                items.removeLast()
            }
            let index = items.firstIndex {
                $0.allocatedBytes < file.allocatedBytes
            } ?? items.endIndex
            items.insert(file, at: index)
        }
    }

    public static func scan(
        rootPath: String,
        options: KBDiskScanOptions,
        partial: @escaping @Sendable (KBDiskScanSnapshot) -> Void = { _ in },
        progress: @escaping @Sendable (KBDiskScanProgress) -> Void
    ) -> KBDiskScanSnapshot {
        let startedAt = Date()
        let startedUptime = DispatchTime.now().uptimeNanoseconds
        let root = (rootPath as NSString).standardizingPath
        let normalizedRoot = root.isEmpty ? "/" : root
        let rootName = normalizedRoot == "/"
            ? "/"
            : (normalizedRoot as NSString).lastPathComponent

        var stack: [Frame] = [Frame(
            name: rootName,
            path: normalizedRoot,
            depth: 0,
            isPackage: false,
            isHidden: false,
            isMountPoint: false,
            allocated: 0
        )]
        var largestFiles = LargestFiles(
            limit: options.largestFilesLimit,
            includeHidden: options.includeHiddenInLargestFiles)
        var deniedPaths: [String] = []
        var scannedFiles = 0
        var scannedFolders = 0
        var scannedBytes: UInt64 = 0
        var retainedNodes = 1
        var cancelled = false
        var scanError: String?
        var lastProgress = startedUptime
        var lastPartial = startedUptime

        func reportProgress(path: String) {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now &- lastProgress >= 100_000_000 else { return }
            lastProgress = now
            progress(KBDiskScanProgress(
                path: path,
                files: scannedFiles,
                folders: scannedFolders,
                bytes: scannedBytes,
                denied: deniedPaths.count,
                elapsed: Double(now &- startedUptime) / 1_000_000_000
            ))
        }

        func denied(_ path: String, code: Int32) {
            if deniedPaths.count < 50 {
                deniedPaths.append(path)
            }
            if normalizedRoot == path {
                scanError = nil
            }
            _ = code
        }

        func closeFrame(_ frame: Frame) -> KBDiskNode {
            var children = frame.children
            var aggregatedChildren = 0

            if children.count > options.maxChildrenRetained && options.maxChildrenRetained > 0 {
                children.sort { $0.allocatedBytes > $1.allocatedBytes }
                let kept = Array(children.prefix(options.maxChildrenRetained))
                let omitted = children.dropFirst(options.maxChildrenRetained)

                var aggregateAllocated: UInt64 = 0
                var aggregateLogical: UInt64 = 0
                var aggregateFiles = 0
                var aggregateFolders = 0
                for child in omitted {
                    aggregateAllocated &+= child.allocatedBytes
                    aggregateLogical &+= child.logicalBytes
                    aggregateFiles += child.fileCount
                    aggregateFolders += child.folderCount
                }
                aggregatedChildren = omitted.count

                let aggregate = KBDiskNode(
                    name: "Other",
                    path: join(frame.path, ".other-\(omitted.count)"),
                    isDirectory: true,
                    isPackage: false,
                    isHidden: false,
                    isMountPoint: false,
                    accessDenied: false,
                    isAggregate: true,
                    allocatedBytes: aggregateAllocated,
                    logicalBytes: aggregateLogical,
                    fileCount: aggregateFiles,
                    folderCount: aggregateFolders,
                    children: [],
                    aggregatedChildren: omitted.count,
                    truncated: false
                )
                children = kept + [aggregate]
            } else {
                children.sort { $0.allocatedBytes > $1.allocatedBytes }
            }

            return KBDiskNode(
                name: frame.name,
                path: frame.path,
                isDirectory: true,
                isPackage: frame.isPackage,
                isHidden: frame.isHidden,
                isMountPoint: frame.isMountPoint,
                accessDenied: frame.accessDenied,
                isAggregate: false,
                allocatedBytes: frame.allocated,
                logicalBytes: frame.logical,
                fileCount: frame.fileCount,
                folderCount: frame.folderCount,
                children: children,
                aggregatedChildren: aggregatedChildren,
                truncated: frame.truncated
            )
        }

        func attach(_ node: KBDiskNode, to parentIndex: Int) {
            stack[parentIndex].children.append(node)
            stack[parentIndex].allocated &+= node.allocatedBytes
            stack[parentIndex].logical &+= node.logicalBytes
            stack[parentIndex].fileCount += node.fileCount
            stack[parentIndex].folderCount += node.folderCount
        }

        /// Builds a snapshot of the tree discovered so far without touching the
        /// real stack: it folds the open chain with `closeFrame` (which is pure)
        /// and adds the in-progress child to each ancestor. Frames still in
        /// `pending` are not visited yet, so they are intentionally omitted.
        func partialNode(at index: Int) -> KBDiskNode {
            var frame = stack[index]
            if index + 1 < stack.count {
                let child = partialNode(at: index + 1)
                frame.children.append(child)
                frame.allocated &+= child.allocatedBytes
                frame.logical &+= child.logicalBytes
                frame.fileCount += child.fileCount
                frame.folderCount += child.folderCount
            }
            return closeFrame(frame)
        }

        func emitPartial(force: Bool = false) {
            guard !stack.isEmpty else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard force || now &- lastPartial >= 400_000_000 else { return }
            if Task.isCancelled { return }
            lastPartial = now

            partial(KBDiskScanSnapshot(
                root: partialNode(at: 0),
                largestFiles: largestFiles.items,
                deniedPaths: deniedPaths,
                options: options,
                generatedAt: Date(),
                duration: Double(now &- startedUptime) / 1_000_000_000,
                cancelled: false,
                error: nil,
                isPartial: true
            ))
        }

        emitPartial(force: true)

        while let currentIndex = stack.indices.last {
            if Task.isCancelled {
                cancelled = true
                break
            }

            if !stack[currentIndex].listed {
                stack[currentIndex].listed = true
                let frame = stack[currentIndex]

                if frame.depth >= options.maxDepth {
                    continue
                }

                var pointer: UnsafeMutablePointer<kb_disk_entry>?
                var count = 0
                let result = kb_disk_list_directory(frame.path, &pointer, &count)

                guard result == 0 else {
                    stack[currentIndex].accessDenied = true
                    stack[currentIndex].truncated = result != EACCES && result != EPERM
                    denied(frame.path, code: result)
                    if frame.depth == 0 && result != EACCES && result != EPERM {
                        scanError = "Cannot scan \(frame.path): \(errorText(result))"
                    }
                    continue
                }

                guard let base = pointer, count > 0 else {
                    reportProgress(path: frame.path)
                    emitPartial()
                    continue
                }
                defer { kb_disk_entries_free(base) }

                stack[currentIndex].pending.removeAll(keepingCapacity: true)

                for index in 0..<count {
                    if index & 0x1FF == 0 && Task.isCancelled {
                        cancelled = true
                        break
                    }

                    let entry = base[index]
                    let name = KBInterop.string(entry.name)
                    guard !name.isEmpty else { continue }
                    let childPath = join(frame.path, name)
                    let flags = entry.flags
                    let hidden = name.hasPrefix(".")
                    let isDirectory = (flags & EntryFlag.directory) != 0
                    let isMountPoint = (flags & EntryFlag.mountPoint) != 0

                    scannedBytes &+= entry.alloc_size

                    if isDirectory {
                        scannedFolders += 1
                        let package = isPackageName(name)

                        if isMountPoint && !options.crossMountPoints {
                            let node = KBDiskNode(
                                name: name,
                                path: childPath,
                                isDirectory: true,
                                isPackage: package,
                                isHidden: hidden,
                                isMountPoint: true,
                                accessDenied: false,
                                isAggregate: false,
                                allocatedBytes: entry.alloc_size,
                                logicalBytes: 0,
                                fileCount: 0,
                                folderCount: 0,
                                children: [],
                                aggregatedChildren: 0,
                                truncated: false
                            )
                            stack[currentIndex].folderCount += 1
                            attach(node, to: currentIndex)
                            continue
                        }

                        if retainedNodes >= options.maxNodes ||
                            frame.depth + 1 >= options.maxDepth {
                            let node = KBDiskNode(
                                name: name,
                                path: childPath,
                                isDirectory: true,
                                isPackage: package,
                                isHidden: hidden,
                                isMountPoint: isMountPoint,
                                accessDenied: false,
                                isAggregate: false,
                                allocatedBytes: entry.alloc_size,
                                logicalBytes: 0,
                                fileCount: 0,
                                folderCount: 0,
                                children: [],
                                aggregatedChildren: 0,
                                truncated: true
                            )
                            stack[currentIndex].folderCount += 1
                            stack[currentIndex].truncated = true
                            attach(node, to: currentIndex)
                            continue
                        }

                        retainedNodes += 1
                        stack[currentIndex].folderCount += 1
                        stack[currentIndex].pending.append(Frame(
                            name: name,
                            path: childPath,
                            depth: frame.depth + 1,
                            isPackage: package,
                            isHidden: hidden,
                            isMountPoint: isMountPoint,
                            allocated: entry.alloc_size
                        ))
                    } else {
                        scannedFiles += 1
                        stack[currentIndex].fileCount += 1
                        stack[currentIndex].allocated &+= entry.alloc_size
                        stack[currentIndex].logical &+= entry.total_size
                        largestFiles.consider(KBDiskFile(
                            name: name,
                            path: childPath,
                            allocatedBytes: entry.alloc_size,
                            logicalBytes: entry.total_size,
                            isHidden: hidden
                        ))
                    }

                    reportProgress(path: frame.path)
                    emitPartial()
                }

                if cancelled {
                    break
                }

                reportProgress(path: frame.path)
                emitPartial()
                continue
            }

            // Process one child at a time so the parent stays directly below it
            // on the stack. Pushing all siblings at once would attach a closing
            // child to its previous sibling instead of its parent.
            if let child = stack[currentIndex].pending.popLast() {
                stack.append(child)
                continue
            }

            // The directory and all its children are complete: close it.
            let frame = stack.removeLast()
            let node = closeFrame(frame)
            if let parentIndex = stack.indices.last {
                attach(node, to: parentIndex)
            } else {
                let finalProgress = KBDiskScanProgress(
                    path: node.path,
                    files: scannedFiles,
                    folders: scannedFolders,
                    bytes: scannedBytes,
                    denied: deniedPaths.count,
                    elapsed: Date().timeIntervalSince(startedAt)
                )
                progress(finalProgress)
                return KBDiskScanSnapshot(
                    root: node,
                    largestFiles: largestFiles.items,
                    deniedPaths: deniedPaths,
                    options: options,
                    generatedAt: Date(),
                    duration: Date().timeIntervalSince(startedAt),
                    cancelled: cancelled,
                    error: scanError
                )
            }
        }

        // Cancelled or stopped: close any open frames bottom-up.
        var rootNode: KBDiskNode?
        while let frame = stack.popLast() {
            let node = closeFrame(frame)
            if let parentIndex = stack.indices.last {
                attach(node, to: parentIndex)
            } else {
                rootNode = node
            }
        }

        let fallback = KBDiskNode(
            name: rootName,
            path: normalizedRoot,
            isDirectory: true,
            isPackage: false,
            isHidden: false,
            isMountPoint: false,
            accessDenied: true,
            isAggregate: false,
            allocatedBytes: 0,
            logicalBytes: 0,
            fileCount: 0,
            folderCount: 0,
            children: [],
            aggregatedChildren: 0,
            truncated: true
        )

        let finalNode = rootNode ?? fallback
        progress(KBDiskScanProgress(
            path: finalNode.path,
            files: scannedFiles,
            folders: scannedFolders,
            bytes: scannedBytes,
            denied: deniedPaths.count,
            elapsed: Date().timeIntervalSince(startedAt)
        ))

        return KBDiskScanSnapshot(
            root: finalNode,
            largestFiles: largestFiles.items,
            deniedPaths: deniedPaths,
            options: options,
            generatedAt: Date(),
            duration: Date().timeIntervalSince(startedAt),
            cancelled: cancelled,
            error: scanError
        )
    }

    private static func join(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    private static func isPackageName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return packageSuffixes.contains { lower.hasSuffix($0) }
    }

    private static func errorText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}
