import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import '../core/countries.dart';
import '../providers/auth_provider.dart';
import '../core/theme/app_theme.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../widgets/brand_mark.dart';
import '../widgets/country_picker.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordVisible = ValueNotifier<bool>(false);
  bool _isLoading = false;

  /// Country for the phone number. Preselected from the visitor's network,
  /// then the browser language; the person can always change it.
  Country? _country;
  bool _countryTouched = false;

  /// Messages from the server, shown under the field they are about.
  final Map<String, String> _serverErrors = {};

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.page('/register');
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
    _guessCountry();
  }

  Future<void> _guessCountry() async {
    String? locale;
    try {
      locale = html.window.navigator.language;
    } catch (_) {}
    final fromLocale = countryFromLocale(locale);
    if (fromLocale != null && mounted) setState(() => _country = fromLocale);
    // Network location first (the hosting edge knows it), then the backend's
    // own guess for hosts without that.
    final where = await AnalyticsService.instance.geo();
    final hint = countryByIso(where['country']) ??
        countryByIso(await ApiService().getGeoHint());
    if (hint != null && mounted && !_countryTouched) {
      setState(() => _country = hint);
    }
  }

  /// A sign-in name is still stored for every account, but nobody has to
  /// invent one: it comes from the email, and people sign in with the email.
  static String _usernameFrom(String email, {String suffix = ''}) {
    var base = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    if (base.length < 3) base = 'user$base';
    if (base.length > 24) base = base.substring(0, 24);
    return '$base$suffix';
  }

  /// Back to where the person came from; to sign-in when this page was
  /// opened directly by its address.
  void _leave() {
    final nav = Navigator.of(context);
    nav.canPop() ? nav.pop() : nav.pushReplacementNamed('/login');
  }

  void _clearServerError(String field) {
    if (_serverErrors.containsKey(field)) {
      setState(() => _serverErrors.remove(field));
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordVisible.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.dangerRed : AppColors.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        margin: AppSpacing.paddingMd,
        duration: Duration(seconds: isError ? 3 : 4),
      ),
    );
  }

  Future<void> _handleRegister() async {
    setState(() => _serverErrors.clear());
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim().toLowerCase();
    final typedPhone = _phoneController.text.trim();
    final who = await AnalyticsService.instance.identity();
    final where = await AnalyticsService.instance.geo();

    String? message;
    String error = '';
    // The sign-in name is derived from the email; if someone else already
    // has it, try again with a short number added instead of asking.
    for (var attempt = 0; attempt < 4; attempt++) {
      final suffix = attempt == 0
          ? ''
          : '${100 + (DateTime.now().microsecondsSinceEpoch + attempt * 37) % 900}';
      message = await authProvider.register(
        _usernameFrom(email, suffix: suffix),
        email,
        _passwordController.text,
        typedPhone,
        fullName: _nameController.text.trim(),
        company: _companyController.text.trim(),
        // Always sent, so the server checks the number properly. A number
        // typed with "+" still wins over the selected country.
        phoneCountry: _country?.iso,
        visitorId: who.visitorId,
        sessionId: who.sessionId,
        geoCountry: where['country'],
        geoCity: where['city'],
      );
      if (message != null) break;
      error = authProvider.errorMessage ?? '';
      if (!error.toLowerCase().contains('username already exists')) break;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (message != null) {
      _showSnackBar(message);
      final uid = authProvider.currentUser?['id'] as int?;
      if (uid != null) AnalyticsService.instance.identify(uid);
      AnalyticsService.instance.track('register');
      _leave();
      return;
    }

    final lower = error.toLowerCase();
    setState(() {
      if (lower.contains('email')) {
        _serverErrors['email'] = lower.contains('already')
            ? 'This email already has an account. Sign in instead.'
            : error;
      } else if (lower.contains('phone')) {
        _serverErrors['phone'] = error;
      } else if (lower.contains('password')) {
        _serverErrors['password'] = error;
      }
    });
    if (_serverErrors.isEmpty) {
      _showSnackBar(
          error.isEmpty ? 'Registration failed. Please try again.' : error,
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // Background Blobs
          _buildBackgroundBlobs(),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header (Back Button)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.chevron_left,
                              color: AppColors.textSecondaryLight),
                          onPressed: _leave,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            // Header Icon
                            _buildHeaderIcon(),
                            const SizedBox(height: AppSpacing.lg),

                            // Register Card
                            _buildRegisterCard(),
                            const SizedBox(height: AppSpacing.lg),

                            // Footer
                            _buildFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundBlobs() {
    return Stack(
      children: [
        // Top Right
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  const Color(0xFF312e81).withValues(alpha: 0.2), // Indigo 900
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        // Bottom Left
        Positioned(
          bottom: -100,
          left: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1e3a8a).withValues(alpha: 0.2), // Blue 900
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderIcon() {
    return Column(
      children: [
        const BrandMark(
          tiled: true,
          tileSize: 80,
          size: 44,
          tileColor: Color(0xFF2C5F6D),
          hoverGlow: true,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Infinity Leads',
          style: AppTypography.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Global lead discovery platform',
          style: AppTypography.bodySmall.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.borderDark,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Fill in your details to get started',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Full name
            _buildLabel('Full name'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('signup-name'),
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'Your name',
                icon: Icons.person_outline_rounded,
              ),
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.length < 2) return 'Please enter your name';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // Email
            _buildLabel('Work email'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('signup-email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearServerError('email'),
              forceErrorText: _serverErrors['email'],
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'you@company.com',
                icon: Icons.mail_outline_rounded,
              ),
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Please enter your email';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) {
                  return 'That email address does not look complete';
                }
                return null;
              },
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'You will sign in with this email.',
                style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondaryLight, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Phone: country + number
            _buildLabel('Phone number'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CountryDialButton(
                  key: const Key('signup-country'),
                  country: _country,
                  background: Colors.white.withValues(alpha: 0.06),
                  border: Colors.white.withValues(alpha: 0.10),
                  foreground: Colors.white,
                  radius: 12,
                  onChanged: (c) => setState(() {
                    _country = c;
                    _countryTouched = true;
                    _serverErrors.remove('phone');
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('signup-phone'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearServerError('phone'),
                    forceErrorText: _serverErrors['phone'],
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      hint: 'Mobile number',
                      icon: Icons.phone_rounded,
                    ),
                    validator: (value) {
                      final raw = (value ?? '').trim();
                      if (raw.isEmpty) return 'Please enter your phone number';
                      if (RegExp(r'[^0-9+()\-\s.]').hasMatch(raw)) {
                        return 'Use digits only';
                      }
                      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.length < 6 || digits.length > 15) {
                        return 'That number does not look complete';
                      }
                      if (!raw.startsWith('+') && _country == null) {
                        return 'Choose your country first';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Company (optional)
            _buildLabel('Company (optional)'),
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('signup-company'),
              controller: _companyController,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'Where you work',
                icon: Icons.business_outlined,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Password (one field with a show/hide toggle; no retyping)
            _buildLabel('Password'),
            const SizedBox(height: 6),
            ValueListenableBuilder<bool>(
              valueListenable: _passwordVisible,
              builder: (context, visible, child) {
                return TextFormField(
                  key: const Key('signup-password'),
                  controller: _passwordController,
                  obscureText: !visible,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => _clearServerError('password'),
                  forceErrorText: _serverErrors['password'],
                  onFieldSubmitted: (_) => _isLoading ? null : _handleRegister(),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    hint: 'At least 8 characters',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      tooltip: visible ? 'Hide password' : 'Show password',
                      icon: Icon(
                        visible
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () => _passwordVisible.value = !visible,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please choose a password';
                    }
                    if (value.length < 8) {
                      return 'Use at least 8 characters';
                    }
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Info Box
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF0c4a6e).withValues(alpha: 0.3), // Sky 900
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: const Color(0xFF075985).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF38bdf8), // Sky 400
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Your account is reviewed before activation. You will receive an email once approved.',
                      style: AppTypography.bodySmall.copyWith(
                        color: const Color(0xFFbae6fd), // Sky 200
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Create Account Button
            Container(
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Create Account',
                            style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.textSecondaryLight,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Same fields as the sign-in page: dark, subtle border, brand focus ring.
  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.white54, size: 20),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: border(Colors.white.withValues(alpha: 0.10)),
      enabledBorder: border(Colors.white.withValues(alpha: 0.10)),
      focusedBorder: border(AppColors.primaryBlue, 2),
      errorBorder: border(AppColors.dangerRed),
      focusedErrorBorder: border(AppColors.dangerRed, 2),
      errorStyle: const TextStyle(color: AppColors.dangerRedLight, fontSize: 12),
    );
  }

  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Already have an account?",
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            TextButton(
              onPressed: _leave,
              child: Text(
                'Sign In',
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Privacy Policy',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/privacy-policy'),
              child: Text(
                'View',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
