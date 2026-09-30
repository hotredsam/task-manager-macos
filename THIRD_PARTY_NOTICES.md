# Third-party notices

## Windows 11 Task Manager icon

The original graph/gray-frame icon artwork in `Assets/TaskManager-Windows.ico` and `Assets/TaskManager-*.png` is Microsoft Windows artwork, obtained from [HaydenReeve/WindowsIcons](https://github.com/HaydenReeve/WindowsIcons/blob/main/Icons/applications/taskmanager.ico). It matches the icon generation in the Windows 11 22H2 visual reference. Microsoft retains any applicable rights; this third-party artwork is **excluded from the project's MIT license**. The source collection identifies its assets as extracted Windows resources and does not grant a separate MIT license to Microsoft's artwork.

`Assets/icon-sources.json` records the source ICO and SHA-256 checksums. `Scripts/ExtractIcon.py` losslessly converts the ICO bitmap representations to PNG; the embedded 256-pixel PNG is copied unchanged. `Scripts/MakeIcon.py` embeds the matching PNG representations in the macOS ICNS container without resampling. No AI-generated replacement is used.

This is an independent project. It is not affiliated with, sponsored by, or endorsed by Microsoft or Apple. Product names and trademarks belong to their respective owners.

## Selawik fonts

The unmodified Selawik Regular and Semibold fonts are Copyright 2015 Microsoft Corporation, distributed under the SIL Open Font License 1.1. The full font license is included in `Assets/Fonts/LICENSE.txt` and in the built app. Source: [microsoft/Selawik, release 1.01](https://github.com/microsoft/Selawik/releases/tag/1.01). The app uses locally available Segoe UI, including fonts in an existing licensed Microsoft Office installation, when available and otherwise uses Selawik; it does not redistribute proprietary Windows fonts.
