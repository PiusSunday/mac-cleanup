class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  url "https://github.com/PiusSunday/mac-cleanup/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "331edf8297b776b0ebb1813e86ae659927482cba3c34063f382040d46baa49c3"
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
