// services/api_service.dart
// import 'dart:convert';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/models/life_event.dart';
import 'package:dreamr/models/subscription.dart';
import 'dio_client.dart';
import 'package:dio/dio.dart';
import 'package:dreamr/constants.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dreamr/utils/log.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

void initDio(Dio dio) {
  if (!kReleaseMode) {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
  }
}

// ---- Quota exceptions ----
class QuotaExhaustedException implements Exception {
  final String kind;        // "text" | "image"
  final DateTime? nextReset;
  QuotaExhaustedException({required this.kind, this.nextReset});
  @override
  String toString() => 'QuotaExhausted($kind, next=$nextReset)';
}

// ---- Notes support (top-level) ----
class NotesConflict implements Exception {
  final Map<String, dynamic> current; // { id, notes, notes_updated_at }
  NotesConflict(this.current);
}

class NotesTooLarge implements Exception {
  const NotesTooLarge();
}

class NotesHttp implements Exception {
  final String message;
  final int? status;
  final dynamic body;
  const NotesHttp(this.message, this.status, this.body);
  @override
  String toString() => 'NotesHttp($status): $message';
}


Map<String, dynamic> _ensureMap(dynamic v, String when, int? status) {
  if (v is Map) return Map<String, dynamic>.from(v);
  throw NotesHttp('Unexpected payload for $when', status, v);
}


class ApiService {

  // Register using email + password
  static Future<String> register(String firstName, String email, String password) async {
      String timezone = await FlutterTimezone.getLocalTimezone();

      final response = await DioClient.dio.post(
        '/api/register',
        data: {
          'email': email,
          'password': password,
          'first_name': firstName,
          'timezone': timezone,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode == 200) {
        return "✅ Check your email to confirm your Dreamr✨ account.";
      } else {
        if (response.data is Map && response.data['error'] != null) {
          return "❌ ${response.data['error']}";
        } else if (response.data is String) {
          return "❌ ${response.data}";
        } else {
          return "❌ Registration failed.";
        }
      }
  }

  // Login or Register using email + password (soft-verify model)
  static Future<Map<String, dynamic>> loginOrRegister(String email, String password) async {
    final res = await DioClient.dio.post('/api/login_or_register',
      data: {'email': email, 'password': password},
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      throw Exception(res.data is Map && res.data['error'] != null
          ? res.data['error']
          : 'Email sign-in failed');
    }
    return Map<String, dynamic>.from(res.data['user'] ?? {});
  }

  // Start a guest session
  static Future<void> startGuestSession() async {
    final res = await DioClient.dio.post('/api/guest/start',
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      throw Exception(res.data is Map && res.data['error'] != null
          ? res.data['error']
          : 'Unable to start guest session');
    }
  }

  // Upgrade guest to email + password account
  static Future<Map<String, dynamic>> upgradeGuestToEmail({
    required String email,
    required String password,
  }) async {
    final res = await DioClient.dio.post('/api/guest/upgrade',
      data: {'email': email, 'password': password},
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      throw Exception(res.data is Map && res.data['error'] != null
          ? res.data['error']
          : 'Upgrade failed');
    }
    return Map<String, dynamic>.from(res.data['user'] ?? {});
  }

  // Login using email + password
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await DioClient.dio.post(
      '/api/login',
      data: {'email': email, 'password': password},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusMessage}');
    }
    return Map<String, dynamic>.from(response.data['user'] ?? {});
  }

  // Check authentication state
  // returns { authenticated: bool, is_guest: bool, email_verified: bool, auth_methods: [...], subscription_tier: 'free'|'pro' }
  static Future<Map<String, dynamic>> authState() async {
    final res = await DioClient.dio.get('/api/auth/state',
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      return {'authenticated': false};
    }
    return Map<String, dynamic>.from(res.data ?? {});
  }

  // Get user's subscription status
  static Future<SubscriptionStatus> getSubscriptionStatus() async {
    try {
      final res = await DioClient.dio.get('/api/subscription/status',
        // options: Options(validateStatus: (status) => status == 200),
      );
      debugPrint('SUB API status=${res.statusCode} url=${res.realUri}');
      debugPrint('SUB API headers auth=${res.requestOptions.headers['Authorization']}');
      debugPrint('SUB API body=${res.data}');

      final Map<String, dynamic> body =
        res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : {};

      // return SubscriptionStatus.fromJson(res.data);
      return SubscriptionStatus.fromJson(body);
    } catch (e) {
      // If there's an error, return a default free tier status
      return SubscriptionStatus.free();
    }
  }

  // Get available subscription plans
  static Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    try {
      logd('Fetching subscription plans from API...');
      final res = await DioClient.dio.get('/api/subscription/plans',
        options: Options(validateStatus: (status) => status == 200),
      );
      logd('API response status: ${res.statusCode}');
      logd('API response data: ${res.data}');
      
      if (res.data is! List) {
        logd('ERROR: API response is not a list. Type: ${res.data.runtimeType}');
        return [];
      }
      
      final List<dynamic> plansJson = res.data;
      logd('Number of plans in response: ${plansJson.length}');
      
      if (plansJson.isNotEmpty) {
        logd('First plan data: ${plansJson.first}');
      }
      
      try {
        final plans = plansJson.map((json) => SubscriptionPlan.fromJson(json)).toList();
        logd('Successfully parsed ${plans.length} plans');
        return plans;
      } catch (parseError) {
        logd('Error parsing subscription plans: $parseError');
        return [];
      }
    } catch (e) {
      logd('Error fetching subscription plans: $e');
      // Return empty list if there's an error
      return [];
    }
  }

  // Initiate a subscription purchase
  // For app store / play store, we also send provider + receipt to the backend.
  static Future<Map<String, dynamic>> initiateSubscription(
    String planId, {
    String? paymentProvider,
    String? receiptData,
  }) async {
    final payload = <String, dynamic>{
      'plan_id': planId,
      if (paymentProvider != null) 'payment_provider': paymentProvider,
      if (receiptData != null) 'receipt_data': receiptData,
    };

    try {
      final res = await DioClient.dio.post(
        '/api/subscription/purchase',
        data: payload,
        // Accept any status < 500 so we can inspect errors instead of throwing
        options: Options(validateStatus: (status) => status != null && status < 500),
      );

      if (res.statusCode != 200) {
        // Log and bubble a controlled error
        final data = res.data;
        debugPrint(
            'SUB: backend returned ${res.statusCode}: ${data is Map ? data['error'] : data}');
        throw Exception('Subscription initiate failed: HTTP ${res.statusCode}');
      }

      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      debugPrint('SUB: DioException ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  // Cancel a subscription
  static Future<bool> cancelSubscription() async {
    try {
      final res = await DioClient.dio.post('/api/subscription/cancel',
        options: Options(validateStatus: (status) => status == 200),
      );
      return res.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // Update payment method
  static Future<bool> updatePaymentMethod(Map<String, dynamic> paymentDetails) async {
    try {
      final res = await DioClient.dio.post('/api/subscription/payment-method',
        data: paymentDetails,
        options: Options(validateStatus: (status) => status == 200),
      );
      return res.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // Request password reset
  static Future<void> requestPasswordReset(String email) async {
    await DioClient.dio.post(
      '/api/request_password_reset',
      data: {'email': email},
      options: Options(validateStatus: (c) => c != null && c >= 200 && c < 300),
    );
  }

  // Reset password using token
  static Future<void> resetPassword(String token, String newPassword) async {
    await DioClient.dio.post(
      '/api/reset_password',
      data: {'token': token, 'new_password': newPassword},
      options: Options(validateStatus: (c) => c != null && c >= 200 && c < 300),
    );
  }

  // Change password (requires auth cookie/bearer via your interceptor)
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await DioClient.dio.post(
      '/api/change_password',
      data: {'current_password': currentPassword, 'new_password': newPassword},
      options: Options(validateStatus: (c) => c != null && c >= 200 && c < 300),
    );
  }

  // Google auth
  static Future<Map<String, dynamic>> googleLogin(String idToken) async {
    final res = await DioClient.dio.post('/api/google_login', data: {'id_token': idToken},
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      throw Exception(res.data is Map && res.data['error'] != null
          ? res.data['error']
          : 'Google login failed');
    }
    return Map<String, dynamic>.from(res.data['user'] ?? {});
  }

  // Apple auth
  static Future<void> appleLogin({
    required String identityToken,
    required String authorizationCode,
    required String userIdentifier,
    String? email,
    String? fullName,
  }) async {
    final res = await DioClient.dio.post(
      '/api/apple_login',
      data: {
        'identity_token': identityToken,
        'authorization_code': authorizationCode,
        'user_identifier': userIdentifier,
        'email': email,
        'full_name': fullName,
      },
      options: Options(validateStatus: (_) => true),
    );

    if (res.statusCode != 200) {
      throw Exception(
        res.data is Map && res.data['error'] != null
            ? res.data['error']
            : 'Apple login failed',
      );
    }
  }


  // Resend verification email
  static Future<void> resendVerificationEmail() async {
    final res = await DioClient.dio.post('/api/email/resend',
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) {
      throw Exception('Resend failed');
    }
  }

  // Link Google to existing account
  static Future<Map<String, dynamic>> linkGoogle(String idToken) async {
    final res = await DioClient.dio.post('/api/google/link',
      data: {'id_token': idToken},
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200) throw Exception('Link failed');
    return Map<String, dynamic>.from(res.data['user'] ?? {});
  }

  // Logout
  static Future<void> logout() async {
    // (Optional) tell the server to invalidate the session
    try { await DioClient.dio.post('/api/logout'); } catch (_) {}

    // Clear any persisted cookies
    await DioClient.clearCookies();

    // Optionally clear any auth headers you might set
    DioClient.dio.options.headers.remove('Authorization');
  }

  // Fetch dream journal (hidden = false)
  static Future<List<Dream>> fetchDreams() async {
    final response = await DioClient.dio.get('/api/dreams');

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((json) => Dream.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch dreams: ${response.statusMessage}');
    }
  }

  // Fetch dreams for Gallery
  static Future<List<Dream>> fetchGallery() async {
    final response = await DioClient.dio.get('/api/gallery');
    // final response = await DioClient.dio.get('/api/dreams');

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((json) => Dream.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch dreams: ${response.statusMessage}');
    }
  }

  // Fetch ALL dream journal (hidden = true)
  static Future<List<Dream>> fetchAllDreams() async {
    final response = await DioClient.dio.get('/api/alldreams');

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((json) => Dream.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch dreams: ${response.statusMessage}');
    }
  }

  // 🗑️ Delete a dream
  static Future<void> deleteDream(int dreamId) async {
    final response = await DioClient.dio.delete('/api/dreams/$dreamId');

    if (response.statusCode != 204) {
      throw Exception('Failed to delete dream: ${response.statusMessage}');
    }
  }

  // 👁️ Toggle hidden status
  static Future<bool> toggleHiddenDream(int dreamId) async {
    final response = await DioClient.dio.post('/api/dreams/$dreamId/toggle-hidden');

    if (response.statusCode == 200) {
      final data = response.data;
      return data['hidden'] == true; // returns the new hidden state
    } else {
      throw Exception('Failed to toggle hidden: ${response.statusMessage}');
    }
  }

  // Submit a dream to the AI
  static Future<Map<String, dynamic>> submitDream(String text) async {
    final response = await DioClient.dio.post(
      '/api/chat',
      data: {'message': text},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return {
        'analysis': data['analysis'] ?? '',
        'tone': data['tone'] ?? '',
        'dream_id': (data['dream_id'] ?? '').toString(),
        'is_question': data['is_question'] == true,
        'should_generate_image': data['should_generate_image'] == true,
      };
    }
    if (response.statusCode == 402) {
      final m = response.data is Map ? Map<String, dynamic>.from(response.data) : const {};
      final kind = (m['kind']?.toString() ?? 'text');
      final iso = m['next_reset_iso']?.toString();
      throw QuotaExhaustedException(
        kind: kind,
        nextReset: (iso != null && iso.isNotEmpty) ? DateTime.parse(iso) : null,
      );
    } else {
      throw Exception('Dream submission failed: ${response.statusMessage}');
    }
  }

  // Generate Image
  static Future<String> generateDreamImage(int dreamId) async {
    final t0 = DateTime.now();
    try {
      final res = await DioClient.dio.post(
        '/api/image_generate',
        data: {"dream_id": dreamId},
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
          // Treat 2xx as OK, but allow 202 so we can log it explicitly
          validateStatus: (s) => s != null && s >= 200 && s < 300 || s == 202,
        ),
      );

      logd('IMG API < ${res.statusCode} in ${DateTime.now().difference(t0).inMilliseconds}ms');
      logd('IMG API hdr: ${res.headers.map}');
      logd('IMG API body: ${_preview(res.data)}');

      if (res.statusCode == 202) {
        // Backend didn’t return a URL; client should NOT spin forever
        throw Exception('image_generate returned 202 (still processing)');
      }
      if (res.statusCode == 402) {
        final m = res.data is Map ? Map<String, dynamic>.from(res.data) : const {};
        throw QuotaExhaustedException(kind: (m['kind']?.toString() ?? 'image'));
      }
      if (res.statusCode != 200) {
        throw Exception('image_generate HTTP ${res.statusCode}');
      }

      // Be liberal about the key shape
      final data = res.data;
      String? url;
      if (data is Map) {
        // common cases: "image_url", "imagePath", "image", or image:{url:...}
        final img = data['image'];
        url = (data['image_url'] ??
               data['imagePath'] ??
               (img is String ? img : (img is Map ? img['url'] : null)))
              ?.toString();
      } else if (data is String) {
        // some servers return the URL as plain text
        url = data;
      }

      if (url == null || url.isEmpty) {
        throw Exception('image URL missing; keys=${data is Map ? data.keys.toList() : data.runtimeType}');
      }

      return _absoluteUrl(url);
    } on DioException catch (e) {
      logd('IMG API DIO ERROR: ${e.message} '
                 'status=${e.response?.statusCode} '
                 'body=${_preview(e.response?.data)}');
      rethrow;
    } catch (e, st) {
      logd('IMG API ERROR: $e\n$st');
      rethrow;
    }
  }

  // Delete User Account
  static Future<void> deleteAccount() async {
    final res = await DioClient.dio.post(
      '/api/delete_account',
      options: Options(validateStatus: (_) => true),
    );

    if (res.statusCode != 200) {
      throw Exception(
        res.data is Map && res.data['error'] != null
            ? res.data['error']
            : 'Failed to delete account',
      );
    }
  }


  // === Notes APIs ===

  /// GET /api/dreams/:id/notes
  /// Returns: { id, notes, notes_updated_at }
  static Future<Map<String, dynamic>> getDreamNotes(int dreamId) async {
    final res = await DioClient.dio.get(
      '/api/dreams/$dreamId/notes',
      options: Options(validateStatus: (_) => true),
    );

    final code = res.statusCode ?? 0;

    if (code == 200) {
      return _ensureMap(res.data, 'notes GET', code);
    }
    if (code == 401 || code == 403) {
      throw NotesHttp('Not authenticated', code, res.data);
    }
    throw NotesHttp('Notes fetch failed', code, res.data);
  }

  /// PATCH /api/dreams/:id/notes
  /// Pass `lastSeen` (ISO) for conflict detection; set `notes: null` to clear.
  /// Returns: { id, notes, notes_updated_at }
  static Future<Map<String, dynamic>> saveDreamNotes({
    required int dreamId,
    required String? notes,
    String? lastSeen,
  }) async {
    final body = <String, dynamic>{'notes': notes};
    if (lastSeen != null) {
      body['last_seen_notes_updated_at'] = lastSeen;
    }

    final res = await DioClient.dio.patch(
      '/api/dreams/$dreamId/notes',
      data: body,
      options: Options(validateStatus: (_) => true),
    );

    final code = res.statusCode ?? 0;

    if (code == 200) {
      return _ensureMap(res.data, 'notes PATCH', code);
    }
    if (code == 409) {
      final m = _ensureMap(res.data, 'notes conflict', code);
      final cur = _ensureMap(m['current'], 'notes conflict.current', code);
      throw NotesConflict(cur);
    }
    if (code == 413) {
      throw const NotesTooLarge();
    }
    if (code == 401 || code == 403) {
      throw NotesHttp('Not authenticated', code, res.data);
    }
    throw NotesHttp('Notes save failed', code, res.data);
  }

  // Fetch dreams updated since a given ISO timestamp
  static Future<List<Dream>> fetchDreamsUpdatedSince({
    String? updatedSinceIso,
    bool includeHidden = false,
  }) async {
    // TEMP fallback so nothing breaks until backend supports it:
    return includeHidden ? fetchAllDreams() : fetchDreams();
  }

  // — helpers —
  static String _absoluteUrl(String maybe) {
    // Return absolute HTTPS URL; don’t guess if baseUrl not set
    if (maybe.startsWith('http://') || maybe.startsWith('https://')) return maybe;
    
    // Dev-time sanity: your base must be absolute
    assert(
      AppConfig.baseUrl.startsWith('http'),
      'AppConfig.baseUrl must be an absolute http(s) URL. Got: ${AppConfig.baseUrl}',
    );
    
    final base = AppConfig.baseUrl; // e.g., "https://dreamr-us-west-01.zentha.me"
    if (base.isEmpty) return maybe;

    final hasSlashEnd = base.endsWith('/');
    final hasSlashStart = maybe.startsWith('/');

    if (hasSlashEnd && hasSlashStart) {
      return base.substring(0, base.length - 1) + maybe;
    } else if (!hasSlashEnd && !hasSlashStart) {
      return '$base/$maybe';
    } else {
      return '$base$maybe';
    }
  }

  static String _preview(dynamic body) {
    String s;
    try {
      s = body is String ? body : jsonEncode(body);
    } catch (_) {
      s = body?.toString() ?? '';
    }
    return s.length > 400 ? '${s.substring(0, 400)}…' : s;
  }


  // get user's profile
  static Future<Map<String, dynamic>> getProfile() async {
    final response = await DioClient.dio.get('/api/profile');

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(response.data ?? {});
      return {
        'email':      (data['email'] ?? '').toString(),
        'first_name': (data['first_name'] ?? '').toString(),
        'birthdate':  (data['birthdate'] ?? '').toString(),
        'gender':     (data['gender'] ?? '').toString(),
        'timezone':   (data['timezone'] ?? '').toString(),
        'avatar_url': (data['avatar_url'] ?? '').toString(),
        'enable_audio': data['enable_audio'] ?? '',
        'subscription_tier': data['subscription_tier'] ?? 'free',
      };
    } else {
      throw Exception('Profile fetch failed: ${response.statusMessage}');
    }
  }
  
  // save user's profile
  static Future<void> setProfile({
    String? email,
    required String firstName,
    String? gender,
    DateTime? birthdate,
    String? timezone,
    bool enableAudio = false,
    MultipartFile? avatarFile, // optional avatar
  }) async {
    final formDataMap = <String, dynamic>{
      // only append if not null
      if (email != null) 'email': email,
      'first_name': firstName,
      if (gender != null) 'gender': gender,
      if (birthdate != null) 'birthdate': birthdate.toIso8601String().split('T')[0], // backend expects yyyy-MM-dd
      if (timezone != null) 'timezone': timezone,
      'enable_audio': enableAudio ? '1' : '0',
      if (avatarFile != null) 'avatar': avatarFile,
    };

    final formData = FormData.fromMap(formDataMap);

    final response = await DioClient.dio.post(
      '/api/profile',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Profile update failed: ${response.statusMessage}');
    }
  }

  // used to fetch user's name from back end
  static Future<Map<String, dynamic>> checkAuth() async {
    final response = await DioClient.dio.get('/api/check_auth');
    return response.data;
  }

  // --- Life Events API Methods ---

  // Fetch all life events
  static Future<List<LifeEvent>> fetchLifeEvents() async {
    try {
      debugPrint('Fetching life events from API');
      final response = await DioClient.dio.get('/api/life-events',
        options: Options(validateStatus: (status) => true),
      );

      debugPrint('Fetch life events response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        if (response.data == null) {
          debugPrint('API returned null data for life events');
          return [];
        }
        
        // Backend returns { items: [...] } structure
        if (response.data is Map && response.data['items'] != null) {
          final List items = response.data['items'];
          debugPrint('API returned ${items.length} life events in items array');
          
          try {
            final events = items.map((json) => LifeEvent.fromJson(json)).toList();
            debugPrint('Successfully parsed ${events.length} life events');
            return events;
          } catch (parseError, stackTrace) {
            debugPrint('Error parsing life events: $parseError');
            debugPrint('Stack trace: $stackTrace');
            debugPrint('Response data sample: ${items.isNotEmpty ? items[0] : "empty"}');
            return [];
          }
        } else {
          debugPrint('API returned unexpected data structure: ${response.data.runtimeType}');
          return [];
        }
      } else {
        debugPrint('Failed to fetch life events: ${response.statusCode} - ${response.statusMessage}');
        debugPrint('Response data: ${response.data}');
        return []; // Return empty list instead of throwing to avoid crashing
      }
    } catch (e, stackTrace) {
      debugPrint('Exception fetching life events: $e');
      debugPrint('Stack trace: $stackTrace');
      return []; // Return empty list on error
    }
  }

  // Create a new life event
  static Future<LifeEvent?> createLifeEvent({
    required DateTime occurredAt,
    required String title,
    String? details,
    List<String>? tags,
  }) async {
    try {
      debugPrint('Creating life event: $title');
      
      final Map<String, dynamic> data = {
        'occurred_at': occurredAt.toIso8601String(),
        'title': title,
      };
      
      // Add optional fields only if they have values
      if (details != null && details.isNotEmpty) {
        data['details'] = details;
      }
      
      if (tags != null && tags.isNotEmpty) {
        data['tags'] = tags;  // Send as array, not comma-separated string
      }
      
      debugPrint('API request data: $data');
      
      final response = await DioClient.dio.post(
        '/api/life-events',
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (status) => true, // Handle all status codes
        ),
      );

      debugPrint('Create life event response status: ${response.statusCode}');
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (response.data == null) {
          debugPrint('API returned null data after creating life event');
          return null;
        }
        
        debugPrint('Life event created successfully, response: ${response.data}');
        
        try {
          final lifeEvent = LifeEvent.fromJson(response.data);
          debugPrint('Successfully parsed created life event with ID: ${lifeEvent.id}');
          return lifeEvent;
        } catch (parseError) {
          debugPrint('Error parsing created life event: $parseError');
          debugPrint('Response data: ${response.data}');
          return null; // Return null instead of throwing
        }
      } else {
        debugPrint('Failed to create life event: ${response.statusCode} - ${response.statusMessage}');
        debugPrint('Response data: ${response.data}');
        return null; // Return null instead of throwing
      }
    } catch (e, stackTrace) {
      debugPrint('Exception creating life event: $e');
      debugPrint('Stack trace: $stackTrace');
      return null; // Return null instead of throwing
    }
  }

  // Update an existing life event
  static Future<LifeEvent?> updateLifeEvent({
    required int id,
    DateTime? occurredAt,
    String? title,
    String? details,
    List<String>? tags,
  }) async {
    try {
      debugPrint('Updating life event ID: $id');
      
      final Map<String, dynamic> data = {};
      if (occurredAt != null) data['occurred_at'] = occurredAt.toIso8601String();
      if (title != null && title.isNotEmpty) data['title'] = title;
      if (details != null) data['details'] = details; // Can be empty to clear
      if (tags != null) data['tags'] = tags; // Send as array, not comma-separated
      
      debugPrint('API update data: $data');

      final response = await DioClient.dio.patch(
        '/api/life-events/$id',
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (status) => true,
        ),
      );

      debugPrint('Update life event response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        if (response.data == null) {
          debugPrint('API returned null data after updating life event');
          return null;
        }
        
        try {
          final updated = LifeEvent.fromJson(response.data);
          debugPrint('Successfully updated and parsed life event');
          return updated;
        } catch (parseError) {
          debugPrint('Error parsing updated life event: $parseError');
          debugPrint('Response data: ${response.data}');
          return null; // Return null instead of throwing
        }
      } else {
        debugPrint('Failed to update life event: ${response.statusCode} - ${response.statusMessage}');
        debugPrint('Response data: ${response.data}');
        return null; // Return null instead of throwing
      }
    } catch (e, stackTrace) {
      debugPrint('Exception updating life event: $e');
      debugPrint('Stack trace: $stackTrace');
      return null; // Return null instead of throwing
    }
  }

  // Delete a life event
  static Future<bool> deleteLifeEvent(int id) async {
    try {
      debugPrint('Deleting life event ID: $id');
      
      final response = await DioClient.dio.delete(
        '/api/life-events/$id',
        options: Options(validateStatus: (status) => true),
      );

      debugPrint('Delete life event response status: ${response.statusCode}');
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        debugPrint('Failed to delete life event: ${response.statusMessage}');
        debugPrint('Response data: ${response.data}');
        return false; // Return false instead of throwing
      }
      
      debugPrint('Life event deleted successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Exception deleting life event: $e');
      debugPrint('Stack trace: $stackTrace');
      return false; // Return false instead of throwing
    }
  }
}


