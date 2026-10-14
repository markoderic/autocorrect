cask "autocorrect" do
  version "0.3.16"
  sha256 "0ed68a6a8f0a335d7ee979c1c6ec2c64733015b80f3ef30d864892763d073d9b"

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
