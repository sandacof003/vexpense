# E2E Test Scenarios (jalankan SETELAH semua task INT selesai)

Catatan: ini level **end-to-end / device**, bukan widget test. Widget test sudah
cover sebagian (transaction_mutation_test, transaction_list_test, dashboard_screen_test)
tapi belum membuktikan sinkronisasi lintas layar + persist setelah restart.

Status: **NOT YET EXECUTED** — diblokir sampai INT-02/04/05/07 selesai.

---

## E2E-1 — Sinkronisasi saldo dashboard

Tujuan: setiap mutasi transaksi langsung konsisten di saldo akun DAN total dashboard.

1. Catat saldo awal akun A (dari layar Akun) + total saldo di Dashboard.
2. Buat transaksi **expense 50.000** di akun A.
3. Cek: saldo akun A turun 50.000; total dashboard turun 50.000.
4. **Edit** transaksi itu jadi **income 50.000**.
5. Cek: saldo akun A naik 50.000 dari nilai awal; total dashboard ikut naik;
   transaksi **tidak** dihitung dua kali.
6. **Hapus** transaksi.
7. Cek: saldo akun A dan total dashboard kembali **persis** ke nilai langkah 1.
8. **Restart app** (kill + buka lagi) → nilai tetap sama (persist, bukan state in-memory).

Expected: `saldo akun == sum(transaksi akun tsb)`, `total dashboard == sum(semua akun)`.
Tidak ada drift setelah create → edit → delete → restart.

## E2E-2 — Multi-currency

Tujuan: transaksi lintas currency konsisten; tidak ada pencampuran nilai mentah
dan tidak ada dua kurs berbeda di dua layar.

1. Siapkan akun **IDR** dan akun **USD**.
2. Catat kurs yang dipakai app di dashboard.
3. Buat transaksi **USD 10** di akun USD.
4. Cek: saldo akun USD turun 10 (satuan USD, **tidak** dikonversi di level akun).
5. Cek: total dashboard mengonversi 10 USD → IDR dengan kurs **yang sama persis**
   seperti langkah 2.
6. Buat **transfer** dari akun IDR ke akun USD.
7. Cek: nilai yang masuk akun tujuan = hasil konversi dengan kurs yang sama,
   dan tidak ada selisih yang hilang di total portofolio.
8. **Restart app** → nilai dan kurs tetap konsisten.

Expected: satu sumber kurs dipakai di semua layar (dashboard, daftar akun, detail
transaksi). `total portofolio == Σ(nilai akun dalam IDR)`, tidak drift setelah
transfer lintas currency.

---

## Kenapa belum dijalankan

Tidak ada direktori `integration_test/` di repo. Acceptance "saldo & dashboard
sinkron setelah tiap mutasi" saat ini hanya terbukti di level widget test.
E2E di atas adalah gate terakhir sebelum MVP dinyatakan selesai.
