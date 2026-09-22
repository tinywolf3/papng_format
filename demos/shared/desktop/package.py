"""Package desktop engine viewers and optional per-user file associations."""
from pathlib import Path
import json, shutil, tarfile, zipfile, hashlib

def package(root: Path, folder: Path, engine: str, platform: str, executable: Path):
    app=f'papng-{engine}-viewer'
    version=(root/'demos'/engine/'viewer/VERSION').read_text().strip()
    manifest={'id':f'org.tinygames.Papng{engine.title()}Viewer','name':f'PAPNG {engine.title()} Viewer','executable':str(executable.relative_to(folder)).replace('\\','/'),'argument':'-PapngFile=' if engine=='unreal' else ''}
    (folder/'app.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for name in ['associate.py']:
        shutil.copy2(root/'demos/shared/desktop'/name,folder/name)
    shutil.copy2(root/'demos/godot/viewer/icon.svg',folder/'icon.svg')
    shutil.copy2(root/'demos'/engine/'viewer/README.md',folder/'README.md')
    licenses=folder/'licenses';licenses.mkdir(exist_ok=True)
    shutil.copy2(root/'LICENSE',licenses/'PAPNG-MIT.txt')
    third=root/'demos/shared/papng/third_party'
    for name in ['miniz-LICENSE','stb-LICENSE.txt']:shutil.copy2(third/name,licenses/name)
    files=[]
    for path in folder.rglob('*'):
        rel=path.relative_to(folder)
        if any(part in {'project','licenses_unused','Saved','Intermediate'} or 'DontShip' in part for part in rel.parts):continue
        if path.name.startswith('Manifest_'):continue
        if path.is_file() and not path.name.endswith(('.log','.tar.gz','.zip','.sha256','.pdb','.debug','.sym','.obj','.lib','.exp')):files.append(path)
    archive=folder/f'{app}-{version}-{platform}-x86_64.{"zip" if platform=="windows" else "tar.gz"}'
    if platform=='windows':
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as output:
            for path in files:output.write(path,path.relative_to(folder))
    else:
        with tarfile.open(archive,'w:gz') as output:
            for path in files:output.add(path,arcname=path.relative_to(folder))
    (folder/(archive.name+'.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
    print('Package:',archive)
