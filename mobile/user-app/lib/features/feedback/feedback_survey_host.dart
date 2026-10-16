import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import 'feedback_survey_dialog.dart';
import 'feedback_survey_service.dart';

/// One survey invitation per signed-in visit, using the same completion API as web.
class FeedbackSurveyHost extends StatefulWidget {
  const FeedbackSurveyHost({
    super.key,
    required this.auth,
    required this.router,
    required this.navigatorKey,
    required this.child,
  });

  final AuthController auth;
  final GoRouter router;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<FeedbackSurveyHost> createState() => _FeedbackSurveyHostState();
}

class _FeedbackSurveyHostState extends State<FeedbackSurveyHost>
    with WidgetsBindingObserver {
  final _view = ValueNotifier(
    const FeedbackSurveyView(FeedbackSurveyPhase.closed),
  );
  Timer? _delay;
  Timer? _retry;
  Timer? _poll;
  DateTime? _pollUntil;
  String? _identity;
  Uri? _formUri;
  DialogRoute<void>? _dialog;
  int _epoch = 0;
  int? _checkingEpoch;
  bool _invitationQueued = false;
  bool _due = false;
  bool _presented = false;
  bool _completed = false;
  bool _openedForm = false;
  bool _returningFromForm = false;
  bool _wasPaused = false;
  bool _foreground = true;
  bool _dialogScheduled = false;

  bool get _allowedRoute => !const [
    '/auth',
    '/splash',
  ].contains(widget.router.routeInformationProvider.value.uri.path);

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_syncAccount);
    widget.router.routerDelegate.addListener(_routeChanged);
    _syncAccount();
  }

  void _syncAccount() {
    final userId = widget.auth.user?['userId'] ?? widget.auth.user?['id'];
    final identity = widget.auth.authenticated && userId != null
        ? '$userId:${widget.auth.sessionGeneration}'
        : null;
    if (identity == _identity) return;
    _identity = identity;
    _beginVisit();
  }

  void _beginVisit() {
    ++_epoch;
    _delay?.cancel();
    _retry?.cancel();
    _poll?.cancel();
    _checkingEpoch = null;
    _invitationQueued = false;
    _due = false;
    _presented = false;
    _completed = false;
    _openedForm = false;
    _returningFromForm = false;
    _formUri = null;
    _view.value = const FeedbackSurveyView(FeedbackSurveyPhase.closed);
    _removeDialog();
    if (_identity != null) {
      _delay = Timer(const Duration(minutes: 2), () {
        _due = true;
        _tryInvitation();
      });
    }
  }

  void _routeChanged() {
    if (!_allowedRoute) {
      _view.value = const FeedbackSurveyView(FeedbackSurveyPhase.closed);
      _removeDialog();
      _poll?.cancel();
    } else {
      _tryInvitation();
    }
  }

  void _tryInvitation() {
    if (!mounted ||
        !_foreground ||
        !_allowedRoute ||
        _identity == null ||
        !_due ||
        _presented ||
        _completed) {
      return;
    }
    unawaited(_checkStatus(invite: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (!_foreground) return;
    final returningFromForm = _returningFromForm;
    _returningFromForm = false;
    if (_wasPaused &&
        !returningFromForm &&
        !_completed &&
        _view.value.phase == FeedbackSurveyPhase.closed) {
      _beginVisit();
    }
    _wasPaused = false;
    if (_identity != null && !_completed && (_openedForm || _dialog != null)) {
      unawaited(_checkStatus());
    }
    _tryInvitation();
    if (_view.value.phase != FeedbackSurveyPhase.closed) _showDialog();
  }

  Future<void> _checkStatus({bool invite = false, int attempt = 0}) async {
    if (!mounted || _identity == null || _completed || !_foreground) return;
    if (_checkingEpoch == _epoch) {
      _invitationQueued = _invitationQueued || invite;
      return;
    }
    final epoch = _epoch;
    _checkingEpoch = epoch;
    try {
      final status = await FeedbackSurveyService(
        widget.auth,
      ).getStatus().timeout(const Duration(seconds: 30));
      if (!mounted || epoch != _epoch) return;
      if (status.hasCompleted) {
        _completed = true;
        _delay?.cancel();
        _retry?.cancel();
        _poll?.cancel();
        _formUri = null;
        if (_view.value.phase != FeedbackSurveyPhase.closed) {
          _setPhase(FeedbackSurveyPhase.thanks);
        }
      } else if (!status.enabled || status.formUri == null) {
        _view.value = const FeedbackSurveyView(FeedbackSurveyPhase.closed);
        _removeDialog();
        _poll?.cancel();
      } else {
        _formUri = status.formUri;
        if (invite && !_presented && _foreground && _allowedRoute) {
          _presented = true;
          _setPhase(FeedbackSurveyPhase.invitation);
        }
      }
    } catch (_) {
      // Keep the app usable if the API is unavailable or not deployed yet.
      // Never log the prefilled URL: it contains the signed account token.
      if (mounted && epoch == _epoch && invite && attempt < 2) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 5), () {
          if (mounted && epoch == _epoch && _allowedRoute) {
            unawaited(_checkStatus(invite: true, attempt: attempt + 1));
          }
        });
      }
    } finally {
      if (mounted && epoch == _epoch) {
        _checkingEpoch = null;
        if (_invitationQueued) {
          _invitationQueued = false;
          _tryInvitation();
        }
      }
    }
  }

  void _setPhase(FeedbackSurveyPhase phase) {
    _view.value = FeedbackSurveyView(phase);
    _showDialog();
  }

  void _showDialog() {
    if (_dialog != null || _dialogScheduled || !_foreground || !_allowedRoute) {
      return;
    }
    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogScheduled = false;
      if (!mounted) return;
      final navigator = widget.navigatorKey.currentState;
      final dialogContext = widget.navigatorKey.currentContext;
      if (!mounted ||
          navigator == null ||
          dialogContext == null ||
          _dialog != null ||
          !_foreground ||
          !_allowedRoute ||
          _view.value.phase == FeedbackSurveyPhase.closed) {
        return;
      }
      final epoch = _epoch;
      final route = DialogRoute<void>(
        context: dialogContext,
        barrierDismissible: true,
        barrierLabel: AppStrings.t('survey.close'),
        builder: (_) => AnimatedBuilder(
          animation: Listenable.merge([_view, AppStrings.currentLang]),
          builder: (_, _) => FeedbackSurveyDialog(
            view: _view.value,
            onClose: _dismiss,
            onOpenForm: () => unawaited(_openForm()),
          ),
        ),
      );
      _dialog = route;
      unawaited(
        navigator.push<void>(route).then((_) {
          if (!mounted || epoch != _epoch || _dialog != route) return;
          _dialog = null;
          final phase = _view.value.phase;
          if (!_completed &&
              _allowedRoute &&
              (phase == FeedbackSurveyPhase.invitation ||
                  phase == FeedbackSurveyPhase.waiting)) {
            _setPhase(FeedbackSurveyPhase.plea);
          } else {
            _view.value = const FeedbackSurveyView(FeedbackSurveyPhase.closed);
            _poll?.cancel();
          }
        }),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _dismiss() {
    final route = _dialog;
    if (route != null && route.isCurrent) route.navigator?.pop();
  }

  void _removeDialog() {
    final route = _dialog;
    _dialog = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _openForm() async {
    final uri = _formUri;
    if (uri == null || _view.value.opening || _completed) return;
    final epoch = _epoch;
    final phase = _view.value.phase;
    final previouslyOpened = _openedForm;
    _openedForm = true;
    _returningFromForm = true;
    _view.value = FeedbackSurveyView(phase, opening: true);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* Present a retry action without exposing the account token. */
    }
    if (!mounted || epoch != _epoch || _completed) return;
    if (!opened) {
      _openedForm = previouslyOpened;
      _returningFromForm = false;
      _view.value = FeedbackSurveyView(phase, openFailed: true);
      return;
    }
    if (_view.value.phase != FeedbackSurveyPhase.closed) {
      _setPhase(FeedbackSurveyPhase.waiting);
    }
    _poll?.cancel();
    _pollUntil = DateTime.now().add(const Duration(minutes: 10));
    _poll = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_pollUntil == null ||
          DateTime.now().isAfter(_pollUntil!) ||
          _completed) {
        timer.cancel();
      } else if (_foreground) {
        unawaited(_checkStatus());
      }
    });
  }

  @override
  void dispose() {
    ++_epoch;
    widget.auth.removeListener(_syncAccount);
    widget.router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _delay?.cancel();
    _retry?.cancel();
    _poll?.cancel();
    _removeDialog();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
