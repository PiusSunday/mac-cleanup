class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  url "https://github.com/PiusSunday/mac-cleanup/archive/refs/tags/v0.3.1.tar.gz"
  sha256 "4edd56bb805e62415f21b8600a3ae6786bdffb9c87efc98a2650f4f6ba87b354"
  license "MIT"

  def install
    bin.install "bin/mac-cleanup"
    libexec.install Dir["lib/*.sh"]

    # Patch the lib source path inside the binary
    inreplace bin/"mac-cleanup", 'LIB_DIR="${SCRIPT_DIR}/../lib"',
              "LIB_DIR=\"#{libexec}\""
  end

  test do
    system "#{bin}/mac-cleanup", "--help"
  end
end
