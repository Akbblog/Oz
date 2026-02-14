# 🌍 Target Market Section - Selection Flow Redesign Plan

---

## 📊 Current State vs Desired State

### Current Behavior
```
┌─────────────────────────────────────────────────────────┐
│                  ALL COUNTRIES VISIBLE                   │
│ ┌──────┬──────┬──────┬──────┬──────┐                    │
│ │ 🇺🇸 USA │ 🇬🇧 UK │ 🇦🇪 UAE │ 🇸🇦 KSA │ 🇦🇺 Aus │    │ (Selected highlighted)
│ └──────┴──────┴──────┴──────┴──────┘                    │
│                                                          │
│                  STATES (for USA)                        │
│ ┌──────┬──────┬──────┐                                  │
│ │ CA   │ TX   │ NY   │ ...                              │
│ └──────┴──────┴──────┘                                  │
│              (Can select different countries anytime)    │
└─────────────────────────────────────────────────────────┘
```

### Desired Behavior (New)
```
┌─────────────────────────────────────────────────────────┐
│               SELECTED COUNTRY ONLY                      │
│ ┌──────────────────────────────────────┐               │
│ │ ← USA  ✕ (button to deselect)         │               │
│ └──────────────────────────────────────┘               │
│                                                          │
│                  STATES (for USA)                        │
│ ┌──────┬──────┬──────┐                                  │
│ │ CA   │ TX   │ NY   │ ...                              │
│ └──────┴──────┴──────┘                                  │
│         (Only USA shown, click ← to change country)     │
└─────────────────────────────────────────────────────────┘

WHEN USER CLICKS ← (back):
┌─────────────────────────────────────────────────────────┐
│                  ALL COUNTRIES VISIBLE                   │
│ ┌──────┬──────┬──────┬──────┬──────┐                    │
│ │ 🇺🇸 USA │ 🇬🇧 UK │ 🇦🇪 UAE │ 🇸🇦 KSA │ 🇦🇺 Aus │    │
│ └──────┴──────┴──────┴──────┴──────┘                    │
│                                                          │
│              (States section hidden)                     │
│              (Cities section hidden)                     │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Changes

### UX Flow
1. **Initial State**: Countries grid visible
   - All countries shown in responsive grid
   - No states/cities visible
   - States & cities sections are hidden

2. **After Selection**: Country selected, details expand
   - Show only the selected country (collapsed view)
   - Display back button (← icon) or chip with deselect (✕)
   - Show states section
   - Show cities section when state selected

3. **On Deselect**: Return to country selection
   - All states/cities hidden
   - All countries shown again
   - Back to initial state

---

## 🔧 Implementation Strategy

### Phase 1: Add Deselect Capability (Small Change)
- Add deselect button to country card when selected
- Clear selected country when clicked
- Show all countries again

### Phase 2: Hide Unselected Countries (Main Change)
- When country selected, hide all other countries
- Show selected country in a "mode bar" at top
- Display states and cities below
- Add back button to return to country selection

### Phase 3: Collapse/Expand States Section (Optional)
- When switching states, smoothly animate
- Show selected state in a chip
- Option to collapse expanded states list

---

## 📝 Detailed Implementation Plan

### STEP 1: Update State Variables

**File**: `frontend/lib/screens/state_selection_screen.dart`

Add new state variable to track selection mode:

```dart
class _StateSelectionScreenState extends State<StateSelectionScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ... existing variables ...

  bool _countrySelectionMode = true;  // NEW: Track if user is selecting country vs states/cities
  
  // ... rest of class ...
}
```

---

### STEP 2: Modify Country Selector UI

**File**: `frontend/lib/screens/state_selection_screen.dart` (lines 600-660)

Replace `_buildCountrySelector()` method:

**OLD** (shows all countries always):
```dart
Widget _buildCountrySelector(LayoutType layoutType) {
  final countryCount = _availableCountries.length;
  final crossAxisCount = countryCount == 0
      ? 1
      : math.min(_countryGridColumns(layoutType), countryCount);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.public_rounded, ...),
          const SizedBox(width: AppSpacing.xs),
          Text('Target Market', ...),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      GridView.builder(
        // ... shows all countries ...
      ),
    ],
  );
}
```

**NEW** (shows countries or selected country):
```dart
Widget _buildCountrySelector(LayoutType layoutType) {
  // If country is selected, show compact selected view
  if (_selectedCountry != null && !_countrySelectionMode) {
    return _buildSelectedCountryBar();
  }

  // Otherwise show country selection grid
  final countryCount = _availableCountries.length;
  final crossAxisCount = countryCount == 0
      ? 1
      : math.min(_countryGridColumns(layoutType), countryCount);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.public_rounded,
            color: _LocationColors.primary,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Target Market',
            style: AppTypography.labelLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.xs,
          mainAxisSpacing: AppSpacing.xs,
          childAspectRatio: 2.0,
        ),
        itemCount: _availableCountries.length,
        itemBuilder: (context, index) {
          final country = _availableCountries[index];
          final isSelected = _selectedCountry == country;
          return _buildCountryCard(country, isSelected);
        },
      ),
    ],
  );
}

/// NEW: Show selected country in a compact bar with deselect button
Widget _buildSelectedCountryBar() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.public_rounded,
            color: _LocationColors.primary,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Target Market',
            style: AppTypography.labelLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      // Selected country in a chip/bar format
      Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _LocationColors.primary.withValues(alpha: 0.15),
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: _LocationColors.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Back button to return to country selection
            GestureDetector(
              onTap: _deselectCountry,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _LocationColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Change',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Country flag and name
            _buildCountryLeading(_selectedCountry!, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _selectedCountry!,
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Deselect button (X icon)
            GestureDetector(
              onTap: _deselectCountry,
              child: Icon(
                Icons.close_rounded,
                color: _LocationColors.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
```

---

### STEP 3: Add Deselect Method

**File**: `frontend/lib/screens/state_selection_screen.dart`

Add new method:

```dart
/// Clear country selection and return to country selection mode
void _deselectCountry() {
  setState(() {
    _selectedCountry = null;
    _countrySelectionMode = true;  // Back to country selection
    _selectedState = null;
    _selectedCities = [];
    _selectAllCities = false;
    _statesAndCities = {};
    _filteredStates = [];
    _filteredCities = [];
    _stateSearchController.clear();
    _citySearchController.clear();
  });
}
```

---

### STEP 4: Update Country Card onClick

**File**: `frontend/lib/screens/state_selection_screen.dart` (lines 640-680)

Modify `_buildCountryCard()` to set `_countrySelectionMode` to false:

```dart
Widget _buildCountryCard(String country, bool isSelected) {
  return GestureDetector(
    onTap: () async {
      if (country != _selectedCountry) {
        setState(() {
          _selectedCountry = country;
          _countrySelectionMode = false;  // NEW: Exit country selection mode
          _selectedState = null;
          _statesAndCities = {};
          _filteredCities = [];
          _isLoading = true;
        });
        await _loadInitialData();
      }
    },
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? _LocationColors.primary.withValues(alpha: 0.15)
            : _LocationColors.surface,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: isSelected
              ? _LocationColors.primary
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCountryLeading(country, isSelected: isSelected),
          const SizedBox(width: AppSpacing.xs),
          Text(
            country,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? Colors.white : _LocationColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
```

---

### STEP 5: Hide States/Cities When Not Selected

**File**: `frontend/lib/screens/state_selection_screen.dart`

Update mobile layout (around line 400):

```dart
Widget _buildMobileContent(LayoutType layoutType) {
  return FadeTransition(
    opacity: _fadeAnimation,
    child: Column(
      children: [
        if (widget.showHeader) _buildHeader(),
        const WorkflowStepper(currentStep: 0),
        _buildWizardProgress(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCountrySelector(layoutType),
                // NEW: Only show states/cities if country is selected
                if (_selectedCountry != null && !_countrySelectionMode) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _buildStateSection(layoutType: layoutType),
                  const SizedBox(height: AppSpacing.lg),
                  if (_selectedState != null)
                    _buildCitiesSection(layoutType: layoutType),
                  if (_selectedState != null)
                    const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                ],
                const SizedBox(height: AppSpacing.xl),
                _buildFooterActions(layoutType),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
```

Update tablet layout (around line 430):

```dart
Widget _buildTabletContent(LayoutType layoutType) {
  return FadeTransition(
    opacity: _fadeAnimation,
    child: Column(
      children: [
        if (widget.showHeader) _buildHeader(),
        const WorkflowStepper(currentStep: 0),
        _buildWizardProgress(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveUtils.getScreenPadding(layoutType),
              ResponsiveUtils.getScreenPadding(layoutType),
              ResponsiveUtils.getScreenPadding(layoutType),
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCountrySelector(layoutType),
                // NEW: Only show states/cities if country is selected
                if (_selectedCountry != null && !_countrySelectionMode) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _buildStateSection(layoutType: layoutType),
                  const SizedBox(height: AppSpacing.lg),
                  if (_selectedState != null)
                    _buildCitiesSection(layoutType: layoutType),
                  if (_selectedState != null)
                    const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                  const SizedBox(height: AppSpacing.xl),
                ],
                _buildFooterActions(layoutType),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
```

Update desktop layout (around line 470):

```dart
Widget _buildDesktopContent(LayoutType layoutType) {
  final leftFlex = layoutType == LayoutType.desktopMedium ? 35 : 40;
  final rightFlex = 100 - leftFlex;
  final showCities = _selectedState != null;
  final showDetails = _selectedCountry != null &&
      !_countrySelectionMode;  // NEW: Only show details if country selected

  return FadeTransition(
    opacity: _fadeAnimation,
    child: Column(
      children: [
        if (widget.showHeader) _buildHeader(),
        const WorkflowStepper(currentStep: 0),
        _buildWizardProgress(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveUtils.getScreenPadding(layoutType),
              ResponsiveUtils.getScreenPadding(layoutType),
              ResponsiveUtils.getScreenPadding(layoutType),
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCountrySelector(layoutType),
                // NEW: Only show states/cities in split panel if country selected
                if (showDetails) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: leftFlex,
                        child: _buildStateSection(
                          layoutType: layoutType,
                          inSplitPanel: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: rightFlex,
                        child: showCities
                            ? _buildCitiesSection(layoutType: layoutType)
                            : _buildEmptyCitiesPanel(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (showDetails) _buildFooterActions(layoutType),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
```

---

### STEP 6: Add Smooth Animation (Optional)

**File**: `frontend/lib/screens/state_selection_screen.dart`

Make transitions smoother with animation:

```dart
// Modify _buildSelectedCountryBar() to add animation
Widget _buildSelectedCountryBar() {
  return ScaleTransition(
    scale: Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _fadeAnimation, curve: Curves.easeOut),
    ),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _LocationColors.primary.withValues(alpha: 0.15),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: _LocationColors.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      // ... rest of widget ...
    ),
  );
}
```

---

## 📋 Implementation Checklist

### Phase 1: Core Implementation
- [ ] Add `_countrySelectionMode` state variable
- [ ] Create `_deselectCountry()` method
- [ ] Create `_buildSelectedCountryBar()` method
- [ ] Update `_buildCountrySelector()` to check selection mode
- [ ] Update `_buildCountryCard()` to set `_countrySelectionMode = false`
- [ ] Update mobile layout to hide states/cities when no country selected
- [ ] Update tablet layout to hide states/cities when no country selected
- [ ] Update desktop layout to hide states/cities when no country selected
- [ ] Test on mobile (countries hide properly)
- [ ] Test on tablet (states/cities hide properly)
- [ ] Test on desktop (split panel behaves correctly)

### Phase 2: UX Polish
- [ ] Add back button styling to match design system
- [ ] Ensure deselect button (X) is clear and accessible
- [ ] Add tooltip to back button
- [ ] Optimize spacing in selected country bar
- [ ] Test on different screen sizes
- [ ] Verify smooth transitions

### Phase 3: Enhanced Features (Optional)
- [ ] Add animation when switching views
- [ ] Add slide transition for bar appearance
- [ ] Add collapse/expand animation for states list
- [ ] Add success feedback when deselecting
- [ ] Add keyboard support (ESC to deselect)

---

## 🧪 Testing Scenarios

### Mobile (< 600px)
```
✅ Step 1: Open screen
   - All countries visible
   - No states/cities visible

✅ Step 2: Select USA
   - All countries HIDDEN
   - "← Change" button visible
   - "× Close" button visible
   - States section appears
   - Smooth transition

✅ Step 3: Click "← Change" button
   - All countries visible again
   - States/cities hidden
   - Back to initial state

✅ Step 4: Select UK
   - Shows UK in bar
   - UK states appear
```

### Tablet (600-1200px)
```
✅ Step 1: Select country
   - Left panel: country bar + states
   - Right panel: "Select a state" message

✅ Step 2: Select state
   - Right panel: cities list appears
   - Smooth transition

✅ Step 3: Click "Change"
   - Both panels reset
   - Country grid visible
```

### Desktop (> 1200px)
```
✅ Step 1: All countries visible
   - Two-column layout ready
   - No right panel content

✅ Step 2: Select country
   - Left panel: selected country bar + states
   - Right panel: cities section
   - Split layout activated

✅ Step 3: Deselect
   - Everything resets
   - Back to initial state
```

---

## 📊 Visual Design Updates

### Selected Country Bar
```
┌───────────────────────────────────────────────┐
│ ┌──────────────┐              🇺🇸 USA        │ ✕
│ │ ← Change     │ (Selected country in middle)  │
│ └──────────────┘                              │
└───────────────────────────────────────────────┘
```

**Colors**:
- Background: `primaryBlue.withValues(alpha: 0.15)`
- Border: `primaryBlue.withValues(alpha: 0.5)`
- Text: White (primary blue on hover)
- Button: `primaryBlue.withValues(alpha: 0.2)` background

**Interactions**:
- Hover back button: Slightly brighten background
- Hover X button: Show "Remove" tooltip
- Click back: Smooth fade-out of states/cities, fade-in of countries
- Click X: Same as click back

---

## 🎯 Benefits

✅ **Clearer Workflow**: Users focus on one country at a time  
✅ **Reduced Cognitive Load**: No distraction from other countries  
✅ **Better Mobile UX**: More space for states/cities  
✅ **Clear Deselection**: Obvious way to change country  
✅ **Responsive Design**: Works perfectly on all sizes  
✅ **Maintains Functionality**: All existing features still work  

---

## 📝 Files to Modify

### Single File Required
- `frontend/lib/screens/state_selection_screen.dart`

**Changes**:
1. Add 1 state variable (`_countrySelectionMode`)
2. Add 2 new methods (`_deselectCountry()`, `_buildSelectedCountryBar()`)
3. Modify 4 existing methods (`_buildCountrySelector()`, `_buildCountryCard()`, layout builders)
4. Add conditional visibility to states/cities sections

**Total Lines Added**: ~150-200  
**Total Lines Modified**: ~50-100  
**Complexity**: Low to Medium  

---

## ⚡ Implementation Order

1. **Add state variable** (5 min)
2. **Add deselect method** (5 min)
3. **Create selected country bar** (15 min)
4. **Update country selector logic** (15 min)
5. **Update country card** (5 min)
6. **Update layout builders** (30 min)
7. **Test all scenarios** (20 min)
8. **Polish animations** (optional, 10 min)

**Total**: 1.5-2 hours

---

## 🔗 Related Code

- Country grid: Lines 600-660
- Country card: Lines 640-720
- Mobile layout: Lines 380-420
- Tablet layout: Lines 425-460
- Desktop layout: Lines 465-525
- State section: Lines 730-800
- Cities section: Lines 900-1100

---

**Status**: ✅ Ready for Implementation  
**Difficulty**: ⭐⭐⭐ Medium  
**Impact**: 🎯 High (Better UX)  

this is my plan please implement this in best possible way this is my input use your experties 