# HEStimate Documentation

Welcome to the **HEStimate** project docs 👋  

HEStimate is a **student‑housing marketplace** that connects students searching for accommodation with property owners offering listings.  
It combines a **Flutter app** (frontend) and a **FastAPI service** (backend) to provide:  

- 🔑 **Authentication** — email/password + optional **Face ID login**  
- 🏠 **Listings** — create, browse, filter, and favorite student housing options  
- 💰 **Price Estimation** — AI‑powered rent suggestions  
- 🚌 **Convenience Info** — distances to campuses & transit stops  
- ⭐ **Reviews** (planned) — two‑sided feedback between students & owners  

---

## 📖 Guides

- [📘 User Guide](HEStimate_User_Guide.md)  
  Step‑by‑step help for **students** and **property owners** using the app. Covers browsing, booking, creating listings, enabling Face ID, and more.

- [🛠️ Developer Guide](HEStimate_Full_Stack_Developer_Guide.md)  
  A deep‑dive for **contributors and maintainers**. Explains the architecture, frontend (`lib/ui`) and backend (`hestimate-api`), data flow, setup instructions, API reference, and extension tips.

---

## 🔗 Repositories

- **Frontend (Flutter)** → [MadeInShineA/HEStimate](https://github.com/MadeInShineA/HEStimate)  
- **Backend (FastAPI)** → [MadeInShineA/HEStimate-api](https://github.com/MadeInShineA/HEStimate-api)

---

## 🚀 Quick Start for Developers

1. **Backend**  
   - Clone [`HEStimate-api`](https://github.com/MadeInShineA/HEStimate-api)  
   - Create `.env` with:  
     ```env
     API_KEY=dev-secret-key
     LOCAL_BLEND_ALPHA=0.3
     ```  
   - Run with:  
     ```bash
     uvicorn main:app --reload
     ```  
   - Docs available at [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)

2. **Frontend**  
   - Clone [`HEStimate`](https://github.com/MadeInShineA/HEStimate)  
   - Run `flutter pub get`  
   - Create `.env` with:  
     ```env
     GOOGLE_API_KEY=your_google_key
     API_KEY=dev-secret-key
     ```  
   - Launch app with:  
     ```bash
     flutter run
     ```  

3. **Test the Flow**  
   - Register as a student  
   - Create a listing → request **Price Estimate**  
   - Save listing → confirm observation logged in backend  
   - Enable **Face ID** → verify face → logout/login with selfie 🚀  

---

## 🤝 Contributing

- Follow coding conventions (Flutter lints, Pydantic models in FastAPI).  
- Write tests (`pytest` for backend, widget tests for Flutter).  
- Open PRs with screenshots/logs of tested features.  

---

© 2025 HEStimate Project
