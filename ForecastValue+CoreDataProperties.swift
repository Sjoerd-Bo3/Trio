//
//  ForecastValue+CoreDataProperties.swift
//  FreeAPS
//
//  Created by Cengiz Deniz on 21.07.24.
//
//

import Foundation
import CoreData


extension ForecastValue {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ForecastValue> {
        return NSFetchRequest<ForecastValue>(entityName: "ForecastValue")
    }

    @NSManaged public var index: Int32
    @NSManaged public var value: Int32
    @NSManaged public var forecast: Forecast?

}

extension ForecastValue : Identifiable {

}
