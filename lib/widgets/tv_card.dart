import 'package:flutter/material.dart';

/// A focusable, remote-navigable card used in TV-style grid menus.
///
/// Highlights (scale + glow) when either it has real input focus or it is
/// externally marked [selected] (e.g. the parent tracks a `selectedIndex`
/// for DPAD navigation independent of raw focus events).
class TvCard extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFocus;

  const TvCard({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onFocus,
  });

  @override
  State<TvCard> createState() => _TvCardState();
}

class _TvCardState extends State<TvCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final hasFocus = _focused || widget.selected;

    return Semantics(
      button: true,
      label: widget.label,
      selected: hasFocus,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (!mounted) return;
          setState(() => _focused = focused);
          if (focused) widget.onFocus();
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: hasFocus ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: hasFocus ? Colors.teal.shade700 : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasFocus ? Colors.tealAccent : Colors.transparent,
                  width: 3,
                ),
                boxShadow: hasFocus
                    ? [
                  BoxShadow(
                    color: Colors.tealAccent.withOpacity(0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}