import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/app_icons.dart';

class OrderControls extends StatelessWidget {
  final VoidCallback? onUp, onDown;
  final String label;
  const OrderControls({super.key, required this.label, this.onUp, this.onDown});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Mover $label para cima',
        onPressed: onUp,
        icon: RotatedBox(
          quarterTurns: 2,
          child: SvgIcon(
            AppIcons.chevronDown,
            size: 18,
            color: onUp == null
                ? Theme.of(context).colorScheme.outline
                : context.successForeground,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Mover $label para baixo',
        onPressed: onDown,
        icon: SvgIcon(
          AppIcons.chevronDown,
          size: 18,
          color: onDown == null
              ? Theme.of(context).colorScheme.outline
              : context.successForeground,
        ),
      ),
    ],
  );
}
