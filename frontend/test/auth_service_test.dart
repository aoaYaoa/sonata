import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solara_flutter/data/api/api_client.dart';
import 'package:solara_flutter/services/auth_service.dart';

void main() {
  setUp(() {
    // shared_preferences 在单元测试里没有平台实现，
    // 不注入内存后端时 setString 会抛 MissingPluginException，
    // 让登录判定为失败。
    SharedPreferences.setMockInitialValues({});
  });

  test('login returns false when credentials are invalid', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'code': 401, 'message': '用户名或密码错误'},
              statusCode: 401,
            ),
          );
        },
      ),
    );

    final auth = AuthStateNotifier(
      client: ApiClient(baseUrl: 'https://example.com', dio: dio),
    );

    final ok = await auth.login('testuser', 'wrongpassword');

    expect(ok, isFalse);
    expect(auth.state.isAuthed, isFalse);
  });

  test('login returns true when credentials are valid', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              // 与后端 SolaraHandler.Login 的真实响应保持一致：
              // {"success": true, "data": {"token": "..."}}
              data: {
                'success': true,
                'data': {'token': 'test.jwt.token'},
              },
              statusCode: 200,
            ),
          );
        },
      ),
    );

    final auth = AuthStateNotifier(
      client: ApiClient(baseUrl: 'https://example.com', dio: dio),
    );

    final ok = await auth.login('testuser', 'correctpassword');

    expect(ok, isTrue);
    expect(auth.state.isAuthed, isTrue);
  });
}
