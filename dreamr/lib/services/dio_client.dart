// services/dio_client.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dreamr/constants.dart';

/// Global offline state driven by Dio request outcomes.
/// true = last request failed with a connection error; false = online.
final ValueNotifier<bool> isOfflineNotifier = ValueNotifier(false);

class _ConnectivityInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    isOfflineNotifier.value = false;
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.error is SocketException) {
      isOfflineNotifier.value = true;
    } else {
      // Server responded (4xx/5xx) — we are online
      isOfflineNotifier.value = false;
    }
    handler.next(err);
  }
}

class DioClient {
  static late final Dio dio;
  static PersistCookieJar? _cookieJar;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final appDocDir = await getApplicationDocumentsDirectory();

    _cookieJar = PersistCookieJar(
      storage: FileStorage('${appDocDir.path}/.cookies/'),
      ignoreExpires: false, // keep Flask-Login "remember" cookie until it expires
    );

    dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
      validateStatus: (status) => status != null && status < 500,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));

    dio.interceptors.add(CookieManager(_cookieJar!));
    dio.interceptors.add(_ConnectivityInterceptor());
  }

  // Added so logout can actually clear the session
  static Future<void> clearCookies() async {
    await _cookieJar?.deleteAll();
  }

  // (optional) if you ever set an auth header, clear it too
  static void removeAuthHeader() {
    dio.options.headers.remove('Authorization');
  }

  static Dio get instance {
    if (!_initialized) {
      throw StateError('DioClient.init() must be called before use.');
    }
    return dio;
  }
}
