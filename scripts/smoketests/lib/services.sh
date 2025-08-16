#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Common service testing functions for media smoketests

test_service() {
    local domain="$1"
    local service_name="$2"
    local expected_port="$3"

    info "testing $service_name connectivity at '$(fmt_bold "$domain")'"

    info "using host 'pi4' as the DNS server"
    dns_ipaddr=$(get_ip "pi4")

    # First check if we can resolve the domain using the AdGuard DNS server
    if ! nslookup "$domain" "$dns_ipaddr" >/dev/null 2>&1; then
        warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
        # Fall back to using IP with Host header
        local response
        local error_output

        # Try HTTPS first
        if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
            response="$error_output"
            if [[ "$response" =~ ^[0-9]{3}$ ]] && [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "$service_name HTTPS responded with HTTP $response (via Host header)"
                return 0
            fi
        fi

        # Try HTTP fallback
        if error_output=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
            response="$error_output"
            if [[ "$response" =~ ^[0-9]{3}$ ]] && [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "$service_name HTTP responded with HTTP $response (via Host header)"
                return 0
            fi
        fi

        fail "failed to connect to $service_name at '$(fmt_bold "$domain")' even with Host header fallback"
        return 1
    fi

    # DNS resolution worked, try curl with --resolve to force the IP
    local response
    local error_output

    # Try HTTPS first
    if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$domain" --connect-timeout 5 --max-time 10 2>&1); then
        response="$error_output"
        if [[ "$response" =~ ^[0-9]{3}$ ]]; then
            if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "$service_name HTTPS responded with HTTP $response"
                return 0
            else
                warn "$service_name HTTPS returned unexpected code: $response"
            fi
        else
            warn "$service_name HTTPS failed: $error_output"
        fi
    fi

    # Fallback to HTTP with forced resolution
    if error_output=$(curl -s -o /dev/null -w "%{http_code}" "http://$domain" --connect-timeout 5 --max-time 10 2>&1); then
        response="$error_output"
        if [[ "$response" =~ ^[0-9]{3}$ ]]; then
            if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "$service_name HTTP responded with HTTP $response"
                return 0
            else
                fail "$service_name HTTP returned unexpected code: $response"
                return 1
            fi
        else
            fail "failed to connect to $service_name at '$(fmt_bold "$domain")': $error_output"
            return 1
        fi
    else
        fail "failed to connect to $service_name at '$(fmt_bold "$domain")'"
        return 1
    fi
}

test_media_service() {
    local service_name="$1"
    local domain="$2"
    local port="$3"
    local systemd_service="$4"
    local host="$5"
    local ipaddr="$6" 
    local user="$7"

    info "testing $service_name media service"
    
    # If no domain is provided, skip the gateway test and only test local service
    if [[ -z "$domain" ]]; then
        warn "$service_name not exposed via gateway, testing local service only"
        if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:$port" >/dev/null 2>&1; then
            pass "$service_name backend is running locally on port $port"
        else
            fail "$service_name backend is not running on $host"
            warn "check $service_name service status: systemctl status $systemd_service"
            return 1
        fi
    else
        # Test via gateway
        if test_service "$domain" "$service_name" "$port"; then
            pass "$service_name connectivity test passed"
        else
            # Check if the backend service is running on the host
            warn "checking if $service_name backend is running on $host"
            if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:$port" >/dev/null 2>&1; then
                fail "$service_name backend is reachable locally, issue might be with gateway routing"
            else
                fail "$service_name backend is not running on $host"
                warn "check $service_name service status: systemctl status $systemd_service"
            fi
            return 1
        fi
    fi
    
    return 0
}