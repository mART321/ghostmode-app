import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/turn_proxy/turn_proxy_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TurnOptionsPage extends ConsumerStatefulWidget {
  const TurnOptionsPage({super.key});

  @override
  ConsumerState<TurnOptionsPage> createState() => _TurnOptionsPageState();
}

class _TurnOptionsPageState extends ConsumerState<TurnOptionsPage> {
  bool _refreshing = false;
  final _linkController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(turnProxyServiceProvider.notifier).refreshLinkInBackground();
    if (mounted) setState(() => _refreshing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка обновлена')),
    );
  }

  Future<void> _applyManualLink() async {
    final input = _linkController.text.trim();
    if (input.isEmpty) return;

    // Определяем: зашифрованная строка или plaintext ссылка
    final isEncrypted = !input.startsWith('http');
    final link = isEncrypted ? decryptLink(input) : input;

    await ref.read(Preferences.vkTurnLink.notifier).update(link);
    _linkController.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка применена')),
    );

    // Перезапускаем прокси с новой ссылкой если он был запущен
    final svc = ref.read(turnProxyServiceProvider.notifier);
    if (ref.read(turnProxyServiceProvider)) {
      await svc.restart(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(turnProxyServiceProvider);
    final savedLink = ref.watch(Preferences.vkTurnLink);
    final theme = Theme.of(context);

    // Показываем дефолтную ссылку если своя ещё не скачана
    const defaultLink = 'https://vk.com/call/join/TUXgOjIk7iVl1PgkTzNJYMIDLQBnZemmgbn-fOBYeOg';
    final activeLink = savedLink.isNotEmpty ? savedLink : defaultLink;
    final isDefault = savedLink.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Резервный канал')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Статус прокси
          Card(
            child: ListTile(
              leading: Icon(
                isRunning ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                color: isRunning ? Colors.green : theme.colorScheme.outline,
              ),
              title: const Text('Обход белых списков'),
              subtitle: Text(isRunning ? 'Прокси запущен (127.0.0.1:9000)' : 'Не запущен'),
              trailing: Switch.adaptive(
                value: isRunning,
                onChanged: (value) async {
                  final svc = ref.read(turnProxyServiceProvider.notifier);
                  if (value) {
                    await svc.start();
                  } else {
                    await svc.stop();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Статус ссылки
          Card(
            child: ListTile(
              leading: Icon(
                isDefault ? Icons.link_rounded : Icons.verified_rounded,
                color: isDefault ? theme.colorScheme.outline : Colors.green,
              ),
              title: Text(isDefault ? 'Встроенная ссылка' : 'Актуальная ссылка'),
              subtitle: Text(
                activeLink.length > 50
                    ? '${activeLink.substring(0, 50)}...'
                    : activeLink,
                style: theme.textTheme.bodySmall,
              ),
              trailing: _refreshing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Обновить с сервера',
                      onPressed: _refresh,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDefault
                ? 'Используется встроенная ссылка. Нажми ↻ для обновления (нужен интернет).'
                : 'Ссылка актуальна. Обновляется автоматически при наличии интернета.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 24),

          // Ручной ввод ссылки (резерв при белых списках)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вставить ссылку вручную',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Получи код активации в боте → «🔑 Резервный канал»',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _linkController,
                          decoration: const InputDecoration(
                            hintText: 'Вставь ссылку или зашифрованную строку',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _applyManualLink,
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Как это работает
          ExpansionTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Подробнее'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Резервный канал автоматически активируется при каждом подключении. '
                  'Работает даже при интернет-ограничениях.\n\n'
                  'Если стандартный VPN не подключается — используй этот конфиг. '
                  'При необходимости обнови код активации через VK бота.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
