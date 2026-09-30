cask "autocorrect" do
  version "0.3.9"
  sha256 "54b24f219f5e0c4d6ddae4b27b8bf4266c3a3efd83f7dfd74eb2c9c3c9091f24"

  url "https://github.com/markoderic/autocorrect/releases/download/v#{version}/AutoCorrect-#{version}-universal.zip"
  name "AutoCorrect"
  desc "Small offline menu bar spelling correction for macOS"
  homepage "https://github.com/markoderic/autocorrect"

  depends_on macos: :ventura
  app "AutoCorrect.app"

  caveats <<~EOS
    AutoCorrect requires Accessibility and Input Monitoring permission.
    This community build is not notarized. Review the project before granting
    permissions, then use macOS Privacy & Security to approve opening it.
  EOS
end
