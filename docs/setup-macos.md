# macOS setup

1. Install Xcode (App Store), open it once, then `xcode-select --install`.
2. Install Swift 5.10+, XcodeGen, and optionally Docker Desktop.
3. `git clone https://github.com/YOUR_USERNAME/syncbench.git && cd syncbench`
4. Start the backend (`cd backend && swift run syncbench-server`) or use `docker compose up --build` from the repository root.
5. ```bash
   cd ios
   xcodegen generate
   open SyncBench.xcodeproj
   ```
6. Pick an iPhone simulator, press Cmd+R. In the app: Settings -> URL `http://127.0.0.1:8000` -> Save & test connection.
7. Run tests: Cmd+U, or `xcodebuild test -project SyncBench.xcodeproj -scheme SyncBench -destination 'platform=iOS Simulator,name=<an installed iPhone>'`.

**Physical iPhone:** use your Mac's LAN IP (`ipconfig getifaddr en0`) or a deployed HTTPS URL; sign the app with your Apple ID team in Xcode.
**Backend on Windows, simulator on Mac:** use the Windows machine's LAN IP and allow port 8000 in Windows Firewall.
**If XcodeGen fails:** create an iOS App project named SyncBench in `ios/` (SwiftUI, tests on), delete the generated
ContentView/App files, add the folders from `ios/SyncBench` and `ios/SyncBenchTests`, and add `NSAllowsLocalNetworking` under App Transport Security.
