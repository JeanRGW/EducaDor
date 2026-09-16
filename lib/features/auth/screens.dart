import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/logo.dart';

// ---------------------------------------------------------------- Splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.authGradientTop,
              AppColors.authGradientBottom,
            ],
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
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.authGradientTop,
                  AppColors.authGradientBottom,
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('BEM-VINDO!',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 18),
                  const Text(
                    'Estamos felizes em ter você aqui.\nVamos juntos aprender a cuidar da sua saúde!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton('Entrar',
                            onPressed: () => context.go('/role-select')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go('/role-select'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text('Criar Conta',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Role select
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.authGradientTop,
              AppColors.authGradientBottom,
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 120,
              child: const LogoLockup(
                  size: 150, color: Color(0x33FFFFFF)),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roleButton(context, 'GESTOR', Role.gestor),
                    const SizedBox(height: 18),
                    _roleButton(context, 'EMPRESA', Role.empresa),
                    const SizedBox(height: 18),
                    _roleButton(context, 'FUNCIONÁRIO', Role.funcionario),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleButton(BuildContext context, String label, Role role) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => context.go('/login', extra: role),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

// ---------------------------------------------------------------- Login
class LoginScreen extends ConsumerStatefulWidget {
  final Role? initialRole;
  const LoginScreen({super.key, this.initialRole});

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

  String get _title {
    switch (widget.initialRole ?? Role.funcionario) {
      case Role.gestor:
        return 'Cadastro Gestor';
      case Role.empresa:
        return 'Cadastro Empresa';
      case Role.funcionario:
        return 'Acesso do Funcionário';
    }
  }

  String get _subtitle {
    switch (widget.initialRole ?? Role.funcionario) {
      case Role.gestor:
        return 'Supervisionar o desempenho da educação em toda a plataforma.';
      case Role.empresa:
        return 'Insira as credenciais fornecidas pelo seu Gestor';
      case Role.funcionario:
        return 'Insira as credenciais fornecidas pelo seu empregador para começar a aprender.';
    }
  }

  Future<void> _submit() async {
    final role = widget.initialRole ?? Role.funcionario;
    if (_email.text.trim().isEmpty || _password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preencha e-mail e senha para continuar.')));
      return;
    }
    setState(() => _loading = true);
    final auth = ref.read(authRepositoryProvider);
    final (user, company, employee) =
        await auth.login(role: role, email: _email.text, password: _password.text);
    ref.read(sessionProvider.notifier).login(
        AppSession(user: user, company: company, employee: employee));
    if (mounted) context.go(user.homePath());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LoginHero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Text(_subtitle,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 24),
                  FormFieldLabel(
                    label: 'Email',
                    hint: 'email@empresa.com',
                    controller: _email,
                    prefixIcon: const SvgIcon(AppIcons.mail,
                        color: AppColors.textMuted),
                  ),
                  const Text('PASSWORD',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'password123',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 16, right: 10),
                        child: SvgIcon(AppIcons.lock,
                            color: AppColors.textMuted),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 0, minHeight: 0),
                      suffixIcon: IconButton(
                        icon: SvgIcon(
                          _obscure ? AppIcons.eyeOff : AppIcons.eye,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.go('/recover'),
                      child: const Text('Esqueci a senha',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    _loading ? 'Entrando…' : 'ENTRAR',
                    onPressed: _loading ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on User {
  String homePath() {
    switch (role) {
      case Role.funcionario:
        return '/funcionario/home';
      case Role.empresa:
        return '/empresa/home';
      case Role.gestor:
        return '/gestor/home';
    }
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      // Photo band approximated with the design's teal gradient + watermark.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3F7D86), Color(0xFF2A5A62)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -20,
            child: Opacity(
              opacity: 0.12,
              child: SvgIcon(AppIcons.logo,
                  color: Colors.white, size: 160),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgIcon(AppIcons.logo, color: Colors.white, size: 34),
                  SizedBox(width: 10),
                  Text('EducaDOR',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Recover
class RecoverPasswordScreen extends StatefulWidget {
  const RecoverPasswordScreen({super.key});

  @override
  State<RecoverPasswordScreen> createState() => _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState extends State<RecoverPasswordScreen> {
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar Senha')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: LogoLockup(size: 90, color: AppColors.primary, showText: true),
          ),
          const SizedBox(height: 24),
          const FormFieldLabel(label: 'Nova Senha', hint: '••••••••'),
          const FormFieldLabel(label: 'Confirmar Nova Senha', hint: '••••••••'),
          const SizedBox(height: 8),
          PrimaryButton(
            'Atualizar Senha',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Senha atualizada.')));
              context.go('/role-select');
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go('/login'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: AppColors.border),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }
}
