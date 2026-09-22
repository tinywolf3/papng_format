#!/usr/bin/env python3
"""Stage engine intermediates and packages only under builds/."""
from pathlib import Path
import argparse, os, shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[3];SOURCE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('platform',choices=['linux','windows']);p.add_argument('--engine',default=os.environ.get('UNREAL_ENGINE',str(Path.home()/'UnrealEngine')));p.add_argument('--editor-only',action='store_true');a=p.parse_args()
engine=Path(a.engine);out=ROOT/'builds'/a.platform/'papng-unreal-viewer';out.mkdir(parents=True,exist_ok=True);project=out/'project';project.mkdir(exist_ok=True)
for folder in ('Source','Config'):shutil.copytree(SOURCE/folder,project/folder,dirs_exist_ok=True)
shutil.copy2(SOURCE/'PapngViewer.uproject',project/'PapngViewer.uproject')
shutil.copytree(ROOT/'demos/shared/papng',project/'Native/papng',dirs_exist_ok=True)
settings=project/'Saved/UnrealBuildTool/BuildConfiguration.xml';settings.parent.mkdir(parents=True,exist_ok=True);settings.write_text('<?xml version="1.0"?><Configuration xmlns="https://www.unrealengine.com/BuildConfiguration"><BuildConfiguration><bAllowUBAExecutor>false</bAllowUBAExecutor><MaxParallelActions>6</MaxParallelActions></BuildConfiguration></Configuration>')
uproject=project/'PapngViewer.uproject'
if a.editor_only:
    tool=engine/'Engine/Build/BatchFiles'/('Build.bat' if os.name=='nt' else 'Linux/Build.sh')
    cmd=([str(tool)] if os.name=='nt' else ['bash',str(tool)])+['PapngViewerEditor','Win64' if os.name=='nt' else 'Linux','Development',f'-Project={uproject}','-WaitMutex','-NoUBA','-MaxParallelActions=6']
else:
    if a.platform=='windows' and os.name!='nt':raise SystemExit('Unreal Windows packaging requires a Windows host with Visual Studio C++ and the matching Unreal Engine. Run this script there.')
    uat=engine/'Engine/Build/BatchFiles'/('RunUAT.bat' if os.name=='nt' else 'RunUAT.sh')
    cmd=([str(uat)] if os.name=='nt' else ['bash',str(uat)])+['BuildCookRun',f'-project={uproject}','-noP4','-utf8output','-build','-cook','-stage','-pak','-archive',f'-archivedirectory={out}',f'-platform={dict(linux="Linux",windows="Win64")[a.platform]}','-clientconfig=Development','-map=/Engine/Maps/Entry','-unattended','-NoUBA','-UbtArgs=-NoUBA -MaxParallelActions=6']
log=out/('editor-build.log' if a.editor_only else 'build.log');print('Unreal build log:',log,flush=True)
try:
    with log.open('w') as f:subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=7200,env=os.environ,cwd=project)
except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
    print(log.read_text(errors='replace')[-6000:])
    raise SystemExit(f'Unreal build failed or timed out. See {log}') from error
print('Build complete:',out)
if not a.editor_only:
    sys.path.insert(0,str(ROOT/'demos/shared/desktop'))
    from package import package
    staged=out
    executable=staged/('PapngViewer.sh' if a.platform=='linux' else 'PapngViewer.exe')
    package(ROOT,staged,'unreal',a.platform,executable)
