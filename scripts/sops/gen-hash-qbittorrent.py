#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""
Generate PBKDF2-SHA512 password hash for qBittorrent WebUI.

This script generates a PBKDF2-SHA512 hash compatible with qBittorrent's
Password_PBKDF2 configuration format. The output can be used directly
in qBittorrent configuration files.

Usage:
    ./gen-hash-qbittorrent.py [password]

Examples:
    ./gen-hash-qbittorrent.py                    # Prompt for password
    ./gen-hash-qbittorrent.py "mypassword"       # Use provided password
"""

import argparse
import base64
import getpass
import hashlib
import secrets
import sys


def generate_qbittorrent_hash(password: str) -> str:
    """
    Generate qBittorrent-compatible PBKDF2-SHA512 hash.

    Args:
        password: The plain text password to hash

    Returns:
        Base64-encoded hash in format "salt:hash"
    """
    # qBittorrent parameters
    iterations = 100000
    salt_length = 16

    # Generate random salt
    salt = secrets.token_bytes(salt_length)

    # Generate PBKDF2-SHA512 hash
    password_bytes = password.encode('utf-8')
    hash_bytes = hashlib.pbkdf2_hmac('sha512', password_bytes, salt, iterations)

    # Base64 encode salt and hash
    salt_b64 = base64.b64encode(salt).decode('ascii')
    hash_b64 = base64.b64encode(hash_bytes).decode('ascii')

    # Return in qBittorrent format
    return f"{salt_b64}:{hash_b64}"


def main():
    parser = argparse.ArgumentParser(
        description="Generate PBKDF2-SHA512 password hash for qBittorrent WebUI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Prompt for password
  %(prog)s "mypassword"       # Use provided password

The output format is compatible with qBittorrent's Password_PBKDF2 setting:
Password_PBKDF2="@ByteArray(salt:hash)"
        """,
    )

    parser.add_argument(
        "password",
        nargs="?",
        help="Password to hash (will prompt if not provided)",
    )

    args = parser.parse_args()

    # Get password
    if args.password:
        password = args.password
    else:
        password = getpass.getpass("Enter password: ")
        confirm_password = getpass.getpass("Confirm password: ")

        if password != confirm_password:
            print("Error: Passwords do not match", file=sys.stderr)
            sys.exit(1)

    if not password:
        print("Error: Password cannot be empty", file=sys.stderr)
        sys.exit(1)

    # Generate hash
    hash_result = generate_qbittorrent_hash(password)

    print("Generated qBittorrent password hash:")
    print("=" * 50)
    print('qbittorrent_admin_password: PLAINTEXT_PASSWORD')
    print(f'qbittorrent_admin_password_hash: {hash_result}')
    print("=" * 50)
    print("Copy the above hash to your SOPS secrets file:")
    print("  make sops-edit-HOST")


if __name__ == "__main__":
    main()
