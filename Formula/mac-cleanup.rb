class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  # url/sha256 are rewritten in the PiusSunday/homebrew-mac-cleanup tap by the
  # release workflow on every v*.*.* tag; this copy is the template and may lag
  # the published formula.
  url "https://github.com/PiusSunday/mac-cleanup/archive/refs/tags/v0.4.2.tar.gz"
  sha256 "89797863637a4ad418768179ab121f591bc8a19da9f5dd5c9dc1025927fe9f1e"
  license "MIT"
  head "https://github.com/PiusSunday/mac-cleanup.git", branch: "main"

  def install
    bin.install "bin/mac-cleanup"
    libexec.install Dir["lib/*"]

    # Patch the lib source path inside the binary
    inreplace bin/"mac-cleanup", 'LIB_DIR="${SCRIPT_DIR}/../lib"',
              "LIB_DIR=\"#{libexec}\""
  end

  test do
    system "#{bin}/mac-cleanup", "--help"
    assert_match "mac-cleanup v", shell_output("#{bin}/mac-cleanup --version")
  end
end
