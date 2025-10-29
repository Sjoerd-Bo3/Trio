import Foundation
import SwiftUI
import Testing

@testable import Trio

@Suite("Settings Hint Manager Tests") struct SettingsHintManagerTests {
    
    @Test("Initial state is correct") func testInitialState() {
        // Given
        let manager = SettingsHintManager()
        
        // Then
        #expect(manager.shouldDisplayHint == false)
        #expect(manager.hintDetent == .large)
        #expect(manager.selectedVerboseHint == nil)
        #expect(manager.hintLabel == nil)
        #expect(manager.decimalPlaceholder == 0.0)
        #expect(manager.booleanPlaceholder == false)
    }
    
    @Test("Decimal placeholder can be updated") func testDecimalPlaceholder() {
        // Given
        let manager = SettingsHintManager()
        
        // When
        manager.decimalPlaceholder = 42.5
        
        // Then
        #expect(manager.decimalPlaceholder == 42.5)
    }
    
    @Test("Boolean placeholder can be updated") func testBooleanPlaceholder() {
        // Given
        let manager = SettingsHintManager()
        
        // When
        manager.booleanPlaceholder = true
        
        // Then
        #expect(manager.booleanPlaceholder == true)
    }
    
    @Test("Should display hint can be toggled") func testShouldDisplayHint() {
        // Given
        let manager = SettingsHintManager()
        
        // When
        manager.shouldDisplayHint = true
        
        // Then
        #expect(manager.shouldDisplayHint == true)
    }
    
    @Test("Hint detent can be changed") func testHintDetent() {
        // Given
        let manager = SettingsHintManager()
        
        // When
        manager.hintDetent = .medium
        
        // Then
        #expect(manager.hintDetent == .medium)
    }
    
    @Test("Verbose hint binding sets label") func testVerboseHintBindingLabel() {
        // Given
        let manager = SettingsHintManager()
        let testLabel = "Test Hint Label"
        
        // When
        let binding = manager.verboseHintBinding(label: testLabel)
        
        // Then - label should be set when binding is created with set operation
        #expect(manager.hintLabel == nil) // Not set until binding.wrappedValue is set
        
        // Simulate setting a value through the binding
        let testView = Text("Test")
        binding.wrappedValue = testView
        
        // Then
        #expect(manager.hintLabel == testLabel)
        #expect(manager.selectedVerboseHint != nil)
    }
    
    @Test("Verbose hint binding get returns current hint") func testVerboseHintBindingGet() {
        // Given
        let manager = SettingsHintManager()
        let testView = AnyView(Text("Test View"))
        manager.selectedVerboseHint = testView
        
        // When
        let binding = manager.verboseHintBinding(label: "Test")
        let retrievedView = binding.wrappedValue
        
        // Then
        #expect(retrievedView != nil)
    }
    
    @Test("Verbose hint binding set updates hint and label") func testVerboseHintBindingSet() {
        // Given
        let manager = SettingsHintManager()
        let testLabel = "Updated Label"
        let binding = manager.verboseHintBinding(label: testLabel)
        
        // When
        let newView = Text("New Hint")
        binding.wrappedValue = newView
        
        // Then
        #expect(manager.hintLabel == testLabel)
        #expect(manager.selectedVerboseHint != nil)
    }
    
    @Test("Verbose hint binding set with nil clears hint") func testVerboseHintBindingSetNil() {
        // Given
        let manager = SettingsHintManager()
        let binding = manager.verboseHintBinding(label: "Test")
        binding.wrappedValue = Text("Initial")
        
        // When
        binding.wrappedValue = nil
        
        // Then
        #expect(manager.selectedVerboseHint == nil)
        #expect(manager.hintLabel == "Test") // Label persists
    }
    
    @Test("Multiple hint bindings can be created") func testMultipleBindings() {
        // Given
        let manager = SettingsHintManager()
        
        // When
        let binding1 = manager.verboseHintBinding(label: "Label 1")
        let binding2 = manager.verboseHintBinding(label: "Label 2")
        
        binding1.wrappedValue = Text("Hint 1")
        #expect(manager.hintLabel == "Label 1")
        
        binding2.wrappedValue = Text("Hint 2")
        #expect(manager.hintLabel == "Label 2")
    }
}
