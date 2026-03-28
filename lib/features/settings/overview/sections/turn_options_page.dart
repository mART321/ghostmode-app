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
  late final TextEditingController _linkController;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(Preferences.vkTurnLink);
    _linkController = TextEditingController(text: saved);
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(turnProxyServiceProvider);
    final savedLink = ref.watch(Preferences.vkTurnLink);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('VK TURN')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Статус
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
                onChanged: savedLink.isEmpty
                    ? null
                    : (value) async {
                        final svc = ref.read(turnProxyServiceProvider.notifier);
                        if (value) {
                          await svc.start(savedLink);
                        } else {
                          await svc.stop();
                        }
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // VK ссылка
          Text(
            'VK Join Link',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _linkController,
            decoration: InputDecoration(
              hintText: 'https://vk.com/call/join/...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_rounded),
                onPressed: () async {
                  final link = _linkController.text.trim();
                  await ref.read(Preferences.vkTurnLink.notifier).update(link);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка сохранена')),
                  );
                  // Если прокси уже запущен — перезапускаем с новой ссылкой
                  if (isRunning) {
                    await ref.read(turnProxyServiceProvider.notifier).restart(link);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Получи ссылку в VK боте: нажми «Обход белых списков» и следуй инструкции.',
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
                  'При включении запускается фоновый процесс, который слушает '
                  '127.0.0.1:9000 и форвардит трафик через VK TURN серверы.',
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
