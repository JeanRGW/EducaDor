import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/admin_styles.dart';

Future<bool> confirmContentDeletion(
  BuildContext context,
  String kind,
  String title,
) async {
  final label = switch (kind) {
    'course' => 'curso',
    'module' => 'módulo',
    _ => 'aula',
  };
  final descendants = switch (kind) {
    'course' =>
      'Todos os módulos, aulas, atribuições, progressos e certificados deste curso serão excluídos.',
    'module' => 'Todas as aulas e os progressos deste módulo serão excluídos.',
    _ => 'O conteúdo e os progressos desta aula serão excluídos.',
  };
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Excluir $label?', style: AdminStyles.formTitle(context)),
          content: Text(
            '“$title” será excluído permanentemente. $descendants Os pontos obtidos nesse conteúdo deixarão de compor o saldo dos funcionários. Os arquivos enviados permanecerão no armazenamento. Esta ação não pode ser desfeita.',
            style: AdminStyles.body(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: Text('Excluir $label'),
            ),
          ],
        ),
      ) ??
      false;
}
