import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/backend_manager.dart';
import '../../../core/services/desktop_auto_setup.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.user,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    Map<String, dynamic>? user,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;

  AuthNotifier(this._api) : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> checkAuthStatus() => _checkAuth();

  Future<void> _checkAuth() async {
    // For desktop embedded mode, auto-setup creates and logs in a local user
    if (DesktopAutoSetup.shouldAutoSetup) {
      await DesktopAutoSetup.ensureSetup(_api);
    }

    final token = await ApiClient.getToken();
    if (token != null) {
      try {
        final resp = await _api.dio.get('/auth/me');
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
          user: resp.data,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
          state = const AuthState(status: AuthStatus.unauthenticated);
        } else {
          // Network/timeout errors: keep token, assume authenticated
          state = AuthState(
            status: AuthStatus.authenticated,
            token: token,
          );
        }
      } catch (_) {
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
        );
      }
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password, {bool rememberLogin = true}) async {
    final backend = BackendManager();

    try {
      state = state.copyWith(error: null);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != email || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != email) {
            await backend.restart(accountId: email);
          } else if (!backend.isRunning) {
            await backend.start(accountId: email);
          }
          await backend.ready;
          if (backend.hasFailed) {
            state = state.copyWith(
              status: AuthStatus.unauthenticated,
            error: 'Local backend startup failed: ${backend.startupError ?? "Unknown error"}',
            );
            return false;
          }
        }
        _api.dio.options.baseUrl = backend.baseUrl;
      }

      final resp = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(email);

      if (rememberLogin) {
        await ApiClient.saveToken(token);
      } else {
        await ApiClient.clearToken();
      }

      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: resp.data['user'],
      );
      return true;
    } on DioException catch (e) {
      String msg;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        if (BackendManager.shouldRunEmbedded) {
          if (!backend.isRunning) {
            msg = 'The local backend is not started. Please click "Enter local mode" to start the backend service first.';
          } else if (backend.hasFailed) {
        msg = 'Local backend startup failed: ${backend.startupError ?? "Check the app logs"}';
          } else {
            msg = 'Local backend health check failed (${backend.baseUrl}), please try again later';
          }
        } else {
          msg = 'Unable to connect to server, please check network connection';
        }
      } else {
        msg = (e.response?.data?['error'] ?? 'Login failed').toString();
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: msg,
      );
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    final backend = BackendManager();

    try {
      state = state.copyWith(error: null);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != email || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != email) {
            await backend.restart(accountId: email);
          } else if (!backend.isRunning) {
            await backend.start(accountId: email);
          }
          await backend.ready;
          if (backend.hasFailed) {
            state = state.copyWith(
            error: 'Local backend startup failed: ${backend.startupError ?? "Unknown error"}',
            );
            return false;
          }
        }
        _api.dio.options.baseUrl = backend.baseUrl;
      }

      final resp = await _api.dio.post('/auth/register', data: {
        'display_name': name,
        'email': email,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(email);
      await ApiClient.saveToken(token);

      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: resp.data['user'],
      );
      return true;
    } on DioException catch (e) {
      String msg;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        if (BackendManager.shouldRunEmbedded) {
          if (!backend.isRunning) {
            msg = 'The local backend is not started. Please click "Enter local mode" to start the backend service first.';
          } else if (backend.hasFailed) {
        msg = 'Local backend startup failed: ${backend.startupError ?? "Check the app logs"}';
          } else {
            msg = 'Local backend health check failed (${backend.baseUrl}), please try again later';
          }
        } else {
          msg = 'Unable to connect to server, please check network connection';
        }
      } else {
        msg = (e.response?.data?['error'] ?? 'Registration failed').toString();
      }
      state = state.copyWith(error: msg);
      return false;
    }
  }

  Future<void> logout({bool clearData = false}) async {
    final email = await ApiClient.getActiveAccount();
    if (clearData) {
      if (email != null) {
        if (BackendManager.shouldRunEmbedded) {
          try {
            await BackendManager().stop();
            await BackendManager().deleteAccountData(email);
          } catch (e) {
            debugPrint('[Auth] Failed to delete account data: $e');
          }
        }
        await ApiClient.removeAccount(email);
      }
      await ApiClient.clearAllAccountData();
    } else {
      await ApiClient.clearToken();
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(api);
});
