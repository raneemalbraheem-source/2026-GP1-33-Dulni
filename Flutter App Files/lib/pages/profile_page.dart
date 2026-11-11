import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'login_page.dart';
import 'welcome_page.dart';
import '../widgets/app_bottom_navigation.dart';
import 'home_page.dart';
import '../services/logout_helper.dart';
import 'favorite_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static final RegExp _englishPrintableCharacters = RegExp(r'[\x21-\x7E]');

  final _nameFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _loadingProfile = true;
  bool _savingName = false;
  bool _changingPassword = false;
  bool _showPasswordFields = false;
  bool _loggingOut = false;
  bool _deletingAccount = false;
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;
  bool _newPasswordTouched = false;
  bool _confirmPasswordTouched = false;
  String? _email;
  String _savedName = '';

  bool get _nameHasChanged => _nameController.text.trim() != _savedName;

  String? get _confirmPasswordErrorText {
    if (!_confirmPasswordTouched) return null;
    if (_confirmPasswordController.text.isEmpty) {
      return 'يرجى تأكيد كلمة المرور الجديدة.';
    }
    if (_confirmPasswordController.text != _newPasswordController.text) {
      return 'كلمتا المرور غير متطابقتين.';
    }
    return null;
  }

  List<_PasswordRule> get _newPasswordRules {
    final password = _newPasswordController.text;
    return [
      _PasswordRule('8 أحرف على الأقل', password.length >= 8),
      _PasswordRule(
        'حرف إنجليزي كبير واحد على الأقل (A–Z)',
        RegExp(r'[A-Z]').hasMatch(password),
      ),
      _PasswordRule(
        'حرف إنجليزي صغير واحد على الأقل (a–z)',
        RegExp(r'[a-z]').hasMatch(password),
      ),
      _PasswordRule(
        'رقم واحد على الأقل (0–9)',
        RegExp(r'\d').hasMatch(password),
      ),
      _PasswordRule(
        'رمز خاص واحد على الأقل (مثل ! أو @ أو #)',
        RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
      ),
      _PasswordRule(
        'يجب أن تختلف عن كلمة المرور الحالية',
        password.isNotEmpty && password != _currentPasswordController.text,
      ),
    ];
  }

  bool get _newPasswordIsValid =>
      _newPasswordController.text.codeUnits.every(
        (unit) => unit >= 0x21 && unit <= 0x7E,
      ) &&
      _newPasswordRules.every((rule) => rule.isMet);

  Color get _successColor => Theme.of(context).brightness == Brightness.dark
      ? Colors.green.shade300
      : Colors.green.shade800;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _authService.currentUser;
      final name = await _authService.getFullName();
      if (!mounted) return;
      _savedName = (name ?? '').trim();
      _nameController.text = _savedName;
      setState(() {
        _email = user?.email;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _email = _authService.currentUser?.email;
        _loadingProfile = false;
      });
      _showMessage(
        'تعذر تحميل بيانات الملف الشخصي. تحقق من اتصالك ثم أعد المحاولة.',
      );
    }
  }

  Future<void> _saveName() async {
    if (!_nameFormKey.currentState!.validate()) return;
    final updatedName = _nameController.text.trim();
    setState(() => _savingName = true);
    try {
      await _authService.updateFullName(updatedName);
      if (!mounted) return;
      _savedName = updatedName;
      _nameController.text = updatedName;
      _showMessage('تم حفظ الاسم بنجاح.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(_firebaseMessage(error));
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر حفظ الاسم. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _changingPassword = true);
    try {
      await _authService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() {
        _showPasswordFields = false;
        _newPasswordTouched = false;
        _confirmPasswordTouched = false;
        _hideCurrentPassword = true;
        _hideNewPassword = true;
        _hideConfirmPassword = true;
      });
      _showMessage('تم تغيير كلمة المرور بنجاح.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(_firebaseMessage(error));
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر تغيير كلمة المرور. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  void _togglePasswordFields() {
    if (_showPasswordFields) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _newPasswordTouched = false;
      _confirmPasswordTouched = false;
    }
    setState(() {
      _showPasswordFields = !_showPasswordFields;
      _hideCurrentPassword = true;
      _hideNewPassword = true;
      _hideConfirmPassword = true;
    });
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر تسجيل الخروج. يرجى المحاولة مرة أخرى.');
      setState(() => _loggingOut = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final password = await _showDeleteConfirmation();
    if (password == null || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await _authService.deleteAccount(password: password);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم حذف الحساب'),
          content: const Text('تم حذف حسابك وبيانات ملفك الشخصي.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
        (_) => false,
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Account deletion failed: ${error.code}: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      _showMessage(_firebaseMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Account deletion failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      _showMessage('تعذر حذف الحساب. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<String?> _showDeleteConfirmation() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'يرجى إدخال الاسم الكامل.';
    if (name.length < 2 || name.length > 20) {
      return 'يجب أن يتراوح الاسم بين حرفين و20 حرفًا.';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'يرجى إدخال كلمة المرور الجديدة.';
    }
    if (value == _currentPasswordController.text) {
      return 'اختر كلمة مرور تختلف عن كلمة المرور الحالية.';
    }
    if (!_newPasswordIsValid) return 'كلمة المرور لا تحقق جميع الشروط.';
    return null;
  }

  String _firebaseMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'تعذّر حفظ الاسم لأن صلاحيات قاعدة البيانات تمنع ذلك. '
            'تحقق من قواعد Firestore.';
      case 'unauthenticated':
        return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى ثم حاول حفظ الاسم.';
      case 'unavailable':
        return 'قاعدة البيانات غير متاحة حاليًا. تحقق من اتصالك ثم أعد المحاولة.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'كلمة المرور الحالية غير صحيحة.';
      case 'requires-recent-login':
        return 'انتهت صلاحية التحقق. سجّل الدخول مرة أخرى ثم أعد المحاولة.';
      case 'weak-password':
        return 'كلمة المرور لا تستوفي متطلبات الأمان.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال ثم أعد المحاولة.';
      case 'no-current-user':
        return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى.';
      default:
        return 'حدث خطأ أثناء تنفيذ الطلب. يرجى المحاولة مرة أخرى.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _passwordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool hidden,
    required VoidCallback toggle,
    String? Function(String?)? validator,
    String? helperText,
    bool livePasswordValidation = false,
    ValueChanged<String>? onChanged,
    String? forceErrorText,
  }) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = !livePasswordValidation || !_newPasswordTouched
        ? colors.outline
        : _newPasswordIsValid
        ? _successColor
        : colors.error;

    OutlineInputBorder outline(Color color, {double width = 1.2}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextFormField(
      controller: controller,
      obscureText: hidden,
      textDirection: TextDirection.ltr,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: livePasswordValidation
          ? [FilteringTextInputFormatter.allow(_englishPrintableCharacters)]
          : null,
      validator: validator,
      forceErrorText: forceErrorText,
      autovalidateMode: livePasswordValidation
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: const Icon(Icons.lock_outline),
        border: outline(colors.outline),
        enabledBorder: outline(borderColor),
        focusedBorder: outline(borderColor, width: 1.8),
        errorBorder: outline(colors.error),
        focusedErrorBorder: outline(colors.error, width: 1.8),
        suffixIcon: IconButton(
          tooltip: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
          onPressed: toggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }

  Widget _buildNewPasswordRules() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'متطلبات كلمة المرور:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ..._newPasswordRules.map((rule) {
            final color = !_newPasswordTouched
                ? theme.colorScheme.onSurfaceVariant
                : rule.isMet
                ? _successColor
                : theme.colorScheme.error;
            final icon = !_newPasswordTouched
                ? Icons.radio_button_unchecked
                : rule.isMet
                ? Icons.check_circle
                : Icons.cancel_outlined;
            final spokenStatus = !_newPasswordTouched
                ? 'لم يبدأ التحقق بعد'
                : rule.isMet
                ? 'مستوفى'
                : 'غير مستوفى';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: '$spokenStatus: ${rule.label}',
                child: Row(
                  children: [
                    ExcludeSemantics(child: Icon(icon, color: color, size: 17)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy =
        _savingName || _changingPassword || _loggingOut || _deletingAccount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        //appBar: AppBar(title: const Text('الملف الشخصي')),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('الملف الشخصي'),
        ),

        body: SafeArea(
          child: _loadingProfile
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                  absorbing: busy,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'معلومات الحساب',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 20),
                            Form(
                              key: _nameFormKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _nameController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: 'الاسم الكامل',
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    validator: _validateName,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    initialValue: _email ?? '',
                                    readOnly: true,
                                    keyboardType: TextInputType.emailAddress,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                      labelText: 'البريد الإلكتروني',
                                      prefixIcon: Icon(Icons.email_outlined),
                                      helperText:
                                          'لا يمكن تغيير البريد الإلكتروني.',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_nameHasChanged)
                                    FilledButton(
                                      onPressed: _savingName ? null : _saveName,
                                      child: _savingName
                                          ? const CircularProgressIndicator()
                                          : const Text('حفظ الاسم'),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: _togglePasswordFields,
                              icon: Icon(
                                _showPasswordFields
                                    ? Icons.expand_less
                                    : Icons.lock_reset_outlined,
                              ),
                              label: Text(
                                _showPasswordFields
                                    ? 'إلغاء تغيير كلمة المرور'
                                    : 'تغيير كلمة المرور',
                              ),
                            ),
                            if (_showPasswordFields) ...[
                              const SizedBox(height: 16),
                              Text(
                                'استخدم كلمة المرور الحالية للتحقق، ثم أدخل كلمة مرور جديدة.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              Form(
                                key: _passwordFormKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _passwordField(
                                      label: 'كلمة المرور الحالية',
                                      hint: '',
                                      controller: _currentPasswordController,
                                      hidden: _hideCurrentPassword,
                                      toggle: () => setState(
                                        () => _hideCurrentPassword =
                                            !_hideCurrentPassword,
                                      ),
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'يرجى إدخال كلمة المرور الحالية.'
                                          : null,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 16),
                                    _passwordField(
                                      label: 'كلمة المرور الجديدة',
                                      hint: '',
                                      controller: _newPasswordController,
                                      hidden: _hideNewPassword,
                                      toggle: () => setState(
                                        () => _hideNewPassword =
                                            !_hideNewPassword,
                                      ),
                                      validator: _validateNewPassword,
                                      livePasswordValidation: true,
                                      onChanged: (_) => setState(
                                        () => _newPasswordTouched = true,
                                      ),
                                    ),
                                    _buildNewPasswordRules(),
                                    const SizedBox(height: 16),
                                    _passwordField(
                                      label: 'تأكيد كلمة المرور الجديدة',
                                      hint: '',
                                      controller: _confirmPasswordController,
                                      hidden: _hideConfirmPassword,
                                      toggle: () => setState(
                                        () => _hideConfirmPassword =
                                            !_hideConfirmPassword,
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'يرجى تأكيد كلمة المرور الجديدة.';
                                        }
                                        if (value !=
                                            _newPasswordController.text) {
                                          return 'كلمتا المرور غير متطابقتين.';
                                        }
                                        return null;
                                      },
                                      forceErrorText: _confirmPasswordErrorText,
                                      onChanged: (_) => setState(
                                        () => _confirmPasswordTouched = true,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: _changingPassword
                                          ? null
                                          : _changePassword,
                                      child: _changingPassword
                                          ? const CircularProgressIndicator()
                                          : const Text(
                                              'حفظ كلمة المرور الجديدة',
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _loggingOut ? null : _confirmSignOut,
                              icon: const Icon(Icons.logout),
                              label: _loggingOut
                                  ? const CircularProgressIndicator()
                                  : const Text('تسجيل الخروج'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              onPressed: _deletingAccount
                                  ? null
                                  : _confirmDeleteAccount,
                              icon: const Icon(Icons.delete_outline),
                              label: _deletingAccount
                                  ? const CircularProgressIndicator()
                                  : const Text('حذف الحساب'),
                            ),
                            if (busy) ...[
                              const SizedBox(height: 12),
                              const Center(child: CircularProgressIndicator()),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        bottomNavigationBar: AppBottomNavigation(
          currentIndex: 3,
          onTap: (index) {
          if (index == 1) {
         Navigator.pushReplacement(
         context,
         MaterialPageRoute(
        builder: (_) => const HomePage(),
        ),
       );
       }

      else if (index == 2) {
       Navigator.pushReplacement(
       context,
       MaterialPageRoute(
        builder: (_) => const FavoritePage(),
      ),
      );
      }

    else if (index == 0) {
     showLogoutDialog(context);
    }
  },

        ),
      ),
    );
  }
}

class _PasswordRule {
  const _PasswordRule(this.label, this.isMet);

  final String label;
  final bool isMet;
}

/// The dialog owns its controller and disposes it when its widget is removed.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  bool _hidePassword = true;
  bool _closing = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_closing || _passwordController.text.isEmpty) return;
    final password = _passwordController.text;
    setState(() => _closing = true);
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('حذف الحساب نهائيًا؟'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيتم حذف حسابك وبيانات ملفك الشخصي نهائيًا. يرجى إدخال كلمة المرور لتأكيد هويتك.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _hidePassword,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: 'كلمة المرور الحالية',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidePassword
                    ? 'إظهار كلمة المرور'
                    : 'إخفاء كلمة المرور',
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _closing || _passwordController.text.isEmpty
              ? null
              : _confirm,
          child: const Text('حذف الحساب'),
        ),
      ],
    );
  }
}
