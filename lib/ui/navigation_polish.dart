import 'package:flutter/material.dart';
import 'deltiecord_theme.dart';

class NavigationHover extends StatefulWidget {
  const NavigationHover({required this.builder, super.key});
  final Widget Function(bool hovered) builder;
  @override
  State<NavigationHover> createState() => _NavigationHoverState();
}

class _NavigationHoverState extends State<NavigationHover> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: widget.builder(hovered),
  );
}

class MemberRoleBadge extends StatelessWidget {
  const MemberRoleBadge({required this.powerLevel, super.key});
  final int powerLevel;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      powerLevel >= 100 ? 'Admin' : 'Mod',
      style: TextStyle(
        fontSize: 10,
        height: 1.1,
        color: context.deltiecord.muted,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
