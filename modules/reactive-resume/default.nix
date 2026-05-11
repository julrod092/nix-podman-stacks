{
  config,
  lib,
  ...
}: let
  name = "reactive-resume";
  dbName = "${name}-db";
  chromeName = "${name}-chrome";
  jobOpsName = "job-ops";

  cfg = config.nps.stacks.${name};
  storage = "${config.nps.storageBaseDir}/${name}";

  category = "General";
  description = "Resume Builder";
  displayName = "Reactive Resume";
  jobOpsDescription = "Job Search Assistant";
  jobOpsDisplayName = "JobOps";
in {
  imports = import ../mkAliases.nix config lib name [
    name
    dbName
    chromeName
    jobOpsName
  ];

  options.nps.stacks.${name} = {
    enable = lib.mkEnableOption name;
    authSecretFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the file containing the auth secret.
        Can be generated using `openssl rand -hex 32`

        See <https://docs.rxresu.me/self-hosting/docker#authentication>
      '';
    };
    extraEnv = lib.mkOption {
      type = (import ../types.nix lib).extraEnv;
      default = {};
      description = ''
        Extra environment variables to set for the container.
        Variables can be either set directly or sourced from a file (e.g. for secrets).

        See <https://docs.rxresu.me/getting-started/quickstart#environment-variables-reference>
      '';
    };

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable OIDC login with Authelia. This will register an OIDC client in Authelia
          and setup the necessary configuration.

          For details, see:
          - <https://docs.rxresu.me/self-hosting/sso#authelia>
        '';
      };
      clientSecretFile = (import ../authelia/options.nix lib).clientSecretFile;
      clientSecretHash = (import ../authelia/options.nix lib).derivableClientSecretHash cfg.oidc.clientSecretFile;
      userGroup = lib.mkOption {
        type = lib.types.str;
        default = "${name}_user";
        description = ''
          Users of this group will be able to log in
        '';
      };
    };
    db = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "rxresume";
        description = ''
          The PostgreSQL user to use for the database.
        '';
      };
      passwordFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          The file containing the PostgreSQL password for the database.
        '';
      };
    };
    jobOps = {
      enable = lib.mkEnableOption "JobOps";
      rxResumeApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to the file containing a Reactive Resume v5 API key for JobOps.
          If unset, JobOps can still be configured through its onboarding flow.
        '';
      };
      extraEnv = lib.mkOption {
        type = (import ../types.nix lib).extraEnv;
        default = {};
        description = ''
          Extra environment variables to set for the JobOps container.
          Variables can be either set directly or sourced from a file (e.g. for secrets).

          See <https://github.com/DaKheera47/job-ops/blob/main/.env.example>
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nps.stacks.lldap.bootstrap.groups = lib.mkIf cfg.oidc.enable {
      ${cfg.oidc.userGroup} = {};
    };
    nps.stacks.authelia = lib.mkIf cfg.oidc.enable {
      oidc.clients.${name} = {
        client_name = displayName;
        client_secret = cfg.oidc.clientSecretHash;
        public = false;
        authorization_policy = name;
        require_pkce = false;
        pkce_challenge_method = "";
        pre_configured_consent_duration = config.nps.stacks.authelia.oidc.defaultConsentDuration;
        redirect_uris = [
          "${cfg.containers.${name}.traefik.serviceUrl}/api/auth/oauth2/callback/custom"
        ];
        token_endpoint_auth_method = "client_secret_post";
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

    services.podman.containers = {
      ${name} = {
        image = "ghcr.io/amruthpillai/reactive-resume:v5.1.9";
        user = "${toString config.nps.defaultUid}:${toString config.nps.defaultGid}";
        volumeMap = {
          data = "${storage}/data:/app/data";
        };

        extraEnv =
          {
            APP_URL = cfg.containers.${name}.traefik.serviceUrl;
            PRINTER_ENDPOINT = "http://${chromeName}:9222";
            PRINTER_APP_URL = "http://${name}:3000";
            AUTH_SECRET.fromFile = cfg.authSecretFile;
            DATABASE_URL.fromTemplate = "postgres://${cfg.db.username}:{{ file.Read `${cfg.db.passwordFile}` }}@${dbName}/rxresume?sslmode=disable";
          }
          // lib.optionalAttrs cfg.oidc.enable {
            FLAG_DISABLE_EMAIL_AUTH = lib.mkDefault true;
            OAUTH_PROVIDER_NAME = "Authelia";
            OAUTH_CLIENT_ID = name;
            OAUTH_CLIENT_SECRET.fromFile = cfg.oidc.clientSecretFile;
            OAUTH_DISCOVERY_URL = "${config.nps.containers.authelia.traefik.serviceUrl}/.well-known/openid-configuration";
          }
          // cfg.extraEnv;

        wantsContainer = [dbName chromeName];

        stack = name;
        port = 3000;
        traefik.name = name;
        homepage = {
          inherit category;
          name = displayName;
          settings = {
            inherit description;
            icon = "reactive-resume";
          };
        };
        glance = {
          inherit category description;
          name = displayName;
          id = name;
          icon = "di:reactive-resume";
        };
      };

      ${chromeName} = {
        image = "docker.io/chromedp/headless-shell:latest";
        stack = name;
        glance = {
          parent = name;
          name = "Chrome";
          icon = "di:chrome";
          inherit category;
        };
      };

      ${dbName} = {
        image = "docker.io/postgres:18";
        volumeMap.data = "${storage}/postgres:/var/lib/postgresql";
        extraEnv = {
          POSTGRES_DB = "rxresume";
          POSTGRES_USER = cfg.db.username;
          POSTGRES_PASSWORD.fromFile = cfg.db.passwordFile;
        };

        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "pg_isready -d rxresume -U ${cfg.db.username}";
          HealthInterval = "10s";
          HealthTimeout = "10s";
          HealthRetries = 5;
          HealthStartPeriod = "10s";
        };

        stack = name;
        glance = {
          parent = name;
          name = "Postgres";
          icon = "di:postgres";
          inherit category;
        };
      };

      ${jobOpsName} = lib.mkIf cfg.jobOps.enable {
        image = "ghcr.io/dakheera47/job-ops:v0.6.2";
        volumeMap = {
          data = "${storage}/job-ops/data:/app/data";
          codexHome = "${storage}/job-ops/codex-home:/app/codex-home";
        };

        extraEnv =
          {
            NODE_ENV = "production";
            PORT = 3001;
            PYTHON_PATH = "/usr/bin/python3";
            CODEX_HOME = "/app/codex-home";
            JOBOPS_PUBLIC_BASE_URL = cfg.containers.${jobOpsName}.traefik.serviceUrl;
            RXRESUME_URL = "http://${name}:3000";
          }
          // lib.optionalAttrs (cfg.jobOps.rxResumeApiKeyFile != null) {
            RXRESUME_API_KEY.fromFile = cfg.jobOps.rxResumeApiKeyFile;
          }
          // cfg.jobOps.extraEnv;

        wantsContainer = [name];

        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "curl -f http://localhost:3001/health";
          HealthInterval = "30s";
          HealthTimeout = "10s";
          HealthRetries = 3;
          HealthStartPeriod = "10s";
        };

        stack = name;
        port = 3001;
        traefik.name = jobOpsName;
        homepage = {
          inherit category;
          name = jobOpsDisplayName;
          settings = {
            description = jobOpsDescription;
            icon = "job-ops";
          };
        };
        glance = {
          inherit category;
          description = jobOpsDescription;
          name = jobOpsDisplayName;
          id = jobOpsName;
          icon = "sh:job-ops";
        };
      };
    };
  };
}
