import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/argentina_date_utils.dart';
import 'client_detail_page.dart';
import 'new_client_page.dart';
import 'client_filters.dart';
import 'client_multi_filter.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _clientes = [];
  final _busqueda = TextEditingController();
  Set<String> _localidades = {};
  String? _zona;
  Set<int> _dias = {};
  bool _visitasHoy = false;
  bool _esAdministrador = false;
  Set<int> get _diasEfectivos =>
      _visitasHoy ? {ArgentinaDateUtils.ahoraArgentina().weekday} : _dias;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('No hay usuario autenticado');
      final usuario = await supabase
          .from('usuarios')
          .select('rol')
          .eq('id', user.id)
          .single();
      final esAdministrador = usuario['rol'] == 'administrador';
      final clientes = <Map<String, dynamic>>[];
      // Paginar evita que el límite de respuesta oculte clientes a los filtros.
      const tamanio = 500;
      for (var desde = 0; ; desde += tamanio) {
        var consulta = supabase.from('clientes').select().eq('activo', true);
        if (!esAdministrador) consulta = consulta.eq('preventista_id', user.id);
        final pagina = await consulta
            .order('nombre_comercio')
            .order('id')
            .range(desde, desde + tamanio - 1);
        clientes.addAll(List<Map<String, dynamic>>.from(pagina));
        if (pagina.length < tamanio) break;
      }
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _esAdministrador = esAdministrador;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los clientes.';
        _cargando = false;
      });
    }
  }

  void _limpiar() => setState(() {
    _busqueda.clear();
    _localidades = {};
    _zona = null;
    _dias = {};
    _visitasHoy = false;
  });

  Future<void> _abrirFiltros() async {
    final seleccionLocalidades = Set<String>.from(_localidades);
    var zona = _zona;
    final seleccionDias = Set<int>.from(_diasEfectivos);
    final localidades = opcionesClientes(_clientes, 'localidad');
    final zonas = opcionesClientes(_clientes, 'zona');
    // Conservar una selección aunque el último cliente haya cambiado de zona.
    for (final localidad in seleccionLocalidades) {
      if (localidad.isNotEmpty) {
        localidades.putIfAbsent(localidad, () => localidad);
      }
    }
    if (zona != null && zona.isNotEmpty) zonas.putIfAbsent(zona, () => zona!);
    final aplicar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, cambiar) {
          Widget selector(
            String titulo,
            String? valor,
            Map<String, String> opciones,
            ValueChanged<String?> onChanged,
          ) => DropdownButtonFormField<String>(
            initialValue: valor ?? '__todos__',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: titulo,
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '__todos__', child: Text('Todas')),
              const DropdownMenuItem(value: '', child: Text('Sin asignar')),
              for (final opcion in opciones.entries)
                DropdownMenuItem(
                  value: opcion.key,
                  child: Text(opcion.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => onChanged(v == '__todos__' ? null : v),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Filtrar clientes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  ClientMultiFilter<String>(
                    title: 'Localidades',
                    allLabel: 'Todas las localidades',
                    options: {'': 'Sin asignar', ...localidades},
                    selected: seleccionLocalidades,
                    onChanged: (values) => cambiar(() {
                      seleccionLocalidades
                        ..clear()
                        ..addAll(values);
                    }),
                  ),
                  const SizedBox(height: 16),
                  selector('Zona', zona, zonas, (v) => cambiar(() => zona = v)),
                  const SizedBox(height: 16),
                  ClientMultiFilter<int>(
                    title: 'Días de visita',
                    allLabel: 'Todos los días',
                    options: {0: 'Sin asignar', ...diasVisita},
                    selected: seleccionDias,
                    onChanged: (values) => cambiar(() {
                      seleccionDias
                        ..clear()
                        ..addAll(values);
                    }),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Aplicar filtros'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (aplicar != true || !mounted) return;
    setState(() {
      _localidades = seleccionLocalidades;
      _zona = zona;
      if (seleccionDias.length != 1 ||
          !seleccionDias.contains(
            ArgentinaDateUtils.ahoraArgentina().weekday,
          )) {
        _visitasHoy = false;
      }
      _dias = seleccionDias;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Clientes')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        final creado = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (_) => const NewClientPage()),
        );
        if (creado != null && mounted) await _cargarClientes();
      },
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Nuevo cliente'),
    ),
    body: _contenido(),
  );

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(
              onPressed: _cargarClientes,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    final filtrados = _clientes
        .where(
          (c) => coincideCliente(
            c,
            busqueda: _busqueda.text,
            localidades: _localidades,
            zona: _zona,
            dias: _diasEfectivos,
          ),
        )
        .toList();
    final hayFiltros =
        _busqueda.text.isNotEmpty ||
        _localidades.isNotEmpty ||
        _zona != null ||
        _diasEfectivos.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _busqueda,
            decoration: const InputDecoration(
              hintText: 'Buscar cliente, localidad o zona...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.today_outlined, size: 18),
                  label: Text(
                    _esAdministrador ? 'Visitas de hoy' : 'Mis visitas de hoy',
                  ),
                  selected: _visitasHoy,
                  onSelected: (v) => setState(() {
                    _visitasHoy = v;
                    _dias = {};
                  }),
                ),
                ActionChip(
                  avatar: const Icon(Icons.filter_list, size: 18),
                  label: const Text('Filtros'),
                  onPressed: _abrirFiltros,
                ),
                if (_localidades.isNotEmpty)
                  InputChip(
                    label: Text('Localidades: ${_localidades.length}'),
                    onPressed: _abrirFiltros,
                    onDeleted: () => setState(() => _localidades = {}),
                  ),
                if (_zona != null)
                  InputChip(
                    label: Text(
                      'Zona: ${_zona!.isEmpty ? "Sin asignar" : _zona}',
                    ),
                    onDeleted: () => setState(() => _zona = null),
                  ),
                if (_diasEfectivos.isNotEmpty)
                  InputChip(
                    label: Text(
                      _diasEfectivos.length == 1
                          ? 'Visita: ${nombreDiaVisita(_diasEfectivos.single)}'
                          : 'Días: ${_diasEfectivos.length}',
                    ),
                    onPressed: _abrirFiltros,
                    onDeleted: () => setState(() {
                      _dias = {};
                      _visitasHoy = false;
                    }),
                  ),
                if (hayFiltros)
                  TextButton(onPressed: _limpiar, child: const Text('Limpiar')),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${filtrados.length} de ${_clientes.length} clientes'),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargarClientes,
            child: filtrados.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        _clientes.isEmpty
                            ? 'Todavía no hay clientes cargados. Presioná Nuevo cliente para agregar el primero.'
                            : 'No hay clientes que coincidan con estos filtros.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : useDesktopLayout(context)
                ? DesktopRecords(
                    records: filtrados,
                    fields: [
                      DesktopField(
                        'Comercio',
                        (r) => r['nombre_comercio'],
                        width: 220,
                      ),
                      DesktopField('Propietario', (r) => r['propietario']),
                      DesktopField(
                        'Dirección',
                        (r) => r['direccion'],
                        width: 220,
                      ),
                      DesktopField('Localidad', (r) => r['localidad']),
                      DesktopField('Zona', (r) => r['zona'], width: 110),
                      DesktopField(
                        'Visita',
                        (r) => nombreDiaVisita(diaVisitaCliente(r)),
                        width: 100,
                      ),
                    ],
                    onOpen: (cliente) async {
                      final actualizado = await Navigator.of(context)
                          .push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ClientDetailPage(cliente: cliente),
                            ),
                          );
                      if (actualizado == true && mounted) {
                        await _cargarClientes();
                      }
                    },
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: filtrados.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final cliente = filtrados[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.storefront),
                          ),
                          title: Text(
                            cliente['nombre_comercio']?.toString() ??
                                'Sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final campo in [
                                'propietario',
                                'direccion',
                                'localidad',
                              ])
                                if (normalizarCliente(
                                  cliente[campo],
                                ).isNotEmpty)
                                  Text(cliente[campo].toString()),
                              if (normalizarCliente(cliente['zona']).isNotEmpty)
                                Text('Zona: ${cliente["zona"]}'),
                              Text(
                                'Visita: ${nombreDiaVisita(diaVisitaCliente(cliente))}',
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final actualizado = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ClientDetailPage(cliente: cliente),
                                  ),
                                );
                            if (actualizado == true && mounted) {
                              await _cargarClientes();
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
