# Windows setup

1. Install Git, VS Code, and optionally Docker Desktop (WSL 2).
2. `git clone https://github.com/YOUR_USERNAME/syncbench.git` and `cd syncbench`
3. ```powershell
   docker compose up --build
   ```
4. Open http://127.0.0.1:8000/health
5. Configure `.env` before exposing the API to a shared network.
6. The iOS app requires Xcode on macOS. Swift server development is supported on macOS/Linux; Docker is the simplest Windows host workflow.
