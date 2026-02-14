import 'package:flutter/material.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_colors.dart';

/// Workflow progress stepper showing current step in the scraping process
/// Steps: Select Cities → Configure → Search → Results
class WorkflowStepper extends StatelessWidget {
  final int currentStep;
  final List<String> steps;
  final Color activeColor;
  final Color inactiveColor;

  const WorkflowStepper({
    super.key,
    required this.currentStep,
    this.steps = const ['Cities', 'Configure', 'Search', 'Results'],
    this.activeColor = AppColors.primaryBlue,
    this.inactiveColor = Colors.white24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: List.generate(
          steps.length,
          (index) => Expanded(
            child: _buildStep(
              index: index,
              label: steps[index],
              isActive: index <= currentStep,
              isLast: index == steps.length - 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required int index,
    required String label,
    required bool isActive,
    required bool isLast,
  }) {
    final isCurrent = index == currentStep;
    final color = isActive ? activeColor : inactiveColor;

    return Row(
      children: [
        // Step indicator
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCurrent
                    ? activeColor
                    : isActive
                        ? activeColor.withValues(alpha: 0.3)
                        : inactiveColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color,
                  width: isCurrent ? 2 : 1,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: isActive && index < currentStep
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : Text(
                        '${index + 1}',
                        style: AppTypography.labelSmall.copyWith(
                          color: isCurrent || isActive
                              ? Colors.white
                              : Colors.white38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isCurrent
                    ? Colors.white
                    : isActive
                        ? Colors.white70
                        : Colors.white38,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
        // Connector line
        if (!isLast)
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    index < currentStep
                        ? activeColor
                        : inactiveColor,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
