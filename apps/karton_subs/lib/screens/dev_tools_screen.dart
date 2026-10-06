import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../controllers/receipt_scan_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_widgets.dart';
import 'plan_conversion_report_screen.dart';

/// Narzedzia deweloperskie (tylko kanal internal): override daty + testy powiadomien.
class DevToolsScreen extends StatelessWidget {
  const DevToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SubscriptionController>();
    final storage = context.read<StorageService>();
    final notifications = context.read<NotificationService>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Developer Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          const SettingsSectionLabel('Data testowa'),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.calendar),
                title: const Text('Override daty'),
                subtitle: Text(
                  storage.getDevDateOverride() != null
                      ? DateFormat(
                          'dd.MM.yyyy',
                        ).format(storage.getDevDateOverride()!)
                      : 'Wyłączony (używa aktualnej daty)',
                ),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => _showDevDatePicker(context, storage),
              ),
              if (storage.getDevDateOverride() != null)
                ListTile(
                  leading: const Icon(LucideIcons.x),
                  title: const Text('Wyłącz override daty'),
                  onTap: () {
                    storage.setDevDateOverride(null);
                    Subscription.devDateOverride = null;
                    ctrl.refresh();
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'TEST POWIADOMIEŃ',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.8,
                color: context.semanticColors.warning,
              ),
            ),
          ),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.clock),
                title: const Text('Trial reminder'),
                subtitle: const Text('Symuluje: trial kończy się za 3 dni'),
                onTap: () => _fire(
                  context,
                  notifications,
                  title: 'Trial Spotify kończy się za 3 dni',
                  body: 'Po trialu: 19,99 zł/mies',
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.calendarClock),
                title: const Text('Renewal reminder'),
                subtitle: const Text('Symuluje: odnowienie za 3 dni'),
                onTap: () => _fire(
                  context,
                  notifications,
                  title: 'Netflix odnawia się za 3 dni',
                  body: 'Kwota: 49,00 zł/mies',
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.ghost),
                title: const Text('Ghost warning'),
                subtitle: const Text('Symuluje: nieużywana >30 dni'),
                onTap: () => _fire(
                  context,
                  notifications,
                  title: 'Adobe CC — nieużywana od 30 dni',
                  body: 'Płacisz 239 zł/mies za coś, czego nie używasz.',
                ),
              ),
            ],
          ),
          const SettingsSectionLabel('Przebudowa: plan roczny'),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.gitCompare),
                title: const Text('Raport konwersji planu'),
                subtitle: const Text(
                  'Stary model budżetu vs nowy plan — sumy roku i różnice',
                ),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PlanConversionReportScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SettingsSectionLabel('Diagnostyka skanu'),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.fileText),
                title: const Text('Ostatni odczyt OCR'),
                subtitle: const Text(
                  'Surowy tekst, ktory model zwrocil dla ostatniego skanu',
                ),
                onTap: () => _showLastOcr(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Podglad surowego odczytu OCR.
  ///
  /// Reguly szybkiej sciezki dostaja tekst zlozony z BLOKOW, ktorych kolejnosc
  /// nie musi odpowiadac ukladowi na ekranie — bez tego podgladu kazda
  /// nietrafiona regula konczyla sie zgadywaniem ukladu i kolejnym wydaniem
  /// „na probe". Tekst zostaje na telefonie; stad da sie go tylko skopiowac.
  void _showLastOcr(BuildContext context) {
    final text = context.read<ReceiptScanController>().lastOcrText;
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Ostatni odczyt OCR'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty
                  ? 'Brak odczytu — zeskanuj cokolwiek szybka sciezka '
                        '(aparat, galeria albo „Udostepnij").'
                  : text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          if (text.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!dctx.mounted) return;
                Navigator.pop(dctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Skopiowano odczyt')),
                );
              },
              child: const Text('Kopiuj'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }

  void _showDevDatePicker(BuildContext context, StorageService storage) async {
    final current = storage.getDevDateOverride() ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Ustaw datę testową',
    );
    if (picked != null) {
      storage.setDevDateOverride(picked);
      Subscription.devDateOverride = picked;
      if (context.mounted) {
        context.read<SubscriptionController>().refresh();
      }
    }
  }

  void _fire(
    BuildContext context,
    NotificationService svc, {
    required String title,
    required String body,
  }) {
    svc.showTestNotification(title: title, body: body);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Wysłano: $title'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
