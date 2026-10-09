import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/subscription.dart';
import '../models/category.dart';
import '../models/spending_allocation_item.dart';
import '../models/budget_entry.dart';
import '../models/plan_position.dart';
import 'backup_crypto_service.dart';
import 'plan_conversion.dart';
import 'storage_service.dart';
import 'app_logger.dart';

/// Wynik importu backupu
class BackupImportResult {
  final int subscriptionsImported;
  final int categoriesImported;
  final int paymentMethodsImported;
  final int budgetEntriesImported;

  /// Czy import odtwarzał stan z pliku (czyścił dane) — do podsumowania.
  final bool replaced;

  /// Ile pozycji (subskrypcje + budżet) usunięto przed odtworzeniem.
  final int removedBeforeRestore;

  BackupImportResult({
    required this.subscriptionsImported,
    required this.categoriesImported,
    this.paymentMethodsImported = 0,
    this.budgetEntriesImported = 0,
    this.replaced = false,
    this.removedBeforeRestore = 0,
  });
}

/// Wynik eksportu
class BackupExportResult {
  final String filePath;
  BackupExportResult(this.filePath);
}

/// Wynik odczytu pliku backupu (przed dekryptowaniem)
class BackupFileInfo {
  final Uint8List bytes;
  final String fileName;
  final BackupFormat format;
  BackupFileInfo({required this.bytes, required this.fileName, required this.format});

  bool get needsPassword =>
      format is EncryptedBackup &&
      (format as EncryptedBackup).keyType == BackupKeyType.password;

  bool get isDeviceKey =>
      format is EncryptedBackup &&
      (format as EncryptedBackup).keyType == BackupKeyType.device;
}

/// Orkiestracja eksportu/importu .subkarton.
/// BackupCryptoService zajmuje się szyfrowaniem,
/// ten serwis zajmuje się serializacją i plikami.
class BackupService {
  static final _log = AppLogger.get('BackupService');
  final BackupCryptoService _crypto;
  final StorageService _storage;

  BackupService(this._storage) : _crypto = BackupCryptoService();

  static const _fileExtension = 'zostaje';
  // Stare rozszerzenie — backupy sprzed zmiany nazwy nadal sie importuja.
  static const _legacyFileExtension = 'subkarton';

  // ── Eksport ────────────────────────────────────────────────────────────────

  /// Eksportuje backup zaszyfrowany kodem odzyskiwania i udostępnia go
  /// przez systemowe okno wysyłania.
  ///
  /// Zastąpiło szyfrowanie kluczem urządzenia: tamten klucz ginął razem
  /// z telefonem, czyli w jedynym scenariuszu, przed którym kopia ma chronić.
  /// Odczyt starych plików z kluczem urządzenia zostaje bez zmian.
  Future<void> exportWithRecoveryCode() async {
    final json = buildJsonPayloadForTest();
    final encrypted = await _crypto.encryptWithRecoveryCode(json);
    await _shareFile(encrypted);
    _log.info('Backup wyeksportowany (kod odzyskiwania)');
  }

  /// Bajty kopii bez zapisywania do pliku — dla kopii na koncie Google.
  Future<Uint8List> buildEncryptedSnapshot() =>
      _crypto.encryptWithRecoveryCode(buildJsonPayloadForTest());

  /// Eksportuje zaszyfrowany backup (hasłem użytkownika).
  Future<void> exportWithPassword(String password) async {
    final json = buildJsonPayloadForTest();
    final encrypted = _crypto.encryptWithPassword(json, password);
    await _shareFile(encrypted);
    _log.info('Backup wyeksportowany (password)');
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Otwiera file picker i zwraca info o pliku (bez dekryptowania).
  /// Rzuca wyjątek jeśli nie wybrano pliku lub format nieznany.
  Future<BackupFileInfo> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      throw const FormatException('Nie wybrano pliku');
    }

    final pickedFile = result.files.first;
    final lowerName = pickedFile.name.toLowerCase();
    if (!lowerName.endsWith('.$_fileExtension') &&
        !lowerName.endsWith('.$_legacyFileExtension')) {
      throw FormatException(
        'Nieprawidłowy plik. Wybierz plik kopii zapasowej (.$_fileExtension)',
      );
    }

    final bytes = pickedFile.bytes;
    if (bytes == null) {
      throw const FormatException('Nie udało się odczytać pliku');
    }

    final format = _crypto.detectFormat(bytes);
    return BackupFileInfo(
      bytes: bytes,
      fileName: pickedFile.name,
      format: format,
    );
  }

  /// Importuje dane z wcześniej odczytanego pliku.
  /// [replace] = odtworzenie stanu z pliku (czysci dane objete backupem).
  /// Domyslnie scalanie — zachowanie sprzed ADR-021.
  Future<BackupImportResult> importFromBytes(
    BackupFileInfo fileInfo, {
    String? password,
    bool replace = false,
  }) async {
    final format = fileInfo.format;
    String jsonString;

    if (format is PlainJsonBackup) {
      jsonString = format.jsonString;
    } else if (format is EncryptedBackup) {
      if (format.keyType == BackupKeyType.password) {
        jsonString = await _decryptPasswordBackup(format, password);
      } else {
        jsonString = await _crypto.decryptWithDeviceKey(format);
      }
    } else {
      throw const FormatException('Nieznany format pliku');
    }

    return await _applyJsonPayload(jsonString, replace: replace);
  }

  /// Czy trzeba pytać użytkownika o hasło. Kopie zrobione na tym telefonie
  /// otwierają się kodem odzyskiwania, więc pytanie byłoby zbędne.
  Future<bool> needsPasswordPrompt(BackupFileInfo fileInfo) async {
    if (!fileInfo.needsPassword) return false;
    return !await _opensWithLocalCode(fileInfo.format as EncryptedBackup);
  }

  Future<bool> _opensWithLocalCode(EncryptedBackup backup) async {
    final code = await _crypto.getRecoveryCode();
    if (code == null) return false;
    try {
      _crypto.decryptWithPassword(backup, code);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Kolejność: kod odzyskiwania z tego telefonu (cicho) → podane hasło →
  /// to samo hasło potraktowane jak kod wpisany luźno (małe litery, spacje).
  Future<String> _decryptPasswordBackup(
    EncryptedBackup backup,
    String? password,
  ) async {
    final code = await _crypto.getRecoveryCode();
    if (code != null) {
      try {
        return _crypto.decryptWithPassword(backup, code);
      } on FormatException {
        // Kopia z innego telefonu — potrzebne hasło albo cudzy kod.
      }
    }

    if (password == null || password.isEmpty) {
      throw const FormatException('Ten backup wymaga hasła lub kodu odzyskiwania');
    }

    try {
      return _crypto.decryptWithPassword(backup, password);
    } on FormatException {
      final asCode = BackupCryptoService.normalizeRecoveryCodeCandidate(password);
      if (asCode != null) return _crypto.decryptWithPassword(backup, asCode);
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Tresc kopii przed zaszyfrowaniem. Publiczne wylacznie dla strazniku
  /// formatu (	est/storage_format_guard_test.dart) — klucze tego JSON-a sa
  /// formatem pliku .zostaje.
  @visibleForTesting
  String buildJsonPayloadForTest() {
    final subs = _storage.getSubscriptions();
    final cats = _storage.getCategories();
    final pms = _storage.getPaymentMethods();
    final budget = _storage.getBudgetEntries(BudgetScope.personal);
    final household = _storage.getBudgetEntries(BudgetScope.household);
    return jsonEncode({
      // v8 (ADR-035): plan roczny w `planPositions`. Stara aplikacja odrzuca
      // wersję > 7, zanim cokolwiek skasuje — nie wczyta pliku bez planu.
      'version': 8,
      'exportDate': DateTime.now().toIso8601String(),
      'subscriptions': subs.map((s) => s.toJson()).toList(),
      'categories': cats
          .where((c) => !defaultCategories.any((d) => d.id == c.id))
          .map((c) => c.toJson())
          .toList(),
      // Pełna lista metod płatności (nie pomijamy defaultów — po
      // rename zachowują ten sam ID, ale zmienioną nazwę, więc filtr po ID
      // byłby błędny). Przy imporcie upsert po ID.
      'paymentMethods': pms.map((pm) => pm.toJson()).toList(),
      // Budżet osobisty (lokalny) i domowy (osobny zbiór, przyszła synchronizacja).
      'budgetEntries': budget.map((e) => e.toJson()).toList(),
      'householdBudgetEntries': household.map((e) => e.toJson()).toList(),
      // Lokalny stan „wykonane" płatności (klucz: scope|sourceId|YYYY-MM-DD).
      'paymentDone': _storage.getAllPaymentDone(),
      // Planner („Na biezace wydatki") — pomniejsza plan „zostaje/mies", wiec
      // bez niego odtworzony budzet pokazywalby inne liczby (wersja 6).
      // Klucz `billsAllocation` to FORMAT PLIKU kopii — nie zmieniac (ADR-032).
      'billsAllocation': {
        for (final scope in BudgetScope.values)
          scope.name: _storage
              .getSpendingAllocationItems(scope)
              .map((e) => e.toJson())
              .toList(),
      },
      // Preferencje użytkownika, które zmieniają liczby albo działanie apki
      // (waluta, limit, tryb budżetu, powiadomienia, asystent, motyw) — v7.
      'settings': _storage.exportSettings(),
      // Plan roczny (v8, ADR-035) — wszystkie budżety. Stare sekcje wyżej
      // zostają jako archiwum: z nich powstał plan i z nich korzysta powrót
      // do poprzedniej wersji aplikacji.
      'planPositions': _storage
          .getPlanPositions()
          .map((p) => p.toJson())
          .toList(),
      // Plan z okresami pozycji (raty, starty) — import nie uzupełnia ich
      // wtedy ze starych pozycji. Kopia bez tego znacznika dostaje okresy
      // po wczytaniu.
      'planPeriods': true,
    });
  }

  /// [replace] = odtworzenie stanu z pliku: dane objęte backupem są najpierw
  /// czyszczone. Bez tego import jest SCALANIEM — pozycje, których nie ma
  /// w pliku, zostają w aplikacji i doliczają się do sum (ADR-021).
  Future<BackupImportResult> _applyJsonPayload(
    String jsonString, {
    required bool replace,
  }) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final version = data['version'] as int? ?? 1;
    if (version > 8) {
      throw FormatException('Nieobsługiwana wersja backupu: $version');
    }
    // Liczba pozycji usuniętych przy odtwarzaniu — do uczciwego podsumowania.
    var removed = 0;
    if (replace) {
      // Czyścimy WYŁĄCZNIE obszary, które ten plik potrafi odtworzyć. Starsze
      // formaty nie mają wszystkich pól, a kasowanie danych bez pokrycia
      // w pliku to utrata bez powrotu (na tym poległ Planner — ADR-021).
      final hasBudget = data['budgetEntries'] != null;
      final hasHousehold = data['householdBudgetEntries'] != null;
      if (hasBudget) {
        removed += _storage.getBudgetEntries(BudgetScope.personal).length;
      }
      if (hasHousehold) {
        removed += _storage.getBudgetEntries(BudgetScope.household).length;
      }
      removed += _storage.getSubscriptions().length;
      await _storage.clearForRestore(
        subscriptions: true, // obecne w każdej wersji formatu
        categories: true, // obecne w każdej wersji formatu
        budgetPersonal: hasBudget,
        budgetHousehold: hasHousehold,
        paymentDone: data['paymentDone'] != null,
        spendingAllocation: data['billsAllocation'] != null,
        planPositions: data['planPositions'] != null,
      );
    }

    int subsImported = 0;
    int catsImported = 0;
    int pmsImported = 0;
    int budgetImported = 0;

    final catsRaw = data['categories'] as List<dynamic>? ?? [];
    for (final c in catsRaw) {
      final cat = Category.fromJson(c as Map<String, dynamic>);
      await _storage.saveCategory(cat);
      catsImported++;
    }

    // Backupy w wersji 1 nie zawierały metod płatności — pole pominięte,
    // istniejące domyślne metody zostają bez zmian.
    final pmsRaw = data['paymentMethods'] as List<dynamic>? ?? [];
    for (final p in pmsRaw) {
      final pm = PaymentMethod.fromJson(p as Map<String, dynamic>);
      await _storage.savePaymentMethod(pm);
      pmsImported++;
    }

    final subsRaw = data['subscriptions'] as List<dynamic>? ?? [];
    for (final s in subsRaw) {
      final sub = Subscription.fromJson(s as Map<String, dynamic>);
      await _storage.saveSubscription(sub);
      subsImported++;
    }

    // Backupy w wersji < 3 nie zawierały pozycji budżetu — pole pominięte.
    final budgetRaw = data['budgetEntries'] as List<dynamic>? ?? [];
    for (final b in budgetRaw) {
      final entry = BudgetEntry.fromJson(b as Map<String, dynamic>);
      await _storage.saveBudgetEntry(entry, BudgetScope.personal);
      budgetImported++;
    }

    // Budżet domowy — backupy w wersji < 4 nie zawierały tego pola.
    final householdRaw = data['householdBudgetEntries'] as List<dynamic>? ?? [];
    for (final b in householdRaw) {
      final entry = BudgetEntry.fromJson(b as Map<String, dynamic>);
      await _storage.saveBudgetEntry(entry, BudgetScope.household);
      budgetImported++;
    }

    // Backupy < 5 nie zawierały stanu „wykonane" płatności — pole pominięte.
    final paymentDoneRaw = data['paymentDone'] as Map<String, dynamic>? ?? {};
    if (paymentDoneRaw.isNotEmpty) {
      await _storage.importPaymentDone(
        paymentDoneRaw.map((k, v) => MapEntry(k, v == true)),
      );
    }

    // Planner („Na bieżące wydatki") — backupy < 6 nie miały tego pola.
    final allocRaw = data['billsAllocation'] as Map<String, dynamic>?;
    if (allocRaw != null) {
      for (final scope in BudgetScope.values) {
        final list = allocRaw[scope.name] as List<dynamic>?;
        if (list == null) continue;
        final items = list
            .whereType<Map<String, dynamic>>()
            .map(SpendingAllocationItem.fromJson)
            .toList();
        // Scalanie: dokładamy tylko pozycje o nieznanym id, żeby nie kasować
        // planu, którego w pliku nie ma. Odtworzenie: lista z pliku wygrywa.
        if (replace) {
          await _storage.setSpendingAllocationItems(scope, items);
        } else {
          final current = _storage.getSpendingAllocationItems(scope);
          final known = current.map((e) => e.id).toSet();
          await _storage.setSpendingAllocationItems(scope, [
            ...current,
            ...items.where((e) => !known.contains(e.id)),
          ]);
        }
      }
    }

    // Ustawienia użytkownika — backupy < 7 nie miały tego pola. Zawsze
    // nadpisujemy (to preferencje, nie lista pozycji do scalania).
    final settingsRaw = data['settings'] as Map<String, dynamic>?;
    if (settingsRaw != null) {
      await _storage.importSettings(settingsRaw);
    }

    // Plan roczny (ADR-035). Kopia v8 niesie go sama: odtworzenie zastępuje
    // plan, scalenie dokłada/aktualizuje pozycje po identyfikatorze. Starsza
    // kopia planu nie ma — powstaje wtedy od razu ze starych pozycji, żeby
    // „Planowanie" nie pokazywało do restartu planu sprzed importu.
    final planRaw = data['planPositions'] as List<dynamic>?;
    if (planRaw != null) {
      for (final p in planRaw) {
        await _storage.savePlanPosition(
          PlanPosition.fromJson(p as Map<String, dynamic>),
        );
      }
      await _storage.setPlanConversionVersion(PlanConversion.version);
      await _storage.setPlanEnvelopeMigrated(true);
      // Kopia z wersji z okresami niesie je sama (także świadomie usunięte —
      // tych nie odtwarzamy). Kopia sprzed okresów dostaje je od razu.
      if (data['planPeriods'] == true) {
        await _storage.setPlanPeriodsMigrated(true);
      } else {
        await PlanConversionRunner(
          _storage,
        ).ensurePeriodsMigrated(Subscription.devDateOverride ?? DateTime.now());
      }
    } else if (budgetImported > 0 || removed > 0) {
      await PlanConversionRunner(
        _storage,
      ).reconvert(Subscription.devDateOverride ?? DateTime.now());
    }

    _log.info(
        'Import (${replace ? "odtworzenie" : "scalenie"}): $subsImported subs, '
        '$catsImported cats, $pmsImported payment methods, '
        '$budgetImported budget entries, usunieto $removed');
    return BackupImportResult(
      subscriptionsImported: subsImported,
      categoriesImported: catsImported,
      paymentMethodsImported: pmsImported,
      budgetEntriesImported: budgetImported,
      replaced: replace,
      removedBeforeRestore: removed,
    );
  }

  Future<void> _shareFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/zostaje-backup-$timestamp.$_fileExtension');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'Zostaje — backup',
    );

    // Plik tymczasowy — usuwamy po chwili
    Future.delayed(const Duration(minutes: 2), () {
      file.deleteSync();
    });
  }
}
