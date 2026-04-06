import Foundation
import Swinject

/// Provides translation between real insulin units (IU) and pump-native (volume-equivalent) units.
///
/// Everything above this service thinks in real insulin units.
/// Everything below (PumpManager / LoopKit) thinks in pump-native units.
///
/// For U-100, all methods are identity (pass-through) — zero behavioral change.
protocol ConcentrationService: AnyObject {
    /// The currently active insulin concentration
    var activeConcentration: InsulinConcentration { get }

    /// The concentration factor (e.g., 2.0 for U-200, 0.5 for U-50)
    var factor: Decimal { get }

    /// Whether concentration translation is active (i.e., not U-100)
    var isActive: Bool { get }

    // MARK: - Outbound: Real Units → Pump Units (divide by factor)

    /// Convert a bolus amount from real units to pump units
    func toPumpUnits(realUnits: Double) -> Double

    /// Convert a basal rate from real units/hr to pump units/hr
    func toPumpRate(realUnitsPerHour: Double) -> Double

    // MARK: - Inbound: Pump Units → Real Units (multiply by factor)

    /// Convert a bolus amount from pump units to real units
    func toRealUnits(pumpUnits: Double) -> Double

    /// Convert a basal rate from pump units/hr to real units/hr
    func toRealRate(pumpUnitsPerHour: Double) -> Double

    /// Convert a Decimal bolus amount from pump units to real units
    func toRealUnits(pumpUnits: Decimal) -> Decimal

    /// Convert a Decimal basal rate from pump units/hr to real units/hr
    func toRealRate(pumpUnitsPerHour: Decimal) -> Decimal

    // MARK: - Reservoir

    /// Convert a reservoir volume (pump units) to real units
    func toRealReservoir(pumpUnits: Decimal) -> Decimal
}

final class BaseConcentrationService: ConcentrationService, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    var activeConcentration: InsulinConcentration {
        guard settingsManager.settings.allowDilution else {
            return .u100
        }
        return settingsManager.settings.insulinConcentration
    }

    var factor: Decimal {
        activeConcentration.factor
    }

    var isActive: Bool {
        !activeConcentration.isStandard
    }

    // MARK: - Outbound: Real Units → Pump Units

    func toPumpUnits(realUnits: Double) -> Double {
        guard isActive else { return realUnits }
        return realUnits / NSDecimalNumber(decimal: factor).doubleValue
    }

    func toPumpRate(realUnitsPerHour: Double) -> Double {
        toPumpUnits(realUnits: realUnitsPerHour)
    }

    // MARK: - Inbound: Pump Units → Real Units

    func toRealUnits(pumpUnits: Double) -> Double {
        guard isActive else { return pumpUnits }
        return pumpUnits * NSDecimalNumber(decimal: factor).doubleValue
    }

    func toRealRate(pumpUnitsPerHour: Double) -> Double {
        toRealUnits(pumpUnits: pumpUnitsPerHour)
    }

    func toRealUnits(pumpUnits: Decimal) -> Decimal {
        guard isActive else { return pumpUnits }
        return pumpUnits * factor
    }

    func toRealRate(pumpUnitsPerHour: Decimal) -> Decimal {
        toRealUnits(pumpUnits: pumpUnitsPerHour)
    }

    // MARK: - Reservoir

    func toRealReservoir(pumpUnits: Decimal) -> Decimal {
        toRealUnits(pumpUnits: pumpUnits)
    }
}
