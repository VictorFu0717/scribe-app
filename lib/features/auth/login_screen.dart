import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_style.dart';
import '../../providers/auth_controller.dart';
import '../../providers/settings_controller.dart';
import '../../routing/app_router.dart';
import '../../widgets/brand_background.dart';
import '../../widgets/brand_wave.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/soft_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).login(
          username: _userCtrl.text.trim(),
          password: _passCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const BrandWave(size: 68),
                    const SizedBox(height: 20),
                    Text(AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontSize: 34)),
                    const SizedBox(height: 6),
                    Text('錄音 · 逐字稿 · 摘要 · AI 助理',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: scheme.outline,
                            fontSize: 15,
                            letterSpacing: 0.2)),
                    const SizedBox(height: 32),
                    SoftCard(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('登入',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text('使用公司帳號',
                                style: TextStyle(color: scheme.outline)),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _userCtrl,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '帳號',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? '請輸入帳號'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '密碼',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? '請輸入密碼' : null,
                            ),
                            if (auth.error != null) ...[
                              const SizedBox(height: 16),
                              _ErrorBanner(message: auth.error!),
                            ],
                            const SizedBox(height: 24),
                            GradientButton(
                              label: '登入',
                              loading: auth.loading,
                              onPressed: _submit,
                              icon: Icons.arrow_forward_rounded,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _FooterHint(settings: settings),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppStyle.rSm),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.error, fontSize: 13))),
        ],
      ),
    );
  }
}

class _FooterHint extends StatelessWidget {
  const _FooterHint({required this.settings});
  final Settings settings;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (settings.useMock) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined, size: 15, color: scheme.outline),
          const SizedBox(width: 6),
          Text('Mock 模式 · 任意帳密即可登入',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
          TextButton(
            onPressed: () => context.push(Routes.settings),
            style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('設定'),
          ),
        ],
      );
    }
    return TextButton.icon(
      onPressed: () => context.push(Routes.settings),
      icon: const Icon(Icons.dns_outlined, size: 16),
      label: Text(settings.baseUrl,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
