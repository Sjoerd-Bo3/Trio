import CoreData
import Foundation

extension Date {
    static var oneDayAgo: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    }

    static var halfHourAgo: Date {
        Calendar.current.date(byAdding: .minute, value: -30, to: Date())!
    }

    static var oneWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    }

    static var oneMonthAgo: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    }

    static var threeMonthsAgo: Date {
        Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    }
}

extension NSPredicate {
    static let all = NSPredicate(format: "TRUEPREDICATE")

    static let none = NSPredicate(format: "FALSEPREDICATE")

    static var predicateForOneDayAgo: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateFor30MinAgo: NSPredicate {
        let date = Date.halfHourAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForOneWeek: NSPredicate {
        let date = Date.oneWeekAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForOneMonth: NSPredicate {
        let date = Date.oneMonthAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }

    static var predicateForThreeMonths: NSPredicate {
        let date = Date.threeMonthsAgo
        return NSPredicate(format: "date >= %@", date as NSDate)
    }
}
