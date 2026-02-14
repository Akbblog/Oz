import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/api_service.dart';

class LivePaymentsGateScreen extends StatefulWidget {
  final Widget enabledChild;
  final Widget disabledChild;

  const LivePaymentsGateScreen({
    super.key,
    required this.enabledChild,
    required this.disabledChild,
  });

  @override
  State<LivePaymentsGateScreen> createState() => _LivePaymentsGateScreenState();
}

class _LivePaymentsGateScreenState extends State<LivePaymentsGateScreen> {
  final ApiService _apiService = ApiService();
  bool _loading = true;
  bool _enabled = true; // Fail-open to avoid blocking users on transient errors.

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final flags = await _apiService.getFeatureFlags();
      final raw = flags['enable_live_payments'];
      final enabled = raw == true ||
          (raw is String && raw.toLowerCase().trim() == 'true');
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }

    return _enabled ? widget.enabledChild : widget.disabledChild;
  }
}
