class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  url "https://github.com/PiusSunday/mac-cleanup/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "bdb1fe0409d083ea33d4801e34ed5d9cedb60abc6598b8aa9612fc7473a76cc9"
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
