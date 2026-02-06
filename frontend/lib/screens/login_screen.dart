import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../core/theme/app_theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordVisible = ValueNotifier<bool>(false);
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _inlineError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadLoginPrefs();
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

    _usernameController.addListener(_clearInlineError);
    _passwordController.addListener(_clearInlineError);
  }

  Future<void> _loadLoginPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUsername = prefs.getString('last_username');
      final rememberMe = prefs.getBool('remember_me');
      if (!mounted) return;
      setState(() {
        if (lastUsername != null && lastUsername.trim().isNotEmpty) {
          _usernameController.text = lastUsername;
        }
        _rememberMe = rememberMe ?? true;
      });
    } catch (_) {
      // Ignore preference load failures.
    }
  }

  Future<void> _saveLoginPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_username', _usernameController.text.trim());
      await prefs.setBool('remember_me', _rememberMe);
    } catch (_) {
      // Ignore preference save failures.
    }
  }

  void _clearInlineError() {
    if (_inlineError == null) return;
    setState(() => _inlineError = null);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.removeListener(_clearInlineError);
    _passwordController.removeListener(_clearInlineError);
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordVisible.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearError();
    setState(() => _inlineError = null);
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
      rememberMe: _rememberMe,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (success && mounted) {
      _saveLoginPrefs();
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (mounted) {
      final message = authProvider.errorMessage ??
          'Login failed. Please check your credentials.';
      setState(() => _inlineError = message);
      _showErrorSnackBar(message);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.dangerRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        margin: AppSpacing.paddingMd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      body: Stack(
        children: [
          // Background Blobs
          _buildBackgroundBlobs(),

          // Main Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo Section
                        _buildLogoSection(),
                        const SizedBox(height: AppSpacing.xl),

                        // Login Card
                        _buildLoginCard(),
                        const SizedBox(height: AppSpacing.lg),

                        // Footer
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundBlobs() {
    return Stack(
      children: [
        // Top Right Blob
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF334155)
                      .withValues(alpha: 0.2), // Slate 700
                  blurRadius: 120,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
        // Bottom Left Blob
        Positioned(
          bottom: -100,
          left: -100,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1e293b)
                      .withValues(alpha: 0.3), // Slate 800
                  blurRadius: 120,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
        // Middle Blob
        Positioned(
          top: MediaQuery.of(context).size.height * 0.4,
          left: -50,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF312e81)
                      .withValues(alpha: 0.1), // Indigo 900
                  blurRadius: 80,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF6366f1),
                Color(0xFF9333ea)
              ], // Indigo to Purple
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366f1).withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.all_inclusive_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
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
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
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
              'Welcome Back',
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to continue lead discovery',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Username
            _buildLabel('Username'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _usernameController,
              style: const TextStyle(color: AppColors.textPrimaryLight),
              decoration: _inputDecoration(
                hint: 'Enter your username',
                icon: Icons.person_outline_rounded,
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Please enter your username' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // Password
            _buildLabel('Password'),
            const SizedBox(height: 6),
            ValueListenableBuilder<bool>(
              valueListenable: _passwordVisible,
              builder: (context, visible, child) {
                return TextFormField(
                  controller: _passwordController,
                  obscureText: !visible,
                  style: const TextStyle(color: AppColors.textPrimaryLight),
                  decoration: _inputDecoration(
                    hint: 'Enter your password',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondaryLight,
                        size: 20,
                      ),
                      onPressed: () => _passwordVisible.value = !visible,
                    ),
                  ),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter your password'
                      : null,
                );
              },
            ),

            if (_inlineError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.dangerRed.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(
                    color: AppColors.dangerRed.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.dangerRed,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _inlineError!,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() => _rememberMe = value ?? true);
                    },
                    activeColor: AppColors.primaryBlue,
                    checkColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Text(
                      'Remember me for 30 days',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Forgot Password
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/forgot-password');
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot Password?',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Login Button
            Container(
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
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
                          const Icon(Icons.login_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Sign In',
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

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF94a3b8), size: 20),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        borderSide: const BorderSide(color: AppColors.dangerRed, width: 1),
      ),
    );
  }

  Widget _buildFooter() {
    return Flexible(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              "Don't have an account?",
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
            child: Text(
              'Sign Up',
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
