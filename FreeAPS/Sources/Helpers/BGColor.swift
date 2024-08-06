import CoreData
import Foundation
import SwiftUI

// Helper function to decide how to pick the BG color
public func setBGColor(bgValue: Int, highBGColorValue: Decimal, lowBGColorValue: Decimal, dynamicBGColor: Bool) -> Color {
    // Auggie - injected fails here
    // Convert Decimal to Int for high and low glucose values
    let lowGlucose = NSDecimalNumber(decimal: lowBGColorValue).intValue - 20
    let highGlucose = NSDecimalNumber(decimal: highBGColorValue).intValue + 20
    let targetGlucose = 90

    // TODO:
    // Only use setDynamicBGColor if the setting is enabled in preferences
    if dynamicBGColor {
        return setDynamicBGColor(
            bgValue: bgValue,
            highGlucose: Int(highGlucose),
            lowGlucose: Int(lowGlucose),
            targetGlucose: targetGlucose
        )
    }
    // Otheriwse, use static (orange = high, red = low, green = range)
    else {
        if bgValue > Int(highGlucose) {
            return Color.orange
        } else if bgValue < Int(lowGlucose) {
            return Color.red
        } else {
            return Color.green
        }
    }
}

// Dynamic color - Define the hue values for the key points
// We'll shift color gradually one BG point at a time
// We'll shift through the rainbow colors of ROY-G-BIV from low to high
// Start at red for lowGlucose, green for targetGlucose, and violet for highGlucose
public func setDynamicBGColor(bgValue: Int, highGlucose: Int, lowGlucose: Int, targetGlucose: Int) -> Color {
    let redHue: CGFloat = 0.0 / 360.0 // 0 degrees
    let greenHue: CGFloat = 120.0 / 360.0 // 120 degrees
    let purpleHue: CGFloat = 270.0 / 360.0 // 270 degrees

    // Calculate the hue based on the bgLevel
    var hue: CGFloat
    if bgValue <= lowGlucose {
        hue = redHue
    } else if bgValue >= highGlucose {
        hue = purpleHue
    } else if bgValue <= targetGlucose {
        // Interpolate between red and green
        let ratio = CGFloat(bgValue - lowGlucose) / CGFloat(targetGlucose - lowGlucose)
        hue = redHue + ratio * (greenHue - redHue)
    } else {
        // Interpolate between green and purple
        let ratio = CGFloat(bgValue - targetGlucose) / CGFloat(highGlucose - targetGlucose)
        hue = greenHue + ratio * (purpleHue - greenHue)
    }

    // Return the color with full saturation and brightness
    let color = Color(hue: hue, saturation: 0.6, brightness: 0.9)
    return color
}
