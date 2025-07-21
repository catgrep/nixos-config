{ config, pkgs, ... }: {
  users.users.nixos.openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
  ];
  users.users.root.openssh.authorizedKeys.keys = config.users.users.nixos.openssh.authorizedKeys.keys;
  system.stateVersion = "24.05";
}
