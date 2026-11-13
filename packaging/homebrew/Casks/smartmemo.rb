# frozen_string_literal: true

# Cask di SmartMemo per il tap GGuidotz/homebrew-tap. Version e sha256 li aggiorna release.sh.
cask "smartmemo" do
  version "0.2.0"
  sha256 "a36b6e6ff81c4af9fe0088e25b32159e9e93e79ccb1b19c6dcaea79dd5c21010"

  url "https://github.com/GGuidotz/smartmemo/releases/download/v#{version}/SmartMemo-#{version}.dmg"
  name "SmartMemo"
  desc "Notes and to-dos that recognise projects, people and dates as you type"
  homepage "https://github.com/GGuidotz/smartmemo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "SmartMemo.app"

  postflight_steps do
    # L'app non è notarizzata (niente account Apple Developer): togliere la quarantena evita "Apri comunque".
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/SmartMemo.app"],
        writable_paths: ["{{appdir}}/SmartMemo.app"],
        must_succeed:   false
  end

  uninstall quit: "local.smartmemo.app"

  zap trash: [
    "~/Library/Application Support/SmartMemo",
    "~/Library/Preferences/local.smartmemo.app.plist",
  ]

  caveats <<~EOS
    Quick open from any app: Control-Option-Space.
    Notes are Markdown files in iCloud Drive/SmartMemo (or Documents/SmartMemo) and are kept on uninstall.
  EOS
end
