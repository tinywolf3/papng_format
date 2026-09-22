#!/usr/bin/env python3
"""Build a standalone Unity viewer in builds/<platform>/papng-unity-viewer/."""
from pathlib import Path
import argparse, os, shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[3]
SOURCE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('platform',choices=['linux','windows']);p.add_argument('--unity',default=os.environ.get('UNITY_BIN',str(Path.home()/'Unity/Hub/Editor/6000.5.7f1/Editor/Unity')));a=p.parse_args()
out=ROOT/'builds'/a.platform/'papng-unity-viewer';out.mkdir(parents=True,exist_ok=True)
project=out/'project';project.mkdir(exist_ok=True)
if (project/'Assets').exists():shutil.rmtree(project/'Assets')
for folder in ('Assets','Packages','ProjectSettings'):shutil.copytree(SOURCE/folder,project/folder,dirs_exist_ok=True)
core=ROOT/'demos/shared/papng'
flags=[]
if a.platform=='windows':
    compiler=os.environ.get('CXX_WINDOWS','cl' if os.name=='nt' else 'x86_64-w64-mingw32-g++');plugin=project/'Assets/Plugins/x86_64/papng.dll'
    flags=['-static-libgcc','-static-libstdc++']
else:compiler=os.environ.get('CXX','c++');plugin=project/'Assets/Plugins/x86_64/libpapng.so'
if not shutil.which(compiler):raise SystemExit(f'Missing C++ compiler: {compiler}. On Windows run in a Visual Studio x64 Native Tools terminal.')
plugin.parent.mkdir(parents=True,exist_ok=True)
if Path(compiler).stem.lower()=='cl':
    subprocess.run([compiler,'/nologo','/std:c++17','/O2','/LD','/EHsc','/utf-8',str(core/'papng.cpp'),'/link','/OUT:'+str(plugin)],cwd=out,check=True)
else:subprocess.run([compiler,'-std=c++17','-O2','-fPIC','-shared',str(core/'papng.cpp'),'-o',str(plugin),*flags],check=True)
product=out/('papng-unity-viewer.exe' if a.platform=='windows' else 'papng-unity-viewer.x86_64')
env=dict(os.environ,PAPNG_PLATFORM=a.platform,PAPNG_OUTPUT=str(product))
log=out/'build.log';print('Unity build log:',log,flush=True)
subprocess.run([a.unity,'-batchmode','-nographics','-quit','-projectPath',str(project),'-buildTarget',{'linux':'Linux64','windows':'Win64'}[a.platform],'-executeMethod','BuildViewer.Build','-logFile',str(log)],env=env,check=True,timeout=3600)
print('Built:',product)

sys.path.insert(0,str(ROOT/"demos/shared/desktop"))
from package import package
package(ROOT,out,"unity",a.platform,product)
