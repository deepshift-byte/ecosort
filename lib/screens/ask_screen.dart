import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/waste_category.dart';
import '../services/waste_advisor.dart';
import '../widgets/common.dart';

/// Describe trash by typing or speaking; get category, handling and bin.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _controller = TextEditingController();
  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _query = '';
  List<AdviceMatch> _matches = [];

  static const _examples = [
    'Old phone charger',
    'Banana peels and a soda can',
    'Used AA batteries',
    'Greasy pizza box',
    'Broken light bulb',
    'Plastic water bottle',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    super.dispose();
  }

  void _ask(String q) {
    final advisor = context.read<WasteAdvisor>();
    setState(() {
      _query = q;
      _matches = advisor.ask(q);
    });
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (r) {
        _controller.text = r.recognizedWords;
        _ask(r.recognizedWords);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final advisor = context.read<WasteAdvisor>();
    final guess = _matches.isEmpty && _query.isNotEmpty ? advisor.guessCategory(_query) : null;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text('Ask EcoSort', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Type or say what you want to throw away.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _ask,
              onChanged: (v) => v.length > 2 ? _ask(v) : null,
              decoration: InputDecoration(
                hintText: 'e.g. "empty paint tin and old newspapers"',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _ask('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _listening
                  ? [BoxShadow(color: WasteCategory.hazardous.color.withValues(alpha: 0.5), blurRadius: 18, spreadRadius: 3)]
                  : null,
            ),
            child: IconButton.filled(
              iconSize: 28,
              style: IconButton.styleFrom(
                backgroundColor: _listening ? WasteCategory.hazardous.color : theme.colorScheme.primary,
                padding: const EdgeInsets.all(14),
              ),
              onPressed: _toggleMic,
              icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            ),
          ),
        ]),
        if (_listening)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Listening… describe your trash', style: TextStyle(color: WasteCategory.hazardous.color)),
          ),
        const SizedBox(height: 14),
        if (_query.isEmpty) ...[
          Text('Try:', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e),
                onPressed: () {
                  _controller.text = e;
                  _ask(e);
                },
              ),
          ]),
        ],
        for (final m in _matches) _AdviceCard(m.item),
        if (_query.isNotEmpty && _matches.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: guess == null
                  ? const Text("I don't know that item yet. Try describing the material "
                      '(plastic, glass, metal, paper, food, electronic, chemical…) or scan it with the camera.')
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Probably:', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      CategoryBadge(guess),
                      const SizedBox(height: 10),
                      for (final t in guess.tips) Text('• $t'),
                    ]),
            ),
          ),
      ]),
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard(this.item);
  final WasteItemInfo item;

  @override
  Widget build(BuildContext context) {
    final c = item.category;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c.color, width: 6))),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_cap(item.name), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              CategoryBadge(c, compact: true),
            ]),
            const SizedBox(height: 12),
            _row(Icons.back_hand_rounded, 'How to handle', item.handling, c.color),
            const SizedBox(height: 10),
            _row(Icons.delete_outline_rounded, 'Where to put it', item.where, c.color),
          ]),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String body, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              Text(body),
            ]),
          ),
        ],
      );

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
