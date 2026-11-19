import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Impide que Atrás cierre un formulario oculto por el bloqueo.
class SessionLockNavigation extends NavigatorObserver
    implements PopEntry<Object?> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);
  @override
  void onPopInvoked(bool didPop) {}
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) route.registerPopEntry(this);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) route.unregisterPopEntry(this);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) route.unregisterPopEntry(this);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is ModalRoute) oldRoute.unregisterPopEntry(this);
    if (newRoute is ModalRoute) newRoute.registerPopEntry(this);
  }
}

/// Mantiene las rutas y formularios montados mientras protege la sesión local.
class SessionLock extends StatefulWidget {
  const SessionLock({
    super.key,
    required this.userId,
    required this.authenticate,
    required this.signOut,
    required this.child,
    this.navigation,
    this.timeout = const Duration(minutes: 5),
  });
  final String? userId;
  final Future<bool> Function() authenticate;
  final Future<void> Function() signOut;
  final Widget child;
  final SessionLockNavigation? navigation;
  final Duration timeout;
  @override
  State<SessionLock> createState() => _SessionLockState();
}

class _SessionLockState extends State<SessionLock> with WidgetsBindingObserver {
  final _elapsed = Stopwatch();
  Timer? _timer;
  bool _locked = false, _hidden = false, _busy = false;

  /// Solo si el teléfono no pudo verificar la identidad aparece la salida (y pide confirmar):
  /// así no se cierra la sesión sin querer al ir a desbloquear.
  bool _verifyFailed = false, _confirmExit = false;

  /// Intentos seguidos sin desbloquear: a los 3 también aparece la salida (por si el teléfono
  /// quedó sin huella, PIN ni patrón y nunca puede verificar).
  int _failures = 0;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.userId != null;
    _activity();
  }

  @override
  void didUpdateWidget(SessionLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _timer?.cancel();
      // Un ingreso con contraseña acaba de verificar la identidad.
      _locked = oldWidget.userId != null && widget.userId != null;
      _message = null;
      _activity();
    }
  }

  void _activity() {
    if (_locked || _hidden || widget.userId == null) return;
    _elapsed
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (mounted && widget.userId != null) setState(() => _locked = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _hidden = state != AppLifecycleState.resumed;
      if (!_hidden &&
          widget.userId != null &&
          _elapsed.elapsed >= widget.timeout) {
        _locked = true;
      }
      if (!_hidden && !_locked && widget.userId != null) {
        _timer?.cancel();
        _timer = Timer(widget.timeout - _elapsed.elapsed, () {
          if (mounted && widget.userId != null) setState(() => _locked = true);
        });
      }
    });
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final user = widget.userId;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await widget.authenticate();
      if (!mounted || user != widget.userId) return;
      setState(() {
        _locked = !ok;
        if (!ok) {
          _message =
              'No se desbloqueó la aplicación. Podés volver a intentarlo.';
          _failures++;
          if (_failures >= 3) _verifyFailed = true;
        }
      });
      if (ok) {
        setState(() {
          _verifyFailed = false;
          _confirmExit = false;
          _failures = 0;
        });
        _elapsed
          ..reset()
          ..start();
        _activity();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifyFailed = true;
          _message =
              'No se pudo verificar tu identidad. Revisá el bloqueo del teléfono (huella, PIN o patrón) y volvé a intentar.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final covered = widget.userId != null && (_locked || _hidden);
    widget.navigation?.canPopNotifier.value = !covered;
    return Listener(
      onPointerDown: (_) => _activity(),
      onPointerMove: (_) => _activity(),
      child: Stack(
        children: [
          Offstage(
            offstage: covered,
            child: FocusScope(canRequestFocus: !covered, child: widget.child),
          ),
          if (covered)
            Positioned.fill(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Alberdi bloqueada',
                            style: TextStyle(fontSize: 22),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Desbloqueá con tu huella, rostro, PIN o patrón del teléfono. Tu trabajo sigue abierto.',
                            textAlign: TextAlign.center,
                          ),
                          if (_message != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                _message!,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy || _hidden ? null : _unlock,
                            child: Text(_busy ? 'Verificando…' : 'Desbloquear'),
                          ),
                          if (_verifyFailed && !_confirmExit) ...[
                            const SizedBox(height: 24),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _confirmExit = true),
                              child: const Text('Cerrar sesión'),
                            ),
                          ],
                          if (_verifyFailed && _confirmExit) ...[
                            const SizedBox(height: 24),
                            const Text(
                              'Se pierde lo que no se envió. ¿Cerrar sesión igual?',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                OutlinedButton(
                                  onPressed: () => setState(() => _confirmExit = false),
                                  child: const Text('No'),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(foregroundColor: AppColors.rojo),
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await widget.signOut();
                                        },
                                  child: const Text('Sí, cerrar sesión'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
