#!/usr/bin/env python3
import hashlib
import os
import getpass

# this is to satisfy the jellyfin hashed password requirements:
#   https://github.com/jellyfin/jellyfin/blob/9eaca73/MediaBrowser.Model/Cryptography/PasswordHash.cs#L14
#   https://github.com/Sveske-Juice/declarative-jellyfin/blob/d677a98/documentation/users.md#usershashedpassword
def generate_jellyfin_hash(password, iterations=210000, key_length_bytes=64):
    # Generate a random 16-byte salt
    salt = os.urandom(16)

    # Generate the PBKDF2-SHA512 hash (64 bytes)
    key = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), salt, iterations, key_length_bytes)

    # Both salt and hash should be uppercase hex (Convert.ToHexString produces uppercase)
    salt_hex = salt.hex().upper()
    key_hex = key.hex().upper()

    # Use the format that matches Jellyfin
    return f"$PBKDF2-SHA512$iterations={iterations}${salt_hex}${key_hex}"

# Usage
password = getpass.getpass("Enter password: ")
hash_result = generate_jellyfin_hash(password)
print(f"\n{hash_result}")
