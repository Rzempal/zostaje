/// Konfiguracja build-time (--dart-define=CHANNEL=internal|production).
/// Port z APPteczka — zmienione URL-e na domenę karton-subs.
class AppConfig {
  static const String channel = String.fromEnvironment(
    'CHANNEL',
    defaultValue: 'production',
  );

  static bool get isInternal => channel == 'internal';

  static const String _baseReleasesUrl =
      'https://michalrapala.app/releases/karton-subs';

  /// Opublikowana polityka prywatnosci — wersja obowiazujaca.
  /// Ten sam adres jest wskazany w ekranie zgody OAuth (Google Cloud) i bedzie
  /// potrzebny w Play Console. `docs/privacy-policy.md` to tylko kopia robocza.
  static const String privacyPolicyUrl =
      'https://www.michalrapala.com/aplikacje/zostaje/privacy';

  static String get versionJsonUrl => isInternal
      ? '$_baseReleasesUrl/internal/version-internal.json'
      : '$_baseReleasesUrl/version.json';

  /// Remote path — used only by deploy.ps1, read from .env at deploy time.
  /// Kept here for backward compatibility until migration to GitHub Releases.
  static String get remoteReleasePath => isInternal
      ? const String.fromEnvironment('DEPLOY_REMOTE_INTERNAL', defaultValue: '')
      : const String.fromEnvironment('DEPLOY_REMOTE_PROD', defaultValue: '');
}
