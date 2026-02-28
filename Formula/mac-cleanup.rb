class MacCleanup < Formula
  desc "Modular macOS developer storage cleanup CLI"
  homepage "https://github.com/PiusSunday/mac-cleanup"
  url "https://github.com/PiusSunday/mac-cleanup/archive/v0.2.0.tar.gz"
  # SHA-256 placeholder — update with actual tarball hash before publishing:
  #   curl -sL https://github.com/PiusSunday/mac-cleanup/archive/v0.2.0.tar.gz | shasum -a 256
  # Current value is the hash of an empty file; brew install will fail until updated.
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  license "MIT"

  def install
    bin.install "bin/mac-cleanup"
    lib.install Dir["lib/*.sh"]

    # Patch the lib source path inside the binary
    inreplace bin/"mac-cleanup", 'LIB_DIR="${SCRIPT_DIR}/../lib"',
              "LIB_DIR=\"#{lib}\""
  end

  test do
    system "#{bin}/mac-cleanup", "--help"
  end
end
