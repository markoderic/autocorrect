cask "autocorrect" do
  version "0.3.7"
  sha256 "23b055f0b236b1ccdf85aad0aa98571ca13c451c56a9dd5ec67b1c50410b0422"

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
