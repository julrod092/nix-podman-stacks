{
  config,
  lib,
  pkgs,
  ...
}: let
  name = "appflowy";
  cloudName = "${name}-cloud";
  gotrueName = "${name}-gotrue";
  oidcBootstrapName = "${name}-oidc-bootstrap";
  workerName = "${name}-worker";
  searchName = "${name}-search";
  adminFrontendName = "${name}-admin";
  dbName = "${name}-db";
  redisName = "${name}-redis";
  minioName = "${name}-minio";

  cfg = config.nps.stacks.${name};
  storage = "${config.nps.storageBaseDir}/${name}";

  utils = import ../utils.nix {inherit lib config;};
  extraEnvType = (import ../types.nix lib).extraEnv;

  category = "General";
  description = "Open source workspace for wikis, projects, and notes";
  displayName = "AppFlowy";

  serviceHost = cfg.containers.${name}.traefik.serviceHost;
  serviceUrl = cfg.containers.${name}.traefik.serviceUrl;
  accessMiddleware =
    if cfg.containers.${name}.expose
    then "public@file"
    else "private@file";
  mkMiddlewares = middlewares: builtins.concatStringsSep "," (middlewares ++ [accessMiddleware]);

  wsBaseUrl =
    if config.nps.stacks.traefik.enable
    then "wss://${serviceHost}/ws/v2"
    else "ws://${serviceHost}/ws/v2";
  dbUrl = "postgres://${cfg.db.username}:{{ file.Read `${cfg.db.passwordFile}` }}@${dbName}:5432/${cfg.db.name}";
  redisUrl = "redis://${redisName}:6379";
  minioUrl = "http://${minioName}:9000";
  bucket = "appflowy";

  oidcBootstrapScript = pkgs.writeText "appflowy-oidc-bootstrap.py" ''
    import base64
    import hashlib
    import hmac
    import json
    import os
    import time
    import urllib.error
    import urllib.parse
    import urllib.request

    def b64url(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

    def admin_token(secret):
        now = int(time.time())
        header = {"alg": "HS256", "typ": "JWT"}
        payload = {
            "aud": "authenticated",
            "exp": now + 3600,
            "iat": now,
            "role": "service_role",
            "sub": "00000000-0000-0000-0000-000000000000",
        }
        signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
        signature = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
        return f"{signing_input}.{b64url(signature)}"

    def request(method, url, token, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Content-Type", "application/json")
        return urllib.request.urlopen(req, timeout=30)

    gotrue_url = os.environ["GOTRUE_URL"].rstrip("/")
    identifier = os.environ["OIDC_IDENTIFIER"]
    encoded_identifier = urllib.parse.quote(identifier, safe="")
    token = admin_token(os.environ["GOTRUE_JWT_SECRET"])
    enabled = True
    skip_nonce_check = False

    body = {
        "provider_type": "oidc",
        "identifier": identifier,
        "name": os.environ["OIDC_NAME"],
        "client_id": os.environ["OIDC_CLIENT_ID"],
        "client_secret": os.environ["OIDC_CLIENT_SECRET"],
        "issuer": os.environ["OIDC_ISSUER"],
        "scopes": ["openid", "profile", "email"],
        "pkce_enabled": True,
        "enabled": enabled,
        "email_optional": False,
        "skip_nonce_check": skip_nonce_check,
    }

    for _ in range(60):
        try:
            request("GET", f"{gotrue_url}/health", token).read()
            break
        except Exception:
            time.sleep(2)
    else:
        raise SystemExit("GoTrue did not become healthy")

    provider_url = f"{gotrue_url}/admin/custom-providers/{encoded_identifier}"
    try:
        request("GET", provider_url, token).read()
        request("PUT", provider_url, token, body).read()
        print(f"Updated AppFlowy OIDC provider {identifier}")
    except urllib.error.HTTPError as err:
        if err.code != 404:
            raise
        request("POST", f"{gotrue_url}/admin/custom-providers", token, body).read()
        print(f"Created AppFlowy OIDC provider {identifier}")
  '';
in {
  imports = import ../mkAliases.nix config lib name [
    name
    cloudName
    gotrueName
    oidcBootstrapName
    workerName
    searchName
    adminFrontendName
    dbName
    redisName
    minioName
  ];

  options.nps.stacks.${name} = {
    enable = lib.mkEnableOption name;

    db = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "appflowy";
        description = "PostgreSQL database name.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "appflowy";
        description = "PostgreSQL user name.";
      };
      passwordFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the file containing the PostgreSQL password.";
      };
    };

    gotrue = {
      adminEmail = lib.mkOption {
        type = lib.types.str;
        default = "admin@example.com";
        description = "Initial GoTrue admin email address.";
      };
      adminPasswordFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the file containing the initial GoTrue admin password.";
      };
      jwtSecretFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the file containing the GoTrue JWT secret. Generate with `openssl rand -hex 32`.";
      };
      disableSignup = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether public signup should be disabled in GoTrue.";
      };
      extraEnv = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the GoTrue container.";
      };
    };

    minio = {
      rootUser = lib.mkOption {
        type = lib.types.str;
        default = "appflowy";
        description = "MinIO root user.";
      };
      rootPasswordFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the file containing the MinIO root password.";
      };
      extraEnv = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the MinIO container.";
      };
    };

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable OIDC login with Authelia. This registers an Authelia
          client and bootstraps a custom OIDC provider in GoTrue.
        '';
      };
      clientSecretFile = (import ../authelia/options.nix lib).clientSecretFile;
      clientSecretHash = (import ../authelia/options.nix lib).derivableClientSecretHash cfg.oidc.clientSecretFile;
      providerIdentifier = lib.mkOption {
        type = lib.types.str;
        default = "custom:authelia";
        description = "GoTrue custom provider identifier for Authelia.";
      };
      userGroup = lib.mkOption {
        type = lib.types.str;
        default = "${name}_user";
        description = "Users of this group will be able to log in.";
      };
    };

    extraEnv = {
      cloud = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the AppFlowy Cloud container.";
      };
      worker = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the AppFlowy Worker container.";
      };
      search = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the AppFlowy Search container.";
      };
      web = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the AppFlowy Web container.";
      };
      adminFrontend = lib.mkOption {
        type = extraEnvType;
        default = {};
        description = "Extra environment variables for the AppFlowy admin frontend container.";
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
        require_pkce = true;
        pkce_challenge_method = "S256";
        redirect_uris = [
          "${serviceUrl}/gotrue/callback"
        ];
        scopes = ["openid" "profile" "email"];
        token_endpoint_auth_method = "client_secret_basic";
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

    nps.stacks.traefik.dynamicConfig.http.middlewares = {
      appflowy-gotrue-stripprefix.stripPrefix.prefixes = ["/gotrue"];
      appflowy-minio-stripprefix.stripPrefix.prefixes = ["/minio"];
      appflowy-minio-api-stripprefix.stripPrefix.prefixes = ["/minio-api"];
      appflowy-minio-api-headers.headers.customRequestHeaders.Host = "${minioName}:9000";
    };

    services.podman.containers = {
      ${name} = {
        image = "docker.io/appflowyinc/appflowy_web:0.13.1";
        extraEnv =
          {
            APPFLOWY_BASE_URL = serviceUrl;
            APPFLOWY_GOTRUE_BASE_URL = "${serviceUrl}/gotrue";
            APPFLOWY_WS_BASE_URL = wsBaseUrl;
          }
          // cfg.extraEnv.web;

        wantsContainer = [cloudName];
        stack = name;
        port = 80;
        traefik.name = name;
        homepage = {
          inherit category;
          name = displayName;
          settings = {
            inherit description;
            icon = "appflowy";
          };
        };
        glance = {
          inherit category description;
          name = displayName;
          id = name;
          icon = "di:appflowy";
        };
      };

      ${cloudName} = {
        image = "docker.io/appflowyinc/appflowy_cloud:0.15.16";
        network = lib.mkIf config.nps.stacks.traefik.enable [config.nps.stacks.traefik.network.name];
        extraEnv =
          {
            RUST_LOG = "info";
            APPFLOWY_ENVIRONMENT = "production";
            APPFLOWY_DATABASE_URL.fromTemplate = dbUrl;
            APPFLOWY_DATABASE_MAX_CONNECTIONS = 40;
            APPFLOWY_REDIS_URI = redisUrl;
            APPFLOWY_GOTRUE_JWT_SECRET.fromFile = cfg.gotrue.jwtSecretFile;
            APPFLOWY_GOTRUE_BASE_URL = "http://${gotrueName}:9999";
            APPFLOWY_S3_CREATE_BUCKET = true;
            APPFLOWY_S3_USE_MINIO = true;
            APPFLOWY_S3_MINIO_URL = minioUrl;
            APPFLOWY_S3_ACCESS_KEY = cfg.minio.rootUser;
            APPFLOWY_S3_SECRET_KEY.fromFile = cfg.minio.rootPasswordFile;
            APPFLOWY_S3_BUCKET = bucket;
            APPFLOWY_S3_REGION = "us-east-1";
            APPFLOWY_S3_PRESIGNED_URL_ENDPOINT = "${serviceUrl}/minio-api";
            APPFLOWY_ACCESS_CONTROL = true;
            APPFLOWY_WEB_URL = serviceUrl;
            APPFLOWY_BASE_URL = serviceUrl;
            APPFLOWY_SEARCH_SERVICE_URL = "http://${searchName}:4002";
            APPFLOWY_SEARCH_REQUEST_TIMEOUT_SECS = 10;
            AI_ENABLED = false;
          }
          // cfg.extraEnv.cloud;

        wantsContainer = [gotrueName redisName minioName searchName];
        stack = name;
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${cloudName}.rule" = utils.escapeOnDemand ''Host(`${serviceHost}`) && (PathPrefix(`/api`) || PathPrefix(`/ws`) || PathPrefix(`/ai`))'';
          "traefik.http.routers.${cloudName}.priority" = "100";
          "traefik.http.routers.${cloudName}.service" = cloudName;
          "traefik.http.routers.${cloudName}.middlewares" = mkMiddlewares [];
          "traefik.http.services.${cloudName}.loadbalancer.server.port" = "8000";
        };
        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "curl --fail http://127.0.0.1:8000/api/health || exit 1";
          HealthInterval = "10s";
          HealthTimeout = "10s";
          HealthRetries = 12;
          HealthStartPeriod = "10s";
        };
        glance = {
          parent = name;
          name = "Cloud";
          icon = "di:appflowy";
          inherit category;
        };
      };

      ${gotrueName} = {
        image = "docker.io/appflowyinc/gotrue:0.15.16";
        network = lib.mkIf config.nps.stacks.traefik.enable [config.nps.stacks.traefik.network.name];
        extraEnv =
          {
            GOTRUE_ADMIN_EMAIL = cfg.gotrue.adminEmail;
            GOTRUE_ADMIN_PASSWORD.fromFile = cfg.gotrue.adminPasswordFile;
            GOTRUE_DISABLE_SIGNUP = cfg.gotrue.disableSignup;
            GOTRUE_SITE_URL = "appflowy-flutter://";
            GOTRUE_URI_ALLOW_LIST = "**";
            GOTRUE_JWT_SECRET.fromFile = cfg.gotrue.jwtSecretFile;
            GOTRUE_JWT_EXP = 604800;
            GOTRUE_JWT_ADMIN_GROUP_NAME = "supabase_admin";
            GOTRUE_DB_DRIVER = "postgres";
            API_EXTERNAL_URL = "${serviceUrl}/gotrue";
            DATABASE_URL.fromTemplate = "${dbUrl}?search_path=auth";
            PORT = 9999;
            GOTRUE_MAILER_URLPATHS_CONFIRMATION = "/gotrue/verify";
            GOTRUE_MAILER_URLPATHS_INVITE = "/gotrue/verify";
            GOTRUE_MAILER_URLPATHS_RECOVERY = "/gotrue/verify";
            GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE = "/gotrue/verify";
            GOTRUE_MAILER_AUTOCONFIRM = true;
            GOTRUE_RATE_LIMIT_EMAIL_SENT = 100;
            GOTRUE_CUSTOM_OAUTH_ENABLED = true;
          }
          // lib.optionalAttrs cfg.oidc.enable {
            GOTRUE_EXTERNAL_EMAIL_ENABLED = false;
            GOTRUE_EXTERNAL_PHONE_ENABLED = false;
          }
          // cfg.gotrue.extraEnv;

        wantsContainer = [dbName];
        stack = name;
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${gotrueName}.rule" = utils.escapeOnDemand ''Host(`${serviceHost}`) && PathPrefix(`/gotrue`)'';
          "traefik.http.routers.${gotrueName}.priority" = "100";
          "traefik.http.routers.${gotrueName}.service" = gotrueName;
          "traefik.http.routers.${gotrueName}.middlewares" = mkMiddlewares ["appflowy-gotrue-stripprefix@file"];
          "traefik.http.services.${gotrueName}.loadbalancer.server.port" = "9999";
        };
        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "curl --fail http://127.0.0.1:9999/health || exit 1";
          HealthInterval = "10s";
          HealthTimeout = "10s";
          HealthRetries = 12;
          HealthStartPeriod = "40s";
        };
      };

      ${oidcBootstrapName} = lib.mkIf cfg.oidc.enable {
        image = "docker.io/python:3.13-alpine";
        volumeMap.bootstrap = "${oidcBootstrapScript}:/bootstrap.py:ro";
        extraEnv = {
          GOTRUE_URL = "http://${gotrueName}:9999";
          GOTRUE_JWT_SECRET.fromFile = cfg.gotrue.jwtSecretFile;
          OIDC_IDENTIFIER = cfg.oidc.providerIdentifier;
          OIDC_NAME = "Authelia";
          OIDC_CLIENT_ID = name;
          OIDC_CLIENT_SECRET.fromFile = cfg.oidc.clientSecretFile;
          OIDC_ISSUER = config.nps.containers.authelia.traefik.serviceUrl;
        };
        wantsContainer = [gotrueName "authelia"];
        stack = name;
        entrypoint = "python";
        exec = "/bootstrap.py";
        autoStart = true;
        extraConfig.Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
        };
      };

      ${workerName} = {
        image = "docker.io/appflowyinc/appflowy_worker:0.15.16";
        extraEnv =
          {
            RUST_LOG = "info";
            APPFLOWY_ENVIRONMENT = "production";
            APPFLOWY_WORKER_REDIS_URL = redisUrl;
            APPFLOWY_WORKER_ENVIRONMENT = "production";
            APPFLOWY_WORKER_DATABASE_URL.fromTemplate = dbUrl;
            APPFLOWY_WORKER_DATABASE_NAME = cfg.db.name;
            APPFLOWY_WORKER_IMPORT_TICK_INTERVAL = 30;
            APPFLOWY_S3_USE_MINIO = true;
            APPFLOWY_S3_MINIO_URL = minioUrl;
            APPFLOWY_S3_ACCESS_KEY = cfg.minio.rootUser;
            APPFLOWY_S3_SECRET_KEY.fromFile = cfg.minio.rootPasswordFile;
            APPFLOWY_S3_BUCKET = bucket;
            APPFLOWY_S3_REGION = "us-east-1";
          }
          // cfg.extraEnv.worker;
        wantsContainer = [dbName redisName cloudName minioName];
        stack = name;
        glance = {
          parent = name;
          name = "Worker";
          icon = "di:appflowy";
          inherit category;
        };
      };

      ${searchName} = {
        image = "docker.io/appflowyinc/appflowy_search:0.15.16";
        volumeMap.keywordIndex = "${storage}/keyword_index:/var/lib/appflowy/keyword_index";
        extraEnv =
          {
            RUST_LOG = "info";
            APPFLOWY_SEARCH_HOST = "[::]";
            APPFLOWY_SEARCH_PORT = 4002;
            APPFLOWY_SEARCH_DATABASE_URL.fromTemplate = dbUrl;
            APPFLOWY_SEARCH_REDIS_URL = redisUrl;
            APPFLOWY_BACKGROUND_INDEXER_ENABLED = true;
            APPFLOWY_INDEXER_DATABASE_ENABLED = false;
            APPFLOWY_KEYWORD_SEARCH_ENABLED = true;
            APPFLOWY_KEYWORD_WORKER_ENABLED = true;
            APPFLOWY_KEYWORD_INDEX_MAP_SIZE_BYTES = 2147483648;
            APPFLOWY_KEYWORD_INDEX_DIR = "/var/lib/appflowy/keyword_index";
            APPFLOWY_GOTRUE_JWT_SECRET.fromFile = cfg.gotrue.jwtSecretFile;
          }
          // cfg.extraEnv.search;
        wantsContainer = [dbName redisName];
        stack = name;
        glance = {
          parent = name;
          name = "Search";
          icon = "di:meilisearch";
          inherit category;
        };
      };

      ${adminFrontendName} = {
        image = "docker.io/appflowyinc/admin_frontend:0.15.16";
        network = lib.mkIf config.nps.stacks.traefik.enable [config.nps.stacks.traefik.network.name];
        extraEnv =
          {
            APPFLOWY_GOTRUE_BASE_URL = "http://${gotrueName}:9999";
            APPFLOWY_BASE_URL = "http://${cloudName}:8000";
          }
          // cfg.extraEnv.adminFrontend;
        wantsContainer = [gotrueName cloudName];
        stack = name;
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${adminFrontendName}.rule" = utils.escapeOnDemand ''Host(`${serviceHost}`) && PathPrefix(`/console`)'';
          "traefik.http.routers.${adminFrontendName}.priority" = "100";
          "traefik.http.routers.${adminFrontendName}.service" = adminFrontendName;
          "traefik.http.routers.${adminFrontendName}.middlewares" = mkMiddlewares [];
          "traefik.http.services.${adminFrontendName}.loadbalancer.server.port" = "3000";
        };
        glance = {
          parent = name;
          name = "Admin Frontend";
          icon = "di:appflowy";
          inherit category;
        };
      };

      ${minioName} = {
        image = "docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z";
        network = lib.mkIf config.nps.stacks.traefik.enable [config.nps.stacks.traefik.network.name];
        volumeMap.data = "${storage}/minio:/data";
        extraEnv =
          {
            MINIO_BROWSER_REDIRECT_URL = "${serviceUrl}/minio";
            MINIO_ROOT_USER = cfg.minio.rootUser;
            MINIO_ROOT_PASSWORD.fromFile = cfg.minio.rootPasswordFile;
          }
          // cfg.minio.extraEnv;
        stack = name;
        exec = "server /data --console-address :9001";
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${minioName}.rule" = utils.escapeOnDemand ''Host(`${serviceHost}`) && PathPrefix(`/minio`)'';
          "traefik.http.routers.${minioName}.priority" = "100";
          "traefik.http.routers.${minioName}.service" = "${minioName}-console";
          "traefik.http.routers.${minioName}.middlewares" = mkMiddlewares ["appflowy-minio-stripprefix@file"];
          "traefik.http.services.${minioName}-console.loadbalancer.server.port" = "9001";
          "traefik.http.routers.${minioName}-api.rule" = utils.escapeOnDemand ''Host(`${serviceHost}`) && PathPrefix(`/minio-api`)'';
          "traefik.http.routers.${minioName}-api.priority" = "100";
          "traefik.http.routers.${minioName}-api.service" = "${minioName}-api";
          "traefik.http.routers.${minioName}-api.middlewares" = mkMiddlewares ["appflowy-minio-api-stripprefix@file" "appflowy-minio-api-headers@file"];
          "traefik.http.services.${minioName}-api.loadbalancer.server.port" = "9000";
        };
        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "curl -f http://localhost:9000/minio/health/live";
          HealthInterval = "30s";
          HealthTimeout = "20s";
          HealthRetries = 3;
        };
        glance = {
          parent = name;
          name = "MinIO";
          icon = "di:minio";
          inherit category;
        };
      };

      ${redisName} = {
        image = "docker.io/redis:8.2";
        stack = name;
        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "redis-cli ping";
          HealthInterval = "10s";
          HealthTimeout = "10s";
          HealthRetries = 5;
          HealthStartPeriod = "10s";
          HealthOnFailure = "kill";
        };
        glance = {
          parent = name;
          name = "Redis";
          icon = "di:redis";
          inherit category;
        };
      };

      ${dbName} = {
        image = "docker.io/pgvector/pgvector:pg16";
        volumeMap.data = "${storage}/postgres:/var/lib/postgresql/data";
        extraEnv = {
          POSTGRES_DB = cfg.db.name;
          POSTGRES_USER = cfg.db.username;
          POSTGRES_PASSWORD.fromFile = cfg.db.passwordFile;
          POSTGRES_HOST = dbName;
          PGPORT = 5432;
        };
        stack = name;
        extraConfig.Container = {
          Notify = "healthy";
          HealthCmd = "pg_isready -d ${cfg.db.name} -U ${cfg.db.username}";
          HealthInterval = "10s";
          HealthTimeout = "10s";
          HealthRetries = 12;
          HealthStartPeriod = "10s";
          HealthOnFailure = "kill";
        };
        glance = {
          parent = name;
          name = "Postgres";
          icon = "di:postgres";
          inherit category;
        };
      };
    };
  };
}
