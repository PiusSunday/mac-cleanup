class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  # url and sha256 are rewritten by the release workflow on every v*.*.* tag.
  # They pin the immutable tarball attached to that GitHub release, not GitHub's
  # generated archive (whose bytes change if history is ever rewritten). The
  # values below deliberately mirror the latest published release.
  url "https://github.com/PiusSunday/mac-cleanup/releases/download/v0.6.0/mac-cleanup-0.6.0.tar.gz"
  sha256 "4dedab753ce08870623332b22553123b6c4a237570f72c7cfeb882316830fc47"
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
