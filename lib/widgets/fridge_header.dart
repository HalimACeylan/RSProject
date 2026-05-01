import 'package:flutter/material.dart';

class FridgeHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? superTitle;
  final Widget? trailing;
  final bool centerTitle;

  const FridgeHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.superTitle,
    this.trailing,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: centerTitle
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (superTitle != null) ...[
                  Text(
                    superTitle!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF13EC13),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102210),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (centerTitle && trailing == null)
            const SizedBox(
              width: 48,
            ), // Balance for back button if needed, but here simple
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}
