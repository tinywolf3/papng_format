"""Shared native viewer tooling. All generated files stay under builds/."""
from pathlib import Path
import os, re, shutil, subprocess
ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'demos/godot/viewer'
TOOLS = ROOT / 'builds/linux/viewer-tools'
VERSION = '4.7.2'

def environment():
    env = dict(os.environ)
    for variable, folder in [('XDG_CONFIG_HOME','config'), ('XDG_DATA_HOME','data'), ('XDG_CACHE_HOME','cache')]:
        path = TOOLS / folder
        path.mkdir(parents=True, exist_ok=True)
        env[variable] = str(path)
    return env

def engine():
    executable = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4') or '/var/lib/flatpak/app/org.godotengine.Godot/current/active/files/bin/godot-bin'
    if not Path(executable).is_file():
        raise SystemExit(f'Install Godot {VERSION} or set GODOT_BIN.')
    version = subprocess.check_output([executable,'--headless','--version'],text=True,env=environment()).strip()
    if not version.startswith(VERSION+'.stable.'):
        raise SystemExit(f'Expected Godot {VERSION}, got {version}')
    return executable

def run_godot(args, log, timeout=180, env=None):
    log = Path(log); log.parent.mkdir(parents=True,exist_ok=True)
    with log.open('w') as output:
        result = subprocess.run([engine(),'--path',str(PROJECT),*map(str,args)],cwd=ROOT,env=env or environment(),stdout=output,stderr=subprocess.STDOUT,timeout=timeout)
    text = log.read_text()
    if result.returncode or re.search(r'SCRIPT ERROR|Parse Error|^ERROR:',text,re.M):
        print(text[-8000:])
        raise SystemExit(f'Godot failed; see {log}')
    print(f'PASS: {log.relative_to(ROOT)}')
    return text
