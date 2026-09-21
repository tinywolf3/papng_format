#!/usr/bin/env python3
"""Build Linux/Windows and Android PAPNG Editor distributions."""
import argparse, hashlib, os, shutil, subprocess, tarfile, zipfile
from pathlib import Path
from common import ROOT, PROJECT, TOOLS, environment, run_godot
p=argparse.ArgumentParser();p.add_argument('platforms',nargs='*',choices=['linux','windows','android'],default=['linux','windows']);p.add_argument('--templates',type=Path);args=p.parse_args()
templates=TOOLS/'templates';templates.mkdir(parents=True,exist_ok=True)
names=['linux_release.x86_64','linux_debug.x86_64','windows_release_x86_64.exe','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe','android_source.zip','version.txt']
if args.templates:
    if args.templates.is_dir():
        if (args.templates/'version.txt').read_text().strip()!='4.7.2.stable':raise SystemExit('Template version mismatch')
        for name in names:shutil.copyfile(args.templates/name,templates/name)
    else:
        with zipfile.ZipFile(args.templates) as archive:
            if archive.read('templates/version.txt').decode().strip()!='4.7.2.stable':raise SystemExit('Template version mismatch')
            for name in names:(templates/name).write_bytes(archive.read('templates/'+name))
if not (templates/'version.txt').exists() or (templates/'version.txt').read_text().strip()!='4.7.2.stable':raise SystemExit('Provide official Godot 4.7.2 export templates via --templates.')
run_godot(['--headless','--editor','--import','--quit'],ROOT/'builds/linux/papng-editor-tests/build-import.log')
version=(PROJECT/'VERSION').read_text().strip()
for platform in args.platforms:
    out=ROOT/'builds'/platform/'papng-editor';out.mkdir(parents=True,exist_ok=True)
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
        target=out/'papng-editor-debug.apk'
        run_godot(['--headless','--export-debug','Android',target],out/'export.log',timeout=900,env=env)
        subprocess.run([str(sdk/'build-tools/36.1.0/apksigner'),'verify','--verbose',str(target)],check=True)
        subprocess.run([str(sdk/'build-tools/36.1.0/zipalign'),'-c','-P','16','4',str(target)],check=True)
    else:
        target=out/('papng-editor.x86_64' if platform=='linux' else 'papng-editor.exe')
        run_godot(['--headless','--export-release',platform.title(),target],out/'export.log')
        if platform=='linux':target.chmod(0o755)
    for name in ['Godot-LICENSE.txt','Godot-COPYRIGHT.txt']:shutil.copyfile(PROJECT/'licenses'/name,out/name)
    shutil.copyfile(ROOT/'LICENSE',out/'LICENSE.txt');shutil.copyfile(PROJECT/'README.md',out/'README.md')
    files=[target,out/'README.md',out/'LICENSE.txt',out/'Godot-LICENSE.txt',out/'Godot-COPYRIGHT.txt']
    artifacts=[target]
    if platform!='android':
        archive_path=out/f'papng-editor-{version}-{platform}-x86_64.{"tar.gz" if platform=="linux" else "zip"}'
        if platform=='linux':
            with tarfile.open(archive_path,'w:gz') as archive:
                for file in files:archive.add(file,arcname='papng-editor/'+file.name)
        else:
            with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED) as archive:
                for file in files:archive.write(file,arcname='papng-editor/'+file.name)
        artifacts.append(archive_path)
    for file in artifacts:file.with_name(file.name+'.sha256').write_text(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.name+'\n')
    print(f'BUILT {version}: {target}')
