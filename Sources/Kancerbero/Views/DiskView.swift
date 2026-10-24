import SwiftUI

struct DiskView: View {
    var body: some View {
        PlannedSectionView(
            section: .disk,
            features: [
                PlannedFeature(
                    icon: "arrow.up.arrow.down.circle",
                    title: "Per-process I/O",
                    detail: "Read and write throughput for every process, sampled alongside the network data."
                ),
                PlannedFeature(
                    icon: "chart.bar.xaxis",
                    title: "Volume usage",
                    detail: "Capacity, free space and activity for each mounted volume."
                ),
                PlannedFeature(
                    icon: "clock.arrow.circlepath",
                    title: "History and peaks",
                    detail: "Sparklines for the last minute plus the processes driving the highest I/O."
                ),
                PlannedFeature(
                    icon: "externaldrive.badge.checkmark",
                    title: "Health checks",
                    detail: "SMART status and space pressure warnings for internal and external disks."
                )
            ]
        )
    }
}
