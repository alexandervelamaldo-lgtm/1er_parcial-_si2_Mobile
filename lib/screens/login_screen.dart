import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}


class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'cliente@emergency.com');
  final _passwordController = TextEditingController(text: 'Password123*');
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();

    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Asistencia Vehicular',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('La app móvil está orientada a clientes y conductores.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Correo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Contraseña'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: sessionProvider.loading ? null : _submit,
                      child: Text(sessionProvider.loading ? 'Ingresando...' : 'Ingresar'),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final sessionProvider = context.read<SessionProvider>();
    setState(() => _errorMessage = null);
    try {
      await sessionProvider.login(_emailController.text.trim(), _passwordController.text.trim());
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      setState(() => _errorMessage = message.isNotEmpty ? message : 'No fue posible iniciar sesión.');
    }
  }
}
