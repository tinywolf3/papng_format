#!/usr/bin/env bash
set -euo pipefail
data_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}
app_dir="$data_dir/papng-viewer"
if [[ "$(xdg-mime query default application/x-papng || true)" == org.tinygames.PapngViewer.desktop && -s "$app_dir/previous-default" ]]; then
  previous=$(cat -- "$app_dir/previous-default")
  [[ -z "$previous" ]] || xdg-mime default "$previous" application/x-papng
fi
# Remove only this application's references from user MIME lists.
config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}
for settings in "$config_dir"/*mimeapps.list "$data_dir/applications"/*mimeapps.list; do
  [[ ! -f "$settings" ]] || sed -i 's/org\.tinygames\.PapngViewer\.desktop;//g' "$settings"
done
[[ ! -f "$app_dir/tinygames-PapngViewer.xml" ]] || xdg-mime uninstall --mode user "$app_dir/tinygames-PapngViewer.xml"
rm -f -- "$data_dir/applications/org.tinygames.PapngViewer.desktop" "$data_dir/icons/hicolor/scalable/apps/org.tinygames.PapngViewer.svg"
for file in papng-viewer.x86_64 icon.svg LICENSE.txt Godot-LICENSE.txt Godot-COPYRIGHT.txt README.md tinygames-PapngViewer.xml previous-default uninstall.sh; do rm -f -- "$app_dir/$file"; done
rmdir -- "$app_dir" 2>/dev/null || true
update-desktop-database "$data_dir/applications"
printf 'PAPNG Viewer removed.\n'
