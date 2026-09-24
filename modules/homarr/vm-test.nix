{
  dummyHash,
  dummySecretFile,
  ...
}: {
  imports = [../authelia/vm-test.nix];

  nps.stacks.homarr = {
    enable = true;
    secretEncryptionKeyFile = dummySecretFile;
    authSecretFile = dummySecretFile;
    oidc = {
      enable = true;
      clientSecretFile = dummySecretFile;
      clientSecretHash = dummyHash;
    };
  };
}
