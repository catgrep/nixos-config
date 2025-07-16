# nixos-config

## Home-Manager

Run
``` sh
nix run home-manager -- switch --flake ./home-manager
```

## Development

This repo uses Determinate System and the flake was bootstrapped with:
``` sh
nix run "https://flakehub.com/f/DeterminateSystems/fh/*" -- init
```

### Prerequisites

You will need:
1) `nix` package manager for installing `nix` packages.
2) `nixfmt` for formatting `nix` files.

Install nix:
``` sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Test with:
``` sh
echo "Hello Nix" | nix run "https://flakehub.com/f/NixOS/nixpkgs/*#charasay" say
```

Install `nixfmt`:

``` sh
nix-env -i -f https://github.com/NixOS/nixfmt/archive/master.tar.gz
```


# macOS Local Network Connectivity Troubleshooting Guide

## Problem: Can't connect to local servers (ping timeouts, connection refused)

### Quick Diagnosis Commands

```bash
# Test basic connectivity
ping 192.168.68.1  # Gateway - should work
ping <target-ip>   # Target host - might fail

# Check DNS resolution
nslookup <hostname>.local
dig @224.0.0.251 -p 5353 <hostname>.local  # Direct mDNS query

# Check ARP table for MAC addresses
arp -a | grep 192.168.68

# Check network interface status
ifconfig en0
netstat -rn  # Routing table
```

### Investigation Steps (in order)

#### 1. Basic Network Layer Check
```bash
# Test gateway connectivity
ping 192.168.68.1

# Check if interface is up and has correct IP
ifconfig en0

# Check routing table
netstat -rn | head -10
```

#### 2. Layer 2 (MAC Address) Issues
```bash
# Check ARP table for duplicates or conflicts
arp -a | grep 192.168.68

# Look for duplicate MAC addresses (key indicator)
arp -a | sort | uniq -c | sort -nr

# Clear ARP cache if needed
sudo arp -d <ip-address>
```

#### 3. DNS/mDNS Problems
```bash
# Check if .local domains resolve
nslookup <hostname>.local

# Direct mDNS query
dig @224.0.0.251 -p 5353 <hostname>.local

# Check mDNS services
dns-sd -B _services._dns-sd._udp local.
```

#### 4. Firewall/Packet Filter Check
```bash
# Check macOS firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode

# Check pfctl (packet filter)
sudo pfctl -s info
sudo pfctl -s rules
sudo pfctl -s state | grep <target-ip>
```

#### 5. VPN/Tunnel Interface Interference
```bash
# Check for active VPN connections
ifconfig | grep utun
netstat -rn | grep utun

# List network services
networksetup -listallnetworkservices
```

### Remediation Steps

#### Step 1: Reset Network Stack
```bash
# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Reset interface
sudo ifconfig en0 down
sudo ifconfig en0 up

# Renew DHCP lease
sudo ipconfig set en0 DHCP
```

#### Step 2: Fix Routing Issues
```bash
# Add specific host routes (if needed)
sudo route add -host <target-ip> -interface en0

# Delete problematic routes
sudo route delete <problematic-route>
```

#### Step 3: Clear ARP Issues
```bash
# Clear specific ARP entries
sudo arp -d <ip-address>

# Clear all ARP entries (nuclear option)
sudo arp -a -d
```

#### Step 4: Add to /etc/hosts (Temporary Fix)
```bash
# Add entries to /etc/hosts
sudo echo "<ip-address> <hostname>.local <hostname>" >> /etc/hosts
```

#### Step 5: Restart Network Services
```bash
# Restart network-related services
sudo launchctl unload /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist
sudo launchctl load /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist
```

### Common Root Causes & Solutions

#### 1. **Duplicate MAC Addresses**
- **Symptom**: ARP table shows same MAC for multiple IPs
- **Cause**: VM bridging, network cloning, or interface conflicts
- **Fix**: Clear ARP cache, restart interfaces

#### 2. **VPN Interference**
- **Symptom**: Multiple utun interfaces, routing conflicts
- **Cause**: VPN software changing routing tables
- **Fix**: Temporarily disable VPN, check routing table

#### 3. **mDNS Resolution Failure**
- **Symptom**: `.local` domains don't resolve
- **Cause**: mDNS responder issues, network changes
- **Fix**: Restart mDNSResponder, check Avahi on target hosts

#### 4. **Stale Network Configuration**
- **Symptom**: Interface shows wrong IP/routing
- **Cause**: Network changes, DHCP lease issues
- **Fix**: Reset interface, renew DHCP

### Prevention Tips

1. **Monitor ARP table** regularly for duplicate MACs
2. **Use static host entries** for critical local servers
3. **Document network changes** that might affect routing
4. **Keep VPN software updated** to avoid routing conflicts
5. **Use IPv6 where possible** - often more reliable for local networks

### Emergency Commands (Nuclear Options)

```bash
# Reset all network configuration
sudo networksetup -setdhcp "Wi-Fi"

# Restart all network services
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
sudo pfctl -d && sudo pfctl -e

# Clear everything and start fresh
sudo arp -a -d
sudo route -n flush
sudo ifconfig en0 down && sudo ifconfig en0 up
```

### Verification After Fix

```bash
# Test connectivity
ping <target-ip>
telnet <target-ip> <port>

# Test DNS resolution
nslookup <hostname>.local

# Check ARP table is clean
arp -a | grep <target-ip>

# Test actual service
curl http://<hostname>.local:<port>
```

### Key Indicators by Problem Type

- **ARP Issues**: Same MAC address for multiple IPs
- **DNS Issues**: nslookup fails for .local domains
- **Routing Issues**: Can ping gateway but not local hosts
- **Firewall Issues**: Connection refused on specific ports
- **Interface Issues**: Wrong IP address or subnet mask

Remember: The combination of interface reset + ARP clearing + mDNS restart often resolves most local network connectivity issues on macOS.
