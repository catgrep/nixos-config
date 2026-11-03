# SPDX-License-Identifier: GPL-3.0-or-later

# Roots that the compromised eMudhra intermediates chain to
# (https://emudhra.we-have-a-problem.com/), as named in the NSS bundle.
# cacert 3.131.1 removes "emSign ECC Root CA - G3" but still trusts this
# root, and the cacert build rejects blocklist names absent from the bundle.
[
  # Six of the intermediates are cross-signed by Sectigo under this root.
  "Comodo AAA Services root"
]
