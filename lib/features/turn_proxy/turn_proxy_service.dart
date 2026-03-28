import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'turn_proxy_service.g.dart';

const _peerAddr = '193.160.208.54:56000';
const _listenAddr = '127.0.0.1:9000';

/// Имя бинарника в assets/bin/ для текущей платформы.
String? _assetBinaryName() {
  if (Platform.isAndroid) {
    // arm64 — подавляющее большинство устройств с 2016 года
    // armv7 — старые 32-битные устройства
    // Проверяем через размер указателя: arm64 = 8 байт
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
  bool build() => false; // false = не запущен

  /// Извлекает бинарник из assets в кеш-директорию и делает его исполняемым.
  Future<String> _extractBinary() async {
    final name = _assetBinaryName();
    if (name == null) throw UnsupportedError('Платформа не поддерживается');

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$name');

    // Перезаписываем при каждом обновлении приложения
    final data = await rootBundle.load('assets/bin/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', file.path]);
    }

    return file.path;
  }

  /// Запустить прокси с указанной VK ссылкой.
  Future<void> start(String vkLink) async {
    if (_process != null) return;

    final binaryPath = await _extractBinary();

    _process = await Process.start(binaryPath, [
      '-vk-link', vkLink,
      '-peer', _peerAddr,
      '-listen', _listenAddr,
    ]);

    _process!.stderr.listen((data) {
      // ignore stderr — vk-turn-client пишет туда обычные логи
    });

    // Если процесс неожиданно упал — сбрасываем состояние
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
  Future<void> restart(String vkLink) async {
    await stop();
    await start(vkLink);
  }
}
