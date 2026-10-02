import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';

void leaveManagementPage(
  BuildContext context,
  String fallbackLocation, {
  Object? result,
}) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
    return;
  }
  context.go(fallbackLocation);
}

class ManagementPage extends StatelessWidget {
  final String title;
  final Widget child;
  final bool busy;
  final String fallbackLocation;
  const ManagementPage({
    super.key,
    required this.title,
    required this.child,
    required this.fallbackLocation,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminStyles.formTheme(Theme.of(context)),
    child: PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: busy
                ? null
                : () => leaveManagementPage(context, fallbackLocation),
            icon: const SvgIcon(
              AppIcons.arrowBack,
              size: 20,
              color: AppColors.successDarkGreen,
            ),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class ManagementField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool requiredValue;
  final int maxLength;
  final int lines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool labelAbove;
  const ManagementField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.requiredValue = false,
    this.maxLength = 200,
    this.lines = 1,
    this.keyboardType,
    this.validator,
    this.labelAbove = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelAbove) ...[
          Text(label, style: AdminStyles.fieldLabel),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          enabled: enabled,
          minLines: lines,
          maxLines: lines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: labelAbove ? null : label,
            counterText: '',
            hintText: labelAbove ? label : null,
          ),
          validator:
              validator ??
              (value) =>
                  requiredValue && (value == null || value.trim().isEmpty)
                  ? 'Informe $label.'
                  : null,
        ),
      ],
    ),
  );
}

class ManagementSelector extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  final VoidCallback? onPressed;
  const ManagementSelector({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AdminStyles.fieldLabel),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            foregroundColor: AppColors.successDarkGreen,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            children: [
              SvgIcon(
                icon,
                size: 18,
                color: onPressed == null
                    ? AppColors.textMuted
                    : AppColors.successDarkGreen,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(value, style: AdminStyles.fieldText)),
              const SizedBox(width: 8),
              const SvgIcon(
                AppIcons.chevronDown,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Future<bool> confirmManagementAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void showManagementMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

String managementError(Object error, String fallback) =>
    error is ManagementException ? error.message : fallback;
