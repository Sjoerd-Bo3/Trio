import Foundation
import SwiftUI
import Testing

@testable import Trio

@Suite("Stat Chart Utils Tests") struct StatChartUtilsTests {
    
    // MARK: - calculatePopoverXOffset Tests
    
    @Test("Calculates zero offset for centered popover") func testCenteredPopover() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600) // 1 hour later
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 1800) // Middle of the range
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - popover is centered, should not need offset
        #expect(offset == 0)
    }
    
    @Test("Calculates positive offset for left edge popover") func testLeftEdgePopover() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 0) // At the start
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should push popover to the right
        #expect(offset > 0)
        #expect(offset == 50) // Half the popover width
    }
    
    @Test("Calculates negative offset for right edge popover") func testRightEdgePopover() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 3600) // At the end
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should push popover to the left
        #expect(offset < 0)
        #expect(offset == -50) // Negative half the popover width
    }
    
    @Test("Returns zero for zero chart width") func testZeroChartWidth() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 1800)
        let chartWidth: CGFloat = 0
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then
        #expect(offset == 0)
    }
    
    @Test("Returns zero for zero domain duration") func testZeroDomainDuration() {
        // Given
        let sameDate = Date(timeIntervalSince1970: 1000)
        let domain = (start: sameDate, end: sameDate) // Same start and end
        let selectedDate = sameDate
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then
        #expect(offset == 0)
    }
    
    @Test("Handles large popover width") func testLargePopoverWidth() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 1800) // Middle
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 400 // Larger than chart
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should adjust for overflow
        #expect(offset != 0)
    }
    
    @Test("Handles fractional pixel values") func testFractionalPixels() {
        // Given
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 3600)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 900) // 1/4 through
        let chartWidth: CGFloat = 333.333
        let popoverWidth: CGFloat = 99.99
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should handle fractional values without crashing
        // The exact value will depend on the calculation, but it should be finite
        #expect(!offset.isNaN)
        #expect(!offset.isInfinite)
    }
    
    @Test("Selected date before domain start") func testDateBeforeStart() {
        // Given
        let startDate = Date(timeIntervalSince1970: 1000)
        let endDate = Date(timeIntervalSince1970: 2000)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 500) // Before start
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should handle gracefully
        #expect(!offset.isNaN)
        #expect(!offset.isInfinite)
    }
    
    @Test("Selected date after domain end") func testDateAfterEnd() {
        // Given
        let startDate = Date(timeIntervalSince1970: 1000)
        let endDate = Date(timeIntervalSince1970: 2000)
        let domain = (start: startDate, end: endDate)
        let selectedDate = Date(timeIntervalSince1970: 3000) // After end
        let chartWidth: CGFloat = 300
        let popoverWidth: CGFloat = 100
        
        // When
        let offset = StatChartUtils.calculatePopoverXOffset(
            domain: domain,
            selectedDate: selectedDate,
            chartWidth: chartWidth,
            popoverWidth: popoverWidth
        )
        
        // Then - should handle gracefully
        #expect(!offset.isNaN)
        #expect(!offset.isInfinite)
        #expect(offset < 0) // Should push left since it's beyond the right edge
    }
}
