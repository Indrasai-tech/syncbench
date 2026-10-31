import os
import tempfile

# Must run before the app is imported: tests use a throwaway SQLite database.
os.environ["DATABASE_URL"] = f"sqlite:///{tempfile.mkdtemp()}/test.db"
os.environ.pop("API_KEY", None)
