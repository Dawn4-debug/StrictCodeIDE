# StrictCode IDE 🚀

A focused, native macOS code editor built entirely with SwiftUI. StrictCode balances a distraction-free practice environment with a robust, kiosk-style lockdown mode designed specifically for conducting programming exams.

---

## 🚧 Project Status

StrictCode IDE is currently in active development. Core features like native text editing, quick compilation (C, C++, Java), and the fullscreen kiosk lockdown mechanism are fully operational. Advanced options like the contextual AI Premium Tier are currently under development.

---

## ✨ Key Features

* **Exam Mode (Kiosk Lockdown):** Turns any Mac into a single-purpose exam station with one click. Blocks app switching (`Cmd + Tab`), Spotlight, and system shortcuts while logging any boundary violations with precise timestamps.
* **Practice Mode:** An open workspace built to train core engineering habits, featuring inline complexity scratchpads and user-defined custom test cases.
* **Native Liquid Glass UI:** A gorgeous, system-native layout designed using modern SwiftUI translucency that responds instantly to macOS Light and Dark modes.

---

## 📦 Download & Installation

You can download the latest compiled version directly from the project landing page:
👉 **[strictcodeide.pages.dev](https://strictcodeide.pages.dev/)**

### 💡 First-Time Launch (macOS Gatekeeper Note)

Because StrictCode is independently developed, macOS will display a Gatekeeper warning on your first launch. The application is completely safe, but requires a one-time launch approval:

1. Open **Finder** and navigate to your **Applications** directory.
2. **Right-click** (or hold Control) the StrictCode IDE icon and click **Open**.
3. If prompted, click **Open Anyway** inside your Mac's *System Settings ➔ Privacy & Security*.

---

## 🛠️ Building From Source

If you want to explore the application structure or contribute to the lockdown mechanisms:

1. Clone the repository:
   ```bash
   git clone [https://github.com/Dawn4-debug/StrictCodeIDE.git](https://github.com/Dawn4-debug/StrictCodeIDE.git)
