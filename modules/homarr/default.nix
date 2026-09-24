{
  config,
  lib,
  ...
}: let
  name = "homarr";
  cfg = config.nps.stacks.${name};
  storage = "${config.nps.storageBaseDir}/${name}";

  category = "Network & Administration";
  description = "Personalized Dashboard";
  displayName = "Homarr";
in {
  imports = import ../mkAliases.nix config lib name [name];

  options.nps.stacks.${name} = {
    enable = lib.mkEnableOption name;
    secretEncryptionKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing a 64-character hexadecimal key used to encrypt Homarr secrets.";
    };
    authSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the Auth.js secret used to sign Homarr sessions.";
    };
    validationRoute.subDomain = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = ''
        Subdomain used for the Homarr validation route. Set this to a unique value,
        such as `homarr-preview`, to run Homarr alongside Homepage before cutover.
      '';
    };
    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable OIDC login with Authelia.";
      };
      clientSecretFile = (import ../authelia/options.nix lib).clientSecretFile;
      clientSecretHash = (import ../authelia/options.nix lib).derivableClientSecretHash cfg.oidc.clientSecretFile;
      userGroup = lib.mkOption {
        type = lib.types.str;
        default = "${name}_user";
        description = "Users in this group are allowed to sign in to Homarr.";
      };
      adminGroup = lib.mkOption {
        type = lib.types.str;
        default = "${name}_admin";
        description = "External IdP group to bootstrap. During Homarr external-provider onboarding, create or select a Homarr group with this exact name and grant it administrator permissions.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nps.stacks.lldap.bootstrap.groups = lib.mkIf cfg.oidc.enable {
      ${cfg.oidc.userGroup} = {};
      ${cfg.oidc.adminGroup} = {};
    };

    nps.stacks.authelia = lib.mkIf cfg.oidc.enable {
      oidc.clients.${name} = {
        client_name = displayName;
        client_secret = cfg.oidc.clientSecretHash;
        public = false;
        authorization_policy = name;
        require_pkce = true;
        pkce_challenge_method = "S256";
        pre_configured_consent_duration = config.nps.stacks.authelia.oidc.defaultConsentDuration;
        redirect_uris = [
          "${cfg.containers.${name}.traefik.serviceUrl}/api/auth/callback/oidc"
        ];
        scopes = ["openid" "profile" "email" "groups"];
        userinfo_signing_algorithm = "none";
      };

      settings.identity_providers.oidc.authorization_policies.${name} = {
        default_policy = "deny";
        rules = [
          {
            policy = config.nps.stacks.authelia.defaultAllowPolicy;
            subject = "group:${cfg.oidc.userGroup}";
          }
        ];
      };
    };

    services.podman.containers.${name} = {
      image = "ghcr.io/homarr-labs/homarr:v1.77.2";
      stack = name;
      volumeMap.appdata = "${storage}/appdata:/appdata";
      environment = {
        PUID = config.nps.defaultUid;
        PGID = config.nps.defaultGid;
        BASE_URL = config.services.podman.containers.${name}.traefik.serviceUrl;
        NEXTAUTH_URL = config.services.podman.containers.${name}.traefik.serviceUrl;
      };
      extraEnv =
        {
          SECRET_ENCRYPTION_KEY.fromFile = cfg.secretEncryptionKeyFile;
          AUTH_SECRET.fromFile = cfg.authSecretFile;
        }
        // lib.optionalAttrs cfg.oidc.enable {
          AUTH_PROVIDERS = "oidc";
          AUTH_OIDC_ISSUER = config.nps.containers.authelia.traefik.serviceUrl;
          AUTH_OIDC_CLIENT_ID = name;
          AUTH_OIDC_CLIENT_SECRET.fromFile = cfg.oidc.clientSecretFile;
          AUTH_OIDC_CLIENT_NAME = "Authelia";
          AUTH_OIDC_AUTO_LOGIN = true;
          AUTH_OIDC_SCOPE_OVERWRITE = "openid profile email groups";
          AUTH_OIDC_GROUPS_ATTRIBUTE = "groups";
          AUTH_OIDC_FORCE_USERINFO = true;
        };
      wantsContainer = lib.optional cfg.oidc.enable "authelia";
      port = 7575;
      traefik = {
        inherit name;
        subDomain = cfg.validationRoute.subDomain;
      };
      homepage = {
        inherit category;
        name = displayName;
        settings = {
          inherit description;
          icon = "homarr";
        };
      };
      glance = {
        inherit category description;
        name = displayName;
        id = name;
        icon = "di:homarr";
      };
    };
  };
}
