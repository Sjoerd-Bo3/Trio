import CoreData
import Foundation

public extension SettingsChangeStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SettingsChangeStored> {
        NSFetchRequest<SettingsChangeStored>(entityName: "SettingsChangeStored")
    }

    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var category: String?
    @NSManaged var subcategory: String?
    @NSManaged var settingName: String?
    @NSManaged var settingKey: String?
    @NSManaged var oldValue: String?
    @NSManaged var newValue: String?
    @NSManaged var unit: String?
    @NSManaged var note: String?
    @NSManaged var source: String?
    @NSManaged var groupId: UUID?
}

extension SettingsChangeStored: Identifiable {}
