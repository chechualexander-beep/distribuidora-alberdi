import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/app_bootstrap.dart';
import 'core/network_status.dart';
import 'package:http/http.dart' as http;
import 'core/environment_frame.dart';
import 'core/environment_auth_storage.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'core/session_lock.dart';
import 'core/desktop_table.dart';
import 'features/desktop/desktop_home.dart';
import 'dart:io';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/orders/new_order_page.dart';
import 'features/clients/clients_page.dart';
import 'features/products/products_page.dart';
import 'features/orders/orders_page.dart';
import 'features/commissions/my_commissions_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'features/admin/commercial_summary_page.dart';
import 'features/commissions/commissions_page.dart';
import 'features/home/home_summary.dart';
import 'features/invoicing/invoicing_page.dart';
import 'features/orders/admin_orders_page.dart';
import 'features/balances/balances_page.dart';
import 'features/catalog/general_catalog_page.dart';
import 'core/offline_queries.dart';
import 'core/offline_prep_card.dart';
import 'core/offline_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'core/pending_orders.dart';
import 'core/pending_orders_page.dart';
import 'features/home/home_menu.dart';
import 'features/stock/stock_data.dart' show canUseDeposit;
import 'features/stock/stock_form_page.dart' show StockFormKind;
import 'features/stock/stock_home_page.dart';
import 'features/stock/vehicle_load_page.dart';
import 'features/orders/finalization_request.dart';
import 'features/finance/finance_home_page.dart';
import 'features/finance/finance_data.dart' show pesos;
import 'features/finance/finance_dashboard_page.dart';
import 'features/sales/special_sale_page.dart';
import 'features/calculator/calculator_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _localAuthentication = LocalAuthentication();
final _lockNavigation = SessionLockNavigation();
Future<void> main() => startApplication();

Future<void> startApplication({bool testingEntrypoint = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  late final AppConfig config;
  try {
    config = await prepareApplication(
      resolveConfig: () =>
          AppConfig.fromCompileTime(testingEntrypoint: testingEntrypoint),
      initializeFirebase: () async {
        if (!Platform.isWindows) await Firebase.initializeApp();
      },
      initializeSupabase: (config) async {
        await Supabase.initialize(
          url: config.supabaseUrl,
          publishableKey: config.supabaseKey,
          authOptions: authOptionsFor(config),
          // Consultas con tiempo máximo: con poca señal, la pantalla ofrece reintentar.
          httpClient: ResilientHttpClient(http.Client()),
        );
      },
    );
  } on FormatException {
    // Never render configuration values or exceptions from external libraries.
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Text(
                'Inicio bloqueado. Revisá la configuración del entorno.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  activateAppConfig(config);
  await loadDataSaver();
  // Copia local de las consultas (para seguir viendo datos sin señal).
  try {
    final support = await getApplicationSupportDirectory();
    offlineCache = await OfflineCache.open(
      p.join(support.path, 'datos_sin_conexion_${config.project}'),
    );
  } catch (_) {
    offlineCache = null;
  }
  runApp(const DistribuidoraAlberdiApp());
}

class DistribuidoraAlberdiApp extends StatelessWidget {
  const DistribuidoraAlberdiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_lockNavigation],
      builder: (context, child) => EnvironmentFrame(
        config: appConfig,
        child: ConnectionBanner(child: _buildPlatformContent(context, child!)),
      ),
      debugShowCheckedModeBanner: false,
      title: appConfig.title,
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      themeMode: Platform.isWindows ? ThemeMode.dark : ThemeMode.light,

      home: const SplashPage(),
    );
  }

  Widget _buildPlatformContent(BuildContext context, Widget child) {
    if (Platform.isWindows && MediaQuery.sizeOf(context).width >= 900) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          visualDensity: VisualDensity.compact,
          iconTheme: theme.iconTheme.copyWith(size: 20),
          listTileTheme: theme.listTileTheme.copyWith(dense: true),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        child: child,
      );
    }
    if (!Platform.isAndroid) return child;
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) => SessionLock(
        navigation: _lockNavigation,
        userId: auth.currentUser?.id,
        authenticate: () => _localAuthentication.authenticate(
          localizedReason: 'Verificá tu identidad para continuar en Alberdi',
          persistAcrossBackgrounding: true,
        ),
        signOut: () async {
          await borrarDatosSinConexion(auth.currentUser?.id);
          await auth.signOut();
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
          );
        },
        child: child,
      ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _continuar();
  }

  Future<void> _continuar() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final tieneSesion = Supabase.instance.client.auth.currentSession != null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => tieneSesion ? const HomePage() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Image.asset(
            'assets/logo/logo_alberdi.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _cargando = false;
  bool _ocultarPassword = true;

  Future<void> _iniciarSesion() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _mostrarMensaje('Ingresá tu correo y contraseña.');
      return;
    }

    setState(() {
      _cargando = true;
    });

    try {
      final respuesta = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (respuesta.user != null && mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } on AuthException catch (error) {
      _mostrarMensaje('No se pudo iniciar sesión: ${error.message}');
    } catch (_) {
      _mostrarMensaje('Ocurrió un error al iniciar sesión.');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 85),
                  const SizedBox(height: 24),
                  const Text(
                    'Distribuidora Alberdi',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sistema de ventas',
                    style: TextStyle(fontSize: 17, color: AppColors.gris),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _passwordController,
                    obscureText: _ocultarPassword,
                    onSubmitted: (_) => _iniciarSesion(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _ocultarPassword = !_ocultarPassword;
                          });
                        },
                        icon: Icon(
                          _ocultarPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _cargando ? null : _iniciarSesion,
                      child: _cargando
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'INICIAR SESIÓN',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _cargandoPerfil = true;

  String? _nombre;
  String? _rol;
  bool _puedeCatalogoGeneral = false;

  /// Ayuda en el depósito (preventista habilitado): ve, cuenta, carga y baja.
  bool _puedeDeposito = false;

  /// Números de la tarjeta "Hoy" (null mientras se leen).
  HomeSummary? _resumen;

  /// Administrador en el teléfono: 0 Inicio, 1 Pedidos, 2 Reparto, 3 Stock (barra de abajo).
  int _tab = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _configurarNotificaciones() async {
    if (!appConfig.notificationsEnabled || !Platform.isAndroid) return;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await messaging.getToken();

      if (token == null) return;

      final usuario = Supabase.instance.client.auth.currentUser;

      if (usuario == null) return;

      await Supabase.instance.client
          .from('dispositivos_notificaciones')
          .upsert({
            'usuario_id': usuario.id,
            'token': token,
            'plataforma': 'android',
            'activo': true,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'token');

      debugPrint('Token FCM del administrador registrado correctamente.');
    }
  }

  Future<void> _cargarPerfil() async {
    try {
      final usuarioAuth = Supabase.instance.client.auth.currentUser;

      if (usuarioAuth == null) {
        if (!mounted) return;

        setState(() {
          _error = 'No hay una sesión iniciada.';
          _cargandoPerfil = false;
        });

        return;
      }

      final perfil = await consultarPerfilInicio(
        Supabase.instance.client,
        usuarioAuth.id,
      );

      final nombre = perfil['nombre'] as String?;

      final apellido = perfil['apellido'] as String?;

      final rol = perfil['rol'] as String?;

      final activo = perfil['activo'] as bool? ?? false;

      if (!mounted) return;

      if (!activo) {
        setState(() {
          _error = 'Este usuario está desactivado.';
          _cargandoPerfil = false;
        });

        return;
      }

      setState(() {
        _nombre = [
          if (nombre != null && nombre.isNotEmpty) nombre,
          if (apellido != null && apellido.isNotEmpty) apellido,
        ].join(' ');

        _rol = rol;
        _cargandoPerfil = false;
      });
      _cargarPermisoCatalogoGeneral();
      if (rol != 'administrador') _cargarPermisoDeposito();
      _cargarResumen();
      // Pedidos guardados sin señal: se envían solos (al iniciar, al volver la conexión, cada 2 min).
      PendingOrders.instance.start(
        Supabase.instance.client,
        sendDelivery: rol == 'administrador' ? _enviarEntregaGuardada : null,
      );
      if (rol == 'administrador') {
        await _configurarNotificaciones();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el perfil del usuario.';
        _cargandoPerfil = false;
      });
    }
  }

  /// Opcional: si el servidor todavía no tiene el catálogo general, el acceso no aparece.
  Future<void> _cargarPermisoCatalogoGeneral() async {
    try {
      final puede = await Supabase.instance.client.rpc(
        'puede_generar_catalogo_general',
      );
      if (mounted) setState(() => _puedeCatalogoGeneral = puede == true);
    } catch (_) {
      if (mounted) setState(() => _puedeCatalogoGeneral = false);
    }
  }

  Future<void> _cargarResumen() async {
    final client = Supabase.instance.client;
    final resumen = await fetchHomeSummary(
      client,
      admin: _rol == 'administrador',
      userId: client.auth.currentUser?.id,
    );
    if (mounted) setState(() => _resumen = resumen);
  }

  Future<void> _cargarPermisoDeposito() async {
    final puede = await canUseDeposit(Supabase.instance.client);
    if (mounted) setState(() => _puedeDeposito = puede);
  }

  /// Envía una gestión de reparto hecha sin señal (la solicitud está en la cola del teléfono).
  static Future<void> _enviarEntregaGuardada(Map<String, dynamic> params) async {
    final client = Supabase.instance.client;
    final store = await finalizationStore(client);
    final pedidoId = params['pedido_id'].toString();
    final payload = store.read(pedidoId);
    if (payload == null) return; // ya se resolvió desde la pantalla del pedido
    await reconcileFinalization(client, payload, store: store, retry: true);
    await store.acknowledge(pedidoId);
  }

  Future<void> _cerrarSesion() async {
    final pendientes = PendingOrders.instance.items.value.length;
    if (pendientes > 0) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay pendientes sin enviar'),
          content: Text(
            'Tenés $pendientes ${pendientes == 1 ? 'pendiente guardado' : 'pendientes guardados'} (pedidos o clientes nuevos) en este teléfono '
            'que todavía no se enviaron. No se pierden: se envían cuando vuelvas a entrar con tu usuario '
            'en este teléfono y haya señal.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cerrar sesión igual'),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
    PendingOrders.instance.stop();
    await borrarDatosSinConexion(Supabase.instance.client.auth.currentUser?.id);
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoPerfil) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Distribuidora Alberdi')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    final esAdministrador = _rol == 'administrador';
    if (useDesktopLayout(context)) {
      return DesktopHome(
        name: _nombre ?? 'Usuario',
        isAdmin: esAdministrador,
        canGeneralCatalog: _puedeCatalogoGeneral,
        onSignOut: _cerrarSesion,
      );
    }
    final inicio = _inicio(esAdministrador);
    if (!esAdministrador) return inicio;
    // Administrador: barra de abajo con lo de todos los días (Inicio, Pedidos, Reparto, Stock).
    final pagina = switch (_tab) {
      1 => const OrdersPage(),
      2 => const AdminOrdersPage(),
      3 => const StockHomePage(),
      _ => inicio,
    };
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _irA(0);
      },
      child: Scaffold(
        body: KeyedSubtree(key: ValueKey('pestana-$_tab'), child: pagina),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _irA,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Pedidos',
            ),
            NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Reparto'),
            NavigationDestination(
              icon: Icon(Icons.warehouse_outlined),
              selectedIcon: Icon(Icons.warehouse),
              label: 'Stock',
            ),
          ],
        ),
      ),
    );
  }

  void _irA(int tab) {
    setState(() => _tab = tab);
    if (tab == 0) _cargarResumen();
  }

  Widget _inicio(bool esAdministrador) {
    final resumen = _resumen;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 72,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DISTRIBUIDORA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.2,
                color: Color(0xFFE5A72D),
              ),
            ),
            Text(
              'Alberdi',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          const DataSaverButton(),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarResumen,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Hola, ${_nombre ?? 'Usuario'}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Tonos.of(context).etiquetaGris.$1,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        esAdministrador
                            ? 'Administrador'
                            : _puedeDeposito
                            ? 'Preventista · Depósito'
                            : 'Preventista',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Tonos.of(context).etiquetaGris.$2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (esAdministrador)
                  _tarjetaHoy(resumen)
                else if (resumen?.weekOrders != null)
                  _semana(resumen!),
                // Nuevo pedido debajo de lo de "sin señal": más cerca del pulgar.
                const PendingOrdersCard(),
                const OfflinePrepCard(),
                const SizedBox(height: 10),
                NewOrderButton(onTap: () => _abrir(const NewOrderPage())),
                if (esAdministrador) ..._seccionesAdministrador(resumen) else ..._seccionesPreventista(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _seccionesAdministrador(HomeSummary? resumen) => [
    HomeSection(
      title: 'VENTAS',
      area: HomeArea.ventas,
      actions: [
        HomeAction(Icons.receipt_long_outlined, 'Pedidos', () => _irA(1)),
        HomeAction(Icons.people_outline, 'Clientes', () => _abrir(const ClientsPage())),
        HomeAction(Icons.point_of_sale, 'Venta especial', () => _abrir(const SpecialSalePage())),
        if (_puedeCatalogoGeneral)
          HomeAction(
            Icons.storefront_outlined,
            'Catálogo general',
            () => _abrir(const GeneralCatalogPage(isAdmin: true)),
          ),
      ],
    ),
    HomeSection(
      title: 'REPARTO Y STOCK',
      area: HomeArea.reparto,
      actions: [
        HomeAction(Icons.route_outlined, 'Reparto', () => _irA(2), badge: resumen?.toDeliver),
        HomeAction(Icons.local_shipping_outlined, 'Cargar / bajar', _cargarBajar),
        HomeAction(Icons.warehouse_outlined, 'Stock', () => _irA(3)),
        HomeAction(Icons.add_shopping_cart, 'Anotar compra', _anotarCompra),
      ],
    ),
    HomeSection(
      title: 'FACTURACIÓN',
      area: HomeArea.facturacion,
      actions: [
        HomeAction(
          Icons.request_quote_outlined,
          'Facturar',
          () => _abrir(const InvoicingPage()),
          badge: resumen?.toInvoice,
        ),
      ],
    ),
    HomeSection(
      title: 'PLATA',
      area: HomeArea.plata,
      actions: [
        HomeAction(Icons.receipt_outlined, 'Anotar gasto', _anotarGasto, highlight: true),
        HomeAction(Icons.savings_outlined, 'Plata del negocio', () => _abrir(const FinanceHomePage())),
        HomeAction(Icons.insights, 'Tablero del mes', () => _abrir(const FinanceDashboardPage())),
        HomeAction(Icons.account_balance_wallet_outlined, 'Saldos', () => _abrir(const BalancesPage())),
        HomeAction(Icons.payments_outlined, 'Comisiones', () => _abrir(const CommissionsPage())),
      ],
    ),
    HomeSection(
      title: 'HERRAMIENTAS',
      area: HomeArea.herramientas,
      actions: [
        HomeAction(Icons.inventory_2_outlined, 'Productos', () => _abrir(const ProductsPage())),
        HomeAction(Icons.calculate_outlined, 'Calculadora', () => _abrir(const CalculatorPage())),
        HomeAction(Icons.analytics_outlined, 'Resumen y estadísticas', () => _abrir(const CommercialSummaryPage())),
      ],
    ),
  ];

  List<Widget> _seccionesPreventista() => [
    HomeSection(
      title: 'VENTAS',
      area: HomeArea.ventas,
      actions: [
        HomeAction(Icons.receipt_long_outlined, 'Pedidos', () => _abrir(const OrdersPage())),
        HomeAction(Icons.people_outline, 'Clientes', () => _abrir(const ClientsPage())),
        HomeAction(Icons.inventory_2_outlined, 'Productos', () => _abrir(const ProductsPage())),
        HomeAction(Icons.local_shipping_outlined, 'Lo que llevamos', () => _abrir(const VehicleLoadPage())),
      ],
    ),
    if (_puedeDeposito)
      HomeSection(
        title: 'DEPÓSITO',
        area: HomeArea.reparto,
        actions: [
          HomeAction(
            Icons.local_shipping_outlined,
            'Cargar vehículo',
            () => openTransfer(context, StockFormKind.load),
          ),
          HomeAction(
            Icons.warehouse_outlined,
            'Bajar al depósito',
            () => openTransfer(context, StockFormKind.unload),
          ),
          HomeAction(
            Icons.fact_check_outlined,
            'Contar y ver stock',
            () => _abrir(const StockHomePage(helper: true)),
          ),
        ],
      ),
    HomeSection(
      title: 'MÍO',
      area: HomeArea.plata,
      actions: [
        HomeAction(Icons.payments_outlined, 'Mis comisiones', () => _abrir(MyCommissionsPage())),
        HomeAction(Icons.calculate_outlined, 'Calculadora', () => _abrir(const CalculatorPage())),
        if (_puedeCatalogoGeneral)
          HomeAction(
            Icons.storefront_outlined,
            'Catálogo general',
            () => _abrir(const GeneralCatalogPage(isAdmin: false)),
          ),
      ],
    ),
  ];

  /// "Hoy": para facturar, para entregar, el viaje y lo que está en negativo.
  Widget _tarjetaHoy(HomeSummary? r) {
    String n(int? v) => v == null ? '–' : '$v';
    final desde = r?.tripSince;
    final viaje = r?.tripOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TodayCard(
        title: 'Hoy, ${_hoyTexto(DateTime.now())}',
        note: r == null
            ? 'Leyendo…'
            : r.cached
            ? 'Sin señal: datos guardados ${describeSavedAt(r.at)}.'
            : null,
        items: [
          TodayItem(HomeArea.facturacion, n(r?.toInvoice), 'para facturar', () => _abrir(const InvoicingPage())),
          TodayItem(HomeArea.reparto, n(r?.toDeliver), 'para entregar', () => _irA(2)),
          TodayItem(
            HomeArea.reparto,
            viaje == null
                ? 'Viaje'
                : viaje
                ? 'Viaje abierto'
                : 'Sin viaje abierto',
            viaje == true && desde != null ? 'desde ${describeSavedAt(desde)}' : '',
            () => _irA(3),
            icon: Icons.local_shipping_outlined,
          ),
          TodayItem(
            HomeArea.herramientas,
            n(r?.negatives),
            'en negativo',
            () => _abrir(const StockHomePage(onlyNegatives: true)),
            alert: (r?.negatives ?? 0) > 0,
          ),
          if (r?.salaryDue != null)
            TodayItem(
              HomeArea.plata,
              pesos(r!.salaryDue!),
              'tu sueldo, sin pagar',
              () => _abrir(const FinanceHomePage()),
              alert: true,
            ),
        ],
      ),
    );
  }

  Widget _semana(HomeSummary r) {
    final colors = AreaColors.of(context, HomeArea.ventas);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: colors.fondo, borderRadius: BorderRadius.circular(12)),
      child: Text(
        'Esta semana: ${r.weekOrders} ${r.weekOrders == 1 ? 'pedido' : 'pedidos'}'
        '${r.cached ? ' (sin señal)' : ''}',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.texto),
      ),
    );
  }

  static String _hoyTexto(DateTime d) {
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    return '${dias[d.weekday - 1]} ${d.day}';
  }

  Future<void> _cargarBajar() async {
    await openTransfer(context, StockFormKind.load);
    if (mounted) _cargarResumen();
  }

  Future<void> _anotarCompra() async {
    await openPurchase(context);
    if (mounted) _cargarResumen();
  }

  Future<void> _anotarGasto() => quickExpense(context);

  Future<void> _abrir(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _cargarResumen();
  }
}
