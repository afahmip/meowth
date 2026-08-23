import 'package:flutter/material.dart';
import '../models/summary.dart';

/// A segmented bar styled after iOS's "iPhone Storage" indicator: one
/// rounded pill per category, sized proportionally to its percentage.
class StoragePercentageBar extends StatelessWidget {
  final List<CategorySummary> categories;
  final List<Color> colors;
  final String? selectedCategoryKey;

  const StoragePercentageBar({
    super.key,
    required this.categories,
    required this.colors,
    this.selectedCategoryKey,
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
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              flex: (categories[i].percentage * 100).round().clamp(1, 1000000),
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
          ],
        ],
      ),
    );
  }

  String _key(CategorySummary c) => c.categoryId?.toString() ?? 'none';
}
