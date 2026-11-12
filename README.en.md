[Polski](README.md)

# KWHotel on macOS

<p align="center">
  <img src="assets/logo.jpg" alt="The orange KWHotel icon and the blue Finder face sharing a heart" width="480">
</p>

This launcher runs the Windows [KWHotel Free](https://kwhotel.com/download/kwhotel-free/) desktop app on a Mac through [Wine](https://www.winehq.org/), without a Windows virtual machine.

This is an independent project. It is not part of KWHotel and it is not affiliated with [KajWare sp. z o.o.](https://kwhotel.com/), the company that publishes the program. The scripts in this repository are released under the MIT license. The KWHotel installer is not part of the repository.

## Motivation

The desktop KWHotel is a WinForms application built on .NET Framework 4.6, and it is published for Windows only. For macOS, the vendor points people to Parallels or to browser products: KWHotel Web and KWHotel Cloud.

A virtual machine means keeping a second operating system: a separate license, disk image, and updates, only to open the reservation book. Wine solves a narrower problem: it provides a Windows API compatibility layer instead of running an entire operating system. [winehq](https://www.winehq.org/)

That does not make the setup simple. The main problem is the dependency on 32-bit x86 code.

## Architecture and dependencies

An Apple Silicon Mac uses ARM64. Rosetta 2 translates x86_64 code, but it does not run 32-bit x86 directly.

This project uses Wine Crossover 23.7.1, based on Wine 8.0.1. That Wine build is a 64-bit x86_64 application, so on Apple Silicon it itself runs through Rosetta.

The chosen version still supports the 32-bit Windows components required to install KWHotel and its dependencies. Newer upstream Wine releases for macOS do not provide the same support, and Gcenx's original release and the Homebrew cask for this build are gone. The script therefore downloads `wine-crossover-23.7.1-1-osx64.tar.xz` from the [jfuruness/wine-crossover-mac](https://github.com/jfuruness/wine-crossover-mac/releases/download/23.7.1-1/wine-crossover-23.7.1-1-osx64.tar.xz) mirror and checks the SHA-256 `e24ba084737c8823e8439f7cb75d436a917fd92fc34b832bcaa0c0037eb33d03` stored in `lib/kwhotel.sh`.

## KWHotel is not simply a 32-bit application

`KWHotel.exe` is a PE32 file, but it contains managed IL built as AnyCPU with the `32BITREQUIRED` flag turned off. After .NET Framework 4.8 is installed in a 64-bit prefix, the CLR compiles the application as 64-bit.

The problem is the software around it:

- the NSIS installer is 32-bit;
- the .NET Framework setup also runs 32-bit installers and NGEN processes, including `mscorsvw.exe` under Wine's WoW64;
- SQL Server Compact and the integrations for fiscal printers, locks, and card readers use native Windows libraries, often 32-bit ones.

Rosetta does not run that 32-bit code directly. The Wine build used here does, inside a 64-bit prefix. At the same time, this build cannot create a 32-bit prefix, even though `winetricks` recommends one for .NET Framework 4.8.

In practice there are several layers: x86_64 Wine running through Rosetta on ARM64, Wine's support for the Windows components, and the CLR executing the application's managed code. KWHotel itself runs as a 64-bit process, but installation and some dependencies still need 32-bit Windows support.

## Limitations and known problems

## Interface

WinForms and DevComponents DotNetBar use GDI. Wine's GDI implementation is incomplete, so the interface can have rendering or layout problems even when the process itself is running correctly.

## `Quartz.dll` conflict

KWHotel ships [Quartz.NET](https://www.quartz-scheduler.net/) as `Quartz.dll`. Wine has its own DirectShow library of the same name: `quartz.dll`.

Without the right configuration, the CLR tries to load the wrong library and fails with `BadImageFormatException`. Setup sets the `quartz=native` override so the library shipped with the application is used.

## .NET Framework installation

Installing .NET Framework 4.8 takes several minutes and is one of the more failure-prone setup steps. The first run needs about 8 GB of free disk space.

## Fiscal printers, locks, and card readers

Integrations with devices such as Posnet, Elzab, and Novitus printers, locks, or card readers may require Windows drivers and USB support that this stack does not provide.

KWHotel starting does not mean external devices will work. Their compatibility has to be checked separately.

## Database

The first launch creates a new SQL Server Compact database. An existing hotel database has to be brought into this environment, or a MySQL connection has to be configured.

## Compatibility with later macOS releases

The Wine build in use is from 2023. This setup was tested on macOS 26.

There is no guarantee of compatibility with later macOS releases. Changes to Rosetta, or to the rules for running unsigned applications, can make this stack stop working.

## Download KWHotel

KajWare publishes the Free 0.47 installer from the buttons on these pages:

- International: <https://kwhotel.com/download/kwhotel-free/>
- Polish: <https://kwhotel.com/pl/pobierz/kwhotel-free/>

Those buttons currently return `KWHotel_0_47_211.exe`. `setup.sh` accepts any `installer/KWHotel*.exe`.

International build:

```bash
mkdir -p installer
curl -fL -o installer/KWHotel_0_47_211.exe \
  "https://kajware.pl/wp-content/downloads/production/Multi/Free/download.php"
shasum -a 256 installer/KWHotel_0_47_211.exe
```

Expected SHA-256:

```text
a99d4b8eaa77e21b16510219bded154cf553191ac9a10b51de18b68d1764a0ee
```

Polish build, which is the one this launcher was run against:

```bash
mkdir -p installer
curl -fL -o installer/KWHotel_0_47_211.exe \
  "https://www.kajware.pl/wp-content/downloads/production/Polska/Free/download.php"
shasum -a 256 installer/KWHotel_0_47_211.exe
```

Expected SHA-256:

```text
82e7b6045eaedffe69a2653d4172f38d0d39ed05b407e1366d3432441ca40e2b
```

`installer/*.exe` is listed in `.gitignore`.

## Run

macOS 12 or newer, Apple Silicon or Intel. The first run needs a network connection and about 8 GB free while .NET Framework is installed.

```bash
xattr -dr com.apple.quarantine .
./setup.sh --launch
```

`setup.sh` can be run again. It skips Wine, the prefix, and .NET Framework when they are already the expected versions. After that, double-click `KWHotel.app`.

## What gets installed

| Piece | Where |
| --- | --- |
| Wine Crossover 23.7.1 | `~/Applications/Wine Crossover.app` |
| Wine prefix and .NET Framework 4.8 | `~/.wine-kwhotel` |
| Program files | `~/Library/Application Support/KWHotel/app` |

On Apple Silicon, Rosetta is installed if it is missing. The script downloads Wine, 7-Zip, winetricks, and cabextract and checks them against the checksums in `lib/kwhotel.sh`.

The fiscal-printer, lock, and card-reader drivers are Windows binaries. Those devices will not work.

## License

The launcher is [MIT](LICENSE). KWHotel, Wine, .NET Framework, 7-Zip, winetricks, and cabextract keep their own licenses.
