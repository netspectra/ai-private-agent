# PrivateAgent

PrivateAgent is an open-source Android automation agent built with Flutter. It utilizes cloud LLM APIs (DeepSeek, Gemini, etc.) and native Android Accessibility Services to interpret screen layouts and execute multi-step tasks across any installed application via natural language commands. 

It now also supports **100% offline on-device inference** via `llama.cpp` integration, allowing for completely private, zero-cost task execution using quantized `.gguf` models.

## Architecture

The system operates on a continuous feedback loop:
1. The user issues a command (via voice, text, or Telegram remote access).
2. The agent captures the current screen hierarchy, calculating the exact spatial coordinates of all interactive elements.
3. The layout data is transmitted to the AI provider (or the local on-device engine) alongside the current task context and the result of the previous action.
4. The AI determines the next optimal action (e.g., clicking specific coordinates, inputting text, scrolling).
5. The native Android layer executes the action.
6. The loop repeats until the task is marked as complete.

## Capabilities

- **Screen Reading:** Parses the Android UI tree to map clickable, scrollable, and editable elements.
- **Coordinate-Based Interaction:** Simulates physical screen taps based on coordinate geometry, mitigating issues with missing text labels or inaccessible icons.
- **Local On-Device Inference:** Run quantized `.gguf` models directly on your device via `llama.cpp` for 100% offline privacy and zero API costs.
- **Auto-Switching Resilience:** Automatically falls back to backup models if a rate limit, server timeout, or API mismatch occurs during a task.
- **Infinite Tasks:** Execute sprawling multi-hour tasks without step limits (by disabling maximum task caps in settings).
- **Remote Access:** Integrates with the Telegram Bot API via background polling, allowing users to issue commands and monitor task execution progress remotely.
- **Voice Control:** Native speech-to-text integration for hands-free operation.

## Installation

Download the latest APK directly from the [Releases Page](https://github.com/orailnoor/private-agent/releases).

Choose `app-universal-release.apk` when it is available. It supports ARM64, 32-bit ARM, and x86_64 devices in one package. If a release only provides split APKs, most modern Android phones—including Snapdragon devices—must use `app-arm64-v8a-release.apk`.

PrivateAgent supports Android 8.0 (API 26) and newer. Current release builds are also checked for Android 15/16's 16 KB native-library alignment requirement.

## Setup Instructions (How to use for FREE)

This app requires an AI brain to operate. You can use it **100% for free** by using OpenRouter's free models or Google AI Studio.

1. Install the APK on your Android device (API 30+ recommended).
2. Go to [OpenRouter.ai](https://openrouter.ai/) or [Google AI Studio](https://aistudio.google.com/) and create a free account.
3. Generate a free API Key.
4. Launch PrivateAgent and go to the **Settings** screen.
5. Tap the **"OpenRouter"** or **"Google"** quick-select chip under Base URL.
6. Paste your API Key.
7. Type `openai/gpt-oss-120b:free` (for OpenRouter) or `gemini-2.5-pro` (for Google) into the Model field.
8. Enable the **"PrivateAgent Screen Control"** service in your Android Accessibility Settings.

### Using Local On-Device Models (Offline Mode)
PrivateAgent supports executing tasks completely offline using locally downloaded GGUF models.

1. Launch PrivateAgent and go to the **Settings** screen.
2. Select **Local On-Device Inference** from the Quick Select Base URLs.
3. Tap **Manage Local Models** to download a recommended lightweight model (like Bonsai or Qwen) or import your own `.gguf` file.
4. The application will dynamically leverage your device's GPU/CPU to execute tasks locally.

### “Restricted setting” when enabling Screen Control

Android may block accessibility access for apps installed from an APK. This is an operating-system safety restriction:

1. Open **Settings → Apps → PrivateAgent**.
2. Open the three-dot menu in the top-right corner.
3. Tap **Allow restricted settings** and confirm.
4. Return to PrivateAgent and open **Accessibility Settings** again.
5. Enable **PrivateAgent Screen Control**.

PrivateAgent now shows these instructions and provides shortcuts to both App Info and Accessibility Settings during onboarding.

## Telegram Integration

To enable remote access:
1. Acquire a bot token from BotFather on Telegram.
2. Input the token in the PrivateAgent Settings screen and enable the integration toggle.
3. The application will maintain a background polling connection to the Telegram API to receive commands.

## License

This project is open-source and available for modification.
