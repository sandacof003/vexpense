# V Expense

Aplikasi pencatat keuangan personal berbasis Flutter (Android first), terinspirasi dari Expense IQ.

## Download

[![Latest release](https://img.shields.io/github/v/release/sandacof003/vexpense?label=latest&color=blue)](https://github.com/sandacof003/vexpense/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/sandacof003/vexpense/total)](https://github.com/sandacof003/vexpense/releases)

**➡️ [Download APK terbaru](https://github.com/sandacof003/vexpense/releases/latest)**

Cara install di Android:
1. Buka halaman release di atas, download file `v-expense-*.apk`
2. Aktifkan "Install unknown apps" untuk browser/file manager yang dipakai
3. Install & buka → onboarding pilih currency → dashboard

> ⚠️ Build **pre-alpha** (belum semua fitur ada — lihat catatan release). APK di-sign dengan debug key, bukan buat Play Store.

## Stack
- Flutter 3.32 (Dart 3.8)
- Riverpod (state management)
- Drift (SQLite ORM)
- fl_chart (chart)

## Struktur
```
lib/
├── main.dart              # Entry point + theme
├── core/
│   ├── data/              # Drift DB, repository (agent BE)
│   └── theme/             # Theme, colors, typography
└── features/
    ├── dashboard/         # Dashboard screen (agent FE)
    ├── transactions/      # Transaksi list + form
    ├── accounts/          # Akun + transfer
    ├── categories/        # Kategori
    ├── reports/           # Laporan + chart
    └── settings/          # Pengaturan + import CSV
```

## Setup
```bash
export ANDROID_HOME=/opt/android-sdk
export PATH="/opt/flutter/bin:$PATH"
cd v_expense
flutter pub get
flutter run
```

## Config
- applicationId: `com.sandacof003.vexpense`
- minSdk: 26 (Android 8.0)
- Dark mode default (lihat wireframe di `wireframes/`)

## Referensi
- PRD: `../PRD.md`
- Wireframe: `../wireframes/wireframe.html`
