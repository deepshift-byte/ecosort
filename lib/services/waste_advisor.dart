import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/waste_category.dart';

class WasteItemInfo {
  WasteItemInfo({
    required this.name,
    required this.aliases,
    required this.category,
    required this.handling,
    required this.where,
  });

  final String name;
  final List<String> aliases;
  final WasteCategory category;
  final String handling;
  final String where;
}

class AdviceMatch {
  AdviceMatch(this.item, this.matchedText, this.score);
  final WasteItemInfo item;
  final String matchedText;
  final double score;
}

/// Answers free-text (typed or spoken) descriptions such as
/// "an old phone charger and some banana peels" fully offline, using the
/// bundled knowledge base `assets/data/waste_knowledge.json`.
class WasteAdvisor {
  WasteAdvisor(this.items);

  final List<WasteItemInfo> items;

  static const asset = 'assets/data/waste_knowledge.json';

  static Future<WasteAdvisor> load() async =>
      WasteAdvisor.fromJson(await rootBundle.loadString(asset));

  factory WasteAdvisor.fromJson(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final list = <WasteItemInfo>[];
    for (final e in j['items'] as List) {
      final m = e as Map<String, dynamic>;
      final cat = WasteCategory.fromId(m['category'] as String);
      if (cat == null) continue;
      list.add(WasteItemInfo(
        name: m['name'] as String,
        aliases: (m['aliases'] as List).cast<String>(),
        category: cat,
        handling: m['handling'] as String,
        where: m['where'] as String,
      ));
    }
    return WasteAdvisor(list);
  }

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _stem(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && (w.endsWith('ches') || w.endsWith('shes') || w.endsWith('xes'))) {
      return w.substring(0, w.length - 2);
    }
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static List<String> _tokens(String s) =>
      normalize(s).split(' ').where((w) => w.isNotEmpty).map(_stem).toList();

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static bool _wordMatch(String q, String k) {
    if (q == k) return true;
    // Tolerate typos and speech-recognition slips on longer words.
    if (k.length >= 5 && q.length >= 4) return _lev(q, k) <= (k.length >= 8 ? 2 : 1);
    return false;
  }

  /// Returns matching items, best first. Multiple distinct items in one
  /// description are all returned.
  List<AdviceMatch> ask(String query, {int limit = 5}) {
    final q = _tokens(query);
    if (q.isEmpty) return const [];
    final results = <AdviceMatch>[];
    for (final item in items) {
      AdviceMatch? best;
      for (final phrase in [item.name, ...item.aliases]) {
        final p = _tokens(phrase);
        if (p.isEmpty || p.length > q.length) continue;
        // Find the phrase as a contiguous (fuzzy) run of query words.
        for (var s = 0; s + p.length <= q.length; s++) {
          var ok = true;
          var exact = 0;
          for (var k = 0; k < p.length; k++) {
            if (!_wordMatch(q[s + k], p[k])) {
              ok = false;
              break;
            }
            if (q[s + k] == p[k]) exact++;
          }
          if (!ok) continue;
          // Longer phrases and exact spellings score higher.
          final score = p.length * 2.0 + exact / p.length;
          if (best == null || score > best.score) {
            best = AdviceMatch(item, phrase, score);
          }
        }
      }
      if (best != null) results.add(best);
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    // Drop weaker matches that are subsumed by a stronger one
    // (e.g. "glass" when "glass bottle" matched).
    final kept = <AdviceMatch>[];
    for (final r in results) {
      final words = _tokens(r.matchedText).toSet();
      final subsumed = kept.any((k) {
        final kw = _tokens(k.matchedText).toSet();
        return k.score > r.score && kw.containsAll(words);
      });
      if (!subsumed) kept.add(r);
      if (kept.length >= limit) break;
    }
    return kept;
  }

  /// Fallback when no item matched: guess a category from keywords.
  WasteCategory? guessCategory(String query) {
    final q = _tokens(query).toSet();
    const hints = {
      WasteCategory.hazardous: ['toxic', 'poison', 'chemical', 'flammable', 'corrosive', 'mercury', 'battery'],
      WasteCategory.ewaste: ['electronic', 'electric', 'device', 'gadget', 'circuit', 'plug', 'digital'],
      WasteCategory.plastic: ['plastic', 'pet', 'nylon', 'polythene', 'pvc'],
      WasteCategory.paper: ['paper', 'cardboard', 'carton'],
      WasteCategory.glass: ['glass'],
      WasteCategory.metal: ['metal', 'steel', 'iron', 'aluminium', 'aluminum', 'tin', 'copper'],
      WasteCategory.organic: ['food', 'peel', 'leaf', 'compost', 'rotten', 'organic', 'fruit', 'vegetable'],
    };
    for (final e in hints.entries) {
      if (e.value.any((h) => q.contains(_stem(h)))) return e.key;
    }
    return null;
  }
}
