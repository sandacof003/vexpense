# V Expense

Aplikasi pencatat keuangan personal berbasis Flutter (Android first), terinspirasi dari Expense IQ.

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
