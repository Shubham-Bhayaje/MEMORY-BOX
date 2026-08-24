# Memory Box

Memory Box is a local-first, multimodal cognitive second brain and intelligent memory retrieval application built with Flutter. It enables users to capture, index, and converse with diverse personal information—including notes, voice recordings, photographs, screenshots, and web bookmarks—backed by modern Large Language Models and Vision AI.

---

## Key Features

### 1. Multimodal Memory Capture
* **Notes**: Quick text capture with automated title extraction and tagging.
* **Voice Recordings**: Built-in audio recorder and player with real-time waveform tracking and transcription support.
* **Photos and Screenshots**: Smart image intake that automatically differentiates device screenshots from photographs based on filesystem paths and metadata.
* **AI Vision Analysis**: Automatic OCR extraction, visual scene description, and URL parsing using multimodal vision models.

### 2. Intelligent Recall Engine
* **Conversational Querying**: Natural language memory lookup powered by configurable AI providers (GitHub Models, Groq, Google Gemini, and Local/Ollama endpoints).
* **Strict Semantic Grounding**: Source-verified citations connecting AI responses directly to the original memory items.
* **Voice Search & Dictation**: Hands-free memory search and queries powered by on-device Speech-to-Text.

### 3. System-Wide Floating Assistant
* **Global Android Overlay**: Accessible quick-action floating bubble that runs across any active app.
* **Instant Ingestion**: Capture thoughts, dictate voice notes, or query your memory box without leaving your current application.

### 4. Privacy & Local Storage
* **Local-First Architecture**: All memories, tags, audio files, and cached analysis are stored locally on-device in an encrypted SQLite database.
* **Secure Keyring**: API credentials and provider keys are protected using platform-native secure storage (`EncryptedSharedPreferences` on Android, `Keychain` on iOS).

---

## Architecture and Project Structure

```
lib/
├── database/
│   └── db_helper.dart            # SQLite database schema, CRUD operations, migrations
├── models/
│   └── memory.dart               # Core data models, memory types, serialization
├── screens/
│   ├── home_screen.dart          # Root scaffold with bottom navigation
│   ├── memory_feed.dart          # Timeline feed, filter chips, pill search bar
│   ├── chat_screen.dart          # Recall conversational interface with source citations
│   ├── add_memory_sheet.dart     # Multimodal creation and editing modal
│   ├── settings_screen.dart      # Provider configuration, API keys, preferences
│   ├── floating_assistant.dart   # System overlay floating assistant interface
│   └── overlay_bubble.dart       # Draggable overlay bubble widget
├── services/
│   └── llm_service.dart          # Unified client for GitHub, Groq, Gemini, and Local AI
├── theme/
│   └── app_theme.dart            # Material 3 color system and typography
└── utils/
    ├── error_handler.dart        # Centralized exception normalization and logging
    ├── secure_storage.dart       # Native secure credential management
    ├── rate_limiter.dart         # API throttle protection
    └── file_helper.dart          # Audio and image path resolution
```

---

## Supported AI Providers

| Provider | Supported Capabilities | Recommended Models |
| :--- | :--- | :--- |
| **GitHub Models** | Text Chat, Vision, Reasoning | `openai/gpt-4.1`, `meta-llama/Llama-3.3-70B-Instruct` |
| **Groq** | Low-Latency Text Chat, Vision | `llama-3.3-70b-versatile`, `llama-3.2-90b-vision-preview` |
| **Google Gemini** | Text Chat, Vision OCR | `gemini-2.5-flash`, `gemini-1.5-flash` |
| **Local / Custom** | Offline Text & Vision | `Ollama`, `LM Studio`, OpenAI-compatible REST endpoints |

---

## Getting Started

### Prerequisites
* Flutter SDK: Version 3.27.0 or higher
* Dart SDK: Version 3.6.0 or higher
* Android SDK: API Level 34+ (for Android 14/15/16 features and overlay permissions)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Shubham-Bhayaje/MEMORY-BOX.git
   cd MEMORY-BOX
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure environment settings:
   Copy `.env.example` to `.env` or configure your API keys directly within the in-app **Settings** tab.

4. Run unit and widget tests:
   ```bash
   flutter test
   ```

5. Launch the application:
   ```bash
   flutter run
   ```

---

## Android Permissions

The application utilizes standard permissions to support voice, camera, and overlay capabilities:
* `SYSTEM_ALERT_WINDOW`: Displays the global floating assistant bubble over other applications.
* `RECORD_AUDIO`: Captures voice notes and enables on-device speech recognition.
* `READ_MEDIA_IMAGES` / `READ_MEDIA_AUDIO`: Imports photos, screenshots, and audio recordings.
* `INTERNET`: Communicates with configured cloud AI inference endpoints.

---

## License

This project is open-source software licensed under the MIT License.
