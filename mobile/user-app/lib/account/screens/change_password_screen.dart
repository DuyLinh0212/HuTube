import 'package:flutter/material.dart';
import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/error_banner.dart';
import '../services/account_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final AccountService _accountService;

  bool _busy = false;
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountService = AccountService(widget.auth);
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty) {
      setState(() => _error = AppStrings.t('password.currentRequired'));
      return;
    }
    if (newPass.length < 8) {
      setState(() => _error = AppStrings.t('password.newRequirement'));
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = AppStrings.t('password.mismatch'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _accountService.changePassword(
        currentPassword: current,
        newPassword: newPass,
        confirmPassword: confirm,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.t('password.updated')),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = AppStrings.apiError(e, fallback: 'common.error'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppStrings.t('password.error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('password.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: 16),
              ],

              Text(
                '${AppStrings.t('password.current')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _hideCurrent,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('password.currentHint'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: AppStrings.t(
                      _hideCurrent ? 'auth.showPassword' : 'auth.hidePassword',
                    ),
                    onPressed: () =>
                        setState(() => _hideCurrent = !_hideCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('password.new')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _hideNew,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('password.newHint'),
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: AppStrings.t(
                      _hideNew ? 'auth.showPassword' : 'auth.hidePassword',
                    ),
                    onPressed: () => setState(() => _hideNew = !_hideNew),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '${AppStrings.t('password.confirm')} *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _hideConfirm,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: AppStrings.t('password.confirmHint'),
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hideConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: AppStrings.t(
                      _hideConfirm ? 'auth.showPassword' : 'auth.hidePassword',
                    ),
                    onPressed: () =>
                        setState(() => _hideConfirm = !_hideConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(AppStrings.t('password.updateBtn')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
