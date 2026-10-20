# Inert test values, injected into the test user by `base-config.nix`. Mixes secret
# files, password hashes and identity strings. NEVER use in a real deployment.
pkgs: {
  # 64-character string, satisfies most stacks' secret format requirements
  dummySecretFile = "${pkgs.writeText "dummy-secret" "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}";
  dummyClientSecretHash = "$pbkdf2-sha512$310000$1THCrOhCoICCVjNz7vfFMQ$2ercGVMG99CVVF42gs9BA4O9v.LlO3m8m8.6w0ynI0UFNJgnDPxadvgMTVc8mkCARlUSS5ZyxrSmm0WP31ZLSw";
  dummyUser = "admin";
  dummyEmail = "admin@example.com";
  dummyId = "dummy";
  dummySecret = "insecure_secret";
  dummyRsaKeyFile = "${pkgs.runCommand "dummy-rsa-key" {
    nativeBuildInputs = [pkgs.openssl];
  } "openssl genrsa -out $out 2048"}";
}
