[English](README.en.md)

# KWHotel na macOS

<p align="center">
  <img src="assets/logo.jpg" alt="Pomarańczowa ikona KWHotel i niebieska twarz Findera ze wspólnym sercem" width="480">
</p>

<p align="center">
  <a href="https://github.com/mockshox/kwhotel-macos/raw/main/download/KWHotel-for-MacOS.zip"><img src="https://img.shields.io/badge/Pobierz-KWHotel%20for%20MacOS-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Pobierz KWHotel for MacOS"></a>
</p>

Launcher uruchamia windowsowy [KWHotel Free](https://kwhotel.com/pl/pobierz/kwhotel-free/) na Macu przez [Wine](https://www.winehq.org/), bez maszyny wirtualnej z Windowsem.

To niezależny projekt — nie jest częścią KWHotel ani nie jest powiązany z [KajWare sp. z o.o.](https://kwhotel.com/), producentem programu. Skrypty w tym repozytorium są udostępniane na licencji MIT. Instalator KWHotel nie jest częścią repozytorium.

## Motywacja

Desktopowy KWHotel to aplikacja WinForms oparta na .NET Framework 4.6, wydawana wyłącznie na Windowsa. Użytkownikom macOS producent proponuje Parallels lub rozwiązania przeglądarkowe: KWHotel Web / KWHotel Cloud.

Maszyna wirtualna oznacza utrzymywanie drugiego systemu: osobnej licencji, obrazu dysku i aktualizacji — tylko po to, żeby otworzyć księgę rezerwacji. Wine rozwiązuje węższy problem: zapewnia warstwę zgodności z API Windowsa, zamiast uruchamiać cały system operacyjny. [winehq](https://www.winehq.org/)

Nie oznacza to jednak, że konfiguracja jest prosta. Głównym problemem są zależności od 32-bitowego kodu x86.

## Architektura i zależności

Mac z Apple Silicon korzysta z ARM64. Rosetta 2 tłumaczy kod x86_64, ale nie obsługuje bezpośrednio 32-bitowego x86.

Projekt korzysta z Wine Crossover 23.7.1, opartego na Wine 8.0.1. Ta kompilacja Wine jest 64-bitową aplikacją x86_64, więc na Apple Silicon sama działa przez Rosettę.

Wybrana wersja nadal obsługuje 32-bitowe komponenty Windows wymagane przez instalację i zależności KWHotel. Nowsze upstreamowe wydania Wine na macOS nie zapewniają tej samej obsługi, a oryginalne wydanie Gcenxa i cask Homebrew z tą kompilacją zniknęły. Skrypt pobiera więc archiwum `wine-crossover-23.7.1-1-osx64.tar.xz` z lustra [jfuruness/wine-crossover-mac](https://github.com/jfuruness/wine-crossover-mac/releases/download/23.7.1-1/wine-crossover-23.7.1-1-osx64.tar.xz) i sprawdza sumę SHA-256 `e24ba084737c8823e8439f7cb75d436a917fd92fc34b832bcaa0c0037eb33d03` zapisaną w `lib/kwhotel.sh`.

## KWHotel nie jest po prostu aplikacją 32-bitową

`KWHotel.exe` ma format PE32, ale zawiera zarządzany kod IL z ustawieniem AnyCPU i wyłączoną flagą `32BITREQUIRED`. Po zainstalowaniu .NET Framework 4.8 w 64-bitowym prefiksie CLR kompiluje kod aplikacji do wersji 64-bitowej.

Problemem są komponenty wokół niej:

- instalator NSIS jest 32-bitowy;
- instalacja .NET Framework uruchamia również 32-bitowe instalatory i procesy NGEN, w tym `mscorsvw.exe` w środowisku WoW64 Wine;
- SQL Server Compact oraz integracje z drukarkami fiskalnymi, zamkami i czytnikami kart korzystają z natywnych bibliotek Windows, często 32-bitowych.

Rosetta nie uruchamia bezpośrednio tego 32-bitowego kodu. Jego obsługę zapewnia używana kompilacja Wine, wewnątrz 64-bitowego prefiksu. Jednocześnie ta kompilacja nie potrafi utworzyć prefiksu 32-bitowego, mimo że `winetricks` rekomenduje taki prefiks dla .NET Framework 4.8.

W praktyce mamy więc kilka warstw: Wine x86_64 działające przez Rosettę na ARM64, obsługę komponentów Windows przez Wine oraz CLR wykonujący zarządzany kod aplikacji. Sam KWHotel działa jako proces 64-bitowy, ale instalacja i część zależności nadal wymagają obsługi 32-bitowego Windowsa.

## Ograniczenia i znane problemy

## Interfejs

WinForms i DevComponents DotNetBar korzystają z GDI. Jego implementacja w Wine nie jest kompletna, więc interfejs może mieć problemy z renderowaniem lub układem kontrolek, nawet jeśli sam proces działa poprawnie.

## Konflikt `Quartz.dll`

KWHotel dostarcza bibliotekę [Quartz.NET](https://www.quartz-scheduler.net/) jako `Quartz.dll`. Wine ma własną bibliotekę DirectShow o tej samej nazwie: `quartz.dll`.

Bez odpowiedniej konfiguracji CLR próbuje załadować niewłaściwą bibliotekę, co kończy się błędem `BadImageFormatException`. Setup ustawia override `quartz=native`, żeby wymusić użycie biblioteki dostarczonej z aplikacją.

## Instalacja .NET Framework

Instalacja .NET Framework 4.8 trwa kilka minut i jest jednym z bardziej podatnych na błędy etapów konfiguracji. Na pierwsze uruchomienie trzeba przygotować około 8 GB wolnego miejsca.

## Drukarki fiskalne, zamki i czytniki kart

Integracje z urządzeniami takimi jak drukarki Posnet, Elzab i Novitus, zamki czy czytniki kart mogą wymagać sterowników Windows oraz obsługi USB, której ten zestaw nie zapewnia.

Samo uruchomienie KWHotel nie oznacza, że urządzenia zewnętrzne będą działały. Ich zgodność trzeba zweryfikować osobno.

## Baza danych

Pierwsze uruchomienie tworzy nową bazę SQL Server Compact. Istniejącą bazę hotelu trzeba przenieść do tego środowiska albo skonfigurować połączenie z MySQL.

## Zgodność z kolejnymi wersjami macOS

Używana kompilacja Wine pochodzi z 2023 roku. Konfiguracja została sprawdzona na macOS 26.

Nie ma gwarancji zgodności z kolejnymi wydaniami macOS. Zmiany w Rosetcie lub zasadach uruchamiania niepodpisanych aplikacji mogą uniemożliwić działanie tego zestawu.

## Pobieranie KWHotel

KajWare publikuje instalator Free 0.47 pod przyciskami na tych stronach:

- Międzynarodowy: <https://kwhotel.com/download/kwhotel-free/>
- Polski: <https://kwhotel.com/pl/pobierz/kwhotel-free/>

Te przyciski zwracają teraz `KWHotel_0_47_211.exe`. Okno instalacji przyjmuje wskazany plik `.exe`. `setup.sh` przyjmuje też dowolny plik `installer/KWHotel*.exe`.

Kompilacja międzynarodowa:

```bash
mkdir -p installer
curl -fL -o installer/KWHotel_0_47_211.exe \
  "https://kajware.pl/wp-content/downloads/production/Multi/Free/download.php"
shasum -a 256 installer/KWHotel_0_47_211.exe
```

Oczekiwana suma SHA-256:

```text
a99d4b8eaa77e21b16510219bded154cf553191ac9a10b51de18b68d1764a0ee
```

Kompilacja polska, na której ten launcher był uruchamiany:

```bash
mkdir -p installer
curl -fL -o installer/KWHotel_0_47_211.exe \
  "https://www.kajware.pl/wp-content/downloads/production/Polska/Free/download.php"
shasum -a 256 installer/KWHotel_0_47_211.exe
```

Oczekiwana suma SHA-256:

```text
82e7b6045eaedffe69a2653d4172f38d0d39ed05b407e1366d3432441ca40e2b
```

Pliki `installer/*.exe` są w `.gitignore`.

## Uruchomienie

macOS 12 lub nowszy, Apple Silicon albo Intel. Pierwsze uruchomienie potrzebuje sieci i około 8 GB wolnego miejsca na czas instalacji .NET Framework.

Pobierz **KWHotel for MacOS** przyciskiem na górze strony i rozpakuj zip. Otwórz aplikację i wskaż pobrany instalator `KWHotel*.exe`. Okno prowadzi krokami Dalej: Powitanie, Konfiguracja, Instalacja, Koniec. Instalacja trwa kilka minut, pobiera Wine oraz .NET Framework i nie uruchamia KWHotel. Na końcu pole „Uruchom KWHotel” otwiera program przy zamknięciu instalatora.

Gdy macOS zablokuje aplikację pobraną z internetu:

```bash
xattr -dr com.apple.quarantine "KWHotel for MacOS.app"
open "KWHotel for MacOS.app"
```

To repozytorium składa tę samą aplikację. `./gui/build.sh` odkłada ją w `dist/KWHotel-for-MacOS.zip`.

## Odinstalowanie

W oknie jest przycisk „Odinstaluj…”. To samo robi skrypt:

```bash
./uninstall.sh
```

Skrypt pyta o potwierdzenie. Usuwa prefiks Wine (`~/.wine-kwhotel`), pliki programu (`~/Library/Application Support/KWHotel`), pamięć podręczną instalacji i skrót `~/Desktop/KWHotel.command`. Usuwa też `~/Applications/Wine Crossover.app`, gdy leży tam ta kompilacja. Rosetta zostaje. Folder projektu i instalator `.exe` też zostają.

Baza hotelu leży wśród plików programu. Żeby ją zachować:

```bash
./uninstall.sh --keep-data
```

Żeby zostawić Wine:

```bash
./uninstall.sh --keep-wine
```

## Co jest instalowane

| Element | Gdzie |
| --- | --- |
| Wine Crossover 23.7.1 | `~/Applications/Wine Crossover.app` |
| Prefiks Wine i .NET Framework 4.8 | `~/.wine-kwhotel` |
| Pliki programu | `~/Library/Application Support/KWHotel/app` |

Na Apple Silicon Rosetta jest doinstalowywana, jeśli jej nie ma. Wine, 7-Zip, winetricks i cabextract pobiera skrypt i sprawdza sumy z `lib/kwhotel.sh`.

Sterowniki drukarek fiskalnych, zamków i czytników kart to binarki Windowsa. Te urządzenia nie zadziałają.

## Licencja

Launcher jest na licencji [MIT](LICENSE). KWHotel, Wine, .NET Framework, 7-Zip, winetricks i cabextract zostają przy swoich licencjach.
