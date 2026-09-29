cask "autocorrect" do
  version "0.2.0"
  sha256 "b213739b27440ec0a03ee6d1c930c789f8169bf7f2a6fe0659b4a6730f169629"

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
