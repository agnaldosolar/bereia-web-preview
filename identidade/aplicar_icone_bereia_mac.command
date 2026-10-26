#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Execute no Mac onde o Bereia está instalado.'
  exit 20
fi
icon_revision="${1:-}"
if [[ ! "$icon_revision" =~ ^[a-f0-9]{40}$ ]]; then
  echo 'O endereço fixo desta imagem não foi informado.'
  exit 21
fi
icon_app_path="$HOME/Bereia-Local/Aplicativo/BereiaMac.app"
if [[ ! -f "$icon_app_path/Contents/Info.plist" ]]; then
  echo 'Aplicativo não encontrado em Bereia-Local/Aplicativo/BereiaMac.app.'
  exit 22
fi
icon_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bereia-icone.XXXXXX")"
trap 'rm -rf "$icon_tmp_dir"' EXIT
icon_image_file="$icon_tmp_dir/Bereia.png"
echo 'Baixando o ícone do Bereia…'
/usr/bin/curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 --retry 2 \
  "https://raw.githubusercontent.com/agnaldosolar/bereia-web-preview/$icon_revision/identidade/bereia-icone.png" \
  --output "$icon_image_file"
icon_actual_sha="$(/usr/bin/shasum -a 256 "$icon_image_file")"
icon_actual_sha="${icon_actual_sha%% *}"
if [[ "$icon_actual_sha" != '94003fdf3dede26b6cd672ca1b2ed211a5c374ee7700d76978b960f6e597252a' ]]; then
  echo 'A imagem recebida não confere. O ícone atual foi preservado.'
  exit 23
fi
/usr/bin/xcrun swift - "$icon_image_file" "$icon_app_path" <<'SWIFT'
import AppKit
import Foundation
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]), image.isValid else {
    print("Imagem inválida. O ícone atual foi preservado."); exit(24)
}
let target = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
for running in NSWorkspace.shared.runningApplications where running.bundleURL?.standardizedFileURL == target {
    guard running.terminate() else {
        print("Feche o Bereia com Command + Q e execute novamente."); exit(25)
    }
    let deadline = Date().addingTimeInterval(30)
    while !running.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard running.isTerminated else {
        print("O Bereia ainda está aberto. Conclua o salvamento, feche-o e execute novamente."); exit(25)
    }
}
guard NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) else {
    print("O macOS não permitiu alterar o ícone deste aplicativo."); exit(26)
}
NSWorkspace.shared.noteFileSystemChanged(target.deletingLastPathComponent().path)
SWIFT
icon_saved_dir="$HOME/Bereia-Local/Identidade"
mkdir -p "$icon_saved_dir"
cp "$icon_image_file" "$icon_saved_dir/Bereia.png"
/usr/bin/touch "$icon_app_path"
icon_register='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ -x "$icon_register" ]]; then
  "$icon_register" -f "$icon_app_path" >/dev/null 2>&1 || true
fi
/usr/bin/killall Dock >/dev/null 2>&1 || true
/usr/bin/open "$icon_app_path"
echo 'Ícone aplicado ao Bereia local. Dados e hinos preservados.'
