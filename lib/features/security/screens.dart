import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';

class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key});
  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final factors = await repo.totpFactors();
      if (factors.isEmpty) throw StateError('No TOTP factor');
      await repo.verifyTotp(factors.first, code.text);
      await ref.read(sessionProvider.notifier).reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível verificar o código. Confira e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verificação em duas etapas')),
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Digite o código do seu aplicativo autenticador.'),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    labelText: 'Código de autenticação',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : verify,
                  child: const Text('Verificar'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => ref.read(sessionProvider.notifier).logout(),
                  child: const Text('Sair'),
                ),
                const Text(
                  'Sem acesso ao autenticador? Entre em contato com o suporte da plataforma.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final code = TextEditingController();
  List<String>? factors;
  ({String id, String secret, String qr})? enrollment;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await ref.read(authRepositoryProvider).totpFactors();
      if (mounted) setState(() => factors = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Não foi possível carregar a segurança da conta.',
        );
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível concluir. Confira o código e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Segurança da conta'),
      leading: BackButton(
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(
              ref.read(sessionProvider).value?.homePath ?? '/contexts',
            );
          }
        },
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Verificação em duas etapas',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (factors == null && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (factors != null && enrollment == null) ...[
                  Text(
                    factors!.isEmpty
                        ? 'Desativada. Proteja sua conta com um aplicativo autenticador.'
                        : 'Ativada. Um código será solicitado ao entrar.',
                  ),
                  const SizedBox(height: 16),
                  if (factors!.isEmpty)
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final result = await ref
                                  .read(authRepositoryProvider)
                                  .enrollTotp();
                              if (mounted) setState(() => enrollment = result);
                            }),
                      child: const Text('Ativar'),
                    ),
                  for (final id in factors!)
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Desativar verificação?'),
                                  content: const Text(
                                    'Sua conta ficará protegida apenas pela senha.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Desativar'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await run(() async {
                                  await ref
                                      .read(authRepositoryProvider)
                                      .removeTotp(id);
                                  await load();
                                  await ref
                                      .read(sessionProvider.notifier)
                                      .reload();
                                });
                              }
                            },
                      child: const Text('Desativar autenticador'),
                    ),
                ],
                if (enrollment case final setup?) ...[
                  const Text(
                    'Escaneie o QR code no aplicativo autenticador ou insira a chave manualmente.',
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Semantics(
                      label: 'QR code para configurar o autenticador',
                      child: SvgPicture.string(
                        setup.qr.replaceFirst('data:image/svg+xml;utf-8,', ''),
                        width: 200,
                        height: 200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Chave de configuração:'),
                  SelectableText(setup.secret),
                  TextField(
                    controller: code,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: const InputDecoration(
                      labelText: 'Código de autenticação',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await ref
                                .read(authRepositoryProvider)
                                .verifyTotp(setup.id, code.text);
                            if (mounted) {
                              setState(() {
                                enrollment = null;
                                code.clear();
                              });
                            }
                            await load();
                            await ref.read(sessionProvider.notifier).reload();
                          }),
                    child: const Text('Confirmar ativação'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await ref
                                .read(authRepositoryProvider)
                                .removeTotp(setup.id);
                            if (mounted) {
                              setState(() {
                                enrollment = null;
                                code.clear();
                              });
                            }
                          }),
                    child: const Text('Cancelar'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (factors == null)
                    TextButton(
                      onPressed: load,
                      child: const Text('Tentar novamente'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
