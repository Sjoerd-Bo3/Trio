import Foundation

/// Represents the concentration of insulin loaded in the pump.
///
/// Standard insulin is U-100 (100 units per mL). When using concentrated (U-200, U-500)
/// or diluted (U-10, U-25, U-50) insulin in a standard pump, the pump delivers a different
/// number of actual insulin units than it believes, because concentration affects volume.
///
/// The `factor` converts between real insulin units and pump-native (volume-equivalent) units:
/// - To pump:   pumpUnits = realUnits / factor
/// - From pump: realUnits = pumpUnits × factor
enum InsulinConcentration: Int, JSON, CaseIterable, Identifiable, Equatable {
    case u10 = 10
    case u25 = 25
    case u50 = 50
    case u100 = 100
    case u200 = 200
    case u300 = 300
    case u500 = 500

    /// Units of insulin per milliliter
    var unitsPerML: Int { rawValue }

    /// Conversion factor relative to U-100.
    ///
    /// - U-100: 1.0 (identity — no conversion needed)
    /// - U-200: 2.0 (pump delivers twice the units per volume)
    /// - U-50:  0.5 (pump delivers half the units per volume)
    var factor: Decimal {
        Decimal(rawValue) / 100
    }

    /// Whether this is the standard concentration (no translation needed)
    var isStandard: Bool { self == .u100 }

    /// Human-readable display label
    var displayName: String {
        "U-\(rawValue)"
    }

    var id: Int { rawValue }
}
