# Building Android APK for Voice Todo App

This guide explains how to convert the Voice Todo App into an Android APK.

## Prerequisites

1. Linux environment (Ubuntu recommended) or using WSL on Windows
2. Python 3.9+
3. Buildozer (included in requirements_android.txt)
4. Android SDK and NDK (will be automatically downloaded by Buildozer)

## Setup Instructions

### 1. Install System Dependencies

On Ubuntu or Debian-based systems:

```bash
sudo apt update
sudo apt install -y git zip unzip openjdk-11-jdk python3-pip autoconf libtool pkg-config zlib1g-dev libncurses5-dev libncursesw5-dev libtinfo5 cmake libffi-dev libssl-dev
```

### 2. Install Python Dependencies

```bash
pip install -r requirements_android.txt
```

### 3. Set Up App Assets

Create a data directory and add icon/splash images:

```bash
mkdir -p data
```

Add your app icon (icon.png) and splash screen (presplash.png) to the data directory.

### 4. Build the APK

```bash
buildozer android debug
```

The first build will take a considerable amount of time (30+ minutes) as it downloads and compiles all dependencies. Subsequent builds will be faster.

### 5. Install the APK

After a successful build, you'll find the APK file in the bin directory:

```
bin/voicetodo-0.1-arm64-v8a_armeabi-v7a-debug.apk
```

You can transfer this APK to your Android device and install it directly.

## Troubleshooting

### Common Issues

1. **SDK/NDK Issues**: If you encounter issues with Android SDK or NDK, you can manually specify their paths in the buildozer.spec file.

2. **Dependencies Issues**: If a Python package fails to build, try adding it to the requirements list in buildozer.spec with a specific version number.

3. **Memory Errors**: The build process requires significant memory. If you encounter memory-related errors, try increasing your system's swap space.

### Error Logs

Check the following logs for detailed error information:

- `~/.buildozer/logs/buildozer.log`
- `.buildozer/android/platform/build-*/build/other_builds/*/stderr.log`

## Notes on App Performance

1. **First Launch**: The first launch of the app will take longer as it sets up the Streamlit server.

2. **Microphone Access**: Make sure to grant microphone permissions to the app for voice input functionality.

3. **Internet Access**: The app requires internet access for connecting to MongoDB Atlas and GitHub AI models.

## Limitations

1. **Battery Usage**: Running a Streamlit server inside an Android app consumes more battery than a native app.

2. **Performance**: The app may be slower than a native Android app due to the WebView and Python runtime overhead.

3. **Compatibility**: The app requires Android 5.0 (API level 21) or higher.

## Alternative Approach

If you encounter issues with this method, consider:

1. Deploying the Streamlit app to a server and creating a WebView-only Android app that connects to it.
2. Using a native Android framework like Kivy with direct MongoDB and API integration.
