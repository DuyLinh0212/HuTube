import 'package:flutter/foundation.dart';

class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();

  static final NetworkStatus instance = NetworkStatus._();

  bool _unavailable = false;
  bool _checking = false;
  bool _dismissed = false;
  int _failedChecks = 0;

  bool get unavailable => _unavailable;
  bool get checking => _checking;
  // A single timeout during app startup is not enough evidence to interrupt
  // the user. Keep retrying in the background and show the banner only after
  // consecutive failed checks.
  bool get showFallback => _unavailable && _failedChecks >= 2 && !_dismissed;

  void beginCheck() {
    if (_checking) return;
    _checking = true;
    notifyListeners();
  }

  void markUnavailable() {
    _failedChecks++;
    if (!_unavailable) _dismissed = false;
    if (_unavailable && !_checking) {
      if (_failedChecks < 2) return;
      notifyListeners();
      return;
    }
    _unavailable = true;
    _checking = false;
    notifyListeners();
  }

  void markAvailable() {
    _failedChecks = 0;
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
