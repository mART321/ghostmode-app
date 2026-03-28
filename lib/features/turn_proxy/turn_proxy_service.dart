import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'turn_proxy_service.g.dart';

const _peerAddr = '193.160.208.54:56000';
const _listenAddr = '127.0.0.1:9000';

/// Дефолтная ссылка зашита в приложение — работает без доступа к нашим серверам.
/// Обновляется в фоне когда сервер доступен.
const _defaultVkLink = 'https://vk.com/call/join/TUXgOjIk7iVl1PgkTzNJYMIDLQBnZemmgbn-fOBYeOg';

/// URL для получения свежей ссылки с сервера (через relay — российский IP).
const _turnLinkUrl = 'https://ghost-mode.ru:8443/turn-link';

/// Имя бинарника в assets/bin/ для текущей платформы.
String? _assetBinaryName() {
  if (Platform.isAndroid) {
    final is64 = Platform.version.contains('arm64') ||
        RegExp('aarch64|arm64').hasMatch(Platform.operatingSystemVersion);
    return is64
        ? 'vk-turn-client-android-arm64'
        : 'vk-turn-client-android-armv7';
  }
  if (Platform.isMacOS) {
    final arch = Process.runSync('uname', ['-m']).stdout.toString().trim();
    return arch == 'arm64'
        ? 'vk-turn-client-darwin-arm64'
        : 'vk-turn-client-darwin-amd64';
  }
  if (Platform.isWindows) return 'vk-turn-client-windows-amd64.exe';
  if (Platform.isLinux) return 'vk-turn-client-linux-amd64';
  return null;
}

@Riverpod(keepAlive: true)
class TurnProxyService extends _$TurnProxyService {
  Process? _process;

  @override
  bool build() => false;

  /// Извлекает бинарник из assets в кеш-директорию и делает его исполняемым.
  Future<String> _extractBinary() async {
    final name = _assetBinaryName();
    if (name == null) throw UnsupportedError('Платформа не поддерживается');

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$name');

    final data = await rootBundle.load('assets/bin/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', file.path]);
    }

    return file.path;
  }

  /// Получить актуальную VK ссылку:
  /// 1. Пробуем скачать свежую с сервера (если доступен)
  /// 2. Иначе берём сохранённую из настроек
  /// 3. Иначе используем дефолтную зашитую в приложение
  Future<String> _resolveLink() async {
    // Пробуем обновить с сервера
    try {
      final resp = await Dio().get<Map<String, dynamic>>(
        _turnLinkUrl,
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      final fresh = resp.data?['vk_link'] as String?;
      if (fresh != null && fresh.isNotEmpty) {
        await ref.read(Preferences.vkTurnLink.notifier).update(fresh);
        return fresh;
      }
    } catch (_) {
      // Сервер недоступен (белые списки активны) — используем кеш
    }

    // Сохранённая ссылка из настроек
    final saved = ref.read(Preferences.vkTurnLink);
    if (saved.isNotEmpty) return saved;

    // Последний резерв — дефолтная из приложения
    return _defaultVkLink;
  }

  /// Запустить прокси. Если ссылка не передана — определяет автоматически.
  Future<void> start([String? vkLink]) async {
    if (_process != null) return;

    final link = vkLink ?? await _resolveLink();
    final binaryPath = await _extractBinary();

    _process = await Process.start(binaryPath, [
      '-vk-link', link,
      '-peer', _peerAddr,
      '-listen', _listenAddr,
    ]);

    _process!.stderr.listen((_) {});

    _process!.exitCode.then((_) {
      _process = null;
      if (state) state = false;
    });

    state = true;
  }

  /// Остановить прокси.
  Future<void> stop() async {
    _process?.kill();
    _process = null;
    state = false;
  }

  /// Перезапустить (при смене ссылки).
  Future<void> restart([String? vkLink]) async {
    await stop();
    await start(vkLink);
  }

  /// Фоновое обновление ссылки (вызывать при старте приложения).
  /// Молча пробует скачать свежую ссылку с сервера и сохранить.
  Future<void> refreshLinkInBackground() async {
    try {
      final resp = await Dio().get<Map<String, dynamic>>(
        _turnLinkUrl,
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      final fresh = resp.data?['vk_link'] as String?;
      if (fresh != null && fresh.isNotEmpty) {
        await ref.read(Preferences.vkTurnLink.notifier).update(fresh);
        if (state) await restart(fresh);
      }
    } catch (_) {
      // Сервер недоступен — ничего не делаем, работаем с кешем
    }
  }
}
