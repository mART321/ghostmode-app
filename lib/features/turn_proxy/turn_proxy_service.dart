import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'turn_proxy_service.g.dart';

const _peerAddr = '193.160.208.54:56000';
const _listenAddr = '127.0.0.1:9000';

/// Дефолтная ссылка зашифрована и зашита в приложение.
/// Обновляется в фоне когда сервер доступен.
const _defaultVkLinkEncrypted = 'DARBNuSMQdxSAY0LfiBbhxIQv6tGD1gCOJCLCA5T4zgPR1wQ-4c-lE8-2SZbFDmtNzCCxkI6VAF6o7w-RHrGMz0VeiE=';

/// URL для получения свежей ссылки с сервера (через relay — российский IP).
const _turnLinkUrl = 'https://ghost-mode.ru:8443/turn-link';

/// XOR-ключ: SHA256("ghostmode-turn-v1") — совпадает с ключом на сервере.
const _cipherKey = <int>[
  0x64, 0x70, 0x35, 0x46, 0x97, 0xb6, 0x6e, 0xf3,
  0x24, 0x6a, 0xa3, 0x68, 0x11, 0x4d, 0x74, 0xe4,
  0x73, 0x7c, 0xd3, 0x84, 0x2c, 0x60, 0x31, 0x6c,
  0x17, 0xc4, 0xde, 0x50, 0x69, 0x1c, 0x89, 0x71,
];

/// Расшифровать VK ссылку полученную с сервера или из VK бота.
String decryptLink(String encrypted) {
  final data = base64Url.decode(encrypted);
  final result = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    result[i] = data[i] ^ _cipherKey[i % _cipherKey.length];
  }
  return utf8.decode(result);
}

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
      final raw = resp.data?['vk_link'] as String?;
      if (raw != null && raw.isNotEmpty) {
        final isEncrypted = resp.data?['encrypted'] == true;
        final fresh = isEncrypted ? decryptLink(raw) : raw;
        await ref.read(Preferences.vkTurnLink.notifier).update(fresh);
        return fresh;
      }
    } catch (_) {
      // Сервер недоступен (белые списки активны) — используем кеш
    }

    // Сохранённая ссылка из настроек
    final saved = ref.read(Preferences.vkTurnLink);
    if (saved.isNotEmpty) return saved;

    // Последний резерв — дефолтная зашифрованная из приложения
    return decryptLink(_defaultVkLinkEncrypted);
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
      final raw = resp.data?['vk_link'] as String?;
      if (raw != null && raw.isNotEmpty) {
        final isEncrypted = resp.data?['encrypted'] == true;
        final fresh = isEncrypted ? decryptLink(raw) : raw;
        await ref.read(Preferences.vkTurnLink.notifier).update(fresh);
        if (state) await restart(fresh);
      }
    } catch (_) {
      // Сервер недоступен — ничего не делаем, работаем с кешем
    }
  }
}
