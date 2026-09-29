cask "autocorrect" do
  version "0.3.5"
  sha256 "26826d8a8b38129882dbfceba6c57744d285cb0ac30612386f2a5b6b06df9e43"

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
