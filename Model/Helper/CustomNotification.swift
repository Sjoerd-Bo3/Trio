import Foundation

extension Notification.Name {
    static let didPerformBatchInsert = Notification.Name("didPerformBatchInsert")
    static let didPerformBatchUpdate = Notification.Name("didPerformBatchUpdate")
    static let didPerformBatchDelete = Notification.Name("didPerformBatchDelete")
    static let didUpdateDetermination = Notification.Name("didUpdateDetermination")
    static let didUpdateOverridePresets = Notification.Name("didUpdateOverridePresets")
}
