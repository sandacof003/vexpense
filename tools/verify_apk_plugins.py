#!/usr/bin/env python3
"""Guard rilis: pastikan APK benar-benar memuat plugin Android.

Kalau kelas plugin hilang dari classes.dex, `SharedPreferences.getInstance()`
di main.dart throw MissingPluginException SEBELUM runApp() → app blank saat
dibuka, tapi build tetap "sukses". Cek ini yang memisahkan APK sehat dari APK
blank, jadi jalankan tiap build (dipanggil build_apk.sh).

Pakai: python3 tools/verify_apk_plugins.py [path.apk]
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIN_PLUGIN_CLASSES = 5  # file_picker, lifecycle, path_provider, shared_prefs, sqlite3


def check(apk: Path) -> list[str]:
    z = zipfile.ZipFile(apk)
    dex = z.read('classes.dex')  # string pool dex: nama kelas ada sebagai literal
    found = sorted(p for p in (
        b'FilePickerPlugin', b'PathProviderPlugin', b'SharedPreferencesPlugin',
        b'Sqlite3FlutterLibsPlugin', b'FlutterAndroidLifecyclePlugin',
    ) if p in dex)
    return [f.decode() for f in found]


if __name__ == '__main__':
    apk = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        ROOT / 'build/app/outputs/flutter-apk/app-release.apk')
    assert apk.exists(), f'tidak ada {apk} — build dulu'
    found = check(apk)
    assert len(found) >= MIN_PLUGIN_CLASSES, (
        f'APK cuma punya {len(found)} dari {MIN_PLUGIN_CLASSES} kelas plugin ({found}) '
        f'→ plugin nggak ke-register, app bakal blank saat dibuka'
    )
    assert b'IntegrationTestPlugin' not in zipfile.ZipFile(apk).read('classes.dex'), (
        'plugin dev integration_test ikut masuk release → buang lewat fix_plugin_registrant.py'
    )
    print(f'APK OK: {len(found)} kelas plugin produksi ada, integration_test tidak ikut')
