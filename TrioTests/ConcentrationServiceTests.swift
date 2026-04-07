import XCTest
@testable import Trio

// MARK: - InsulinConcentration Model Tests

final class InsulinConcentrationTests: XCTestCase {
    func testUnitsPerML() {
        XCTAssertEqual(InsulinConcentration.u10.unitsPerML, 10)
        XCTAssertEqual(InsulinConcentration.u25.unitsPerML, 25)
        XCTAssertEqual(InsulinConcentration.u50.unitsPerML, 50)
        XCTAssertEqual(InsulinConcentration.u100.unitsPerML, 100)
        XCTAssertEqual(InsulinConcentration.u200.unitsPerML, 200)
        XCTAssertEqual(InsulinConcentration.u300.unitsPerML, 300)
        XCTAssertEqual(InsulinConcentration.u500.unitsPerML, 500)
    }

    func testFactor() {
        XCTAssertEqual(InsulinConcentration.u10.factor, Decimal(string: "0.1"))
        XCTAssertEqual(InsulinConcentration.u25.factor, Decimal(string: "0.25"))
        XCTAssertEqual(InsulinConcentration.u50.factor, Decimal(string: "0.5"))
        XCTAssertEqual(InsulinConcentration.u100.factor, Decimal(1))
        XCTAssertEqual(InsulinConcentration.u200.factor, Decimal(2))
        XCTAssertEqual(InsulinConcentration.u300.factor, Decimal(3))
        XCTAssertEqual(InsulinConcentration.u500.factor, Decimal(5))
    }

    func testIsStandard() {
        XCTAssertFalse(InsulinConcentration.u10.isStandard)
        XCTAssertFalse(InsulinConcentration.u50.isStandard)
        XCTAssertTrue(InsulinConcentration.u100.isStandard)
        XCTAssertFalse(InsulinConcentration.u200.isStandard)
        XCTAssertFalse(InsulinConcentration.u500.isStandard)
    }

    func testDisplayName() {
        XCTAssertEqual(InsulinConcentration.u100.displayName, "U-100")
        XCTAssertEqual(InsulinConcentration.u200.displayName, "U-200")
        XCTAssertEqual(InsulinConcentration.u50.displayName, "U-50")
    }

    func testAllCases() {
        XCTAssertEqual(InsulinConcentration.allCases.count, 7)
        XCTAssertEqual(InsulinConcentration.allCases.first, .u10)
        XCTAssertEqual(InsulinConcentration.allCases.last, .u500)
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for concentration in InsulinConcentration.allCases {
            let data = try encoder.encode(concentration)
            let decoded = try decoder.decode(InsulinConcentration.self, from: data)
            XCTAssertEqual(decoded, concentration, "Codable roundtrip failed for \(concentration.displayName)")
        }
    }

    func testRawValueInit() {
        XCTAssertEqual(InsulinConcentration(rawValue: 100), .u100)
        XCTAssertEqual(InsulinConcentration(rawValue: 200), .u200)
        XCTAssertEqual(InsulinConcentration(rawValue: 50), .u50)
        XCTAssertNil(InsulinConcentration(rawValue: 150))
        XCTAssertNil(InsulinConcentration(rawValue: 0))
    }
}

// MARK: - Mock ConcentrationService for Testing

final class MockConcentrationService: ConcentrationService {
    var activeConcentration: InsulinConcentration

    init(concentration: InsulinConcentration = .u100) {
        self.activeConcentration = concentration
    }

    var factor: Decimal { activeConcentration.factor }
    var isActive: Bool { !activeConcentration.isStandard }

    func toPumpUnits(realUnits: Double) -> Double {
        guard isActive else { return realUnits }
        return realUnits / NSDecimalNumber(decimal: factor).doubleValue
    }

    func toPumpRate(realUnitsPerHour: Double) -> Double {
        toPumpUnits(realUnits: realUnitsPerHour)
    }

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

    func toRealReservoir(pumpUnits: Decimal) -> Decimal {
        toRealUnits(pumpUnits: pumpUnits)
    }
}

// MARK: - ConcentrationService Translation Tests

final class ConcentrationServiceTests: XCTestCase {
    // MARK: - U-100 (Standard / Identity)

    func testU100IsIdentity() {
        let service = MockConcentrationService(concentration: .u100)

        // All conversions should be identity for U-100
        XCTAssertEqual(service.toPumpUnits(realUnits: 2.0), 2.0, accuracy: 0.001)
        XCTAssertEqual(service.toPumpRate(realUnitsPerHour: 1.5), 1.5, accuracy: 0.001)
        XCTAssertEqual(service.toRealUnits(pumpUnits: 3.0), 3.0, accuracy: 0.001)
        XCTAssertEqual(service.toRealRate(pumpUnitsPerHour: 0.8), 0.8, accuracy: 0.001)
        XCTAssertEqual(service.toRealUnits(pumpUnits: Decimal(5)), Decimal(5))
        XCTAssertEqual(service.toRealReservoir(pumpUnits: Decimal(100)), Decimal(100))
        XCTAssertFalse(service.isActive)
    }

    // MARK: - U-200 (Concentrated)

    func testU200OutboundToPump() {
        let service = MockConcentrationService(concentration: .u200)

        // User wants 2U real → pump should get 1U (half volume)
        XCTAssertEqual(service.toPumpUnits(realUnits: 2.0), 1.0, accuracy: 0.001)

        // User wants 1.0 U/hr real → pump should get 0.5 U/hr
        XCTAssertEqual(service.toPumpRate(realUnitsPerHour: 1.0), 0.5, accuracy: 0.001)
    }

    func testU200InboundFromPump() {
        let service = MockConcentrationService(concentration: .u200)

        // Pump reports 1U delivered → actually 2U real
        XCTAssertEqual(service.toRealUnits(pumpUnits: 1.0), 2.0, accuracy: 0.001)

        // Pump reports 0.5 U/hr → actually 1.0 U/hr real
        XCTAssertEqual(service.toRealRate(pumpUnitsPerHour: 0.5), 1.0, accuracy: 0.001)

        // Pump reports 50U reservoir → actually 100U real
        XCTAssertEqual(service.toRealReservoir(pumpUnits: Decimal(50)), Decimal(100))
    }

    func testU200RoundTrip() {
        let service = MockConcentrationService(concentration: .u200)

        // Real → Pump → Real should be identity
        let original = 3.5
        let pumpUnits = service.toPumpUnits(realUnits: original)
        let roundTripped = service.toRealUnits(pumpUnits: pumpUnits)
        XCTAssertEqual(roundTripped, original, accuracy: 0.001)
    }

    // MARK: - U-50 (Diluted)

    func testU50OutboundToPump() {
        let service = MockConcentrationService(concentration: .u50)

        // User wants 2U real → pump should get 4U (double volume)
        XCTAssertEqual(service.toPumpUnits(realUnits: 2.0), 4.0, accuracy: 0.001)

        // User wants 0.5 U/hr real → pump should get 1.0 U/hr
        XCTAssertEqual(service.toPumpRate(realUnitsPerHour: 0.5), 1.0, accuracy: 0.001)
    }

    func testU50InboundFromPump() {
        let service = MockConcentrationService(concentration: .u50)

        // Pump reports 4U delivered → actually 2U real
        XCTAssertEqual(service.toRealUnits(pumpUnits: 4.0), 2.0, accuracy: 0.001)

        // Pump reports 1.0 U/hr → actually 0.5 U/hr real
        XCTAssertEqual(service.toRealRate(pumpUnitsPerHour: 1.0), 0.5, accuracy: 0.001)

        // Pump reports 200U reservoir → actually 100U real
        XCTAssertEqual(service.toRealReservoir(pumpUnits: Decimal(200)), Decimal(100))
    }

    func testU50RoundTrip() {
        let service = MockConcentrationService(concentration: .u50)

        let original = 1.75
        let pumpUnits = service.toPumpUnits(realUnits: original)
        let roundTripped = service.toRealUnits(pumpUnits: pumpUnits)
        XCTAssertEqual(roundTripped, original, accuracy: 0.001)
    }

    // MARK: - U-500

    func testU500OutboundToPump() {
        let service = MockConcentrationService(concentration: .u500)

        // User wants 5U real → pump should get 1U
        XCTAssertEqual(service.toPumpUnits(realUnits: 5.0), 1.0, accuracy: 0.001)

        // User wants 2.5 U/hr → pump should get 0.5 U/hr
        XCTAssertEqual(service.toPumpRate(realUnitsPerHour: 2.5), 0.5, accuracy: 0.001)
    }

    func testU500InboundFromPump() {
        let service = MockConcentrationService(concentration: .u500)

        // Pump reports 1U → actually 5U real
        XCTAssertEqual(service.toRealUnits(pumpUnits: 1.0), 5.0, accuracy: 0.001)

        // Pump reports 20U reservoir → actually 100U real
        XCTAssertEqual(service.toRealReservoir(pumpUnits: Decimal(20)), Decimal(100))
    }

    // MARK: - U-10 (Highly Diluted)

    func testU10OutboundToPump() {
        let service = MockConcentrationService(concentration: .u10)

        // User wants 1U real → pump should get 10U
        XCTAssertEqual(service.toPumpUnits(realUnits: 1.0), 10.0, accuracy: 0.001)
    }

    func testU10InboundFromPump() {
        let service = MockConcentrationService(concentration: .u10)

        // Pump reports 10U → actually 1U real
        XCTAssertEqual(service.toRealUnits(pumpUnits: 10.0), 1.0, accuracy: 0.001)
    }

    // MARK: - U-300

    func testU300Conversions() {
        let service = MockConcentrationService(concentration: .u300)

        // User wants 3U real → pump should get 1U
        XCTAssertEqual(service.toPumpUnits(realUnits: 3.0), 1.0, accuracy: 0.001)

        // Pump reports 1U → actually 3U real
        XCTAssertEqual(service.toRealUnits(pumpUnits: 1.0), 3.0, accuracy: 0.001)
    }

    // MARK: - Decimal Conversion Tests

    func testDecimalPrecision() {
        let service = MockConcentrationService(concentration: .u200)

        let pumpRate: Decimal = Decimal(string: "0.75")!
        let realRate = service.toRealRate(pumpUnitsPerHour: pumpRate)
        XCTAssertEqual(realRate, Decimal(string: "1.5"))
    }

    // MARK: - Edge Cases

    func testZeroValues() {
        let service = MockConcentrationService(concentration: .u200)

        XCTAssertEqual(service.toPumpUnits(realUnits: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(service.toRealUnits(pumpUnits: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(service.toRealReservoir(pumpUnits: Decimal(0)), Decimal(0))
    }

    func testIsActiveForNonStandard() {
        XCTAssertFalse(MockConcentrationService(concentration: .u100).isActive)
        XCTAssertTrue(MockConcentrationService(concentration: .u200).isActive)
        XCTAssertTrue(MockConcentrationService(concentration: .u50).isActive)
        XCTAssertTrue(MockConcentrationService(concentration: .u500).isActive)
        XCTAssertTrue(MockConcentrationService(concentration: .u10).isActive)
    }
}
