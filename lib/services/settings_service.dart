import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SharedPreferences? _p;

  double confidence = 0.35;
  int collectionWeekday = DateTime.monday;
  bool useGpu = false;
  bool showConfidence = true;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    confidence = _p!.getDouble('confidence') ?? confidence;
    collectionWeekday = _p!.getInt('collectionWeekday') ?? collectionWeekday;
    useGpu = _p!.getBool('useGpu') ?? useGpu;
    showConfidence = _p!.getBool('showConfidence') ?? showConfidence;
    notifyListeners();
  }

  Future<void> setConfidence(double v) async {
    confidence = v;
    notifyListeners();
    await _p?.setDouble('confidence', v);
  }

  Future<void> setCollectionWeekday(int v) async {
    collectionWeekday = v;
    notifyListeners();
    await _p?.setInt('collectionWeekday', v);
  }

  Future<void> setUseGpu(bool v) async {
    useGpu = v;
    notifyListeners();
    await _p?.setBool('useGpu', v);
  }

  Future<void> setShowConfidence(bool v) async {
    showConfidence = v;
    notifyListeners();
    await _p?.setBool('showConfidence', v);
  }
}
