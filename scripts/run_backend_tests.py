import subprocess
import sys
from pathlib import Path

backend = Path(__file__).resolve().parents[1] / "backend"
sys.exit(subprocess.call([sys.executable, "-m", "pytest", "-q"], cwd=backend))
