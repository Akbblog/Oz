import 'package:flutter/material.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_colors.dart';

/// Animated workflow progress stepper.
/// Steps: Cities → Configure → Search → Results
class WorkflowStepper extends StatefulWidget {
  final int currentStep;
  final List<String> steps;
  final Color activeColor;
  final Color inactiveColor;

  /// Optional explicit progress value (0.0–1.0).
  /// When null, progress is derived from [currentStep] / [steps.length].
  final double? progress;

  const WorkflowStepper({
    super.key,
    required this.currentStep,
    this.steps = const ['Cities', 'Configure', 'Search', 'Results'],
    this.activeColor = AppColors.brandPurple,
    this.inactiveColor = Colors.white12,
    this.progress,
  });

  @override
  State<WorkflowStepper> createState() => _WorkflowStepperState();
}

class _WorkflowStepperState extends State<WorkflowStepper>
    with TickerProviderStateMixin {
  // Per-step entrance animations
  late List<AnimationController> _stepControllers;
  late List<Animation<double>> _stepScaleAnims;
  late List<Animation<double>> _stepFadeAnims;

  // Pulse ring on active step
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Progress bar fill
  late AnimationController _progressController;
  late Animation<double> _progressAnim;

  // Connector fill per segment
  late List<AnimationController> _connectorControllers;
  late List<Animation<double>> _connectorAnims;

  int _previousStep = -1;

  @override
  void initState() {
    super.initState();
    _previousStep = widget.currentStep;
    _initStepAnimations();
    _initPulse();
    _initProgress();
    _initConnectors();
    _playEntranceAnimations();
  }

  void _initStepAnimations() {
    _stepControllers = List.generate(
      widget.steps.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 350 + i * 80),
      ),
    );
    _stepScaleAnims = _stepControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutBack))
        .map((a) => Tween<double>(begin: 0.4, end: 1.0).animate(a))
        .toList();
    _stepFadeAnims = _stepControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .map((a) => Tween<double>(begin: 0.0, end: 1.0).animate(a))
        .toList();
  }

  void _initPulse() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _initProgress() {
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _progressAnim = Tween<double>(
      begin: 0.0,
      end: _targetProgress,
    ).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
    _progressController.forward();
  }

  void _initConnectors() {
    final segmentCount = widget.steps.length - 1;
    _connectorControllers = List.generate(
      segmentCount,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );
    _connectorAnims = _connectorControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeInOut))
        .map((a) => Tween<double>(begin: 0.0, end: 1.0).animate(a))
        .toList();
    // Fill connectors that are already complete
    for (int i = 0; i < segmentCount; i++) {
      if (i < widget.currentStep) {
        _connectorControllers[i].value = 1.0;
      }
    }
  }

  double get _targetProgress {
    if (widget.progress != null) return widget.progress!.clamp(0.0, 1.0);
    if (widget.steps.isEmpty) return 0.0;
    return widget.currentStep / (widget.steps.length - 1);
  }

  void _playEntranceAnimations() {
    for (int i = 0; i < _stepControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (mounted) _stepControllers[i].forward();
      });
    }
  }

  @override
  void didUpdateWidget(WorkflowStepper old) {
    super.didUpdateWidget(old);
    if (old.currentStep != widget.currentStep ||
        old.progress != widget.progress) {
      // Animate progress bar to new target
      _progressAnim = Tween<double>(
        begin: _progressAnim.value,
        end: _targetProgress,
      ).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
      );
      _progressController
        ..reset()
        ..forward();

      // Animate newly completed connector
      final step = widget.currentStep;
      if (step > _previousStep) {
        for (int i = _previousStep; i < step && i < _connectorAnims.length; i++) {
          _connectorControllers[i]
            ..reset()
            ..forward();
        }
      } else if (step < _previousStep) {
        for (int i = step; i < _previousStep && i < _connectorAnims.length; i++) {
          _connectorControllers[i].reset();
          _connectorControllers[i].value = 0.0;
        }
      }

      // Bounce newly active step
      if (step < _stepControllers.length) {
        _stepControllers[step]
          ..reset()
          ..forward();
      }

      _previousStep = step;
    }
  }

  @override
  void dispose() {
    for (final c in _stepControllers) {
      c.dispose();
    }
    for (final c in _connectorControllers) {
      c.dispose();
    }
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Step row ──────────────────────────────────────────────────
          SizedBox(
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildStepRowChildren(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // ── Progress bar ──────────────────────────────────────────────
          _AnimatedProgressBar(
            animation: _progressAnim,
            activeColor: widget.activeColor,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStepRowChildren() {
    final children = <Widget>[];
    for (int i = 0; i < widget.steps.length; i++) {
      final isCompleted = i < widget.currentStep;
      final isCurrent = i == widget.currentStep;

      children.add(
        FadeTransition(
          opacity: _stepFadeAnims[i],
          child: ScaleTransition(
            scale: _stepScaleAnims[i],
            child: _StepDot(
              index: i,
              label: widget.steps[i],
              isCompleted: isCompleted,
              isCurrent: isCurrent,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
              pulseAnim: isCurrent ? _pulseAnim : null,
            ),
          ),
        ),
      );

      // Connector between steps
      if (i < widget.steps.length - 1) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: _AnimatedConnector(
                fillAnimation: _connectorAnims[i],
                activeColor: widget.activeColor,
                inactiveColor: widget.inactiveColor,
                isFull: isCompleted,
              ),
            ),
          ),
        );
      }
    }
    return children;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single step dot + label
// ─────────────────────────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final int index;
  final String label;
  final bool isCompleted;
  final bool isCurrent;
  final Color activeColor;
  final Color inactiveColor;
  final Animation<double>? pulseAnim;

  const _StepDot({
    required this.index,
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
    required this.activeColor,
    required this.inactiveColor,
    this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring (active step only)
              if (isCurrent && pulseAnim != null)
                AnimatedBuilder(
                  animation: pulseAnim!,
                  builder: (_, __) {
                    final t = pulseAnim!.value;
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: activeColor.withValues(alpha: 0.35 * (1 - t)),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              // Completed glow ring
              if (isCompleted)
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: activeColor.withValues(alpha: 0.18),
                      width: 6,
                    ),
                  ),
                ),
              // Main dot
              Container(
                width: isCurrent ? 34 : 30,
                height: isCurrent ? 34 : 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? activeColor.withValues(alpha: 0.15)
                      : isCurrent
                          ? activeColor
                          : inactiveColor,
                  border: Border.all(
                    color: isCompleted || isCurrent
                        ? activeColor
                        : Colors.white24,
                    width: isCurrent ? 2.5 : 1.5,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.45),
                            blurRadius: 16,
                            spreadRadius: -2,
                          ),
                        ]
                      : isCompleted
                          ? [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: -4,
                              ),
                            ]
                          : null,
                ),
                child: Center(
                  child: isCompleted
                      ? Icon(Icons.check_rounded,
                          size: 15, color: activeColor)
                      : Text(
                          '${index + 1}',
                          style: AppTypography.labelSmall.copyWith(
                            color: isCurrent
                                ? Colors.white
                                : Colors.white38,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isCurrent
                ? Colors.white
                : isCompleted
                    ? Colors.white60
                    : Colors.white30,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            fontSize: 10,
            letterSpacing: isCurrent ? 0.4 : 0.0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated connector line between steps
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedConnector extends StatelessWidget {
  final Animation<double> fillAnimation;
  final Color activeColor;
  final Color inactiveColor;
  final bool isFull;

  const _AnimatedConnector({
    required this.fillAnimation,
    required this.activeColor,
    required this.inactiveColor,
    required this.isFull,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;
      return SizedBox(
        height: 2,
        child: Stack(
          children: [
            // Track
            Container(
              width: totalWidth,
              height: 2,
              decoration: BoxDecoration(
                color: inactiveColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            // Fill
            AnimatedBuilder(
              animation: fillAnimation,
              builder: (_, __) {
                final pct = isFull ? 1.0 : fillAnimation.value;
                return Container(
                  width: totalWidth * pct,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        activeColor.withValues(alpha: 0.7),
                        activeColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: pct > 0.05
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                            )
                          ]
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated bottom progress bar
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedProgressBar extends StatelessWidget {
  final Animation<double> animation;
  final Color activeColor;

  const _AnimatedProgressBar({
    required this.animation,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final pct = animation.value;
        final label = '${(pct * 100).round()}%';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: pct > 0
                      ? activeColor
                      : Colors.white30,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  // Track
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Fill
                  FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            activeColor.withValues(alpha: 0.6),
                            activeColor,
                            activeColor.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: pct > 0.02
                            ? [
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                  spreadRadius: -1,
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                  // Shimmer sweep
                  if (pct > 0.02 && pct < 1.0)
                    _ShimmerSweep(
                      activeColor: activeColor,
                      progress: pct,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer sweep overlay on the progress bar
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerSweep extends StatefulWidget {
  final Color activeColor;
  final double progress;

  const _ShimmerSweep({required this.activeColor, required this.progress});

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final fillWidth = box.maxWidth * widget.progress;
      return AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final sweepX = _anim.value * (fillWidth + 40) - 20;
          return ClipRect(
            child: SizedBox(
              width: fillWidth,
              height: 4,
              child: Transform.translate(
                offset: Offset(sweepX, 0),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
