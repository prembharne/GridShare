import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'models/models.dart';
import 'services/api_service.dart';
import 'services/real_services.dart';

/// HTTP client provider (configure base URL + timeout + interceptors)
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

String get _resolvedApiBaseUrl {
  const envUrl = String.fromEnvironment('API_BASE_URL');
  if (envUrl.isNotEmpty) return envUrl;
  return 'http://localhost:8080';
}

final String apiBaseUrl = _resolvedApiBaseUrl;

/// Core API service
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: apiBaseUrl,
    client: ref.watch(httpClientProvider),
  );
});

/// Secure storage for JWT tokens
final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage());


/// Real service providers (swap MockOutletService → OutletService, etc.)
final outletServiceProvider = Provider<OutletService>((ref) => OutletService(ref.watch(apiServiceProvider)));
final sessionServiceProvider = Provider<SessionService>((ref) => SessionService(ref.watch(apiServiceProvider)));
final telemetryServiceProvider = Provider<TelemetryService>((ref) => TelemetryService());
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(apiServiceProvider), ref.watch(secureStorageProvider)));
final hostServiceProvider = Provider<HostService>((ref) => HostService(ref.watch(apiServiceProvider)));

/// Current user state (auth + wallet balance)
final currentUserProvider = StateProvider<User?>((_) => null);

/// Selected outlet for payment flow (passed via router extra)
/// No provider needed - passed as GoRoute.extra

/// Selected session for charging screen
/// No provider needed - passed as GoRoute.extra