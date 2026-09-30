import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

Future<ContentAudience?> pickContentAudience(
  BuildContext context,
  ContentAudience initial,
) => showModalBottomSheet<ContentAudience>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AudiencePicker(initial: initial),
);

class _AudiencePicker extends ConsumerStatefulWidget {
  final ContentAudience initial;
  const _AudiencePicker({required this.initial});

  @override
  ConsumerState<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends ConsumerState<_AudiencePicker> {
  late bool _all = widget.initial.allCompanies;
  late final Set<String> _selected = widget.initial.companyIds.toSet();
  List<CompanyOption>? _companies;
  bool _loading = false;
  bool _error = false;
  bool _more = false;
  String _search = '';
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (!_all) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    final offset = append ? _companies!.length : 0;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await ref
          .read(companyRepositoryProvider)
          .options(offset: offset, search: _search);
      if (!mounted || request != _request) return;
      setState(() {
        _companies = [if (append) ..._companies!, ...rows];
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
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
                    'Liberar para',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                SwitchListTile(
                  title: const Text('Todas as empresas'),
                  subtitle: const Text(
                    'Inclui também as empresas cadastradas no futuro.',
                  ),
                  activeThumbColor: AppColors.successDarkGreen,
                  value: _all,
                  onChanged: (value) {
                    setState(() => _all = value);
                    if (!value && _companies == null && !_loading) _load();
                  },
                ),
                if (!_all) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SearchField(
                      'Pesquisar empresa',
                      onChanged: _searchChanged,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('${_selected.length} empresas selecionadas'),
                  ),
                ],
                if (_all)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: SvgIcon(
                        AppIcons.companies,
                        size: 64,
                        color: AppColors.successDarkGreen,
                      ),
                    ),
                  )
                else ...[
                  if (_loading && _companies == null)
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
                  for (final company in _companies ?? <CompanyOption>[])
                    CheckboxListTile(
                      title: Text(company.name),
                      subtitle: company.active
                          ? null
                          : const Text('Empresa inativa'),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(company.id),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(company.id);
                        } else {
                          _selected.remove(company.id);
                        }
                      }),
                    ),
                  if (!_loading && !_error && _companies?.isEmpty == true)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhuma empresa encontrada.'),
                    ),
                  if (_more)
                    TextButton(
                      onPressed: _loading ? null : () => _load(append: true),
                      child: Text(
                        _loading ? 'Carregando...' : 'Carregar mais empresas',
                      ),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(20),
            child: PrimaryButton(
              'Confirmar seleção',
              onPressed: !_all && _selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      ContentAudience(
                        allCompanies: _all,
                        companyIds: _selected.toList()..sort(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
