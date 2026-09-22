#!/usr/bin/env python3
"""Register this unpacked viewer in Open With; never change PNG/APNG defaults."""
from pathlib import Path
import argparse, json, os, subprocess, sys
ROOT=Path(__file__).resolve().parent
# Build-generated strict JSON; keep the optional installer standard-library-only.
APP=json.loads((ROOT/'app.json').read_text())
p=argparse.ArgumentParser();p.add_argument('--remove',action='store_true');a=p.parse_args()
exe=(ROOT/APP['executable']).resolve()
if not exe.is_file():raise SystemExit('Keep this script beside the complete unpacked application.')
if sys.platform=='win32':
    import winreg
    base='Software\\Classes\\'+APP['id']
    def setkey(path,name,value):
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER,path) as key:winreg.SetValueEx(key,name,0,winreg.REG_SZ,value)
    def remove_tree(path):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,path,0,winreg.KEY_READ|winreg.KEY_WRITE) as key:
                children=[];i=0
                while True:
                    try:children.append(winreg.EnumKey(key,i));i+=1
                    except OSError:break
            for child in children:remove_tree(path+'\\'+child)
            winreg.DeleteKey(winreg.HKEY_CURRENT_USER,path)
        except FileNotFoundError:pass
    if a.remove:
        remove_tree(base)
        for ext in ['.papng','.apng','.png']:
            try:
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER,'Software\\Classes\\'+ext+'\\OpenWithProgids',0,winreg.KEY_SET_VALUE) as key:winreg.DeleteValue(key,APP['id'])
            except FileNotFoundError:pass
    else:
        setkey(base,'',APP['name']);setkey(base+'\\shell\\open\\command','',f'"{exe}" {APP["argument"]}"%1"')
        setkey(base+'\\Application','ApplicationName',APP['name'])
        for ext in ['.papng','.apng','.png']:
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER,'Software\\Classes\\'+ext+'\\OpenWithProgids') as key:winreg.SetValueEx(key,APP['id'],0,winreg.REG_NONE,b'')
    import ctypes
    ctypes.windll.shell32.SHChangeNotify(0x08000000,0,None,None)
    print('Removed application association.' if a.remove else 'Registered in Open With. Choose this app in Windows Default apps to make it the default.')
elif sys.platform.startswith('linux'):
    data=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))
    desktop=data/'applications'/(APP['id']+'.desktop');mime=data/'mime/packages'/(APP['id']+'.xml')
    for tool in ['update-desktop-database','update-mime-database']:
        import shutil
        if not shutil.which(tool):raise SystemExit('Install desktop-file-utils and shared-mime-info first.')
    if a.remove:
        desktop.unlink(missing_ok=True);mime.unlink(missing_ok=True)
    else:
        def quoted(s):
            for old,new in [('\\','\\\\'),('"','\\"'),('`','\\`'),('$','\\$'),('%','%%')]:s=s.replace(old,new)
            return '"'+s+'"'
        desktop.parent.mkdir(parents=True,exist_ok=True);mime.parent.mkdir(parents=True,exist_ok=True)
        command=quoted(str(exe))+' %f'
        desktop.write_text('[Desktop Entry]\nType=Application\nName='+APP['name']+'\nExec='+command+'\nIcon='+str(ROOT/'icon.svg')+'\nTerminal=false\nCategories=Graphics;Viewer;\nMimeType=application/x-papng;image/png;image/apng;\n')
        mime.write_text('<?xml version="1.0"?><mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info"><mime-type type="application/x-papng"><comment>PAPNG pixel art animation</comment><sub-class-of type="image/png"/><glob pattern="*.papng"/></mime-type></mime-info>')
    if desktop.parent.exists():subprocess.run(['update-desktop-database',str(desktop.parent)],check=True)
    if mime.parent.parent.exists():subprocess.run(['update-mime-database',str(mime.parent.parent)],check=True)
    print('Removed association.' if a.remove else 'Registered in Open With. Keep this application directory in place.')
else:raise SystemExit('Supported registration platforms: Linux and Windows.')
