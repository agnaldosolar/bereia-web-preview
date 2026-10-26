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
  "https://raw.githubusercontent.com/agnaldosolar/bereia-web-preview/$icon_revision/identidade/bereia-icone-macos.png" \
  --output "$icon_image_file"
icon_actual_sha="$(/usr/bin/shasum -a 256 "$icon_image_file")"
icon_actual_sha="${icon_actual_sha%% *}"
if [[ "$icon_actual_sha" != 'd240688cbff3d12b76a8d01b9c8cd5069c00cb5427b47036e53c64788031e7e3' ]]; then
  echo 'A imagem recebida não confere. O ícone atual foi preservado.'
  exit 23
fi
icon_saved_dir="$HOME/Bereia-Local/Identidade"
mkdir -p "$icon_saved_dir"
/usr/bin/xcrun swift - "$icon_image_file" "$icon_app_path" "$icon_saved_dir/Bereia.png" <<'SWIFT'
import AppKit
import Foundation
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
guard CommandLine.arguments.count == 4,
      let original = NSImage(contentsOfFile: CommandLine.arguments[1]), original.isValid else {
    print("Imagem inválida. O ícone atual foi preservado."); exit(24)
}
// Transparent 1024px canvas, with the visible tile precisely 824px square.
// Original alpha >= 128 bounds: (70,81)-(1184,1164), PNG 1254 x 1254.
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    print("Não foi possível preparar o ícone."); exit(27)
}
original.size = NSSize(width: 1254, height: 1254)
let scaleX: CGFloat = 824.0 / 1114.0
let scaleY: CGFloat = 824.0 / 1083.0
let rectangle = NSRect(x: 512 - 627 * scaleX, y: 512 - 631.5 * scaleY,
                       width: 1254 * scaleX, height: 1254 * scaleY)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
graphics.cgContext.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
original.draw(in: rectangle, from: NSRect(origin: .zero, size: original.size), operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.addRepresentation(bitmap)
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
do {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Não foi possível guardar o ícone ajustado."); exit(28)
    }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
    let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask,
        appropriateFor: nil, create: false)
    let shortcut = desktop.appendingPathComponent("Bereia Local.alias")
    if FileManager.default.fileExists(atPath: shortcut.path) {
        let info = try shortcut.resourceValues(forKeys: [.isAliasFileKey])
        guard info.isAliasFile == true else {
            print("Já existe um arquivo comum chamado Bereia Local.alias. Ele foi preservado."); exit(29)
        }
    }
    let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile,
        includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(bookmark, to: shortcut)
    guard NSWorkspace.shared.setIcon(image, forFile: shortcut.path, options: []) else {
        print("Ícone do aplicativo ajustado, mas o macOS não atualizou o atalho."); exit(30)
    }
    NSWorkspace.shared.noteFileSystemChanged(desktop.path)
} catch {
    print("Ícone do aplicativo ajustado; falha ao concluir o atalho: \(error.localizedDescription)"); exit(31)
}
NSWorkspace.shared.noteFileSystemChanged(target.deletingLastPathComponent().path)
SWIFT
/usr/bin/touch "$icon_app_path"
icon_register='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ -x "$icon_register" ]]; then
  "$icon_register" -f "$icon_app_path" >/dev/null 2>&1 || true
fi
/usr/bin/killall Dock >/dev/null 2>&1 || true
/usr/bin/open "$icon_app_path"
echo 'Ícone ajustado ao padrão do Mac no aplicativo e no atalho Bereia Local da Mesa. Dados e hinos preservados.'
