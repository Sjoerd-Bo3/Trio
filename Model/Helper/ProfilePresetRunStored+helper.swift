import CoreData
import Foundation

extension NSPredicate {
    static var profilePresetRunStoredFromOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@", date as NSDate)
    }

    static var activeProfilePresetRun: NSPredicate {
        NSPredicate(format: "endDate == nil")
    }

    static var profilePresetRunsNotYetUploadedToNS: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "startDate >= %@ AND isUploadedToNS == %@", date as NSDate, false as NSNumber)
    }
}
