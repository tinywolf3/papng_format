#!/usr/bin/env python3
"""Build standalone viewers with matching official export templates."""
import argparse, hashlib, os, shutil, subprocess, tarfile, zipfile
from pathlib import Path
from common import ROOT, PROJECT, TOOLS, VERSION, environment, run_godot

parser=argparse.ArgumentParser()
parser.add_argument('platforms', nargs='*', choices=['linux','windows','android'],default=['linux','windows','android'])
parser.add_argument('--templates',type=Path,help='Official Godot export_templates.tpz archive or extracted templates directory')
args=parser.parse_args()
templates=TOOLS/'templates';templates.mkdir(parents=True,exist_ok=True)
if args.templates:
    if args.templates.is_dir():
        if (args.templates/'version.txt').read_text().strip()!=VERSION+'.stable': raise SystemExit('Template version mismatch')
        for name in ['linux_release.x86_64','linux_debug.x86_64','windows_release_x86_64.exe','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe','android_source.zip','version.txt']:
            shutil.copyfile(args.templates/name,templates/name)
    else:
        with zipfile.ZipFile(args.templates) as archive:
            if archive.read('templates/version.txt').decode().strip()!=VERSION+'.stable': raise SystemExit('Template version mismatch')
            for name in ['linux_release.x86_64','linux_debug.x86_64','windows_release_x86_64.exe','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe','android_source.zip','version.txt']:
                (templates/name).write_bytes(archive.read('templates/'+name))
if not (templates/'version.txt').exists(): raise SystemExit('Provide --templates with the official Godot 4.7.2 export templates.')
if (templates/'version.txt').read_text().strip()!=VERSION+'.stable': raise SystemExit('Template version mismatch')
version=(PROJECT/'VERSION').read_text().strip()
logs=ROOT/'builds/linux/papng-viewer-tests'
run_godot(['--headless','--editor','--import','--quit'],logs/'import.log')
for platform in args.platforms:
    out=ROOT/'builds'/platform/'papng-viewer';out.mkdir(parents=True,exist_ok=True)
    env=environment()
    if platform=='android':
        sdk=Path(os.environ.get('ANDROID_HOME',str(Path.home()/'Android/Sdk')))
        java=Path(os.environ.get('JAVA_HOME',str(Path(shutil.which('java') or '').resolve().parents[1])))
        env.update(ANDROID_HOME=str(sdk),JAVA_HOME=str(java))
        if not (sdk/'build-tools/36.1.0/apksigner').exists(): raise SystemExit('Install Android SDK build-tools 36.1.0; set ANDROID_HOME if necessary.')
        gradle=out/'gradle/build'
        if not (gradle/'build.gradle').exists():
            with zipfile.ZipFile(templates/'android_source.zip') as archive: archive.extractall(gradle)
        (gradle/'gradlew').chmod(0o755)
        # The export directory marker is used by Godot to verify its template version.
        (gradle.parent/'.build_version').write_text('../../../builds/linux/viewer-tools/templates/android_source.zip ['+hashlib.md5((templates/'android_source.zip').read_bytes()).hexdigest()+']\n')
        (gradle/'.gdignore').touch()
        # Keep the template manifest pristine; the editor export plugin adds intents.
        with zipfile.ZipFile(templates/'android_source.zip') as archive:
            (gradle/'src/main/AndroidManifest.xml').write_bytes(archive.read('src/main/AndroidManifest.xml'))
        key=TOOLS/'debug.keystore'
        if not key.exists():
            subprocess.run([str(java/'bin/keytool'),'-genkeypair','-keystore',str(key),'-storepass','android','-alias','androiddebugkey','-keypass','android','-dname','CN=Android Debug,O=Android,C=US','-keyalg','RSA','-keysize','2048','-validity','10000'],check=True,capture_output=True)
        settings=TOOLS/'config/godot/editor_settings-4.7.tres';settings.parent.mkdir(parents=True,exist_ok=True)
        # Godot paths are POSIX here; no credentials other than the standard local debug key.
        settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'+f'export/android/android_sdk_path = "{sdk}"\nexport/android/java_sdk_path = "{java}"\nexport/android/debug_keystore = "{key}"\nexport/android/debug_keystore_user = "androiddebugkey"\nexport/android/debug_keystore_pass = "android"\n')
        target=out/'papng-viewer-debug.apk'
        run_godot(['--headless','--export-debug','Android',target],out/'export.log',timeout=900,env=env)
        subprocess.run([str(sdk/'build-tools/36.1.0/apksigner'),'verify','--verbose',str(target)],check=True)
        subprocess.run([str(sdk/'build-tools/36.1.0/zipalign'),'-c','-P','16','4',str(target)],check=True)
    else:
        target=out/('papng-viewer.x86_64' if platform=='linux' else 'papng-viewer.exe')
        run_godot(['--headless','--export-release',platform.title(),target],out/'export.log')
        if platform=='linux':
            target.chmod(0o755)
            for name in ['install.sh','uninstall.sh','tinygames-PapngViewer.xml']:
                shutil.copyfile(ROOT/'packaging/linux'/name,out/name)
            (out/'install.sh').chmod(0o755);(out/'uninstall.sh').chmod(0o755)
        else:
            for name in ['install.ps1','uninstall.ps1']:
                shutil.copyfile(ROOT/'packaging/windows'/name,out/name)
    for name in ['Godot-LICENSE.txt','Godot-COPYRIGHT.txt']:
        shutil.copyfile(PROJECT/'licenses'/name,out/name)
    shutil.copyfile(ROOT/'LICENSE',out/'LICENSE.txt')
    shutil.copyfile(PROJECT/'icon.svg',out/'icon.svg')
    shutil.copyfile(PROJECT/'README.md',out/'README.md')
    target.with_suffix(target.suffix+'.sha256').write_text(hashlib.sha256(target.read_bytes()).hexdigest()+'  '+target.name+'\n')
    if platform != 'android':
        names=[target.name,target.name+'.sha256','README.md','LICENSE.txt','Godot-LICENSE.txt','Godot-COPYRIGHT.txt','icon.svg']
        names += ['install.sh','uninstall.sh','tinygames-PapngViewer.xml'] if platform=='linux' else ['install.ps1','uninstall.ps1']
        archive_path=out/f'papng-viewer-{version}-{platform}-x86_64.{"tar.gz" if platform=="linux" else "zip"}'
        if platform=='linux':
            with tarfile.open(archive_path,'w:gz') as archive:
                for name in names: archive.add(out/name,arcname='papng-viewer/'+name)
        else:
            with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED) as archive:
                for name in names: archive.write(out/name,arcname='papng-viewer/'+name)
        archive_path.with_name(archive_path.name+'.sha256').write_text(hashlib.sha256(archive_path.read_bytes()).hexdigest()+'  '+archive_path.name+'\n')
    print(f'BUILT {version}: {target}')
