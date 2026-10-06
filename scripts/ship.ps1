# ship.ps1
# Pelne wydanie jednym poleceniem: kontrola -> build+upload -> commit -> push ->
# GitHub Release. Kolejnosc jest wymuszona przez skrypt, nie przez pamiec.
#
# Uzycie:
#   .\scripts\ship.ps1 -Channel internal  -Message "Opis zmian" -Notes "- co nowego"
#   .\scripts\ship.ps1 -Channel production -Message "Opis zmian" -Notes "- A`n- B" -BumpType minor
#   .\scripts\ship.ps1 -Channel internal -DryRun        # tylko pokaz plan i kontrole
#
# DLACZEGO JEDEN SKRYPT: wydanie ma piec krokow, ktore MUSZA isc w tej kolejnosci
# (deploy zmienia pubspec/changelog/version.json, wiec release i tag musza powstac
# PO commicie, inaczej wskazuja kod sprzed wydania). Kazdy krok osobno to pieć
# okazji, zeby cos pominac — a apke sprawdza sie dopiero na telefonie, wiec blad
# wychodzi po fakcie.

param(
    [ValidateSet("internal", "production")]
    [string]$Channel = "internal",

    # Opis commita (po polsku, bez znakow diakrytycznych — CLAUDE.md).
    [string]$Message,

    # Notatki wydania (widoczne w aplikacji, changelogu i na GitHubie).
    [string]$Notes = "- bug fixes",

    [ValidateSet("", "patch", "minor", "major", "changelog")]
    [string]$BumpType = "patch",

    # Pomija testy i analize (uzywac tylko swiadomie).
    [switch]$SkipChecks,

    # Nie publikuje na GitHubie (np. gdy GitHub nie odpowiada).
    [switch]$SkipRelease,

    # Pokazuje plan i wynik kontroli, nic nie zmienia.
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Show-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Show-Success($msg) { Write-Host $msg -ForegroundColor Green }
function Show-Warning($msg) { Write-Host $msg -ForegroundColor Yellow }
function Show-Error($msg) { Write-Host $msg -ForegroundColor Red }
function Show-Step($n, $msg) { Write-Host "`n[$n/5] $msg" -ForegroundColor Magenta }

# Ponowienie zapytania przy awarii sieci (jak w publish-release.ps1). Lacze do
# api.github.com bywa kaprysne: pojedyncze zapytanie potrafi czekac 20 s i pasc,
# a nastepne przechodzi w ulamku sekundy. Blad 4xx to odpowiedz, nie awaria —
# ponawianie nic nie da, wiec wychodzi od razu.
function Invoke-WithRetry {
    param([scriptblock]$Action, [int]$Attempts = 3, [int]$DelaySeconds = 5, [string]$What = "operacja")
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            return & $Action
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -ge 400 -and $status -lt 500) { throw }
            if ($i -eq $Attempts) { throw }
            Show-Warning "  $What nie powiodla sie ($i/$Attempts): $($_.Exception.Message)"
            Start-Sleep -Seconds ($DelaySeconds * $i)
        }
    }
}

$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
$MOBILE_DIR = Join-Path $PROJECT_ROOT "apps\karton_subs"

if (-not $Message) {
    $Message = if ($Channel -eq "production") { "Wydanie PROD" } else { "Wydanie DEV" }
}

Show-Info "=== Wydanie: kanal $Channel ==="
Show-Info "Commit:  $Message"
Show-Info "Bump:    $BumpType"

# ── [0/5] Kontrola przed wydaniem ────────────────────────────────────────────
# Wszystko, co moze zablokowac wydanie, sprawdzamy PRZED zmiana czegokolwiek:
# nieudany build po podbiciu wersji zostawia repozytorium w polowie drogi.

Show-Step 0 "Kontrola przed wydaniem"

Push-Location $PROJECT_ROOT
try {
    # 1. Galaz: PROD wydajemy wylacznie z main (workflow trunk-based, CLAUDE.md).
    #    DEV wolno wydac z galezi roboczej — przebudowe testujemy na telefonie
    #    bez scalania jej do main, ktory w tym czasie zostaje wersja PROD.
    $branch = git rev-parse --abbrev-ref HEAD
    if ($branch -eq "HEAD") {
        Show-Error "Odlaczony HEAD — wydanie wymaga galezi (tag i push ida za galezia)."
        exit 1
    }
    if ($Channel -eq "production" -and $branch -ne "main") {
        Show-Error "Jestes na galezi '$branch', a wydanie PROD idzie wylacznie z 'main'."
        exit 1
    }
    if ($branch -ne "main") {
        Show-Warning "  galaz robocza: $branch (wydanie DEV z galezi)"
    }

    # 2. Dostep do GitHuba — sprawdzamy TERAZ, bo publikacja jest ostatnim
    #    krokiem i brak tokenu wyszedlby po kilku minutach builda.
    $token = $null
    if (-not $SkipRelease) {
        $token = gh auth token 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $token) { $token = $env:GITHUB_TOKEN }
        if (-not $token) {
            Show-Error "Brak tokenu GitHuba (gh auth login albo GITHUB_TOKEN)."
            Show-Info "Mozesz wydac bez publikacji: -SkipRelease (pamietaj o niej pozniej)."
            exit 1
        }
        $token = $token.ToString().Trim()
        Show-Success "  token GitHuba: jest"
    }

    # 3. Czy POPRZEDNIE wydanie tego kanalu ma swoj release na GitHubie.
    #    Gdy GitHub zostaje w tyle, Obtainium widzi w systemie wersje nowsza niz
    #    ostatni release i proponuje aktualizacje wstecz.
    #
    #    Trzy stany, nie dwa: „brak release'u" i „GitHub nieosiagalny" wygladaja
    #    tak samo w kodzie wyjscia `gh`, a znacza co innego. Mylenie ich albo
    #    blokuje wydanie bez powodu, albo przepuszcza rozjazd wersji.
    if (-not $SkipRelease) {
        $verFile = Join-Path $PROJECT_ROOT (
            $Channel -eq "internal" ? "releases\version-internal.json" : "releases\version.json"
        )
        if (Test-Path $verFile) {
            $prev = (Get-Content $verFile -Raw | ConvertFrom-Json).version
            $prevTag = ($Channel -eq "internal" ? "dev-v" : "v") + $prev

            # REST przez .NET, nie `gh`: w srodowiskach z filtrowaniem ruchu po
            # nazwie hosta `gh` nie dociera do API, a .NET dociera.
            $slug = (git remote get-url origin) -replace '.*[:/]([^/:]+/[^/]+?)(\.git)?$', '$1'
            $ghHeaders = @{
                Authorization = "Bearer $token"
                Accept        = "application/vnd.github+json"
                "User-Agent"  = "zostaje-release-script"
            }
            # Tylko odpowiedz 404 znaczy „release nie istnieje". Brak odpowiedzi
            # w limicie czasu to „nie wiem" — dawniej oba stany konczyly sie
            # komunikatem o braku wydania i blokowaly PROD bez powodu.
            $prevState = "published"   # published | missing | unreachable
            try {
                Invoke-WithRetry -What "polaczenie z GitHubem" -Action {
                    Invoke-RestMethod -Uri "https://api.github.com/repos/$slug" `
                        -Headers $ghHeaders -TimeoutSec 20 | Out-Null
                }
                try {
                    Invoke-WithRetry -What "sprawdzenie poprzedniego wydania" -Action {
                        Invoke-RestMethod -Uri "https://api.github.com/repos/$slug/releases/tags/$prevTag" `
                            -Headers $ghHeaders -TimeoutSec 20 | Out-Null
                    }
                }
                catch {
                    if ($_.Exception.Response.StatusCode.value__ -eq 404) { $prevState = "missing" }
                    else { throw }
                }
            }
            catch { $prevState = "unreachable" }

            if ($prevState -eq "unreachable") {
                if ($Channel -eq "production") {
                    Show-Error "GitHub nieosiagalny — nie moge sprawdzic, czy poprzednie wydanie jest opublikowane."
                    Show-Info "Wydaj bez publikacji: -SkipRelease (i opublikuj, gdy wroci polaczenie)."
                    exit 1
                }
                Show-Warning "  GitHub nieosiagalny — pomijam kontrole publikacji (DEV)."
            }
            elseif ($prevState -eq "missing") {
                if ($Channel -eq "production") {
                    Show-Error "Poprzednie wydanie PROD ($prev) nie ma release'u na GitHubie."
                    Show-Info "Opublikuj je: .\scripts\publish-release.ps1 -Channel production"
                    Show-Info "Albo wydaj bez publikacji: -SkipRelease"
                    exit 1
                }
                # DEV bywa wypuszczany kilka razy pod rzad w trakcie pracy —
                # blokada bylaby tu tylko przeszkoda.
                Show-Warning "  Poprzednie wydanie DEV ($prev) nie ma release'u — nadrobimy przy tym."
            }
            else {
                Show-Success "  poprzednie wydanie ($prev) opublikowane"
            }
        }
    }

    # 4. Analiza i testy — jedyna kontrola jakosci przed telefonem.
    if (-not $SkipChecks) {
        Push-Location $MOBILE_DIR
        try {
            Show-Info "  flutter analyze..."
            $analyze = & flutter analyze 2>&1
            if ($LASTEXITCODE -ne 0) {
                $analyze | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
                Show-Error "Analiza znalazla problemy — wydanie przerwane."
                exit 1
            }
            Show-Success "  analiza: czysto"

            Show-Info "  flutter test..."
            $tests = & flutter test 2>&1
            if ($LASTEXITCODE -ne 0) {
                $tests | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
                Show-Error "Testy nie przechodza — wydanie przerwane."
                exit 1
            }
            Show-Success "  testy: przechodza ($(($tests | Select-Object -Last 1) -replace '.*\+(\d+).*', '$1') przypadkow)"
        }
        finally { Pop-Location }
    }
    else {
        Show-Warning "  pominieto analize i testy (-SkipChecks)"
    }

    if ($DryRun) {
        Show-Success "`nDryRun: kontrola przeszla, nic nie zostalo zmienione."
        exit 0
    }

    # ── [1/5] Build + upload ─────────────────────────────────────────────────
    Show-Step 1 "Build i wysylka na serwer"
    & (Join-Path $PSScriptRoot "deploy.ps1") -Channel $Channel -BumpType $BumpType -ReleaseNotes $Notes
    if ($LASTEXITCODE -ne 0) {
        Show-Error "Deploy nie powiodl sie. Repozytorium moze miec podbita wersje w pubspec — sprawdz `git diff`."
        exit 1
    }

    # Wersja, ktora faktycznie poszla (czytamy z pliku, nie zgadujemy).
    $verFile = Join-Path $PROJECT_ROOT (
        $Channel -eq "internal" ? "releases\version-internal.json" : "releases\version.json"
    )
    $version = (Get-Content $verFile -Raw | ConvertFrom-Json).version

    # ── [2/5] Commit ─────────────────────────────────────────────────────────
    Show-Step 2 "Commit"
    git add .
    $commitMsg = "$Message`n`nWydanie $Channel $version.`n`nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
    git commit -m $commitMsg
    if ($LASTEXITCODE -ne 0) {
        Show-Warning "Nie bylo czego commitowac — ide dalej."
    }

    # ── [3/5] Push ───────────────────────────────────────────────────────────
    # Z ponowieniem: chwilowa awaria sieci nie moze zostawiac wydania w polowie
    # (kod zbudowany i wyslany na serwer, ale commit tylko lokalnie).
    Show-Step 3 "Push na $branch"
    $pushed = $false
    foreach ($attempt in 1..3) {
        # -u: pierwszy push galezi roboczej zaklada jej odpowiednik na serwerze.
        git push -u origin $branch
        if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
        if ($attempt -lt 3) {
            Show-Warning "  push nie powiodl sie ($attempt/3) — ponawiam za $(5 * $attempt) s"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    if (-not $pushed) {
        Show-Error "Push odrzucony po trzech probach."
        Show-Info "Zsynchronizuj (git pull --rebase origin $branch), potem: .\scripts\publish-release.ps1 -Channel $Channel"
        exit 1
    }

    # ── [4/5] GitHub Release ─────────────────────────────────────────────────
    Show-Step 4 "GitHub Release"
    if ($SkipRelease) {
        Show-Warning "Pominieto (-SkipRelease). Pamietaj: .\scripts\publish-release.ps1 -Channel $Channel"
    }
    else {
        & (Join-Path $PSScriptRoot "publish-release.ps1") -Channel $Channel
        if ($LASTEXITCODE -ne 0) {
            Show-Error "Publikacja nie powiodla sie — kod jest juz wydany i wypchniety."
            Show-Info "Dokoncz recznie: .\scripts\publish-release.ps1 -Channel $Channel"
            exit 1
        }
    }

    # ── [5/5] Gotowe ─────────────────────────────────────────────────────────
    Show-Step 5 "Gotowe"
    Show-Success "Wydano $version na kanal $Channel."
    Show-Info "Sprawdz na telefonie: aktualizacja OTA albo Obtainium."
}
finally {
    Pop-Location
}
