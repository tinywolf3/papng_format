#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
data_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}
app_dir="$data_dir/papng-viewer"
for tool in xdg-mime update-desktop-database; do
  command -v "$tool" >/dev/null || { echo "Install xdg-utils and desktop-file-utils first." >&2; exit 1; }
done
mkdir -p "$app_dir" "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps"
previous=$(xdg-mime query default application/x-papng || true)
if [[ "$previous" != org.tinygames.PapngViewer.desktop && ! -e "$app_dir/previous-default" ]]; then
  printf '%s\n' "$previous" > "$app_dir/previous-default"
fi
for file in papng-viewer.x86_64 icon.svg LICENSE.txt Godot-LICENSE.txt Godot-COPYRIGHT.txt README.md tinygames-PapngViewer.xml uninstall.sh; do
  [[ "$source_dir/$file" == "$app_dir/$file" ]] || cp -- "$source_dir/$file" "$app_dir/$file"
done
chmod +x "$app_dir/papng-viewer.x86_64" "$app_dir/uninstall.sh"
cp -- "$app_dir/icon.svg" "$data_dir/icons/hicolor/scalable/apps/org.tinygames.PapngViewer.svg"
escaped=$(printf '%s' "$app_dir/papng-viewer.x86_64" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g; s/%/%%/g')
cat > "$data_dir/applications/org.tinygames.PapngViewer.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=PAPNG Viewer
Comment=View PAPNG, PNG and APNG images
Exec="$escaped" -- %f
Icon=org.tinygames.PapngViewer
Terminal=false
Categories=Graphics;Viewer;
MimeType=application/x-papng;image/png;image/apng;
StartupNotify=true
DESKTOP
xdg-mime install --mode user "$app_dir/tinygames-PapngViewer.xml"
update-desktop-database "$data_dir/applications"
xdg-mime default org.tinygames.PapngViewer.desktop application/x-papng
printf 'Installed: %s\nPAPNG association registered. PNG/APNG defaults are unchanged.\n' "$app_dir"
