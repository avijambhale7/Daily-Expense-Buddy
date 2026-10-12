import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// Brand logo. Uses the bundled raster asset and falls back to a vector icon
/// if the asset is missing, so branding never blocks the UI.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.showName = false});

  final double size;
  final bool showName;

  static const markAsset = 'assets/branding/logo_mark.png';

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      markAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Daily Expense Buddy logo',
      errorBuilder: (context, _, _) => Icon(
        Icons.account_balance_wallet_rounded,
        size: size * 0.9,
        color: context.colors.primary,
      ),
    );
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Flexible(child: AppWordmark(fontSize: size * 0.36)),
      ],
    );
  }
}

/// "Daily Expense Buddy" wordmark rendered as themed text.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.fontSize = 18, this.textAlign});

  final double fontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = context.text.titleLarge!.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Daily Expense ', style: base),
          TextSpan(
            text: 'Buddy',
            style: base.copyWith(color: context.appColors.success),
          ),
        ],
      ),
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
