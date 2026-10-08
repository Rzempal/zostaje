import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../controllers/budget_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recovery_code_dialog.dart';
import '../widgets/settings_widgets.dart';

/// Decyzja przy laczeniu konta, na ktorym juz lezy kopia.
enum _CloudConnectChoice { restore, overwrite, nothing }

/// Ekran backupu — kopia na koncie Google, eksport (kod / haslo), import.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isBusy = false;

  final _cloud = CloudBackupService.instance;
  bool _cloudBusy = false;
  String? _cloudEmail;
  DateTime? _cloudLastBackup;

  @override
  void initState() {
    super.initState();
    _refreshCloudState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          _buildCloudGroup(),
          SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.upload),
                title: const Text('Eksportuj backup'),
                subtitle: const Text(
                  'Zaszyfrowany kodem odzyskiwania — odtworzysz go także '
                  'na nowym telefonie',
                ),
                trailing: _isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.chevronRight),
                onTap: _isBusy ? null : _export,
              ),
              ListTile(
                leading: const Icon(LucideIcons.key),
                title: const Text('Pokaż kod odzyskiwania'),
                subtitle: const Text(
                  'Potrzebny do otwarcia kopii na innym urządzeniu',
                ),
                trailing: _isBusy ? null : const Icon(LucideIcons.chevronRight),
                onTap: _isBusy ? null : _showRecoveryCode,
              ),
              ListTile(
                leading: const Icon(LucideIcons.uploadCloud),
                title: const Text('Eksportuj z hasłem'),
                subtitle: const Text('Do przenoszenia między urządzeniami'),
                trailing: _isBusy ? null : const Icon(LucideIcons.chevronRight),
                onTap: _isBusy ? null : _exportWithPassword,
              ),
              ListTile(
                leading: const Icon(LucideIcons.download),
                title: const Text('Importuj backup'),
                subtitle: const Text(
                  'Przywróć z pliku .zostaje (lub starego .subkarton)',
                ),
                trailing: _isBusy ? null : const Icon(LucideIcons.chevronRight),
                onTap: _isBusy ? null : _import,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Kopia na koncie Google ─────────────────────────────────────────────────

  Widget _buildCloudGroup() {
    final connected = _cloudEmail != null;
    return SettingsGroup(
      children: [
        ListTile(
          leading: _cloudBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.cloud),
          title: const Text('Kopia na koncie Google'),
          subtitle: Text(
            connected
                ? '$_cloudEmail\n${_cloudStatusLine()}'
                : 'Kopia robi się sama i wraca po zalogowaniu na nowym '
                      'telefonie — bez przepisywania kodu',
          ),
          isThreeLine: connected,
          trailing: _cloudBusy ? null : const Icon(LucideIcons.chevronRight),
          onTap: _cloudBusy
              ? null
              : (connected ? _backupToCloudNow : _connectCloud),
        ),
        if (connected) ...[
          ListTile(
            leading: const Icon(LucideIcons.downloadCloud),
            title: const Text('Przywróć z chmury'),
            trailing: _cloudBusy ? null : const Icon(LucideIcons.chevronRight),
            onTap: _cloudBusy ? null : _restoreFromCloud,
          ),
          ListTile(
            leading: const Icon(LucideIcons.logOut),
            title: const Text('Odłącz konto'),
            subtitle: const Text('Kopie w chmurze zostaną nietknięte'),
            trailing: _cloudBusy ? null : const Icon(LucideIcons.chevronRight),
            onTap: _cloudBusy ? null : _disconnectCloud,
          ),
        ],
      ],
    );
  }

  String _cloudStatusLine() {
    final last = _cloudLastBackup;
    if (last == null) return 'Kopii jeszcze nie było';
    return 'Ostatnia kopia: ${DateFormat('d MMMM, HH:mm', 'pl').format(last)}';
  }

  Future<void> _refreshCloudState() async {
    if (!_cloud.isConnected) await _cloud.restoreSession();
    final last = await _cloud.lastBackupAt();
    if (!mounted) return;
    setState(() {
      _cloudEmail = _cloud.accountEmail;
      _cloudLastBackup = last;
    });
  }

  /// Laczy konto. Kopia NIE jest wysylana automatycznie, gdy w chmurze cos juz
  /// lezy — inaczej podlaczenie konta po wyczyszczeniu danych nadpisaloby
  /// dobra kopie pustka. O tym, co ma wygrac, decyduje uzytkownik.
  Future<void> _connectCloud() async {
    setState(() => _cloudBusy = true);
    try {
      if (!await _cloud.connect()) return; // anulowano

      final snapshots = await _cloud.listSnapshots();
      if (snapshots.isEmpty) {
        await _uploadToCloud();
        if (mounted) _showInfo('Konto połączone, kopia zapisana');
        return;
      }

      final counts = await _cloud.peekCounts(snapshots.first.id);
      if (!mounted) return;
      final choice = await _askWhatToDoWithExistingBackup(
        snapshots.first,
        counts,
      );
      switch (choice) {
        case _CloudConnectChoice.restore:
          await _restoreSnapshot(snapshots.first);
        case _CloudConnectChoice.overwrite:
          await _uploadToCloud();
          if (mounted) _showInfo('Kopia w chmurze zastąpiona');
        case _CloudConnectChoice.nothing:
        case null:
          // Bez decyzji nie zostawiamy polaczonego konta - automat wyslalby
          // zawartosc telefonu w ciagu doby.
          await _cloud.disconnect();
          if (mounted) _showInfo('Konto odłączone. W chmurze bez zmian.');
      }
    } catch (e) {
      if (mounted) _showError('Nie udało się połączyć konta: $e');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
      await _refreshCloudState();
    }
  }

  Future<void> _disconnectCloud() async {
    await _cloud.disconnect();
    await _refreshCloudState();
    if (mounted) _showInfo('Konto odłączone. Kopie w chmurze zostały nietknięte.');
  }

  Future<void> _backupToCloudNow() async {
    setState(() => _cloudBusy = true);
    try {
      await _uploadToCloud();
      if (mounted) _showInfo('Kopia zapisana na koncie Google');
    } catch (e) {
      if (mounted) _showError('Nie udało się zapisać kopii: $e');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
      await _refreshCloudState();
    }
  }

  Future<void> _uploadToCloud() async {
    final backup = context.read<BackupService>();
    final crypto = BackupCryptoService();
    await _cloud.uploadSnapshot(
      await backup.buildEncryptedSnapshot(),
      recoveryCode: await crypto.getOrCreateRecoveryCode(),
      now: DateTime.now(),
    );
  }

  Future<void> _restoreFromCloud() async {
    setState(() => _cloudBusy = true);
    try {
      final snapshots = await _cloud.listSnapshots();
      if (snapshots.isEmpty) {
        _showError('Na koncie Google nie ma jeszcze żadnej kopii');
        return;
      }
      await _restoreSnapshot(snapshots.first);
    } catch (e) {
      if (mounted) _showError('Nie udało się przywrócić kopii: $e');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  /// Kod odzyskiwania bierzemy z chmury, wiec na nowym telefonie nie ma pytan.
  /// Dalej idzie ta sama sciezka importu co dla pliku z dysku.
  Future<void> _restoreSnapshot(CloudSnapshot snapshot) async {
    final crypto = BackupCryptoService();
    final code = await _cloud.downloadRecoveryCode();
    if (code != null) await crypto.adoptRecoveryCode(code);

    final bytes = await _cloud.download(snapshot.id);
    if (!mounted) return;

    final replace = await _askImportMode();
    if (replace == null) return;
    if (!mounted) return;

    final backup = context.read<BackupService>();
    final result = await backup.importFromBytes(
      BackupFileInfo(
        bytes: bytes,
        fileName: snapshot.name,
        format: crypto.detectFormat(bytes),
      ),
      replace: replace,
    );

    if (!mounted) return;
    context.read<SubscriptionController>().refresh();
    context.read<BudgetController>().refresh();
    _showInfo(
      replace
          ? 'Odtworzono z chmury: ${result.subscriptionsImported} subskrypcji'
          : 'Dodano z chmury: ${result.subscriptionsImported} subskrypcji',
    );
  }

  Future<_CloudConnectChoice?> _askWhatToDoWithExistingBackup(
    CloudSnapshot snapshot,
    ({int subscriptions, int budgetEntries})? counts,
  ) {
    final date = DateFormat('d MMMM, HH:mm', 'pl').format(snapshot.createdAt);
    final storage = context.read<StorageService>();
    final localSubs = storage.getSubscriptions().length;
    final cloudLine = counts == null
        ? 'W chmurze: kopia z $date (nie udało się odczytać zawartości)'
        : 'W chmurze: ${counts.subscriptions} subskrypcji, '
              '${counts.budgetEntries} pozycji budżetu ($date)';

    return showDialog<_CloudConnectChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          icon: Icon(
            LucideIcons.cloud,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          title: const Text('Na koncie jest już kopia'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cloudLine\nW tym telefonie: $localSubs subskrypcji',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Która wersja ma być tą aktualną?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _choiceTile(
                  icon: LucideIcons.downloadCloud,
                  title: 'Wczytaj kopię z chmury',
                  subtitle:
                      'Dane z chmury trafią do tego telefonu. Zapytamy '
                      'jeszcze, czy dodać je do obecnych, czy zastąpić.',
                  choice: _CloudConnectChoice.restore,
                  highlighted: true,
                ),
                _choiceTile(
                  icon: LucideIcons.smartphone,
                  title: 'Wyślij zawartość tego telefonu',
                  subtitle:
                      'To, co masz w telefonie, stanie się najnowszą kopią. '
                      'Poprzednie kopie zostają — trzymamy trzy ostatnie.',
                  choice: _CloudConnectChoice.overwrite,
                ),
                _choiceTile(
                  icon: LucideIcons.x,
                  title: 'Rezygnuję',
                  subtitle:
                      'Konto zostanie odłączone, w chmurze nic się nie zmieni.',
                  choice: _CloudConnectChoice.nothing,
                ),
              ],
            ),
          ),
          actions: const [],
        );
      },
    );
  }

  Widget _choiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required _CloudConnectChoice choice,
    bool highlighted = false,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final color = highlighted
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
        return InkWell(
          onTap: () => Navigator.pop(context, choice),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: highlighted ? color : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    // Pierwszy eksport: pokaz kod i kaz go zachowac PRZED zapisem kopii.
    // Gdy kod siedzi juz w sejfie konta Google, okno tylko informuje.
    final crypto = BackupCryptoService();
    final hadCode = await crypto.getRecoveryCode() != null;
    if (!hadCode) {
      final code = await crypto.getOrCreateRecoveryCode();
      final backedUp = await crypto.isCodeBackedUpToAccount();
      if (!mounted) return;
      final saved = await showRecoveryCodeDialog(
        context,
        code,
        firstTime: true,
        backedUp: backedUp,
      );
      if (saved != true) return; // anulowano — bez kodu nie ma kopii
    }

    setState(() => _isBusy = true);
    try {
      if (!mounted) return;
      await context.read<BackupService>().exportWithRecoveryCode();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showRecoveryCode() async {
    final crypto = BackupCryptoService();
    final code = await crypto.getOrCreateRecoveryCode();
    final backedUp = await crypto.isCodeBackedUpToAccount();
    if (!mounted) return;
    await showRecoveryCodeDialog(
      context,
      code,
      firstTime: false,
      backedUp: backedUp,
    );
  }

  Future<void> _exportWithPassword() async {
    final password = await _askPassword(
      title: 'Ustaw hasło backupu',
      confirm: true,
    );
    if (password == null || password.isEmpty) return;
    setState(() => _isBusy = true);
    try {
      // ignore: use_build_context_synchronously
      await context.read<BackupService>().exportWithPassword(password);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _isBusy = true);
    try {
      final backup = context.read<BackupService>();
      final fileInfo = await backup.pickFile();

      // Tryb importu PRZED hasłem: to decyzja o danych, więc pytamy o nią
      // zanim użytkownik zacznie cokolwiek wpisywać.
      if (!mounted) return;
      final replace = await _askImportMode();
      if (replace == null) {
        if (mounted) setState(() => _isBusy = false);
        return;
      }

      // Kopie zrobione na tym telefonie otwiera kod odzyskiwania — wtedy
      // nie ma o co pytac. Pytamy tylko o cudze pliki chronione haslem.
      String? password;
      if (await backup.needsPasswordPrompt(fileInfo) && mounted) {
        password = await _askPassword(title: 'Hasło lub kod odzyskiwania');
        if (password == null) {
          if (mounted) setState(() => _isBusy = false);
          return;
        }
      }

      final result = await backup.importFromBytes(
        fileInfo,
        password: password,
        replace: replace,
      );

      if (mounted) {
        context.read<SubscriptionController>().refresh();
        context.read<BudgetController>().refresh();
        final parts = [
          '${result.subscriptionsImported} subskrypcji',
          '${result.categoriesImported} kategorii',
          if (result.paymentMethodsImported > 0)
            '${result.paymentMethodsImported} metod płatności',
          if (result.budgetEntriesImported > 0)
            '${result.budgetEntriesImported} pozycji budżetu',
        ];
        // Uczciwe podsumowanie: przy odtworzeniu mówimy WPROST, ile pozycji
        // usunięto — inaczej różnica w sumach byłaby zagadką.
        final head = result.replaced
            ? 'Odtworzono z pliku (usunięto ${result.removedBeforeRestore} '
                  'wcześniejszych pozycji)'
            : 'Scalono z obecnymi danymi';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$head: ${parts.join(', ')}')),
        );
      }
    } on FormatException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Wybór trybu importu. `true` = odtworzenie stanu z pliku, `false` = scalenie,
  /// `null` = anulowano.
  Future<bool?> _askImportMode() async {
    var replace = true;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Jak wgrać backup?'),
          content: RadioGroup<bool>(
            groupValue: replace,
            onChanged: (v) => setLocal(() => replace = v!),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<bool>(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Odtwórz stan z pliku'),
                  subtitle: Text(
                    'Aplikacja będzie miała dokładnie to, co w backupie. '
                    'Pozycje dodane po jego zrobieniu ZNIKNĄ.',
                  ),
                ),
                RadioListTile<bool>(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Scal z obecnymi danymi'),
                  subtitle: Text(
                    'Dokłada zawartość pliku do tego, co już jest. Pozycje '
                    'spoza pliku zostają — sumy mogą być wyższe niż w źródle.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, replace),
              child: const Text('Dalej'),
            ),
          ],
        ),
      ),
    );
  }

  /// Pyta o hasło. [confirm] dokłada drugie pole — przy eksporcie literówki nie
  /// da się wykryć później: plik zaszyfrowany błędnym hasłem otworzy się TYM
  /// błędnym hasłem, więc powtórzenie to jedyna kontrola.
  Future<String?> _askPassword({
    required String title,
    bool confirm = false,
  }) async {
    final ctrl = TextEditingController();
    final repeatCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final pass = ctrl.text;
          final repeat = repeatCtrl.text;
          final mismatch = confirm && repeat.isNotEmpty && pass != repeat;
          final canSave =
              pass.isNotEmpty && (!confirm || (pass == repeat && repeat.isNotEmpty));
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Hasło'),
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: repeatCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Powtórz hasło',
                      errorText: mismatch ? 'Hasła są różne' : null,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Zapamiętaj to hasło. Bez niego pliku nie da się odczytać — '
                    'nie ma sposobu na jego odzyskanie.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: canSave ? () => Navigator.pop(ctx, ctrl.text) : null,
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Błąd: $msg'),
        backgroundColor: context.semanticColors.negative,
      ),
    );
  }
}
