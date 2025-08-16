# KeyboardAI iOS Bundle

This project contains:

- Container App (settings & storage)
- Custom Keyboard Extension (Enhance/Reply, style picker, clipboard reply, suggestion pill, tips, sticky context)
- Share/Action Extension (Generate Reply from selected text; hands back via App Group + clipboard)

## Replace placeholders

- YOUR_TEAM_ID
- com.yourco.KeyboardAI (app bundle id)
- group.com.yourco.KeyboardAI (App Group id)
- API endpoint/key (in app settings)

## Generate Xcode project

1. Install XcodeGen: `brew install xcodegen`
2. Generate project: `xcodegen generate`
3. Open `KeyboardAI.xcodeproj` in Xcode.
4. In Signing & Capabilities, set your Team and ensure App Groups include `group.com.yourco.KeyboardAI` on all three targets.

## Targets

- KeyboardAI (iOS App)
- Keyboard (Custom Keyboard Extension)
- Share (Action Extension – text)

## Run

- Build & run the app on a device.
- In the app, set API Endpoint and optional API Key.
- Add the keyboard in iOS Settings → Keyboards → KeyboardAI → Allow Full Access (for server mode).
- Use Share/Action "Generate Reply" on selected text to copy a reply; the keyboard will suggest pasting it.

## Offline model (optional)

`App/ModelInstaller.swift` copies a bundled GGUF into the App Group container if present. To integrate llama.cpp, follow the notes in your spec: add sources, bridging header, and the wrapper, then route generations in the keyboard.

## Server contract

POST `${endpoint}` with body `{ text, mode, style }` → returns `{ text }`.

