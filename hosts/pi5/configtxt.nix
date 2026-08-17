# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  hardware.raspberry-pi.configtxt.settings.all = {
    # [all] conditional filter, https://www.raspberrypi.com/documentation/computers/config_txt.html#conditional-filters
    #
    # This list is at normal priority and therefore REPLACES the module default
    # `dtparam = lib.mkDefault [ "audio=on" ]` from nixos-hardware's
    # raspberry-pi/common/config-txt-defaults.nix -- it does not merge with it.
    # `audio=on` must stay listed here or it silently disappears.
    #
    # Deliberately absent: the two serial-console UART settings this file used to
    # force on. nixos-hardware's raspberry-pi/common/config-txt-defaults.nix turns
    # the mini UART back off under the [pi5] filter on purpose, because the Pi 5 has
    # a dedicated debug UART and leaving the mini UART on feeds ghost input into
    # boot. The previous values here were debugging aids from the original fork
    # install. Do not re-add them.
    dtparam = [
      "audio=on"
      # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#enable-pcie
      "pciex1=on"
      # PCIe Gen 3.0
      # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#pcie-gen-3-0
      "pciex1_gen=3"
    ];
  };
}
