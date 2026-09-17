import Darwin

/// Process CPU time and memory footprint, for logging the cost of a recording.
public enum ResourceUsage {
    public static var cpuSeconds: Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    public static var footprintMB: Double { usage.map { Double($0.ri_phys_footprint) / 1_048_576 } ?? 0 }

    public static var peakFootprintMB: Double { usage.map { Double($0.ri_lifetime_max_phys_footprint) / 1_048_576 } ?? 0 }

    private static var usage: rusage_info_v4? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? info : nil
    }
}
