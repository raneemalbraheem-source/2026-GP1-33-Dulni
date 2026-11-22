import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'home_page.dart';
import '../services/logout_helper.dart';
import 'favorite_page.dart';
import 'voice_preferences_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _authService = AuthService();

  bool _loadingProfile = true;
  bool _savingName = false;
  bool _loggingOut = false;
  bool _deletingAccount = false;
  String? _email;
  String _savedName = '';

  bool get _nameHasChanged => _nameController.text.trim() != _savedName;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
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
    final shouldDelete = await _showDeleteConfirmation();
    if (shouldDelete != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await _authService.sendAccountDeletionLink();
      if (!mounted) return;
      _showMessage(
        'أرسلنا رابط تأكيد حذف الحساب إلى بريدك الإلكتروني. افتحيه على هذا الجهاز لإكمال الحذف.',
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(_firebaseMessage(error));
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر إرسال رابط الحذف. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<bool?> _showDeleteConfirmation() {
    return showDialog<bool>(
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _savingName || _loggingOut || _deletingAccount;

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
                            const SizedBox(height: 24),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.record_voice_over),
                                title: const Text('تفضيلات الصوت'),
                                subtitle: const Text(
                                  'اختيار الصوت وضبط سرعة التحدث',
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const VoicePreferencesPage(),
                                  ),
                                ),
                              ),
                            ),
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

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('حذف الحساب؟'),
      content: const Text(
        'سيتم حذف حسابك وبيانات ملفك الشخصي نهائيًا. سنرسل رابط تأكيد إلى بريدك الإلكتروني. افتحي الرابط على هذا الجهاز لإكمال الحذف.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('إرسال رابط الحذف'),
        ),
      ],
    );
  }
}
