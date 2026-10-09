import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;

import '../models/budget_entry.dart';
import '../models/subscription.dart' show PaymentMethod;
import '../theme/app_theme.dart' show AppSemanticColors;

/// Ikona RODZAJU pozycji — pokazywana, gdy pozycja nie ma własnej kategorii.
///
/// Jedna reguła: **ikona wiersza = ikona zakładki, do której pozycja należy**
/// (ADR-032). Dzięki temu ta sama pozycja wygląda tak samo na liście, w
/// „Płatnościach" i w „Podsumowaniu miesiąca". Wcześniej reguła była
/// zduplikowana w dwóch miejscach i rozjechała się przy zmianie nazw: wydatek
/// bieżący dostawał strzałkę kierunku, czyli to samo co koszt cykliczny.
IconData budgetEntryIcon(BudgetEntryType type) => switch (type) {
  // „Bieżące" — ta sama ikona co w pasku nawigacji.
  BudgetEntryType.spending => lucide.LucideIcons.receiptText,
  // „Cykliczne" — powtarzalność jest sednem tej sekcji. Rata też tu należy:
  // to koszt cykliczny z końcem, a nie osobny rodzaj pieniędzy.
  BudgetEntryType.recurringCost ||
  BudgetEntryType.installment => LucideIcons.repeat,
  // „Wpływy".
  BudgetEntryType.income ||
  BudgetEntryType.oneTimeIncome => LucideIcons.trendingUp,
  // Przesunięcie między budżetami — nie koszt, więc ani strzałka w dół, ani
  // powtarzalność nie byłyby prawdą.
  BudgetEntryType.householdTransfer => LucideIcons.arrowRightLeft,
};

/// Ikona subskrypcji — `repeat` należy do zakładki „Cykliczne", więc
/// subskrypcja (jej sekcja) musi mieć własną (ADR-032).
const IconData subscriptionIcon = LucideIcons.badgeCheck;

/// Ikona metody płatności. **Kształt mówi, SKĄD pieniądze, kolor — KTO płaci**
/// (ADR-033):
///
/// | metoda | ikona | kolor |
/// |---|---|---|
/// | zwykła manualna | rączka | domyślny |
/// | zwykła automatyczna | piorun | domyślny |
/// | kredytowa manualna | karta | czerwony |
/// | kredytowa automatyczna | karta | żółty |
///
/// Żółty i czerwony to ta sama para, którą kalendarz oznacza płatność
/// automatyczną i manualną — nie wprowadzamy drugiego języka kolorów.
IconData paymentMethodIcon(PaymentMethod pm) => pm.isCreditCard
    ? LucideIcons.creditCard
    : (pm.isAutomatic ? LucideIcons.zap : LucideIcons.hand);

/// Kolor ikony metody — `null` dla zwykłych metod, żeby dziedziczyły kolor
/// z otoczenia (tak wyglądają dziś i nie ma powodu tego ruszać).
Color? paymentMethodIconColor(PaymentMethod pm, AppSemanticColors c) =>
    pm.isCreditCard ? (pm.isAutomatic ? c.warning : c.negative) : null;

/// Ikony kategorii — słownik wspólny dla subskrypcji, pozycji budżetu i ekranu
/// zarządzania kategoriami. Mieszkały przy karcie subskrypcji, ale z kategorii
/// korzysta dziś każda lista, a wiersz subskrypcji potrzebuje formatowania
/// z `budget_widgets` (import w drugą stronę zapętliłby oba pliki).
///
/// Dwie paczki Lucide: `lucide_icons` (starsza, większość zestawu) i
/// `lucide_icons_flutter` (nowsza — ma ikony, których tamta nie zna, np. `drill`,
/// `tent-tree`, `train-front`, `volleyball`). Obie fonty są w APK i aplikacja
/// używa ich obok siebie także poza tym plikiem.

/// Mapuje nazwę ikony na [IconData] (Lucide).
///
/// Nazwa kanoniczna to nazwa z Lucide w camelCase; warianty z myślnikiem
/// i skróty są przyjmowane jako aliasy, bo w bazie siedzą nazwy zapisane
/// wcześniej i nie ma po co ich migrować.
IconData categoryIcon(String? name) {
  return switch (name) {
    // ── Ludzie i pieniądze (także ikony budżetów, ADR-037) ──
    'user' => LucideIcons.user,
    'users' => LucideIcons.users,
    'briefcase' => LucideIcons.briefcase,
    'piggyBank' || 'piggy-bank' => LucideIcons.piggyBank,

    // ── Dom i wydatki bieżące ──
    'home' => LucideIcons.home,
    'bed' => LucideIcons.bed,
    'zap' => LucideIcons.zap,
    'wifi' => LucideIcons.wifi,
    'phone' => LucideIcons.phone,
    'mail' => LucideIcons.mail,
    'drill' || 'tools' => lucide.LucideIcons.drill,
    'soapDispenserDroplet' ||
    'soap-dispenser-droplet' ||
    'soap' => lucide.LucideIcons.soapDispenserDroplet,
    'swatchBook' || 'swatch-book' || 'swatch' => lucide.LucideIcons.swatchBook,

    // ── Zakupy i jedzenie ──
    'shoppingCart' || 'cart' => LucideIcons.shoppingCart,
    'shopping' || 'shoppingBag' => LucideIcons.shoppingBag,
    'utensils' || 'food' => LucideIcons.utensils,
    'coffee' => LucideIcons.coffee,
    'shirt' || 'clothes' => LucideIcons.shirt,

    // ── Transport i podróże ──
    'car' => LucideIcons.car,
    'fuel' => LucideIcons.fuel,
    'bike' => LucideIcons.bike,
    'trainFront' || 'train-front' || 'train' => lucide.LucideIcons.trainFront,
    'plane' => LucideIcons.plane,
    'tentTree' || 'tent-tree' || 'tent' => lucide.LucideIcons.tentTree,
    'treePalm' || 'tree-palm' || 'palm' => lucide.LucideIcons.treePalm,
    'camera' => LucideIcons.camera,

    // ── Zdrowie, sport i rodzina ──
    'heart' => LucideIcons.heart,
    'fitness_center' || 'dumbbell' => LucideIcons.dumbbell,
    'volleyball' || 'ball' => lucide.LucideIcons.volleyball,
    'baby' || 'child' => LucideIcons.baby,
    'dog' || 'pet' || 'paw' => LucideIcons.dog,
    'flower2' || 'flower-2' || 'flower' => LucideIcons.flower2,
    'gift' => LucideIcons.gift,
    'partyPopper' || 'party-popper' || 'party' => LucideIcons.partyPopper,

    // ── Rozrywka i media ──
    'play_circle' || 'play-circle' => LucideIcons.playCircle,
    'tv' => LucideIcons.tv,
    'music' => LucideIcons.music,
    'headphones' => LucideIcons.headphones,
    'sports_esports' || 'gamepad-2' || 'gamepad2' => LucideIcons.gamepad2,
    'book' => LucideIcons.bookOpen,

    // ── Praca, nauka i technika ──
    'code' => LucideIcons.code,
    'cloud' => LucideIcons.cloud,
    'globe' => LucideIcons.globe,
    'brain' => LucideIcons.brain,
    'school' ||
    'graduation-cap' ||
    'graduationCap' => LucideIcons.graduationCap,
    'shield' => LucideIcons.shield,

    // ── Pozostałe ──
    'receipt' => LucideIcons.receipt,
    'star' => LucideIcons.star,
    _ => LucideIcons.folder,
  };
}

/// Ikony do wyboru w Ustawieniach — kolejność jest tematyczna (dom, zakupy,
/// transport, zdrowie, rozrywka, praca), żeby przy kilkudziesięciu pozycjach
/// dało się szukać wzrokiem, a nie tylko przewijać.
const List<String> availableIconNames = [
  // Ludzie i pieniądze (także ikony budżetów)
  'user', 'users', 'briefcase', 'piggyBank',
  // Dom i wydatki bieżące
  'home', 'bed', 'zap', 'wifi', 'phone', 'mail',
  'drill', 'soapDispenserDroplet', 'swatchBook',
  // Zakupy i jedzenie
  'shoppingCart', 'shopping', 'utensils', 'coffee', 'shirt',
  // Transport i podróże
  'car',
  'fuel',
  'bike',
  'trainFront',
  'plane',
  'tentTree',
  'treePalm',
  'camera',
  // Zdrowie, sport i rodzina
  'heart', 'dumbbell', 'volleyball', 'baby', 'dog', 'flower2', 'gift',
  'partyPopper',
  // Rozrywka i media
  'play_circle', 'tv', 'music', 'headphones', 'gamepad2', 'book',
  // Praca, nauka i technika
  'code', 'cloud', 'globe', 'brain', 'graduationCap', 'shield',
  // Pozostałe
  'receipt', 'star', 'folder',
];
