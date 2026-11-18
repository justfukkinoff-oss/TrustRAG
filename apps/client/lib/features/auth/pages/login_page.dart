import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/backend_manager.dart';
import '../../../core/services/desktop_auto_setup.dart';
import '../../../core/services/mode_manager.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberLogin = true;
  bool _localAutoLoginAttempted = false;
  String? _localAutoLoginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
          rememberLogin: _rememberLogin,
        );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        context.go('/dashboard');
      }
    }
  }

  Future<void> _tryLocalAutoLogin() async {
    if (_localAutoLoginAttempted) return;
    _localAutoLoginAttempted = true;

    try {
      final bm = BackendManager();
      if (!kIsWeb && BackendManager.shouldRunEmbedded) {
        if (!bm.isRunning) {
          await bm.start(accountId: 'local@trustrag.desktop');
          await bm.ready;
          if (bm.hasFailed) {
            if (mounted) {
              setState(() => _localAutoLoginError = bm.startupError ?? 'Local backend startup failed');
            }
            return;
          }
        }

        final api = ref.read(apiClientProvider);
        api.dio.options.baseUrl = bm.baseUrl;
        await DesktopAutoSetup.ensureSetup(api);
      }

      ref.invalidate(authProvider);
      ref.read(authProvider.notifier).checkAuthStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _localAutoLoginError = '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final modeState = ref.watch(modeProvider);

    if (authState.status == AuthStatus.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/dashboard');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (authState.status == AuthStatus.unknown) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLocalMode = modeState.mode == AppMode.local;

    if (isLocalMode && !_localAutoLoginAttempted && _localAutoLoginError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLocalAutoLogin());
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Starting local service...', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    String modeLabel;
    IconData modeIcon;
    Color modeBadgeColor;
    if (isLocalMode) {
      modeLabel = 'local mode';
      modeIcon = Icons.computer_rounded;
      modeBadgeColor = Colors.green;
    } else {
      modeLabel = 'Server mode';
      modeIcon = Icons.cloud_rounded;
      modeBadgeColor = theme.colorScheme.primary;
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'TrustRAG',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isLocalMode
                      ? 'Trustworthy RAG knowledge workbench'
                  : 'Server: ${modeState.serverUrl ?? "Not configured"}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: modeBadgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: modeBadgeColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(modeIcon, size: 16, color: modeBadgeColor),
                        const SizedBox(width: 6),
                        Text(
                          modeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: modeBadgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_localAutoLoginError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Local service failed to start',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _localAutoLoginError!,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _localAutoLoginAttempted = false;
                              _localAutoLoginError = null;
                            });
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter your email';
                          if (!v.contains('@')) return 'Please enter a valid email address';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter password';
                          if (v.length < 8) return 'Password must be at least 8 characters';
                          return null;
                        },
                        onFieldSubmitted: (_) => _handleLogin(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _rememberLogin,
                        onChanged: (v) =>
                            setState(() => _rememberLogin = v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _rememberLogin = !_rememberLogin),
                      child: Text(
                        'Stay logged in',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                if (authState.error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      authState.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Login'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Don’t have an account yet?'),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Register'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await ref.read(modeProvider.notifier).resetMode();
                    if (context.mounted) context.go('/onboarding');
                  },
                  child: Text(
                    'Switch usage',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
