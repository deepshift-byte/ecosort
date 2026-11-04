import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/waste_category.dart';
import '../services/detector_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/time_service.dart';
import 'live_scan_screen.dart';
import 'photo_result_screen.dart';
import 'settings_screen.dart';
import 'video_result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenAsk});
  final VoidCallback onOpenAsk;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh countdown every minute.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _photo(ImageSource source) async {
    final file = await _picker.pickImage(source: source, maxWidth: 1920, imageQuality: 92);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoResultScreen(bytes: bytes)));
  }

  Future<void> _video() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (file == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoResultScreen(path: file.path)));
  }

  @override
  Widget build(BuildContext context) {
    final time = context.watch<TimeService>();
    final history = context.watch<HistoryService>();
    final settings = context.watch<SettingsService>();
    final detector = context.watch<DetectorService>();
    final now = time.now();
    final next = TimeService.nextCollection(now.local, settings.collectionWeekday);
    final until = next.difference(now.local);
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${TimeService.greeting(now.local)} 👋', style: theme.textTheme.bodyMedium),
                Text('EcoSort', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
            IconButton.filledTonal(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.tune_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          _Hero(onScan: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveScanScreen()))),
          if (detector.error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Model not loaded'),
                subtitle: Text(detector.error!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _ActionTile(icon: Icons.photo_camera_rounded, label: 'Take photo', color: const Color(0xFF2D9CDB), onTap: () => _photo(ImageSource.camera))),
            const SizedBox(width: 12),
            Expanded(child: _ActionTile(icon: Icons.photo_library_rounded, label: 'Upload photo', color: const Color(0xFF9B51E0), onTap: () => _photo(ImageSource.gallery))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ActionTile(icon: Icons.video_library_rounded, label: 'Upload video', color: const Color(0xFFF2994A), onTap: _video)),
            const SizedBox(width: 12),
            Expanded(child: _ActionTile(icon: Icons.mic_rounded, label: 'Type or speak', color: const Color(0xFFEB5757), onTap: widget.onOpenAsk)),
          ]),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: EcoColors.leaf.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.local_shipping_rounded, color: EcoColors.leaf),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Next collection', style: theme.textTheme.bodySmall),
                    Text(DateFormat('EEEE, d MMM · HH:mm').format(next),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('in ${until.inDays}d ${until.inHours % 24}h ${until.inMinutes % 60}m',
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
                Tooltip(
                  message: time.isVerified ? 'Time verified by ${time.source} (${time.timezone})' : 'Using device clock',
                  child: Icon(
                    time.isVerified ? Icons.verified_rounded : Icons.schedule_rounded,
                    color: time.isVerified ? EcoColors.leaf : theme.disabledColor,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(value: '${history.totalItems}', label: 'Items sorted', icon: Icons.recycling_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _Stat(value: '${history.streak(now)}🔥', label: 'Day streak', icon: Icons.calendar_today_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _Stat(value: '${history.records.length}', label: 'Scans', icon: Icons.center_focus_strong_rounded)),
          ]),
          const SizedBox(height: 20),
          Text('Seven categories', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in WasteCategory.values)
              Chip(
                avatar: CircleAvatar(backgroundColor: c.color, radius: 7),
                label: Text(c.label),
                side: BorderSide(color: c.color.withValues(alpha: 0.5)),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: EcoColors.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: EcoColors.forest.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Point. Detect. Sort.',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Live camera outlines every item in its category colour — fully on-device.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: EcoColors.forest),
              onPressed: onScan,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('Start live scan'),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.recycling_rounded, size: 84, color: Colors.white24),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: t.bodySmall),
        ]),
      ),
    );
  }
}
