import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ошибка сервера синхронизации — с понятным человеку текстом.
class SyncError implements Exception {
  const SyncError(this.code, this.message, {this.status = 0});

  final String code;
  final String message;
  final int status;

  /// Нет связи с сервером (ещё раз попробуем позже, данные не теряются).
  bool get offline => code == 'offline';

  /// Устройство отключили от гильдии (или гильдию удалили).
  bool get revoked => status == 401;

  @override
  String toString() => 'SyncError($code, $message)';
}

/// Транспорт до сервера: один адрес, POST с JSON {"op": …}.
abstract class SyncApi {
  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> body, {String? token});
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this.url, {http.Client? client}) : _client = client ?? http.Client();

  final String url;
  final http.Client _client;

  static const timeout = Duration(seconds: 25);

  @override
  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> body, {String? token}) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              // Не Authorization: его в Yandex Cloud Functions проверяет шлюз как IAM-токен.
              'X-Rodquest-Token': ?token,
            },
            body: jsonEncode({'op': op, ...body}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const SyncError('offline', 'Сервер не ответил — проверьте интернет');
    } catch (_) {
      throw const SyncError('offline', 'Нет связи с сервером — проверьте интернет');
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw SyncError('bad_reply', 'Сервер ответил непонятно (код ${res.statusCode})', status: res.statusCode);
    }
    if (res.statusCode != 200 || data['ok'] != true) {
      throw SyncError(
        data['error'] as String? ?? 'error',
        data['message'] as String? ?? 'Ошибка сервера (код ${res.statusCode})',
        status: res.statusCode,
      );
    }
    return data;
  }
}
