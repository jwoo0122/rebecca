cask "rebecca" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/jwoo0122/rebecca/releases/download/v#{version}/Rebecca-#{version}.zip"
  name "Rebecca"
  desc "macOS GUI automation tool for AI agents"
  homepage "https://github.com/jwoo0122/rebecca"

  app "Rebecca.app"

  binary "Rebecca.app/Contents/Resources/bin/rebecca"

  uninstall delete: [
    "~/Library/Application Support/Rebecca",
  ]

  zap trash: [
    "~/Library/Application Support/Rebecca",
    "~/Library/Preferences/dev.jwoo0122.rebecca.plist",
  ]
end
