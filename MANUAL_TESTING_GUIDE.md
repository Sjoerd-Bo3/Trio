# Manual Testing Guide for Refactored Code

This guide provides step-by-step instructions for manually testing the refactored code changes in the Trio app.

## Overview

Two main areas have been refactored:
1. **Settings Hint Management** - Affects 15 settings views
2. **Chart Popover Positioning** - Affects 3 chart views

## Automated Tests

Run the automated test suites first:

```bash
# In Xcode, run the test target
# Or use command line:
xcodebuild test -workspace Trio.xcworkspace -scheme Trio -destination 'platform=iOS Simulator,name=iPhone 15'
```

The following test files have been added:
- `TrioTests/SettingsHintManagerTests.swift` - Tests for SettingsHintManager
- `TrioTests/StatChartUtilsTests.swift` - Tests for chart popover positioning

## Manual Testing

### Part 1: Settings Hint Display (15 Views)

Test the hint display functionality in all affected settings views to ensure the refactored code works correctly.

#### Settings Views to Test:

1. **SMB Settings** (`Settings` → `SMB Settings`)
2. **Autosens Settings** (`Settings` → `Autosens Settings`)
3. **Autotune Config** (`Settings` → `Autotune Config`)
4. **CGM Settings** (`Settings` → `CGM Settings`)
5. **Dynamic Settings** (`Settings` → `Dynamic Settings`)
6. **Units & Limits Settings** (`Settings` → `General Settings` → `Units & Limits`)
7. **Meal Settings** (`Settings` → `Meal Settings`)
8. **Nightscout Config** (`Settings` → `Nightscout Config`)
9. **Nightscout Fetch** (within Nightscout Config)
10. **Nightscout Upload** (within Nightscout Config)
11. **Settings Root** (main settings page)
12. **Notifications View** (`Settings` → `Notifications`)
13. **Tidepool Start** (`Settings` → `Tidepool`)
14. **Shortcuts Config** (`Settings` → `Shortcuts`)
15. **Target Behavior** (`Settings` → `Target Behavior`)

#### Test Steps for Each Settings View:

1. **Navigate to the settings view**
   - Open the Trio app
   - Navigate to the specific settings page

2. **Test hint icon interaction**
   - Look for the information icon (ℹ️) next to setting labels
   - Tap the info icon
   - **Expected**: A sheet should appear with detailed help information

3. **Verify hint content**
   - Read the hint text in the sheet
   - **Expected**: The hint label should match the setting name
   - **Expected**: The hint content should be relevant to that setting

4. **Test hint dismissal**
   - Tap the "Got it!" button or swipe down to dismiss
   - **Expected**: The sheet should close smoothly

5. **Test multiple hints in same view**
   - If the view has multiple settings with hints, test several
   - **Expected**: Each hint should display its own specific content
   - **Expected**: No content from previous hints should leak into new ones

6. **Test hint detent (sheet size)**
   - When the sheet appears, try to drag it
   - **Expected**: Sheet should support standard iOS sheet behaviors
   - **Expected**: Sheet should not glitch or flicker

### Part 2: Chart Popover Positioning (3 Views)

Test the popover positioning in chart views to ensure they stay within bounds.

#### Chart Views to Test:

1. **Meal Stats Chart** (`Statistics` → `Meal` tab)
2. **Total Daily Dose Chart** (`Statistics` → `Insulin` tab)
3. **Bolus Stats Chart** (`Statistics` → `Insulin` tab)

#### Test Steps for Each Chart View:

1. **Navigate to the chart**
   - Open the Trio app
   - Go to the Statistics section
   - Select the appropriate tab (Meal or Insulin)

2. **Test center data point selection**
   - Tap on a data point in the middle of the chart
   - **Expected**: A popover should appear above the data point
   - **Expected**: The popover should be centered over the data point

3. **Test left edge data point**
   - Tap on a data point near the left edge of the chart
   - **Expected**: The popover should appear but shift right to stay within bounds
   - **Expected**: The popover should not be cut off on the left side

4. **Test right edge data point**
   - Tap on a data point near the right edge of the chart
   - **Expected**: The popover should appear but shift left to stay within bounds
   - **Expected**: The popover should not be cut off on the right side

5. **Test popover content**
   - Verify that the popover displays correct data for the selected point
   - **Expected**: Data values match the selected time/date

6. **Test with different time ranges**
   - Change the time interval (day/week/month/total)
   - Repeat tests 2-4 with different time ranges
   - **Expected**: Popover positioning works correctly in all time ranges

7. **Test on different device sizes**
   - Test on iPhone SE (small screen)
   - Test on iPhone Pro Max (large screen)
   - Test on iPad (if supported)
   - **Expected**: Popover positioning adapts correctly to screen size

### Part 3: Regression Testing

Ensure that the refactoring hasn't broken any existing functionality.

#### General Functionality Tests:

1. **Settings persistence**
   - Change a setting value
   - Close and reopen the app
   - **Expected**: Setting value is preserved

2. **Settings validation**
   - Try to enter invalid values (if applicable)
   - **Expected**: Validation works as before

3. **Chart interactions**
   - Scroll through chart data
   - Zoom (if applicable)
   - Switch between different metrics
   - **Expected**: All chart interactions work smoothly

4. **Performance**
   - Navigate quickly between settings views
   - Rapidly tap on different chart data points
   - **Expected**: No lag or performance degradation
   - **Expected**: No memory leaks

## Checklist

Use this checklist to track your testing progress:

### Settings Hint Display
- [ ] SMB Settings
- [ ] Autosens Settings
- [ ] Autotune Config
- [ ] CGM Settings
- [ ] Dynamic Settings
- [ ] Units & Limits Settings
- [ ] Meal Settings
- [ ] Nightscout Config
- [ ] Nightscout Fetch
- [ ] Nightscout Upload
- [ ] Settings Root
- [ ] Notifications View
- [ ] Tidepool Start
- [ ] Shortcuts Config
- [ ] Target Behavior

### Chart Popover Positioning
- [ ] Meal Stats Chart - center point
- [ ] Meal Stats Chart - left edge
- [ ] Meal Stats Chart - right edge
- [ ] Total Daily Dose Chart - center point
- [ ] Total Daily Dose Chart - left edge
- [ ] Total Daily Dose Chart - right edge
- [ ] Bolus Stats Chart - center point
- [ ] Bolus Stats Chart - left edge
- [ ] Bolus Stats Chart - right edge

### Regression Testing
- [ ] Settings persistence works
- [ ] Settings validation works
- [ ] Chart scrolling works
- [ ] No performance issues
- [ ] Tested on multiple device sizes

## Reporting Issues

If you find any issues during testing:

1. Note the specific view/chart where the issue occurs
2. Describe the steps to reproduce
3. Include screenshots or screen recordings if possible
4. Note the device model and iOS version
5. Report on the GitHub PR thread

## Additional Notes

### What Changed Internally

**Settings Hint Management:**
- Before: Each settings view managed its own hint state with 6 separate @State variables
- After: All hint state is now managed by a single `SettingsHintManager` object
- Impact: No visible change to end users, but more maintainable code

**Chart Popover Positioning:**
- Before: Each chart had its own copy of the `xOffset()` calculation function
- After: All charts use a shared `StatChartUtils.calculatePopoverXOffset()` function
- Impact: No visible change to end users, but fixes can now be applied once for all charts

### Expected Behavior

The refactoring should be **completely transparent** to users. If you notice ANY difference in behavior compared to the previous version, that's a bug that should be reported.
