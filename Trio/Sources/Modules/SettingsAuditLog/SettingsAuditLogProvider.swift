import Foundation
import Swinject

extension SettingsAuditLog {
    final class Provider: BaseProvider, SettingsAuditLogProvider {
        @Injected() var auditStorage: SettingsAuditStorage!
    }
}
