{
  dummyClientSecretHash,
  dummySecretFile,
  ...
}: {
  imports = [../authelia/vm-test.nix];
  nps.stacks.homebox = {
    enable = true;
    apiKeyPepperFile = dummySecretFile;
    oidc = {
      enable = true;
      clientSecretFile = dummySecretFile;
      clientSecretHash = dummyClientSecretHash;
    };
    db = {
      type = "postgres";
      passwordFile = dummySecretFile;
    };
  };
}
