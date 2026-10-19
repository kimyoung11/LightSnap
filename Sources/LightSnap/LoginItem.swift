import ServiceManagement

protocol LoginItemService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}
enum LoginItemState: Equatable {
    case enabled, disabled, approvalRequired, unavailable
    var description: String {
        switch self {
        case .enabled: return "로그인 시 자동 실행 켜짐"
        case .disabled: return "로그인 시 자동 실행 꺼짐"
        case .approvalRequired: return "로그인 항목에서 사용자 승인 필요"
        case .unavailable: return "로그인 항목을 사용할 수 없습니다. 앱 위치와 서명을 확인해 주세요."
        }
    }
    var requested: Bool { self == .enabled || self == .approvalRequired }
}
struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .approvalRequired
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
struct LoginItemController {
    let service: LoginItemService
    init(service: LoginItemService = SystemLoginItemService()) { self.service = service }
    var state: LoginItemState { service.state }
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled { if state != .enabled && state != .approvalRequired { try service.register() } }
            else if state.requested { try service.unregister() }
            return nil
        } catch { return "자동 실행 변경 실패: \(error.localizedDescription)" }
    }
}
