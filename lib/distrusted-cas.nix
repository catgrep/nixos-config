# SPDX-License-Identifier: GPL-3.0-or-later

# Roots that the compromised eMudhra intermediates chain to
# (https://emudhra.we-have-a-problem.com/), as named in the NSS bundle.
# nixos-26.05 ships cacert 3.126, which still trusts them; the list is
# redundant once its cacert is 3.131.1 or newer.
[
  "emSign ECC Root CA - G3"
  # Six of the intermediates are cross-signed by Sectigo under this root.
  "Comodo AAA Services root"
]
