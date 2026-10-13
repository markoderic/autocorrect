cask "autocorrect" do
  version "0.3.14"
  sha256 "5aaadc913aa7c050683d1d5943944c1a4de5ed0fd572756841381cdbfec51898"

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
