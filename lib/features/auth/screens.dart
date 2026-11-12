import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/logo.dart';

export 'recovery_screens.dart' show RecoverPasswordScreen;

// ---------------------------------------------------------------- Splash
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;
  bool _elapsed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      _elapsed = true;
      _continueIfReady();
    });
  }

  void _continueIfReady() {
    if (mounted && _elapsed && !ref.read(sessionProvider).isLoading) {
      context.go('/welcome');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, _) => _continueIfReady());
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.authGradientTop, AppColors.authGradientBottom],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [LogoLockup(size: 150)],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Welcome
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF023F57), Color(0xFF054544)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: const Alignment(0, 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 480),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(28, 60, 28, 76),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'BEM-VINDO!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppFonts.outfit,
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Theme.of(context).colorScheme.onSurface
                                    : const Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 28),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Text(
                                'Estamos felizes em ter você aqui.\nVamos juntos aprender a\ncuidar da sua saúde!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: AppFonts.inter,
                                  fontSize: 16,
                                  height: 1.45,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).colorScheme.onSurface
                                      : const Color(0xFF333333),
                                ),
                              ),
                            ),
                            const SizedBox(height: 60),
                            FilledButton(
                              onPressed: () => context.go('/login'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(130, 44),
                                elevation: 2,
                                shadowColor: Colors.black26,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: AppFonts.inter,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('Entrar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Login
class LoginScreen extends ConsumerStatefulWidget {
  final String? redirectTo;
  const LoginScreen({super.key, this.redirectTo});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_email.text.trim().isEmpty || _password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha e-mail e senha para continuar.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final session = await ref
          .read(sessionProvider.notifier)
          .login(email: _email.text, password: _password.text);
      if (!mounted) return;
      final redirect = widget.redirectTo;
      context.go(
        redirect != null && redirect.startsWith('/invite/accept?token=')
            ? redirect
            : session.needsPassword
            ? '/set-password'
            : session.homePath,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível entrar. Verifique e-mail e senha.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TextStyle get _fieldStyle => TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 14,
    height: 1.4,
    color: Theme.of(context).colorScheme.onSurface,
  );

  InputDecoration _decoration(String hint, String icon) => InputDecoration(
    hintText: hint,
    hintStyle: _fieldStyle.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    fillColor: Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).scaffoldBackgroundColor
        : Theme.of(context).scaffoldBackgroundColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 14, right: 12),
      child: SvgIcon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 56),
                    const _LoginHero(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 84, 28, 48),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Entrar no EducaDOR',
                              style: TextStyle(
                                fontFamily: AppFonts.outfit,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Use seu e-mail e a senha criada ao aceitar o convite.',
                              style: TextStyle(
                                fontFamily: AppFonts.inter,
                                fontSize: 14,
                                height: 1.3,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const _LoginFieldLabel('E-mail'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _email,
                              enabled: !_loading,
                              style: _fieldStyle.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: _decoration(
                                'email@empresa.com',
                                AppIcons.mail,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _LoginFieldLabel('Senha'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _password,
                              enabled: !_loading,
                              obscureText: _obscure,
                              style: _fieldStyle.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              decoration:
                                  _decoration(
                                    'Sua senha',
                                    AppIcons.lock,
                                  ).copyWith(
                                    suffixIconConstraints: const BoxConstraints(
                                      minHeight: 46,
                                      minWidth: 44,
                                    ),
                                    suffixIcon: IconButton(
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(44, 46),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      tooltip: _obscure
                                          ? 'Mostrar senha'
                                          : 'Ocultar senha',
                                      onPressed: _loading
                                          ? null
                                          : () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                      icon: SvgIcon(
                                        _obscure
                                            ? AppIcons.eyeOff
                                            : AppIcons.eye,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.go('/recover'),
                                style: TextButton.styleFrom(
                                  foregroundColor: context.successForeground,
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(
                                    fontFamily: AppFonts.inter,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                child: const Text('Esqueci a senha'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            PrimaryButton(
                              _loading ? 'Entrando…' : 'ENTRAR',
                              compact: true,
                              onPressed: _loading ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _LoginFieldLabel extends StatelessWidget {
  final String label;
  const _LoginFieldLabel(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: TextStyle(
      fontFamily: AppFonts.inter,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 20 / 11,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/alongamento_login.jpg',
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
        const ColoredBox(color: Color(0x99000000)),
        Positioned(
          left: 24,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0x1FFFFFFF),
              borderRadius: BorderRadius.all(Radius.circular(12)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x4DFFFFFF)),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgIcon(AppIcons.logoColor, size: 28),
                SizedBox(width: 10),
                Text(
                  'EducaDOR',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: AppFonts.outfit,
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
