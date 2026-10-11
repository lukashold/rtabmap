# Berkontribusi pada KANTURA

KANTURA adalah fork independen RTAB-Map. Pengembangan dan pull request menargetkan [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). [Panduan utama berbahasa Inggris](../../CONTRIBUTING.md) menjelaskan proses lengkapnya.

## Memulai dan mengembangkan

Baca [panduan ruang kerja](../../tools/scan-workspace/README.md), [perbandingan fitur](../KANTURA-FEATURES.md), dan [catatan validasi](../../tools/scan-workspace/VALIDATION.md). Telusuri [daftar masalah proyek](https://github.com/lukashold/rtabmap/issues) terlebih dahulu. Laporan masalah yang dapat direproduksi, perbaikan terarah, terjemahan, atau pengujian perangkat nyata merupakan kontribusi awal yang berguna.

Untuk versi peramban, gunakan repositori lengkap, Node.js 24, dan pnpm 11.25.0. Buat cabang dari `kantura/main`. Di `tools/scan-workspace`, jalankan:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Buka `http://localhost:4173`. Panduan utama menjelaskan Corepack, Docker, dan penyimpanan server. Uji perubahan geometri dan penyimpanan data. Untuk koreksi teks, periksa bahasa dan tata letaknya. Cantumkan pemeriksaan yang benar-benar dijalankan serta yang belum dapat dijalankan.

## Menerjemahkan dan menjelaskan

Paket bahasa Indonesia berada di `tools/scan-workspace/locales/id.json`. Pertahankan kunci, ID adegan dan ikon, satuan, serta tempat penampung. Selaraskan takarir dengan narasi. Periksa juga integrasi pada panduan bawaan dan antarmuka; terjemahan panduan tidak membuktikan bahwa semua layar bawaan telah diterjemahkan. Lampirkan tangkapan layar jika teks terpotong.

Video merupakan animasi sintetis, bukan hasil pindai nyata. Pertahankan keterangan tersebut, perbedaan antara RoomPlan dan LiDAR, serta batasan pengukuran dan perkiraan pemindahan. Setiap ruangan memiliki titik asal sendiri dan tidak disejajarkan secara otomatis.

## Menguji perangkat

iOS memerlukan Mac, Xcode yang kompatibel, dependensi bawaan, dan penandatanganan Anda sendiri. Lihat [panduan pemasangan](../APP-STORE-RELEASE.md). Pengujian Swift di `app/ios/Tests/run-scan-tracking-tests.sh` dan `run-measurement-guide-tests.sh` tidak menggantikan pemindaian pada iPhone.

Sertakan revisi, perangkat, versi iOS, mode, langkah, serta hasil yang diharapkan dan diamati. Bandingkan pengukuran dengan meteran dan tuliskan nilai beserta satuannya. Tandai data sintetis. Sesuai perubahan, uji ruangan, gerbang, interupsi, simpan/buka kembali, foto, dan ekspor. Bagikan hanya contoh yang diizinkan tanpa mengungkap interior pribadi, orang, atau kredensial secara tidak semestinya.

## Mengajukan perubahan dan mematuhi lisensi

Buat fork dan cabang dari `kantura/main`, lakukan perubahan terarah, uji, lalu buka pull request ke **`lukashold/rtabmap:kantura/main`**. Jelaskan masalah, hasil akhir, dan batasannya. Perbaikan umum RTAB-Map dapat diajukan secara terpisah ke proyek asal; fitur khusus KANTURA ditujukan terlebih dahulu ke fork ini.

Kode proyek menggunakan [BSD 3-Clause](../../LICENSE). Pertahankan atribusi dan sumbangkan hanya konten yang boleh didistribusikan. Dependensi bawaan memiliki ketentuan masing-masing: ORB-Octree yang diaktifkan melalui `WITH_ORB_OCTREE` menggunakan GPLv3; OpenCV mengaktifkan Nonfree; komponen SuiteSparse/g2o serta LASzip 2.0.1/libLAS yang ditautkan secara statis masih perlu diaudit. Dokumentasikan versi dan lisensi dependensi baru. [Audit penerbitan](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) bukan persetujuan App Store yang telah selesai.
