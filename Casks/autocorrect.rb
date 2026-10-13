cask "autocorrect" do
  version "0.3.15"
  sha256 "834f5a45862365af671d5b349ad94bc9c216cc110b4de9a282f10c099663e8c0"

  url "https://github.com/markoderic/autocorrect/releases/download/v#{version}/AutoCorrect-#{version}-universal.zip"
  name "AutoCorrect"
  desc "Small offline menu bar spelling correction for macOS"
  homepage "https://github.com/markoderic/autocorrect"

  depends_on macos: :ventura
  app "AutoCorrect.app"

  caveats <<~EOS
    AutoCorrect requires Accessibility and Input Monitoring permission.
    This preview is Developer ID signed and Apple notarized.
    Review the project before granting typing-related permissions.
  EOS
end
