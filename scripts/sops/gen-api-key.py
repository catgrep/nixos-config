#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""
Generate API keys for Sonarr and Radarr services.

This script generates cryptographically secure 32-character hexadecimal API keys.
The generated keys can be copied and pasted into SOPS secrets files.

Usage:
    ./gen-api-key.py [--count N]

Examples:
    ./gen-api-key.py                    # Generate one API key
    ./gen-api-key.py --count 2          # Generate two API keys
"""

import argparse
import secrets


def generate_api_key():
    """Generate a 32-character hexadecimal API key."""
    return secrets.token_hex(16)


def main():
    parser = argparse.ArgumentParser(
        description="Generate API keys for Sonarr and Radarr services",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # Generate one API key
  %(prog)s --number 2         # Generate two API keys
        """,
    )

    parser.add_argument(
        "--number",
        type=int,
        default=1,
        help="Number of API keys to generate (default: 1)",
    )

    args = parser.parse_args()
    print("Generated API key")
    print("=" * 50)
    for i in range(args.number):
        api_key = generate_api_key()
        if args.number > 1:
            print(f"api_key_{i+1}: {api_key}")
        else:
            print(f"api_key: {api_key}")
    print("=" * 50)
    print("Copy the above key(s) to your SOPS secrets file:")
    print("  make sops-edit-HOST")


if __name__ == "__main__":
    main()
