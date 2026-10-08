#!/bin/bash
set -e

wget -q https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip -O godot.zip
unzip -oq godot.zip
chmod +x Godot_v4.5.1-stable_linux.x86_64

wget -q https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz -O templates.tpz
mkdir -p ~/.local/share/godot/export_templates/4.5.1.stable
unzip -oq templates.tpz 'templates/*' -d /tmp/godot-templates
cp -r /tmp/godot-templates/templates/. ~/.local/share/godot/export_templates/4.5.1.stable/

./Godot_v4.5.1-stable_linux.x86_64 --headless --path . --import
mkdir -p build/web
./Godot_v4.5.1-stable_linux.x86_64 --headless --path . --export-release "Web" build/web/index.html
