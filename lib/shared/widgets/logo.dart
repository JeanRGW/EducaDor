import 'package:flutter/material.dart';

import 'app_icons.dart';

/// EducaDor logo lockup using the vector asset exported from Figma
/// (`logo_full.svg`, a white monochrome render so it can be tinted).
class LogoLockup extends StatelessWidget {
  final double size;
  final Color color;
  final bool showText;

  const LogoLockup({
    super.key,
    this.size = 96,
    this.color = Colors.white,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final mark = SvgIcon(AppIcons.logoFull, color: color, size: size);
    final text = showText
        ? Padding(
            padding: EdgeInsets.only(top: size * 0.04),
            child: Text(
              'EducaDOR',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.18,
                letterSpacing: 1.2,
              ),
            ),
          )
        : const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        mark,
        if (showText) text,
      ],
    );
  }
}
