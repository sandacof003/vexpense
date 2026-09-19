# V Expense

Aplikasi pencatat keuangan personal berbasis Flutter (Android first), terinspirasi dari Expense IQ.

## Download

[![Latest release](https://img.shields.io/github/v/release/sandacof003/vexpense?label=latest&color=blue)](https://github.com/sandacof003/vexpense/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/sandacof003/vexpense/total)](https://github.com/sandacof003/vexpense/releases)

**➡️ [Download APK terbaru](https://github.com/sandacof003/vexpense/releases/latest)** — `v0.1.0-alpha.4` (reports + chart, import CSV)

Link langsung: [v-expense-0.1.0-alpha.4.apk](https://github.com/sandacof003/vexpense/releases/download/v0.1.0-alpha.4/v-expense-0.1.0-alpha.4.apk) (55 MB)

Cara install di Android:
1. Buka halaman release di atas, download file `v-expense-*.apk`
2. Aktifkan "Install unknown apps" untuk browser/file manager yang dipakai
3. Install & buka → onboarding pilih currency → dashboard

> ⚠️ Build **pre-alpha** (belum semua fitur ada — lihat catatan release). APK di-sign dengan debug key, bukan buat Play Store.

## Yang sudah jalan
- Onboarding pilih currency default + dark mode Material 3
- **Dashboard** (FE-03): total saldo gabungan multi-currency → IDR, income vs expense bulan berjalan, 5 transaksi terbaru, quick add
- **Transaksi** (FE-04/05): tambah/edit/hapus, daftar + filter (tipe, akun, kategori, rentang tanggal) + search, transfer antar akun same-currency
- **Akun & Kategori** (FE-06): kelola akun dan kategori
- Belum ada: import CSV dari UI (FE-08)

## Stack
- Flutter 3.32 (Dart 3.8)
- Riverpod (state management)
- Drift (SQLite ORM)
- fl_chart 1.0.0 (chart — dipin; 1.1.0 tidak compile di Flutter 3.32)
- file_picker (pilih file CSV)

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
