# DartLingvo

DartLingvo is a standalone offline dictionary app for Lingvo `.lsd` and `.dsl` dictionary files.

It is built with Flutter and keeps the entire lookup flow local to the device. You can load one or more dictionaries, search across them, open entries in tabs, and return to previous lookups with navigation history.

## Features

- Load Lingvo `.lsd` and `.dsl` files from disk
- Search across loaded dictionaries
- Open results in separate lookup tabs
- Navigate back and forward through entry history
- Restore previously loaded dictionaries on startup
- Switch between light, dark, and system theme modes
- Parse Lingvo formatting such as bold, italic, references, and examples

## Requirements

- Flutter 3.8 or newer
- Dart 3.8 or newer
- A platform-specific toolchain for the target you want to run

## Getting Started

Clone the repository and install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Run the tests:

```bash
flutter test
```

## Using the App

1. Launch DartLingvo.
2. Tap the `+` button in the app bar.
3. Select a `.lsd` or `.dsl` dictionary file.
4. Start typing in the search bar.
5. Tap a result to open the entry.
6. Use the tab bar and navigation buttons to move between lookups.

Loaded dictionaries are cached so they can be restored the next time the app starts.

## Windows Native Decoder

The repository includes a native decoder wrapper used by the Windows build.

If you need to rebuild the Windows decoder DLL, use:

```bat
native\build_windows.bat
```

## Project Structure

- `lib/` - Flutter UI, state, search, parsing, and dictionary management
- `native/` - C wrapper and native decoder build files
- `test/` - Unit tests for the parser and indexing logic
- `tool/` - Small local debugging and inspection utilities

## Notes

- This repository is intended for offline use.
- Dictionary load time depends on file size and format.
- If a dictionary fails to load, check that the file is a valid Lingvo `.lsd` or `.dsl` file.

