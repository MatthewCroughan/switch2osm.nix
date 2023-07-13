{ pkgs, ... }:
let
  mapnik-xml = pkgs.symlinkJoin {
    name = "mapnik-source-with-xml";
    buildInputs = [ pkgs.nodePackages.carto ];
    paths = [
      (pkgs.fetchFromGitHub {
        owner = "gravitystorm";
        repo = "openstreetmap-carto";
        rev = "v5.7.0";
        sha256 = "sha256-GOEIe0UoymRLapMWvXRyg82kXm/08VrNV8dqCxGl5jM=";
      })
    ];
    postBuild = ''
      ls -lah $out
      carto $out/project.mml > $out/mapnik.xml
    '';
  };
  runTheThing = pkgs.writeScriptBin "runTheThing" ''
    set -eu
    export TMPDIR=$(mktemp -d)
    sudo -u _renderd osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script ${mapnik-xml}/openstreetmap-carto.lua -C 2500 --number-processes 1 -S ${mapnik-xml}/openstreetmap-carto.style $1
    sudo -u _renderd psql -d gis -f ${mapnik-xml}/indexes.sql
    sudo -u _renderd ${mapnik-xml}/scripts/get-external-data.py -D /home/_renderd -c ${mapnik-xml}/external-data.yml
  '';
in
{
  users.users._renderd.isNormalUser = true;

  environment.etc."renderd.conf".text = ''
    [renderd]
    pid_file=/run/renderd/renderd.pid
    stats_file=/run/renderd/renderd.stats
    socketname=/run/renderd/renderd.sock
    num_threads=4
    tile_dir=/var/cache/renderd/tiles

    [mapnik]
    plugins_dir=${pkgs.mapnik}/lib/mapnik/input
    font_dir=${pkgs.noto-fonts}/share/fonts/noto
    font_dir_recurse=true

    [s2o]
    URI=/hot/
    XML=${mapnik-xml}/mapnik.xml
    HOST=localhost
    TILESIZE=256
    MAXZOOM=20
  '';

  systemd.tmpfiles.rules = [
    "d /var/cache/renderd/tiles              0755 _renderd    users"
  ];

  systemd.services.renderd = {
    description = "Daemon that renders map tiles using mapnik";
    wantedBy = [ "multi-user.target" ];
    after = [ "networking.target" "postgresql.service" ];
    environment.G_MESSAGES_DEBUG = "all";
    serviceConfig = {
      User = "_renderd";
      #Group = cfg.group;
      ExecStart = "${pkgs.apacheHttpdPackages.mod_tile}/bin/renderd -f -c /etc/renderd.conf";
      PrivateTmp = true;
      Restart = "always";
      #WorkingDirectory = "/tmp";
      CacheDirectory = "renderd";
      RuntimeDirectory = "renderd";
      #StateDirectory = "renderd";
    };
  };

  services.httpd = {
    enable = true;
    extraModules = [
      {
        name = "tile";
        path = "${pkgs.apacheHttpdPackages.mod_tile}/modules/mod_tile.so";
      }
    ];
    virtualHosts = {
      localhost = {
        listen = [ { ip = "*"; port = 8081; } ];
        extraConfig = ''
          LoadTileConfigFile /etc/renderd.conf
          ModTileBulkMode Off
          ModTileCacheDurationDirty 900
          ModTileCacheDurationLowZoom 9 518400
          ModTileCacheDurationMax 604800
          ModTileCacheDurationMediumZoom 13 86400
          ModTileCacheDurationMinimum 10800
          ModTileCacheLastModifiedFactor 0.20
          ModTileEnableStats On
          ModTileEnableTileThrottling Off
          ModTileEnableTileThrottlingXForward 0
          ModTileMaxLoadMissing 5
          ModTileMaxLoadOld 2
          ModTileMissingRequestTimeout 10
          ModTileRenderdSocketName /run/renderd/renderd.sock
          ModTileRequestTimeout 3
          ModTileThrottlingRenders 128 0.2
          ModTileThrottlingTiles 10000 1
          ModTileTileDir /var/cache/renderd/tiles
        '';
      };
    };
  };
  services.postgresql = {
    enable = true;
    initialScript = pkgs.writeText "switch2osm-init.sql" ''
      CREATE USER _renderd;
      CREATE DATABASE "gis" WITH OWNER "_renderd";

      \connect gis
      CREATE EXTENSION postgis;
      CREATE EXTENSION hstore;

      ALTER TABLE geometry_columns OWNER TO "_renderd";
      ALTER TABLE spatial_ref_sys OWNER TO "_renderd";
    '';
    package = pkgs.postgresql_14;
    extraPlugins = [ pkgs.postgresql_14.pkgs.postgis ];
  };

  environment.systemPackages = with pkgs; [
    runTheThing

    kitty
    magic-wormhole

    osm2pgsql
    gdal
    nodePackages.carto
    (python3.withPackages (p: with p; [
      python-mapnik
      psycopg2
      pyyaml
      requests
      urllib3
    ]))
  ];
}
