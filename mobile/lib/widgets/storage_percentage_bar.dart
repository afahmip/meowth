import 'package:flutter/material.dart';
import '../models/summary.dart';

/// A segmented bar styled after iOS's "iPhone Storage" indicator: one
/// rounded pill per category, sized proportionally to its percentage. Each
/// segment is tappable, toggling that category's selection the same way the
/// tags below the bar do.
class StoragePercentageBar extends StatelessWidget {
  final List<CategorySummary> categories;
  final List<Color> colors;
  final String? selectedCategoryKey;
  final ValueChanged<String>? onSelect;

  const StoragePercentageBar({
    super.key,
    required this.categories,
    required this.colors,
    this.selectedCategoryKey,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Container(
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(11),
        ),
      );
    }

    return SizedBox(
      height: 22,
      child: Row(
        // Row's default cross-axis alignment only sizes children to their
        // intrinsic size, and a childless DecoratedBox has none — without
        // stretch every segment collapses to zero height and the bar
        // renders as nothing.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              flex: (categories[i].percentage * 100).round().clamp(1, 1000000),
              child: GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(_key(categories[i])),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: selectedCategoryKey == null ||
                          selectedCategoryKey == _key(categories[i])
                      ? 1
                      : 0.25,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _key(CategorySummary c) => c.categoryId?.toString() ?? 'none';
}
