import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Central registry of the app's SVG icon assets.
///
/// The icons were rebuilt as standalone assets to match the Figma mockups.
/// They are monochrome (stroked, outline style) so a single [SvgIcon] renders
/// them with any color via a `srcIn` color filter — the same way Material icons
/// are tinted. This also keeps the design's teal/gray active-inactive states.
abstract class AppIcons {
  AppIcons._();

  // ---- Bottom navigation (glyphs exported from Figma) ----
  static const String grid = 'assets/icons/nav_grid.svg';
  static const String book = 'assets/icons/nav_book.svg';
  static const String reports = 'assets/icons/nav_reports.svg';
  static const String rewards = 'assets/icons/nav_rewards.svg';
  static const String profile = 'assets/icons/nav_profile.svg';
  static const String employees = 'assets/icons/nav_employees.svg';
  static const String companies = 'assets/icons/nav_companies.svg';
  static const String building = 'assets/icons/building.svg';

  // ---- Generic screen icons ----
  static const String search = 'assets/icons/search.svg';
  static const String chevronDown = 'assets/icons/chevron_down.svg';
  static const String chevronRight = 'assets/icons/chevron_right.svg';
  static const String arrowBack = 'assets/icons/arrow_back.svg';
  static const String bell = 'assets/icons/bell.svg';
  static const String logout = 'assets/icons/logout.svg';
  static const String download = 'assets/icons/download.svg';
  static const String calendar = 'assets/icons/calendar.svg';
  static const String lock = 'assets/icons/lock.svg';
  static const String mail = 'assets/icons/mail.svg';
  static const String clock = 'assets/icons/clock.svg';
  static const String check = 'assets/icons/check.svg';
  static const String checkCircle = 'assets/icons/check_circle.svg';
  static const String edit = 'assets/icons/edit.svg';
  static const String gift = 'assets/icons/gift.svg';
  static const String coffee = 'assets/icons/coffee.svg';
  static const String headphones = 'assets/icons/headphones.svg';
  static const String headset = 'assets/icons/headset.svg';
  static const String camera = 'assets/icons/camera.svg';
  static const String eye = 'assets/icons/eye.svg';
  static const String eyeOff = 'assets/icons/eye_off.svg';
  static const String globe = 'assets/icons/globe.svg';
  static const String moon = 'assets/icons/moon.svg';
  static const String help = 'assets/icons/help.svg';
  static const String settings = 'assets/icons/settings.svg';
  static const String shield = 'assets/icons/shield.svg';
  static const String manageAccount = 'assets/icons/manage_account.svg';
  static const String groups = 'assets/icons/groups.svg';
  static const String play = 'assets/icons/play.svg';
  static const String pdf = 'assets/icons/pdf.svg';
  static const String quiz = 'assets/icons/quiz.svg';
  static const String fire = 'assets/icons/fire.svg';
  static const String health = 'assets/icons/health.svg';
  static const String award = 'assets/icons/award.svg';
  static const String trendUp = 'assets/icons/trend_up.svg';
  static const String task = 'assets/icons/task.svg';
  static const String plus = 'assets/icons/plus.svg';
  static const String compose = 'assets/icons/compose.svg';
  static const String briefcase = 'assets/icons/briefcase.svg';
  static const String key = 'assets/icons/key.svg';
  static const String logo = 'assets/icons/logo.svg';
  static const String logoFull = 'assets/icons/logo_full.svg';
}

/// A color-tintable SVG icon.
///
/// Icon assets are monochrome, so [color] is applied via a `srcIn` color fill.
/// When [color] is null the asset is rendered as authored (black strokes).
class SvgIcon extends StatelessWidget {
  final String asset;
  final Color? color;
  final double size;
  final BoxFit fit;

  const SvgIcon(
    this.asset, {
    super.key,
    this.color,
    this.size = 24,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: fit,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

/// Convenience builder that returns a tinted [SvgIcon] for an [AppIcons] asset.
Widget appIcon(String asset, {Color? color, double size = 24}) =>
    SvgIcon(asset, color: color, size: size);
