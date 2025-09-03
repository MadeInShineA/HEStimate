# HEStimate User Guide

Welcome to **HEStimate**!  
HEStimate is a Flutter-based application scaffold designed to be cross-platform (mobile, web, and desktop) and ready for future extensions such as Firebase integration and environment-based configuration.  

This guide will walk you through setup, usage, and common troubleshooting scenarios.

---

## 1. Installation & Setup

### Prerequisites

Before you begin, ensure the following are installed on your system:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable version recommended)
- Dart SDK (bundled with Flutter)
- Git
- An IDE such as **Visual Studio Code**, **Android Studio**, or **IntelliJ IDEA**

Optional but recommended:

- Xcode (for iOS builds, macOS only)
- Android Studio SDK (for Android builds)
- Chrome or another supported browser (for web builds)

### Steps to Install

1. Clone the repository:

   ```bash
   git clone https://github.com/MadeInShineA/HEStimate.git
   cd HEStimate
   ```

2. Fetch dependencies:

   ```bash
   flutter pub get
   ```

3. Run the application:

   ```bash
   flutter run
   ```

4. To run on specific platforms:
   - **Android/iOS**: connect a device or start an emulator/simulator.
   - **Web**:  

     ```bash
     flutter run -d chrome
     ```

   - **Windows/macOS/Linux**:  

     ```bash
     flutter run -d windows   # or macos / linux
     ```

---

## 2. Core Features

Although HEStimate is in its early stages, the current version includes:

- Account creation for Students and Homeowners
- Listing creation for Homeowners

### 📱 Cross-Platform Support

- Android  
- iOS  
- Web  
- Windows, macOS, and Linux desktop  

### ☁️ Firebase Integration Ready

- A `firebase.json` file is included for future integration.
- Intended support for services like Authentication, Firestore, or Analytics.

### ⚙️ Environment Configuration

- `.env.example` is included.
- To use:
  1. Copy it to `.env`.
  2. Add API keys, environment variables, or feature flags.
- This allows safe handling of secrets and switching between dev/prod modes.

---

## 3. Navigation

The current app provides a simple navigation flow:

- **Home Screen**
  - Displays the counter.
  - Provides the “+” button to increment.
- **Additional Pages**
  - To be added in future development as features expand.

---

## 4. Settings & Customization

### Environment Variables

- Developers can manage app configuration via the `.env` file.
- Examples include:
  - API base URLs
  - Firebase keys
  - Feature toggles

### Themes & UI

- Flutter makes it easy to customize:
  - Primary colors
  - Typography
  - Dark/light modes

---

## 5. Troubleshooting

### Common Issues & Fixes

#### 🚫 App Won’t Start

- Ensure you have the latest Flutter SDK installed.
- Check that a device or emulator is connected.
- Run:

  ```bash
  flutter doctor
  ```

  and fix any issues reported.

#### 📦 Missing Dependencies

- Run:

  ```bash
  flutter pub get
  ```

#### ⚡ Build Errors

- **iOS**: Make sure Xcode is installed and configured.
- **Android**: Ensure Android SDK is installed in Android Studio.
- **Web/Desktop**: Verify Flutter supports your platform with:

  ```bash
  flutter devices
  ```

#### 🔑 Firebase Errors

- Ensure `firebase.json` is configured with valid Firebase project details.
- Confirm that the necessary Firebase packages are added to `pubspec.yaml`.

---

## 6. Roadmap

Planned future features include:

- Integration with Firebase Authentication and Firestore.
- A results dashboard with charts and statistics.
- Support for saving and exporting data (CSV, JSON).
- Improved navigation with multiple screens.
- Dark mode and advanced theming.

---

## 7. Feedback & Support

- Report bugs or request new features via the [GitHub Issues page](https://github.com/MadeInShineA/HEStimate/issues).
- For general Flutter help, see the [Flutter documentation](https://docs.flutter.dev/).
- Contributions are welcome — feel free to fork the repo and open a pull request!
