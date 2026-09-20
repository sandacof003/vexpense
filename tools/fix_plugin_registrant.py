#!/usr/bin/env python3
"""Buang plugin dev_dependency dari GeneratedPluginRegistrant.java (build release).

KENAPA INI ADA
--------------
Flutter 3.32 menulis SEMUA plugin Android ke GeneratedPluginRegistrant.java,
termasuk yang datang dari `dev_dependencies` (di sini: `integration_test`).
Tapi plugin dev TIDAK ikut classpath build release → `compileReleaseJavaWithJavac`
gagal: "package dev.flutter.plugins.integration_test does not exist".

Flutter SEHARUSNYA memfilter ini sendiri lewat `injectPlugins(releaseMode: true)`,
tapi di 3.32 jalur itu terkunci di balik fitur `explicit-package-dependencies`
yang masih `false` hardcoded (flutter_tools/lib/src/features.dart:55) dan
tidak punya `flutter config` flag. Jadi kita filter sendiri di sini.

JANGAN hapus file registrant-nya (itu yang bikin app blank — lihat catatan
di EXECUTION-ORDER.md 2026-09-20): file itu WAJIB ada, isinya yang dibersihkan.

Pakai: python3 tools/fix_plugin_registrant.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRANT = ROOT / 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
DEPS = ROOT / '.flutter-plugins-dependencies'

# Satu blok registrasi plugin di template Flutter:
#   try {
#     flutterEngine.getPlugins().add(new <pkg>.<Class>());
#   } catch (Exception e) {
#     Log.e(TAG, "...", e);
#   }
BLOCK = re.compile(
    r'\n[ \t]*try \{\n'
    r'[ \t]*flutterEngine\.getPlugins\(\)\.add\(new [^\n]*\);\n'
    r'[ \t]*\} catch \(Exception e\) \{\n'
    r'[ \t]*Log\.e\(TAG, [^\n]*\);\n'
    r'[ \t]*\}',
)


def dev_dependency_plugins() -> set[str]:
    """Nama plugin Android yang datang dari dev_dependencies."""
    data = json.loads(DEPS.read_text())['plugins']
    return {p['name'] for p in data.get('android', []) if p.get('dev_dependency')}


def strip_dev_plugins() -> int:
    src = REGISTRANT.read_text()
    dev = dev_dependency_plugins()
    removed = 0
    for name in sorted(dev):
        # blok yang menyebut plugin ini (di add() maupun di pesan Log.e)
        for m in list(BLOCK.finditer(src)):
            if name in m.group(0):
                src = src.replace(m.group(0), '')
                removed += 1
    REGISTRANT.write_text(src)
    return removed


def verify(removed: int) -> None:
    """Self-check: gagal = APK bakal blank atau build bakal gagal."""
    src = REGISTRANT.read_text()
    dev = dev_dependency_plugins()

    for name in dev:
        assert name not in src, (
            f'plugin dev "{name}" masih terdaftar di registrant → '
            f'compileReleaseJavaWithJavac bakal gagal'
        )
    assert removed > 0, (
        'nol blok dihapus padahal ada dev plugin — pola template Flutter berubah, '
        'cek ulang regex BLOCK'
    )
    # Plugin produksi WAJIB masih ada, kalau tidak app-nya blank saat dibuka.
    for must in ('SharedPreferencesPlugin', 'PathProviderPlugin', 'FilePickerPlugin'):
        assert must in src, f'plugin produksi "{must}" hilang dari registrant → app blank'
    assert 'registerWith' in src, 'method registerWith hilang → registrant rusak'


if __name__ == '__main__':
    if not REGISTRANT.exists():
        sys.exit(f'{REGISTRANT} tidak ada — jalankan `flutter pub get` dulu')
    n = strip_dev_plugins()
    verify(n)
    print(f'registrant OK: {n} blok plugin dev dibuang; produksi utuh')
