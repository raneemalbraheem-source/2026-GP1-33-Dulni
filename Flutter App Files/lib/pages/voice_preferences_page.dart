import 'package:flutter/material.dart';

import '../services/voice_preferences_service.dart';

class VoicePreferencesPage extends StatefulWidget {
  const VoicePreferencesPage({super.key});

  @override
  State<VoicePreferencesPage> createState() => _VoicePreferencesPageState();
}

class _VoicePreferencesPageState extends State<VoicePreferencesPage> {
  final VoicePreferencesService _preferencesService =
      VoicePreferencesService();

  String _voicePersona = 'default';
  double _speechRate = 1.0;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final preferences = await _preferencesService.load();
      if (!mounted) return;
      setState(() {
        _voicePersona = preferences.voicePersona;
        _speechRate = preferences.speechRate;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _saving = true);

    try {
      await _preferencesService.save(
        VoicePreferences(
          voicePersona: _voicePersona,
          speechRate: _speechRate,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ تفضيلات الصوت.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حفظ التفضيلات. تحقق من الاتصال وحاول مرة أخرى.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _rateDescription(double rate) {
    if (rate < 0.55) return 'بطيئة';
    if (rate < 0.8) return 'متوسطة';
    return 'سريعة';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفضيلات الصوت')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'تعذّر تحميل تفضيلات الصوت.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _loadPreferences,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : AbsorbPointer(
                      absorbing: _saving,
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            'اختر الصوت وسرعة التحدث التي تناسبك.',
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<String>(
                            initialValue: _voicePersona,
                            decoration: const InputDecoration(
                              labelText: 'الصوت المفضّل',
                              prefixIcon: Icon(Icons.record_voice_over),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'default',
                                child: Text('الصوت الافتراضي'),
                              ),
                              DropdownMenuItem(
                                value: 'male',
                                child: Text('صوت رجالي'),
                              ),
                              DropdownMenuItem(
                                value: 'female',
                                child: Text('صوت نسائي'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _voicePersona = value);
                              }
                            },
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'سرعة التحدث',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(_rateDescription(_speechRate)),
                            ],
                          ),
                          Slider(
                            value: _speechRate,
                            min: 0.3,
                            max: 1.0,
                            divisions: 7,
                            label: _speechRate.toStringAsFixed(1),
                            onChanged: (value) =>
                                setState(() => _speechRate = value),
                          ),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('أبطأ'),
                              Text('أسرع'),
                            ],
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _saving ? null : _savePreferences,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('حفظ التفضيلات'),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
