# Feature Request: Display Sensor Age After Expiration in MedtrumKit

## Is your feature request related to a problem? Please describe.

When a Medtrum CGM sensor expires, the detailed age display (e.g., "Age: 3 days 8 hours 45 minutes") is replaced with just "EXPIRED" text in the MedtrumKit screens. This removes visibility of the total sensor age, making it harder to track how long the sensor has been in use when running in extended mode.

**Current behavior:**
- Normal lifetime: 3 days 8 hours
- Extended lifetime: Until battery or insulin is depleted
- Before expiration: Shows detailed age in MedtrumKit screens ✓
- After expiration: Shows only "EXPIRED" in MedtrumKit screens (loses age details)
- Home screen: Shows time until expiring/expired duration ✓ (works well)

## Describe the solution you'd like

Continue displaying the sensor age in the same detailed format after expiration, with an "EXPIRED" indicator added:

**Proposed formats:**
```
EXPIRED - Age: 12 days 8 hours 45 minutes
```
or
```
Age: 12 days 8 hours 45 minutes (EXPIRED)
```

This maintains UI consistency and allows users to quickly see total sensor age without navigating to the home screen or doing mental calculations.

## Describe alternatives you've considered

1. **Using only the home screen display** - Already shows "expired for X time" but requires navigation and doesn't show total age
2. **Manual calculation** - Adding the "expired for" time to the 3d 8h official lifespan is cumbersome
3. **Current "EXPIRED" only** - Removes valuable age tracking information

The proposed solution maintains consistency with the pre-expiration display while clearly indicating expired status.

## Additional context

**Visual reference:**
See attached screenshot showing the current age display format that should be preserved after expiration.

![Sensor Age Display](attachment)

**Use case:** Many users run sensors in extended mode beyond the 3d 8h official lifespan. Seeing the total age (e.g., "10 days 2 hours") helps track sensor performance and decide when to replace it.

**Gauging interest:** Would other Medtrum users find this helpful?

## Technical Details

**Implementation:**
- Modify MedtrumKit sensor age display logic to show age format instead of just "EXPIRED" text
- Age calculation already works (shown on home screen)
- Primarily a UI display change in MedtrumKit/MedtrumKitUI
- Add visual styling (red text/icon) for expired indicator

**Files to investigate:**
- `MedtrumKit/MedtrumKitUI/` - UI components for sensor display
- Sensor age formatting logic in MedtrumKit

## User Impact

**Impact:** Medium - Quality-of-life improvement for Medtrum users running sensors in extended mode

**Benefits:**
- Consistent UI throughout sensor lifecycle
- Quick total age visibility without screen navigation
- Better tracking for decision-making on sensor replacement
- Complements existing home screen "expired for" display
