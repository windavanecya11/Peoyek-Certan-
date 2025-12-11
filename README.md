🐔 Smart Diagnosis of Chicken Diseases Using Convolutional Neural Network (CNN)-Based Image Classification

📌 Deskripsi Proyek

Proyek Smart Diagnosis of Chicken Diseases merupakan aplikasi berbasis mobile yang mampu mendeteksi penyakit ayam secara otomatis menggunakan model Convolutional Neural Network (CNN).

Aplikasi ini memanfaatkan gambar bagian tubuh ayam (misalnya mata, bulu, atau keseluruhan tubuh) untuk mengklasifikasi apakah ayam tersebut:

Sehat

Terkena penyakit tertentu (Contoh: ND, CRD, Fowl Pox, dan lainnya)

Membutuhkan pemeriksaan lebih lanjut

Model CNN dilatih menggunakan dataset gambar ayam, diproses dengan Python, kemudian di-deploy pada aplikasi mobile berbasis Flutter.

Proyek ini dikembangkan untuk membantu peternak, mahasiswa, dan peneliti dalam mendiagnosis penyakit secara cepat, murah, dan efisien tanpa memerlukan alat laboratorium.

🎯 Tujuan Proyek
- Menyediakan solusi diagnosis penyakit ayam otomatis dengan akurasi tinggi
- Mengurangi risiko penyebaran penyakit pada peternakan
- Menghadirkan teknologi deep learning ke pengguna non-teknis
- Membantu pengambilan keputusan cepat berdasarkan data visual

  ⭐ Fitur Utama
  - 📸 Upload atau Ambil Foto Ayam untuk analisis
  - 🤖 Prediksi Penyakit Menggunakan CNN
  - 📊 Tampilkan Confidence Score / Probabilitas
  - 📝 Deskripsi Penyakit + Saran Penanganan
  - 📂 Riwayat Diagnosis (opsional jika ditambahkan)
  - 📱 Aplikasi Mobile Berbasis Flutter
  - 🚀 Model cepat, ringan, dan bisa offline (jika TFLite digunakan)
 
  🧠 Arsitektur Sistem
  📱 Flutter Mobile App
        ↓ (send image)
🌐 FastAPI / Flask Backend (Python)
        ↓
🧠 CNN Model (PyTorch/TensorFlow)
        ↓
📊 JSON Response (disease + confidence)

🛠 Tech Stack
Mobile
Flutter
Dart
Provider / GetX (opsional)
Machine Learning & Backend
Python
PyTorch / TensorFlow
FastAPI (app.py di folder /api)
NumPy, Pillow
CNN (Custom architecture / pretrained MobileNet / EfficientNet)

📂 Struktur Folder Proyek
📦 Chicken-disease-Kel01
│
├── 📁 api
│   ├── app.py
│   ├── best_model.pth
│   ├── requirements.txt
│   └── __pycache__
│
└── 📁 mobile
    ├── lib
    │   └── main.dart
    ├── pubspec.yaml
    └── android / ios / assets ...

🚀 Cara Menjalankan Aplikasi
1. Backend (Python API)
   cd api
pip install -r requirements.txt
uvicorn app:app --reload
2. Mobile App (Flutter)
   cd mobile
flutter pub get
flutter run
📈 Dataset & Model
Model CNN dilatih menggunakan:
Dataset gambar ayam (jumlah & kelas sesuai penelitian)
Arsitektur: CNN-based classifier
Input image: 224×224 px
Optimizer: Adam
Loss Function: Cross Entropy
Output: Disease Classification (multi-class)

