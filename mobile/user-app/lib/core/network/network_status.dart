import 'package:flutter/foundation.dart';

class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  bool _unavailable = false;
  bool _checking = false;
  bool _dismissed = false;

  bool get unavailable => _unavailable;
  bool get checking => _checking;
  bool get showFallback => _unavailable && !_dismissed;

  void beginCheck() {
    if (_checking) return;
    _checking = true;
    notifyListeners();
  }

  void markUnavailable() {
    if (!_unavailable) _dismissed = false;
    if (_unavailable && !_checking) return;
    _unavailable = true;
    _checking = false;
    notifyListeners();
  }

  void markAvailable() {
    if (!_unavailable && !_checking && !_dismissed) return;
    _unavailable = false;
    _checking = false;
    _dismissed = false;
    notifyListeners();
  }

  void continueOffline() {
    if (!_unavailable || _dismissed) return;
    _dismissed = true;
    notifyListeners();
  }
}
