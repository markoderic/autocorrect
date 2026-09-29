cask "autocorrect" do
  version "0.2.1"
  sha256 "8e862173ce809f96f6715cea9dab7771dd399840d5445dcde0a43382c44236b8"

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
