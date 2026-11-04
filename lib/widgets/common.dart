import 'package:flutter/material.dart';

import '../models/waste_category.dart';

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.count, this.compact = false});

  final WasteCategory category;
  final int? count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = category.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 7),
      decoration: BoxDecoration(
        color: category.color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(category.icon, size: compact ? 14 : 16, color: fg),
        const SizedBox(width: 5),
        Text(
          count == null ? category.label : '${category.label} · $count',
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 13),
        ),
      ]),
    );
  }
}

/// Horizontal bars showing how many items of each category were found.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown(this.counts, {super.key});

  final Map<WasteCategory, int> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No waste items detected.'),
      );
    }
    return Column(children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: e.key.color.withValues(alpha: 0.18),
              child: Icon(e.key.icon, size: 18, color: e.key.color),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 82,
              child: Text(e.key.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: e.value / total,
                  minHeight: 10,
                  color: e.key.color,
                  backgroundColor: e.key.color.withValues(alpha: 0.12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

/// Bottom sheet with tips for one category.
Future<void> showCategorySheet(BuildContext context, WasteCategory c, {String? itemLabel}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: c.color,
              child: Icon(c.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (itemLabel != null)
                  Text('Detected: $itemLabel', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          for (final t in c.tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle_rounded, size: 18, color: c.color),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ]),
            ),
          const SizedBox(height: 10),
          Text('Always check your local council rules.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
