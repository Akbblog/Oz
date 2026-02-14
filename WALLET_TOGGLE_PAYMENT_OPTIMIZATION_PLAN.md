# 💳 Wallet Toggle & Payment Methods Optimization Plan


## 📊 Current State Analysis

### Problem 1: Slow Wallet Loading
**Location**: `frontend/lib/screens/wallet_screen.dart` (lines 35-130)

**Current Issues**:
- Makes **6 parallel API calls** on screen load:
  1. `getCreditBalance()` 
  2. `getMySubscription()`
  3. `getCreditHistory()`
  4. `getPaymentTransactions()`
  5. `getInvoices()`
  6. `getMyCreditRequests()`

- **Performance Impact**:
  - No loading state distinction (shows generic loading)
  - All requests have 30-second timeout
  - Failed requests (not critical) still block UI
  - Tab content loads before tabs are visible
  - Non-critical data delays critical data

**Loading Code** (lines 52-130):
```dart
Future<void> _loadData() async {
  setState(() {
    _isLoading = true;
    _error = null;
  });

  try {
    // Loads ALL 6 at once, sequentially!
    var creditBalance = <String, dynamic>{};
    var subscription = <String, dynamic>{};
    var creditHistory = <Map<String, dynamic>>[];
    var paymentTransactions = <Map<String, dynamic>>[];
    var invoices = <Map<String, dynamic>>[];
    var creditRequests = <Map<String, dynamic>>[];

    try {
      creditBalance = await _apiService.getCreditBalance();
    } catch (e) {
      print('Failed to load credit balance: $e');
    }

    try {
      subscription = await _apiService.getMySubscription();
    } catch (e) {
      print('Failed to load subscription: $e');
    }
    
    // ... 4 more try-catch blocks ...
```

---

### Problem 2: No Payment Method Toggle
**Current State**:
- Payment methods are hardcoded into screens
- No admin control over which payment method pages are shown
- No "Coming Soon" page for future payment methods
- Users can't tell which payment methods are available

---

## ✅ Solution Overview

### Phase 1: Admin Payment Toggle
Create a toggle in admin settings to control:
- ✅ **Wallet Feature State**: 
  - `TRUE` → Show current wallet (request credits)
  - `FALSE` → Show "Coming Soon" page with Stripe, PayPal, Coinbase coming soon

### Phase 2: Wallet Performance Optimization
Optimize wallet loading by:
- Load **critical data first** (credit balance)
- **Lazy-load tabs** (load data only when tab is selected)
- **Deferred loading** for non-critical data
- Separate loading states for each section

### Phase 3: Coming Soon Page
Create a "Payment Methods Coming Soon" page showing:
- Stripe badge
- PayPal badge
- Coinbase badge
- Message: "Live payments coming soon. For now, request credits from admins."
- Button to navigate to current wallet (request credits)

---

## 🔧 Implementation Plan

### STEP 1: Backend - Add Payment Features Toggle Setting

**File**: `backend/main.py`

Add to admin settings initialization (around line where settings are created):

```python
# In database initialization function
def ensure_admin_settings():
    """Ensure default admin settings exist"""
    
    # ... existing settings ...
    
    # Add payment feature toggle (NEW)
    if not get_admin_setting('enable_live_payments'):
        set_admin_setting(
            'enable_live_payments',
            'false',  # Default: disabled (show Coming Soon)
            admin_id=1
        )
    
    if not get_admin_setting('payment_methods_enabled'):
        set_admin_setting(
            'payment_methods_enabled',
            'stripe,paypal,coinbase',  # Future: comma-separated list
            admin_id=1
        )
```

**Note**: The existing `getAdminSettings()`, `getAdminSetting()`, and `updateAdminSetting()` endpoints already exist in your code. No backend changes needed - just use existing endpoints!

---

### STEP 2: Frontend - Update Admin Dashboard

**File**: `frontend/lib/screens/admin_dashboard_screen.dart`

Add toggle in **Settings Tab** (find the settings tab around line 2800+):

Add this new section to `_buildSettingsView()`:

```dart
Widget _buildPaymentSettingsSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader('Payment Features', ''),
      const SizedBox(height: AppSpacing.md),
      
      Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.elevatedCardDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Payment Methods',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enable/disable live payment features for users',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _paymentFeaturesEnabled,
                  onChanged: (value) async {
                    setState(() => _paymentFeaturesEnabled = value);
                    await _updatePaymentToggle(value);
                  },
                  activeColor: AppColors.successGreen,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: AppSpacing.paddingSm,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: AppSpacing.borderRadiusMd,
              ),
              child: Row(
                children: [
                  Icon(
                    _paymentFeaturesEnabled 
                        ? Icons.check_circle 
                        : Icons.info_outline,
                    color: _paymentFeaturesEnabled 
                        ? AppColors.successGreen 
                        : AppColors.warningYellow,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _paymentFeaturesEnabled
                          ? 'Users can access wallet and process payments'
                          : 'Users see Coming Soon page (request credits only)',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Container(
        padding: AppSpacing.paddingSm,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: AppColors.primaryBlue,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Note: When disabled, users can still request credits from the Coming Soon page.',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Future<void> _updatePaymentToggle(bool enabled) async {
  try {
    await _apiService.updateAdminSetting(
      'enable_live_payments',
      enabled ? 'true' : 'false',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment features ${enabled ? 'enabled' : 'disabled'}',
          ),
          backgroundColor: AppColors.successGreen,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update settings: $e'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    }
  }
}
```

Add to admin dashboard state:

```dart
bool _paymentFeaturesEnabled = false;

@override
void initState() {
  super.initState();
  _loadPaymentSettings(); // Add this
}

Future<void> _loadPaymentSettings() async {
  try {
    final setting = await _apiService.getAdminSetting('enable_live_payments');
    if (mounted) {
      setState(() {
        _paymentFeaturesEnabled = (setting ?? 'false').toLowerCase() == 'true';
      });
    }
  } catch (e) {
    print('Failed to load payment settings: $e');
  }
}
```

---

### STEP 3: Create Coming Soon Payment Page

**File**: `frontend/lib/screens/wallet_coming_soon_screen.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

class WalletComingSoonScreen extends StatefulWidget {
  const WalletComingSoonScreen({super.key});

  @override
  State<WalletComingSoonScreen> createState() => _WalletComingSoonScreenState();
}

class _WalletComingSoonScreenState extends State<WalletComingSoonScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  int _creditBalance = 0;

  @override
  void initState() {
    super.initState();
    _loadCreditBalance();
  }

  Future<void> _loadCreditBalance() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getCreditBalance();
      if (mounted) {
        setState(() {
          _creditBalance = data['balance'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutType = AppBreakpoints.getLayoutType(
      MediaQuery.of(context).size.width,
    );
    final padding = ResponsiveUtils.getScreenPadding(layoutType);

    return Scaffold(
      backgroundColor: _ComingSoonColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Billing & Payments',
          style: AppTypography.headlineSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryBlue,
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Current Balance Card
                    _buildBalanceCard(),
                    const SizedBox(height: AppSpacing.lg),

                    // Coming Soon Header
                    _buildComingSoonHeader(),
                    const SizedBox(height: AppSpacing.lg),

                    // Payment Methods Grid
                    _buildPaymentMethodsGrid(layoutType),
                    const SizedBox(height: AppSpacing.lg),

                    // Request Credits Card
                    _buildRequestCreditsCard(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlueDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Balance',
            style: AppTypography.labelMedium.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$_creditBalance',
                style: AppTypography.displaySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Credits',
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoonHeader() {
    return Column(
      children: [
        Container(
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: AppColors.warningYellow.withValues(alpha: 0.1),
            borderRadius: AppSpacing.borderRadiusMd,
            border: Border.all(
              color: AppColors.warningYellow.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                color: AppColors.warningYellow,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Payment methods coming soon!',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.warningYellow,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'We\'re preparing secure payment integrations to make purchasing credits easier.',
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white70,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPaymentMethodsGrid(LayoutType layoutType) {
    final paymentMethods = [
      {
        'name': 'Stripe',
        'icon': '🧾',
        'color': const Color(0xFF635BFF),
        'status': 'Coming Soon',
      },
      {
        'name': 'PayPal',
        'icon': '💳',
        'color': const Color(0xFF003087),
        'status': 'Coming Soon',
      },
      {
        'name': 'Coinbase',
        'icon': '₿',
        'color': const Color(0xFF1652F0),
        'status': 'Coming Soon',
      },
      {
        'name': 'Bank Transfer',
        'icon': '🏦',
        'color': const Color(0xFF4CAF50),
        'status': 'Coming Soon',
      },
    ];

    final crossAxisCount = layoutType == LayoutType.mobile ? 2 : 4;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.0,
      ),
      itemCount: paymentMethods.length,
      itemBuilder: (context, index) {
        final method = paymentMethods[index];
        return _buildPaymentMethodCard(
          method['name'] as String,
          method['icon'] as String,
          method['color'] as Color,
        );
      },
    );
  }

  Widget _buildPaymentMethodCard(String name, String icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            style: AppTypography.labelMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Coming soon',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCreditsCard() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.successGreen.withValues(alpha: 0.2),
            AppColors.successGreen.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.thumb_up_alt_rounded,
                color: AppColors.successGreen,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need Credits Now?',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Request credits from our team',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/wallet');
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Go to Wallet'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonColors {
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.surfaceDark;
  static const Color primary = AppColors.primaryBlue;
}
```

---

### STEP 4: Update Wallet Screen with Check

**File**: `frontend/lib/screens/wallet_screen.dart`

Modify at the beginning of `_WalletScreenState.initState()`:

```dart
@override
void initState() {
  super.initState();
  _tabController = TabController(length: 4, vsync: this);
  print('Wallet screen initState - checking payment feature status');
  _checkPaymentFeatureStatus(); // ADD THIS
  _loadData();
}

Future<void> _checkPaymentFeatureStatus() async {
  try {
    final setting = await _apiService.getAdminSetting('enable_live_payments');
    final enabled = (setting ?? 'false').toLowerCase() == 'true';
    
    if (!enabled && mounted) {
      // Redirect to coming soon page
      Navigator.of(context).pushReplacementNamed('/wallet-coming-soon');
      return;
    }
  } catch (e) {
    print('Failed to check payment settings: $e');
    // Continue with normal loading if check fails
  }
}
```

---

### STEP 5: Optimize Wallet Loading (Performance)

**File**: `frontend/lib/screens/wallet_screen.dart`

Replace the `_loadData()` method with optimized version:

```dart
Future<void> _loadData() async {
  setState(() {
    _isLoading = true;
    _error = null;
  });

  try {
    // PHASE 1: Load critical data first (blocking)
    print('Wallet: Loading critical data (balance)...');
    var creditBalance = <String, dynamic>{};
    try {
      creditBalance = await _apiService.getCreditBalance();
      print('Wallet: Balance loaded');
    } catch (e) {
      print('Failed to load credit balance: $e');
    }

    // Update UI with critical data immediately
    if (mounted) {
      setState(() {
        final balanceData = creditBalance;
        final map = Map<String, dynamic>.from(balanceData);
        final rawBalance = map['balance'];
        _creditBalance = rawBalance is num
            ? rawBalance.toInt()
            : (rawBalance is String ? int.tryParse(rawBalance) ?? 0 : 0);
        _isLoading = false; // Show UI immediately!
        print('Wallet: Critical data loaded. Balance: $_creditBalance');
      });
    }

    // PHASE 2: Load other data in background (non-blocking)
    print('Wallet: Loading secondary data in background...');
    _loadSecondaryData();

  } catch (e) {
    if (mounted) {
      setState(() {
        final errorStr = e.toString();
        if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
          _error = 'You must be logged in to view your wallet';
        } else {
          _error = 'Failed to load wallet data: $e';
        }
        _isLoading = false;
      });
      print('Wallet error: $e');
    }
  }
}

/// Load secondary data asynchronously (doesn't block UI)
Future<void> _loadSecondaryData() async {
  try {
    var subscription = <String, dynamic>{};
    var creditHistory = <Map<String, dynamic>>[];
    var paymentTransactions = <Map<String, dynamic>>[];
    var invoices = <Map<String, dynamic>>[];
    var creditRequests = <Map<String, dynamic>>[];

    // Load subscription
    try {
      subscription = await _apiService.getMySubscription();
      print('Wallet: Subscription loaded');
    } catch (e) {
      print('Failed to load subscription: $e');
    }

    // Load credit history
    try {
      creditHistory = await _apiService.getCreditHistory();
      print('Wallet: Credit history loaded');
    } catch (e) {
      print('Failed to load credit history: $e');
    }

    // Load payment transactions
    try {
      paymentTransactions = await _apiService.getPaymentTransactions();
      print('Wallet: Payment transactions loaded');
    } catch (e) {
      print('Failed to load payment transactions: $e');
    }

    // Load invoices
    try {
      invoices = await _apiService.getInvoices();
      print('Wallet: Invoices loaded');
    } catch (e) {
      print('Failed to load invoices: $e');
    }

    // Load credit requests
    try {
      creditRequests = await _apiService.getMyCreditRequests();
      print('Wallet: Credit requests loaded');
    } catch (e) {
      print('Failed to load credit requests: $e');
    }

    // Update UI with all secondary data
    if (mounted) {
      setState(() {
        final subData = subscription;
        final sub = Map<String, dynamic>.from(subData);
        _subscription = sub.isEmpty ? null : sub;
        _creditHistory = creditHistory;
        _paymentTransactions = paymentTransactions;
        _invoices = invoices;
        _creditRequests = creditRequests;
        print('Wallet: All secondary data loaded');
      });
    }
  } catch (e) {
    print('Secondary data load error: $e');
    // Silent fail - UI already showing with basic data
  }
}
```

---

### STEP 6: Add Route for Coming Soon Page

**File**: `frontend/lib/main.dart`

Add import at top:
```dart
import 'screens/wallet_coming_soon_screen.dart';
```

Add route in `routes` map:
```dart
'/wallet-coming-soon': (context) => const _ProtectedRoute(
  child: WalletComingSoonScreen(),
),
```

---

### STEP 7: Lazy-Load Tab Content (Optional Enhancement)

**File**: `frontend/lib/screens/wallet_screen.dart`

Modify `_buildTabContent()` to lazy-load expensive tabs:

```dart
// Add state variable
bool _tabsInitialized = {0: true, 1: false, 2: false, 3: false};

// In tab view builder
Widget _buildTabContent() {
  int currentTab = _tabController.index;
  
  return TabBarView(
    controller: _tabController,
    children: [
      // Tab 0: Overview (always loaded)
      _buildOverviewTab(),
      
      // Tab 1: Transactions (load on demand)
      if (_tabsInitialized[1] == true)
        _buildTransactionsTab()
      else
        Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryBlue,
          ),
        ),
      
      // Tab 2: Invoices (load on demand)
      if (_tabsInitialized[2] == true)
        _buildInvoicesTab()
      else
        Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryBlue,
          ),
        ),
      
      // Tab 3: Requests (load on demand)
      if (_tabsInitialized[3] == true)
        _buildRequestsTab()
      else
        Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryBlue,
          ),
        ),
    ],
  );
}

// Listen to tab changes
void _setupTabListener() {
  _tabController.addListener(() {
    final index = _tabController.index;
    if (!_tabsInitialized[index]!) {
      setState(() => _tabsInitialized[index] = true);
    }
  });
}
```

---

## 📋 Implementation Checklist

### Phase 1: Admin Toggle & Coming Soon Page (Required)
- [ ] Create `wallet_coming_soon_screen.dart` (NEW)
- [ ] Add import to `main.dart`
- [ ] Add `/wallet-coming-soon` route to `main.dart`
- [ ] Update admin dashboard with payment toggle section
- [ ] Add `_loadPaymentSettings()` to admin dashboard
- [ ] Add `_checkPaymentFeatureStatus()` check to wallet screen
- [ ] Test toggle in admin settings
- [ ] Test coming soon redirect when disabled

### Phase 2: Wallet Performance (Recommended)
- [ ] Replace `_loadData()` with optimized two-phase version
- [ ] Add `_loadSecondaryData()` method
- [ ] Test wallet loads quickly
- [ ] Verify all tabs still load eventually
- [ ] Check browser console for loading sequence

### Phase 3: Lazy-Load Tabs (Optional)
- [ ] Add `_tabsInitialized` state variable
- [ ] Create `_setupTabListener()` method
- [ ] Modify `_buildTabContent()` to lazy-load
- [ ] Test tab switching performance

---

## 🧪 Testing Plan

### Admin Toggle Testing
```
1. ✅ Login as admin
2. ✅ Navigate to /admin
3. ✅ Go to Settings tab
4. ✅ Find "Payment Features" section
5. ✅ Toggle OFF → verify UI feedback
6. ✅ Toggle ON → verify UI feedback
7. ✅ Logout / Login as regular user
8. ✅ Click wallet → should show Coming Soon (if toggle OFF)
9. ✅ Coming Soon page shows all 4 payment methods
10. ✅ "Go to Wallet" button navigates to request credits
```

### Performance Testing
```
1. ✅ Open wallet page
2. ✅ Should show balance within 2 seconds
3. ✅ Other tabs load in background
4. ✅ Check browser Network tab for 6 separate requests
5. ✅ Verify no blocking/waiting
6. ✅ Switch tabs → content already loaded or loads shown
```

### User Flow Testing
```
1. ✅ Payment OFF: Wallet → redirected to Coming Soon
2. ✅ Payment OFF: Coming Soon → request credits button works
3. ✅ Payment ON: Wallet → shows normal wallet
4. ✅ All tabs accessible when payment ON
5. ✅ Mobile layout looks good
6. ✅ Tablet layout looks good
7. ✅ Desktop layout looks good
```

---

## 📊 Before & After Comparison

### Wallet Load Time

**Before**:
```
Timeline:
0s   - Start loading
0.5s - 404/timeout on getCreditHistory?
1.2s - 404 on getPaymentTransactions?
2.5s - 404 on getInvoices?
...  - Loading spinner still showing
5s+  - Finally shows partial data
```

**After (Critical First)**:
```
Timeline:
0s     - Start loading
0.3s   - getCreditBalance returns ✅
0.3s   - UI updates with balance, spinner GONE
0.5s+  - Secondary data loads in background (non-blocking)
Result: User sees content immediately!
```

---

## 🎯 Expected Benefits

✅ **Better UX**:
- Wallet shows content in <1 second (vs 5+ seconds)
- No wait time for non-critical features
- Graceful handling of timeout/failures

✅ **Admin Control**:
- Easy toggle for payment methods availability
- Users always see appropriate screen
- Can enable payment methods when ready

✅ **Scalability**:
- New payment providers can be added to Coming Soon grid
- Toggle scales to multiple payment features
- Settings stored in database (can be managed via API)

✅ **User Communication**:
- Clear "Coming Soon" messaging
- Shows which payment methods are planned
- Alternative path (request credits) always available

---

## 📝 Files to Create/Modify

### New Files
- ✅ `frontend/lib/screens/wallet_coming_soon_screen.dart`

### Modified Files
1. `frontend/lib/main.dart` - Add route
2. `frontend/lib/screens/wallet_screen.dart` - Add check & optimize loading
3. `frontend/lib/screens/admin_dashboard_screen.dart` - Add payment toggle

### Backend (No changes needed!)
- Uses existing `getAdminSetting()`, `updateAdminSetting()` endpoints

---

## 🚀 Deployment Order

1. **Deploy Backend**: Nothing needed (existing settings endpoints)
2. **Deploy Frontend**: 
   - Create coming soon screen
   - Update wallet with check
   - Add admin toggle (optional: update admin dashboard)
3. **Test**: Verify toggle works end-to-end
4. **Optimize Wallet** (after ensuring toggle works)

---

## ⚡ Quick Start Summary

**To implement minimum (Admin Toggle + Coming Soon)**:
1. Create `wallet_coming_soon_screen.dart` (copy from plan above)
2. Update `main.dart` with new route
3. Add 5-line check to `wallet_screen.dart` initState
4. Add payment toggle to admin dashboard

**Estimated time**: 30-45 minutes

**To also optimize wallet loading**:
- Replace `_loadData()` with two-phase version
- Additional 15-20 minutes

---

## 🔗 Reference Links

- Admin Settings: `ADMIN_SETTINGS_IMPLEMENTATION.md`
- Wallet Screenshot: Payment methods UI in `peaceful-cuddling-bumblebee.md`
- API Endpoint Docs: Backend `main.py` lines 3574-3576 (wallet payment URLs)

---

**Status**: ✅ Ready for Implementation  
**Difficulty**: ⭐⭐⭐ Medium  
**Time**: 45-60 minutes total  
**Payoff**: 🎯 High (UX + Admin Control + Performance)

---

this is my plan please implement this in best possible way this is my input use your experties 
