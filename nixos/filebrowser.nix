{pkgs, ...}: {
  environment.etc."filebrowser/config.json".text = ''
    {
      "port": 8080,
      "baseURL": "/filebrowser",
      "address": "127.0.0.1",
      "log": "stdout",
      "database": "/var/lib/filebrowser/filebrowser.db",
      "root": "/srv"
    }
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/filebrowser 0755 filebrowser filebrowser -"
  ];

  users.users.filebrowser = {
    isSystemUser = true;
    group = "filebrowser";
    home = "/var/lib/filebrowser";
    createHome = true;
  };
  users.groups.filebrowser = {};

  systemd.services.filebrowser = {
    description = "File Browser";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      ExecStart = "${pkgs.filebrowser}/bin/filebrowser -c /etc/filebrowser/config.json";
      Restart = "always";
      User = "filebrowser";
      Group = "filebrowser";
      WorkingDirectory = "/var/lib/filebrowser";
      StateDirectory = "filebrowser";
    };
  };
}
