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

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(turnProxyServiceProvider.notifier).refreshLinkInBackground();
    if (mounted) setState(() => _refreshing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка обновлена')),
    );
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
      appBar: AppBar(title: const Text('VK TURN')),
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

          // Как это работает
          ExpansionTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Как это работает'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'VK TURN использует серверы видеозвонков ВКонтакте как туннель. '
                  'Их IP входит в белый список операторов РФ, поэтому трафик '
                  'проходит даже при блокировке стандартных VPN.\n\n'
                  'Ссылка на звонок хранится в приложении и обновляется в фоне '
                  'когда сервер доступен. При белых списках используется '
                  'последняя сохранённая ссылка.',
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
