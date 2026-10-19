#!/usr/bin/env python3
"""Metadata pública del binario; nunca incorpora configuración de la máquina."""
import json
import os
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
try: commit=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
except (OSError,subprocess.CalledProcessError):commit='no disponible'
(root/'build-info.json').write_text(json.dumps({'commit':commit},indent=2)+'\n')
