import AppKit
import Darwin

struct ResourceSample: Codable {
    let uptimeSeconds: Double
    let cpuSeconds: Double
    let residentBytes: UInt64
    let footprintBytes: UInt64
    static func capture() -> Self? {
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let code = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count) }
        }
        var usage = rusage()
        guard code == KERN_SUCCESS, getrusage(RUSAGE_SELF,&usage) == 0 else { return nil }
        let cpu = Double(usage.ru_utime.tv_sec)+Double(usage.ru_utime.tv_usec)/1_000_000 + Double(usage.ru_stime.tv_sec)+Double(usage.ru_stime.tv_usec)/1_000_000
        return Self(uptimeSeconds: ProcessInfo.processInfo.systemUptime,cpuSeconds: cpu,residentBytes: vm.resident_size,footprintBytes: vm.phys_footprint)
    }
}

struct ResourceReport: Codable {
    let mode: String
    let os: String
    let sampleCount: Int
    let durationSeconds: Double
    let cpuPercentOfOneCore: Double
    let peakSampledFootprintMB: Double
    let peakSampledResidentMB: Double
    let footprintUnder50MB: Bool
    let samples: [ResourceSample]
    init?(mode: String, samples: [ResourceSample]) {
        guard let first = samples.first, let last = samples.last, last.uptimeSeconds > first.uptimeSeconds else { return nil }
        self.mode = mode; self.samples = samples; os = ProcessInfo.processInfo.operatingSystemVersionString
        sampleCount = samples.count; durationSeconds = last.uptimeSeconds-first.uptimeSeconds
        cpuPercentOfOneCore = max(0,(last.cpuSeconds-first.cpuSeconds)/durationSeconds*100)
        peakSampledFootprintMB = Double(samples.map(\.footprintBytes).max()!)/1_000_000
        peakSampledResidentMB = Double(samples.map(\.residentBytes).max()!)/1_000_000
        footprintUnder50MB = peakSampledFootprintMB <= 50
    }
    var summary: String {
        String(format:"측정 %.1f초 · CPU %.2f%% (코어 1개 기준)\n메모리 footprint 최대 %.1f MB · RSS 최대 %.1f MB\n50 MB 목표: %@\n※ 측정 구간의 표본 기준이며 앱 사용 상태에 따라 달라집니다.", durationSeconds,cpuPercentOfOneCore,peakSampledFootprintMB,peakSampledResidentMB,footprintUnder50MB ? "충족" : "초과")
    }
}

final class SnapMetrics {
    struct Entry: Codable { let milliseconds: Double; let status: SnapOutcome.Status }
    private(set) var entries: [Entry] = []
    func record(milliseconds: Double, status: SnapOutcome.Status) {
        if entries.count >= 100 { entries.removeFirst() }
        entries.append(Entry(milliseconds: milliseconds,status: status))
    }
    var summary: String {
        let successes = entries.filter { $0.status == .success }.map(\.milliseconds).sorted()
        guard !successes.isEmpty else { return "성공한 스냅 측정 없음 · 접근성 허용 후 단축키를 사용해 주세요." }
        let p95 = successes[max(0,Int(ceil(Double(successes.count)*0.95))-1)]
        let under = successes.filter { $0 < 50 }.count
        return String(format:"최근 성공 %d회 · p95 %.1f ms · 최대 %.1f ms\n50 ms 미만 %d/%d회 · 실패·제약 %d회\n단축키 콜백부터 결과 확인까지의 시간입니다. 물리 키 입력·화면 렌더링 시간은 제외합니다.",successes.count,p95,successes.last!,under,successes.count,entries.count-successes.count)
    }
}

struct DiagnosticExport: Codable {
    let createdAt: String
    let resources: ResourceReport?
    let recentSnaps: [SnapMetrics.Entry]
    let notes: String
}
