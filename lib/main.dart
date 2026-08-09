import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/clients/clients_page.dart';
import 'features/products/products_page.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vmbncsqapqdyffscwfwo.supabase.co',
    anonKey: 'sb_publishable_w_nz47b753qQkzv2pr7lhA_Yl4eZsTB',
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginPage()
          : const HomePage(),
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

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Distribuidora Alberdi'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
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
              child: ListTile(
                leading: const Icon(
                  Icons.people_outline,
                ),
                title:
                    const Text('Clientes'),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ClientsPage(),
                    ),
                  );
                },
              ),
            ),

            // PRODUCTOS
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                ),
                title:
                    const Text('Productos'),
                trailing: const Icon(
                  Icons.chevron_right,
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
              child: ListTile(
                leading: const Icon(
                  Icons.shopping_cart_outlined,
                ),
                title:
                    const Text('Nuevo pedido'),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: () {},
              ),
            ),

            // PEDIDOS
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.receipt_long_outlined,
                ),
                title:
                    const Text('Pedidos'),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: () {},
              ),
            ),

            // ADMINISTRACIÓN
            if (esAdministrador)
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons
                        .admin_panel_settings_outlined,
                  ),
                  title: const Text(
                    'Administración',
                  ),
                  subtitle: const Text(
                    'Solo administrador',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}