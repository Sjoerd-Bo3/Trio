import CoreData
import Foundation

public extension ProfilePresetRunStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ProfilePresetRunStored> {
        NSFetchRequest<ProfilePresetRunStored>(entityName: "ProfilePresetRunStored")
    }

    @NSManaged var endDate: Date?
    @NSManaged var icon: String?
    @NSManaged var id: UUID?
    @NSManaged var isDiverted: Bool
    @NSManaged var isUploadedToNS: Bool
    @NSManaged var name: String?
    @NSManaged var presetId: String?
    @NSManaged var startDate: Date?
}

extension ProfilePresetRunStored: Identifiable {}
