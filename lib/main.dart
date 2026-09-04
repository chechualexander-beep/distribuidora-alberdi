import 'package:flutter/material.dart';
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

import 'features/admin/admin_page.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
  await Firebase.initializeApp();
}

  const bool useTesting = bool.fromEnvironment(
  'USE_TESTING',
  defaultValue: false,
);

const String productionUrl = 'https://vmbncsqapqdyffscwfwo.supabase.co';
const String productionKey = 'sb_publishable_w_nz47b753qQkzv2pr7lhA_Yl4eZsTB';

const String testingUrl = String.fromEnvironment('SUPABASE_TESTING_URL');
const String testingKey = String.fromEnvironment('SUPABASE_TESTING_KEY');

await Supabase.initialize(
  url: useTesting ? testingUrl : productionUrl,
  publishableKey: useTesting ? testingKey : productionKey,
);

  runApp(const DistribuidoraAlberdiApp());
}

class DistribuidoraAlberdiApp extends StatelessWidget {
  const DistribuidoraAlberdiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Distribuidora Alberdi',
      locale: const Locale('es', 'AR'),
supportedLocales: const [
  Locale('es', 'AR'),
],
localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
  useMaterial3: true,
  colorSchemeSeed: Colors.indigo,
),
darkTheme: ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: Colors.indigo,
),
themeMode: Platform.isWindows ? ThemeMode.dark : ThemeMode.light,


      home: const SplashPage(),
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

    final tieneSesion =
        Supabase.instance.client.auth.currentSession != null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            tieneSesion ? const HomePage() : const LoginPage(),
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
      final respuesta =
          await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (respuesta.user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const HomePage(),
          ),
        );
      }
    } on AuthException catch (error) {
      _mostrarMensaje(
        'No se pudo iniciar sesión: ${error.message}',
      );
    } catch (_) {
      _mostrarMensaje(
        'Ocurrió un error al iniciar sesión.',
      );
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
      ),
    );
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
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 85,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Distribuidora Alberdi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sistema de ventas',
                    style: TextStyle(
                      fontSize: 17,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType:
                        TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon:
                          Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _passwordController,
                    obscureText: _ocultarPassword,
                    onSubmitted: (_) =>
                        _iniciarSesion(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon:
                          const Icon(Icons.lock_outline),
                      border:
                          const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _ocultarPassword =
                                !_ocultarPassword;
                          });
                        },
                        icon: Icon(
                          _ocultarPassword
                              ? Icons.visibility_outlined
                              : Icons
                                  .visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _cargando
                          ? null
                          : _iniciarSesion,
                      child: _cargando
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'INICIAR SESIÓN',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
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
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  
  bool _cargandoPerfil = true;

  String? _nombre;
  String? _rol;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }
  Future<void> _configurarNotificaciones() async {
  if (!Platform.isAndroid) return;

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

    final usuario =
        Supabase.instance.client.auth.currentUser;

    if (usuario == null) return;

    await Supabase.instance.client
        .from('dispositivos_notificaciones')
        .upsert(
      {
        'usuario_id': usuario.id,
        'token': token,
        'plataforma': 'android',
        'activo': true,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'token',
    );

    debugPrint('Token FCM del administrador registrado correctamente.');
  }
}

  Future<void> _cargarPerfil() async {
    try {
      final usuarioAuth =
          Supabase.instance.client.auth.currentUser;

      if (usuarioAuth == null) {
        if (!mounted) return;

        setState(() {
          _error = 'No hay una sesión iniciada.';
          _cargandoPerfil = false;
        });

        return;
      }

      final perfil = await Supabase.instance.client
          .from('usuarios')
          .select(
            'nombre, apellido, rol, activo',
          )
          .eq('id', usuarioAuth.id)
          .single();

      final nombre =
          perfil['nombre'] as String?;

      final apellido =
          perfil['apellido'] as String?;

      final rol =
          perfil['rol'] as String?;

      final activo =
          perfil['activo'] as bool? ?? false;

      if (!mounted) return;

      if (!activo) {
        setState(() {
          _error =
              'Este usuario está desactivado.';
          _cargandoPerfil = false;
        });

        return;
      }

      setState(() {
        _nombre = [
          if (nombre != null &&
              nombre.isNotEmpty)
            nombre,
          if (apellido != null &&
              apellido.isNotEmpty)
            apellido,
        ].join(' ');

        _rol = rol;
        _cargandoPerfil = false;
      });
      if (rol == 'administrador') {
  await _configurarNotificaciones();
}
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'No se pudo cargar el perfil del usuario.';
        _cargandoPerfil = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoPerfil) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text('Distribuidora Alberdi'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    final esAdministrador =
        _rol == 'administrador';
        final bool esModoOscuro =
    Theme.of(context).brightness == Brightness.dark;

final Color colorPrincipal =
    esModoOscuro ? Colors.white : const Color(0xFF0B2854);

final Color colorSecundario =
    esModoOscuro ? Colors.white70 : Colors.black54;

    return Scaffold(
  appBar: AppBar(
    backgroundColor: const Color(0xFF062A5E),
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
      IconButton(
        tooltip: 'Cerrar sesión',
        onPressed: _cerrarSesion,
        icon: const Icon(Icons.logout),
      ),
      const SizedBox(width: 8),
    ],
  ),
      body: SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hola, ${_nombre ?? 'Usuario'}',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              esAdministrador
                  ? 'Administrador'
                  : 'Preventista',
              style: const TextStyle(
                fontSize: 17,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),

            // CLIENTES
Card(
  elevation: 2,
  margin: const EdgeInsets.only(bottom: 10),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 18,
      vertical: 8,
    ),
    leading: Icon(
      Icons.people_outline,
      size: 32,
      color: colorPrincipal,
    ),
    title: Text(
      'Clientes',
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: colorPrincipal,
      ),
    ),
    subtitle: Padding(
      padding: EdgeInsets.only(top: 3),
      child: Text(
        'Gestión de clientes',
        style: TextStyle(
          fontSize: 13,
          color: colorSecundario,
        ),
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: colorPrincipal,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ClientsPage(),
        ),
      );
    },
  ),
),

           // PRODUCTOS
Card(
  elevation: 2,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    leading:  Icon(
      Icons.inventory_2_outlined,
      size: 30,
      color: colorPrincipal,
    ),
    title:  Text(
      'Productos',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colorPrincipal,
      ),
    ),
    subtitle:  Padding(
      padding: EdgeInsets.only(top: 3),
      child: Text(
        'Consultá precios y stock',
        style: TextStyle(
          fontSize: 13,
          color: colorSecundario,
        ),
      ),
    ),
    trailing:  Icon(
      Icons.chevron_right,
      color: colorPrincipal,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ProductsPage(),
        ),
      );
    },
  ),
),

            // NUEVO PEDIDO
Card(
  elevation: 2,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
  color: const Color(0xFF1565C0),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    leading: const Icon(
      Icons.shopping_cart_outlined,
      size: 30,
      color: Colors.white,
    ),
    title: const Text(
      'Nuevo pedido',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    subtitle: const Padding(
      padding: EdgeInsets.only(top: 3),
      child: Text(
        'Crear un nuevo pedido',
        style: TextStyle(
          fontSize: 13,
          color: Colors.white70,
        ),
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      color: Colors.white,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const NewOrderPage(),
        ),
      );
    },
  ),
),

            // PEDIDOS
Card(
  elevation: 2,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    leading: Icon(
      Icons.receipt_long_outlined,
      size: 30,
      color: colorPrincipal,
    ),
    title: Text(
      'Pedidos',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colorPrincipal,
      ),
    ),
    subtitle:  Padding(
      padding: EdgeInsets.only(top: 3),
      child: Text(
        'Ver pedidos realizados',
        style: TextStyle(
          fontSize: 13,
          color: colorSecundario,
        ),
      ),
    ),
    trailing:  Icon(
      Icons.chevron_right,
      color: colorPrincipal,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OrdersPage(),
        ),
      );
    },
  ),
),
Card(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    leading: Icon(
      Icons.payments_outlined,
      color: colorPrincipal,
    ),
    title: Text(
      'Mis comisiones',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colorPrincipal,
      ),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        'Consultar mis ganancias',
        style: TextStyle(
          fontSize: 13,
          color: colorSecundario,
        ),
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: colorPrincipal,
    ),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MyCommissionsPage(),
        ),
      );
    },
  ),
),

            // ADMINISTRACIÓN
if (esAdministrador)
  Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      leading:  Icon(
        Icons.admin_panel_settings_outlined,
        color: colorPrincipal,
        size: 28,
      ),
      title:  Text(
        'Administración',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colorPrincipal,
        ),
      ),
      subtitle:  Padding(
        padding: EdgeInsets.only(top: 3),
        child: Text(
          'Solo administrador',
          style: TextStyle(
            fontSize: 13,
            color: colorSecundario,
          ),
        ),
      ),
      trailing:  Icon(
        Icons.chevron_right,
        color: colorPrincipal,
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AdminPage(),
          ),
        );
      },
    ),
  ),
          ],
        ),
      ),
      ),
    );
  }
}