# Windows setup

1. Install Git, Python 3.12 (tick "Add to PATH"), VS Code, and optionally Docker Desktop (WSL 2).
2. `git clone https://github.com/YOUR_USERNAME/syncbench.git` and `cd syncbench`
3. ```powershell
   cd backend
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1      # if blocked: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   pip install -r requirements.txt
   pytest -q
   uvicorn app.main:app --reload
   ```
4. Open http://127.0.0.1:8000/docs
5. With Docker: from the repo root `docker compose up --build`.
6. Commit and push; the `backend-ci` workflow runs automatically. Swift files can be edited on Windows but only compiled on a Mac.
