class Bursula < Formula
  desc "Fetch and file your invoices"
  homepage "https://github.com/Bursula/homebrew-tap"
  url "https://github.com/Bursula/homebrew-tap/releases/download/v0.3.7/bursula-0.3.7.tgz"
  sha256 "90110c45e651d2a7da5042945b2f170bddda49549567080c1685a06e41f273b1"
  license :cannot_represent

  depends_on "python" => :build
  depends_on "node"

  def install
    # better-sqlite3 is a native dependency and must run its reviewed npm install script.
    system "npm", "install", *std_npm_args(ignore_scripts: false)
    bin.install_symlink libexec/"bin/bursula"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/bursula --version").strip
    assert_match "automation:chatgpt", shell_output("#{bin}/bursula automations list")

    sqlite_module = libexec/"lib/node_modules/bursula/node_modules/better-sqlite3"
    script = <<~JS
      const Database = require("#{sqlite_module}");
      const database = new Database(":memory:");
      const result = database.prepare("SELECT 1 AS value").get();
      database.close();
      if (result.value !== 1) process.exit(1);
    JS
    system formula_opt_bin("node")/"node", "-e", script
  end
end
