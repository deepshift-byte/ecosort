import 'package:flutter/material.dart';

import '../models/waste_category.dart';
import '../widgets/common.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text('Sorting guide', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Each colour matches the outline you see in the scanner.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (final c in WasteCategory.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showCategorySheet(context, c),
                child: Row(children: [
                  Container(
                    width: 84,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.color, c.color.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(c.icon, color: Colors.white, size: 38),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(c.examples.join(' · '), style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.chevron_right_rounded)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
