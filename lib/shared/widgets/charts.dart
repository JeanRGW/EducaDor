import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Lightweight line chart drawn with [CustomPaint] — no chart dependency.
class LineChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final double height;
  final List<MapEntry<String, double>>? secondaryData;

  const LineChart(
    this.data, {
    super.key,
    this.height = 140,
    this.secondaryData,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _LinePainter(data, secondaryData),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<MapEntry<String, double>> data;
  final List<MapEntry<String, double>>? secondaryData;
  _LinePainter(this.data, this.secondaryData);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final leftPad = 4.0, rightPad = 4.0, topPad = 12.0, bottomPad = 22.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    Offset point(int i) {
      final x = leftPad + chartW * (i / (data.length - 1));
      final y = topPad + chartH * (1 - data[i].value);
      return Offset(x, y);
    }

    // Line
    final line = Path();
    for (var i = 0; i < data.length; i++) {
      final p = point(i);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.chartBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final secondary = secondaryData;
    if (secondary != null && secondary.length == data.length) {
      final path = Path();
      for (var i = 0; i < secondary.length; i++) {
        final x = leftPad + chartW * (i / (secondary.length - 1));
        final y = topPad + chartH * (1 - secondary[i].value);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.accentTeal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Labels
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (var i = 0; i < data.length; i++) {
      tp.text = TextSpan(
        text: data[i].key,
        style: const TextStyle(
          fontFamily: AppFonts.inter,
          color: AppColors.textMuted,
          fontSize: 10,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(point(i).dx - tp.width / 2, topPad + chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.data != data || old.secondaryData != secondaryData;
}

/// Vertical bar chart.
class BarChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final double height;
  final Color color;

  const BarChart(
    this.data, {
    super.key,
    this.height = 140,
    this.color = AppColors.chartBlue,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < data.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: (height - 22) * data[i].value,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      data[i].key,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != data.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Donut chart for a percentage.
class DonutChart extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  const DonutChart(
    this.value, {
    super.key,
    this.size = 96,
    this.strokeWidth = 10,
    this.color = AppColors.primary,
    this.trackColor = AppColors.chipBg,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(value, strokeWidth, color, trackColor),
        child: Center(
          child: Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              fontFamily: AppFonts.outfit,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double value;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  _DonutPainter(this.value, this.strokeWidth, this.color, this.trackColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.28318 * value.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.value != value ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// A row label with a value and a horizontal bar (used in reports).
class ReportBarRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool compact;
  final Color? valueColor;

  const ReportBarRow(
    this.label,
    this.value, {
    super.key,
    this.color = AppColors.chartBlue,
    this.compact = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.inter,
                    fontSize: compact ? 12 : 14,
                    fontWeight: compact ? FontWeight.w400 : FontWeight.w600,
                    color: compact ? const Color(0xFF475569) : null,
                  ),
                ),
              ),
              Text(
                '${value.round()}%',
                style: TextStyle(
                  fontFamily: AppFonts.inter,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: compact ? 8 : 9,
              backgroundColor: compact
                  ? AppColors.background
                  : AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
