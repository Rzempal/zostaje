import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../controllers/budget_controller.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/update_inline_section.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'budgets_screen.dart';
import 'category_management_screen.dart';
import 'currency_screen.dart';
import 'data_export_screen.dart';
import 'dev_tools_screen.dart';
import 'notifications_screen.dart';
import 'payment_method_management_screen.dart';

/// Ekran Ustawien — lista nawigacyjna do osobnych ekranow (kazda sekcja = ekran).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 112),
        children: [
          const SettingsSectionLabel('Personalizacja'),
          SettingsGroup(children: [
            _navTile(context,
                icon: LucideIcons.palette,
                title: 'Wygląd',
                subtitle: 'Motyw aplikacji',
                screen: const AppearanceScreen()),
            _navTile(context,
                icon: LucideIcons.coins,
                title: 'Waluta i limit',
                screen: const CurrencyScreen()),
            _navTile(context,
                icon: LucideIcons.wallet,
                title: 'Budżety',
                subtitle: context
                    .watch<BudgetController>()
                    .visibleBudgets
                    .map((b) => b.name)
                    .join(', '),
                screen: const BudgetsScreen()),
            _navTile(context,
                icon: LucideIcons.bell,
                title: 'Powiadomienia',
                screen: const NotificationsScreen()),
            // Kategorie i metody płatności to słowniki, którymi użytkownik
            // opisuje SWÓJ budżet — bliżej im do personalizacji niż do sekcji
            // „Dane", gdzie mieszkają kopie i eksport.
            _navTile(context,
                icon: LucideIcons.tag,
                title: 'Zarządzaj kategoriami',
                screen: const CategoryManagementScreen()),
            _navTile(context,
                icon: LucideIcons.creditCard,
                title: 'Metody płatności',
                screen: const PaymentMethodManagementScreen()),
          ]),

          const SettingsSectionLabel('Dane'),
          SettingsGroup(children: [
            // „Asystent AI" i „Archiwum paragonów" zniknęły razem ze skanem
            // paragonów, „Budżet domowy" (synchronizacja) — bo nikt jej nie
            // używał; budżet udostępnia się arkuszem planu (ADR-035).
            _navTile(context,
                icon: LucideIcons.databaseBackup,
                title: 'Backup',
                subtitle: 'Kopia zapasowa i odtwarzanie',
                screen: const BackupScreen()),
            // Eksport do plików: wcześniej ikony XLSX/PDF w paskach ekranów.
            // Robi się go raz na jakiś czas, a zabierał miejsce przy codziennej
            // pracy — i był rozrzucony po dwóch ekranach.
            _navTile(context,
                icon: LucideIcons.fileSpreadsheet,
                title: 'Eksport/import danych',
                subtitle: 'Arkusz XLSX (w obie strony) i raport PDF',
                screen: const DataExportScreen()),
          ]),

          const SettingsSectionLabel('Aplikacja'),
          SettingsGroup(children: [
            const UpdateInlineSection(),
            _linkTile(
              icon: LucideIcons.shield,
              title: 'Polityka prywatności',
              subtitle: 'Co zostaje na telefonie, a co nie',
              url: AppConfig.privacyPolicyUrl,
            ),
            if (AppConfig.isInternal)
              _navTile(context,
                  icon: LucideIcons.wrench,
                  title: 'Developer Tools',
                  screen: const DevToolsScreen()),
          ]),
        ],
      ),
    );
  }

  /// Pozycja otwierajaca adres w przegladarce systemowej.
  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.externalLink, size: 16),
      onTap: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget screen,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
    );
  }
}
