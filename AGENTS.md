# V Expense — Agent Guide (subfolder v_expense)

Semua agent yang kerja di folder ini WAJIB baca dulu `../AGENTS.md` (guardrail proyek) dan `../PRD.md`.

## Stack & Konvensi
- Flutter 3.32 / Dart 3.8, Android only (web/iOS nyusul)
- State: **Riverpod** (flutter_riverpod + hooks opsional)
- DB: **Drift** (SQLite ORM, `lib/core/data/`)
- Chart: **fl_chart** (dipin `1.0.0` — versi 1.1.0 gagal compile di VPS ini: `Matrix4.translateByDouble` tidak ada di vector_math-2.1.4 yang dipin Flutter 3.32; jangan naikkan tanpa cek `flutter test` penuh)
- File picker (import CSV): **file_picker**
- Dark mode default, Material 3
- `applicationId: com.sandacof003.vexpense`, `minSdk 26`

## Struktur
```
lib/
├── main.dart              # Entry point + theme (jangan diubah tanpa konfirmasi)
├── core/
│   ├── data/              # Drift DB schema, DAO, repository (owner: BE)
│   └── theme/             # Theme, colors, typography (owner: FE)
└── features/
    ├── dashboard/         # (owner: FE)
    ├── transactions/      # (owner: FE) — form + list
    ├── accounts/          # (owner: FE)
    ├── categories/        # (owner: FE)
    ├── reports/           # (owner: FE) — fl_chart
    └── settings/          # (owner: FE) — import CSV
```

## Pembagian kerja agent
| Area | Owner | Notes |
|---|---|---|
| UI screens (features/*) | FE (Qwen 3.8 Max) | Ikut wireframe, dark mode |
| Theme | FE | `lib/core/theme/` |
| Drift schema + DAO | BE (deepseek-v4-pro) | `lib/core/data/`, pastikan minor unit integer |
| Repository + service | BE | Panggil DAO, expose ke FE |
| Import CSV parser | BE | `csv` package, handle ID format |
| QA / test | QA (Qwen 3.7 Flash) | `test/` |

## Build & Verifikasi
```bash
export ANDROID_HOME=/opt/android-sdk
export PATH="/opt/flutter/bin:$PATH"
cd /home/ubuntu/Projects/money-tracking/v_expense
flutter analyze          # harus 0 issues
flutter test             # harus pass
flutter build apk --debug
```

## Aturan khusus VPS (RAM 2.5GB!)
- Gradle DAEMON OFF + JVM heap dibatasi — sudah di-set di `android/gradle.properties`, JANGAN diubah
- Build APK = `flutter build apk --debug --no-pub` (pakai `--no-pub` biar gak nunggu pub get)
- `flutter run` butuh device — di VPS headless pakai `flutter build` aja

## Fix bug = PATCH ONLY (wajib, FE & BE)
- Bug fix: targeted edit minimal, JANGAN rewrite/refactor ulang 1 file penuh.
- Root cause: satu guard di shared function > guard di tiap caller.
- Commit per fix: `fix: <deskripsi>` — terpisah dari task lain.
- Regresi → revert commit itu, bukan lanjut tambal.

## Git
- Repo: GitHub `sandacof003/vexpense` (branch main)
- Jangan commit `build/`, `.dart_tool/`, `android/local.properties`, `android/.gradle/` (sudah di .gitignore)
- Commit message: `feat:`, `fix:`, `chore:`
