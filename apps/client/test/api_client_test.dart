import 'package:client/core/api/api_client.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API client initializes its response cache in debug mode', () {
    final client = ApiClient(baseUrl: 'http://localhost:8080');
    addTearDown(() => client.dio.close(force: true));

    expect(
      client.dio.interceptors.whereType<DioCacheInterceptor>(),
      hasLength(1),
    );
  });
}
