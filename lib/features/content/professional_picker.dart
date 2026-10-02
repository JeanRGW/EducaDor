import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';

Future<ProfessionalOption?> pickProfessional(
  BuildContext context,
  ProfessionalOption? initial,
) => showModalBottomSheet<ProfessionalOption>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surface,
  showDragHandle: true,
  builder: (_) => _ProfessionalPicker(initial: initial),
);

class _ProfessionalPicker extends ConsumerStatefulWidget {
  final ProfessionalOption? initial;
  const _ProfessionalPicker({required this.initial});

  @override
  ConsumerState<_ProfessionalPicker> createState() =>
      _ProfessionalPickerState();
}

class _ProfessionalPickerState extends ConsumerState<_ProfessionalPicker> {
  ProfessionalOption? _selected;
  List<ProfessionalOption>? _people;
  bool _loading = false;
  bool _error = false;
  String _search = '';
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await ref
          .read(peopleRepositoryProvider)
          .platformProfessionals(search: _search);
      if (!mounted || request != _request) return;
      setState(() => _people = rows);
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  void _searchChanged(String value) {
    _search = value;
    _request++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load());
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Profissional Responsável',
                    style: AdminStyles.formTitle,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.successDarkGreen,
                    textStyle: AdminStyles.body,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SearchField(
              'Pesquisar profissional',
              compact: true,
              prefixIcon: const SvgIcon(
                AppIcons.search,
                size: 26,
                color: Color(0xFF475569),
              ),
              onChanged: _searchChanged,
            ),
          ),
          Expanded(
            child: RadioGroup<String>(
              groupValue: _selected?.id,
              onChanged: (value) => setState(
                () => _selected = _people
                    ?.where((person) => person.id == value)
                    .firstOrNull,
              ),
              child: ListView(
                children: [
                  if (_loading && _people == null)
                    for (var i = 0; i < 3; i++)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: SizedBox(
                          height: 36,
                          child: ColoredBox(color: AppColors.chipBg),
                        ),
                      ),
                  if (_error)
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text(
                        'Não foi possível carregar. Tentar novamente',
                      ),
                    ),
                  for (final person in _people ?? <ProfessionalOption>[])
                    RadioListTile<String>(
                      activeColor: AppColors.successDarkGreen,
                      dense: true,
                      title: Text(person.name, style: AdminStyles.body),
                      value: person.id,
                    ),
                  if (!_loading && !_error && _people?.isEmpty == true)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum profissional encontrado.'),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(20),
            child: PrimaryButton(
              'Confirmar seleção',
              compact: true,
              color: AppColors.successDarkGreen,
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected),
            ),
          ),
        ],
      ),
    ),
  );
}
