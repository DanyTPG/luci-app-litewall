#!/usr/bin/lua
local uci = require("luci.model.uci").cursor()
local json = require("luci.jsonc")

local function urldecode(str)
    str = string.gsub(str, "+", " ")
    return string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
end

local function parse_vless(url, socks_port)
    socks_port = tonumber(socks_port) or 10808
    local uuid, host, port, query = url:match("^vless://([^@]+)@([^:]+):(%d+)%?(.*)$")
    if not uuid then return nil, "Invalid VLESS URL format" end
    
    local params = {}
    local raw_query = query:match("([^#]+)") or query
    for k, v in raw_query:gmatch("([^&=]+)=([^&=]*)") do
        params[k] = urldecode(v)
    end
    
    local alpn_list = {}
    if params["alpn"] then
        for a in params["alpn"]:gmatch("[^,]+") do
            table.insert(alpn_list, a)
        end
    end
    
    local extra_obj = nil
    if params["extra"] then
        extra_obj = json.parse(params["extra"])
        if extra_obj and type(extra_obj) == "table" and extra_obj.scMaxEachPostBytes then
            local max_post_bytes = tonumber(uci:get("xray-rust", "main", "max_post_bytes")) or 32768
            local pb = tonumber(extra_obj.scMaxEachPostBytes)
            if pb and pb > max_post_bytes then
                extra_obj.scMaxEachPostBytes = tostring(max_post_bytes)
            end
        end
    end
    
    local stream_settings = {
        network = params["type"] or "tcp",
        security = params["security"] or "none"
    }
    
    if stream_settings.security == "tls" then
        stream_settings.tlsSettings = {
            serverName = params["sni"] or host,
            fingerprint = params["fp"] or "chrome",
            alpn = #alpn_list > 0 and alpn_list or {"h2", "http/1.1"}
        }
    elseif stream_settings.security == "reality" then
        stream_settings.realitySettings = {
            serverName = params["sni"] or host,
            fingerprint = params["fp"] or "chrome",
            publicKey = params["pbk"] or "",
            shortId = params["sid"] or "",
            spiderX = params["spx"] or ""
        }
    end
    
    if stream_settings.network == "xhttp" or stream_settings.network == "splithttp" then
        local h2_window = tonumber(uci:get("xray-rust", "main", "h2_window")) or 262144
        stream_settings.xhttpSettings = {
            host = params["host"] or host,
            path = params["path"] or "/",
            mode = params["mode"] or "auto",
            extra = extra_obj,
            h2StreamReceiveWindow = h2_window
        }
    elseif stream_settings.network == "ws" or stream_settings.network == "websocket" then
        stream_settings.wsSettings = {
            path = params["path"] or "/",
            headers = { Host = params["host"] or host }
        }
    elseif stream_settings.network == "httpupgrade" then
        stream_settings.httpupgradeSettings = {
            path = params["path"] or "/",
            host = params["host"] or host
        }
    elseif stream_settings.network == "grpc" then
        stream_settings.grpcSettings = {
            serviceName = params["serviceName"] or ""
        }
    end
    
    return {
        address = host,
        port = tonumber(port),
        uuid = uuid,
        encryption = params["encryption"] or "none",
        flow = params["flow"] or "",
        stream_settings = stream_settings
    }
end

local function get_node_data(node_id, socks_port)
    local node_sec = uci:get_all("xray-rust", node_id)
    if not node_sec then return nil end
    if node_sec.raw_link and node_sec.raw_link ~= "" then
        return parse_vless(node_sec.raw_link, socks_port)
    else
        local server = node_sec.server
        local port = tonumber(node_sec.port) or 443
        local uuid = node_sec.uuid
        local transport = node_sec.transport or "xhttp"
        local security = node_sec.security or "tls"
        local sni = (node_sec.sni and node_sec.sni ~= "") and node_sec.sni or server
        local fp = node_sec.fp or "chrome"
        local path = node_sec.path or "/"
        local mode = node_sec.xhttp_mode or node_sec.mode or "auto"
        local flow = node_sec.flow or ""
        local encryption = node_sec.encryption or "none"

        local alpn_list = {}
        if node_sec.alpn and node_sec.alpn ~= "" then
            for a in node_sec.alpn:gmatch("[^,]+") do
                table.insert(alpn_list, (a:gsub("^%s*(.-)%s*$", "%1")))
            end
        else
            alpn_list = {"h2", "http/1.1"}
        end

        local stream_settings = { network = transport, security = security }
        if security == "tls" then
            local tls_settings = {
                serverName = sni,
                fingerprint = fp,
                alpn = alpn_list
            }
            if node_sec.allow_insecure == "1" then
                tls_settings.allowInsecure = true
            end
            stream_settings.tlsSettings = tls_settings
        elseif security == "reality" then
            stream_settings.realitySettings = {
                serverName = sni,
                fingerprint = fp,
                publicKey = node_sec.pbk or "",
                shortId = node_sec.sid or "",
                spiderX = node_sec.spx or ""
            }
        end

        if transport == "xhttp" or transport == "splithttp" then
            local h2_window = tonumber(uci:get("xray-rust", "main", "h2_window")) or 262144
            local xhttp_host = (node_sec.xhttp_host and node_sec.xhttp_host ~= "") and node_sec.xhttp_host or sni
            local xhttp_settings = {
                host = xhttp_host,
                path = path,
                mode = mode,
                h2StreamReceiveWindow = h2_window
            }
            if node_sec.extra and node_sec.extra ~= "" then
                local node_extra = json.parse(node_sec.extra)
                if node_extra and type(node_extra) == "table" then
                    local max_post_bytes = tonumber(uci:get("xray-rust", "main", "max_post_bytes")) or 32768
                    if node_extra.scMaxEachPostBytes then
                        local pb = tonumber(node_extra.scMaxEachPostBytes)
                        if pb and pb > max_post_bytes then
                            node_extra.scMaxEachPostBytes = tostring(max_post_bytes)
                        end
                    end
                    xhttp_settings.extra = node_extra
                end
            end
            if node_sec.xhttp_xmux == "1" then
                xhttp_settings.xmux = { maxConcurrency = 4, maxConnections = 2 }
            end
            if node_sec.xhttp_headers and type(node_sec.xhttp_headers) == "table" then
                local hdr_obj = {}
                for _, h in ipairs(node_sec.xhttp_headers) do
                    local hk, hv = h:match("^([^:]+):%s*(.+)$")
                    if hk and hv then hdr_obj[hk] = hv end
                end
                xhttp_settings.headers = hdr_obj
            end
            stream_settings.xhttpSettings = xhttp_settings
        elseif transport == "ws" or transport == "websocket" then
            local ws_host = (node_sec.xhttp_host and node_sec.xhttp_host ~= "") and node_sec.xhttp_host or sni
            stream_settings.wsSettings = {
                path = path,
                headers = { Host = ws_host }
            }
        elseif transport == "httpupgrade" then
            local hu_host = (node_sec.xhttp_host and node_sec.xhttp_host ~= "") and node_sec.xhttp_host or sni
            stream_settings.httpupgradeSettings = {
                path = path,
                host = hu_host
            }
        elseif transport == "grpc" then
            stream_settings.grpcSettings = {
                serviceName = path or ""
            }
        end

        return {
            address = server,
            port = port,
            uuid = uuid,
            encryption = encryption,
            flow = flow,
            stream_settings = stream_settings
        }
    end
end

local function build_outbound(tag, node_data)
    return {
        tag = tag,
        protocol = "vless",
        settings = {
            vnext = {
                {
                    address = node_data.address,
                    port = node_data.port,
                    users = {
                        {
                            id = node_data.uuid,
                            encryption = node_data.encryption or "none",
                            flow = node_data.flow or ""
                        }
                    }
                }
            }
        },
        streamSettings = node_data.stream_settings
    }
end

local socks_port = tonumber(arg[3]) or tonumber(uci:get("xray-rust", "main", "socks_port")) or 10808
local out_file = arg[1] or "/var/etc/xray-rust/config.json"
local single_node_id = arg[2]
local conf_dir = "/var/etc/xray-rust"

os.execute("mkdir -p " .. conf_dir)

-- If running single node test
if single_node_id and single_node_id ~= "" then
    local nd = get_node_data(single_node_id, socks_port)
    if not nd then
        io.stderr:write("Node " .. single_node_id .. " not found\n")
        os.exit(1)
    end
    local test_cfg = {
        inbounds = {
            {
                tag = "socks-in",
                protocol = "socks",
                listen = "127.0.0.1",
                port = socks_port,
                settings = { auth = "noauth", udp = true }
            }
        },
        outbounds = {
            build_outbound("proxy", nd),
            { tag = "direct", protocol = "freedom" }
        }
    }
    local f = io.open(out_file, "w")
    if f then
        f:write(json.stringify(test_cfg, true))
        f:close()
        os.exit(0)
    else
        os.exit(1)
    end
end

local active_node = uci:get("xray-rust", "main", "active_node") or "node1"
local active_node_data = get_node_data(active_node, socks_port)

if not active_node_data then
    local link = uci:get("xray-rust", "main", "share_link") or ""
    if link ~= "" then
        active_node_data = parse_vless(link, socks_port)
    end
end

if not active_node_data then
    io.stderr:write("No valid active node configured\n")
    os.exit(1)
end

-- Collect all rule groups and custom nodes
local needed_nodes = {}
needed_nodes[active_node] = active_node_data

uci:foreach("xray-rust", "rule_group", function(rg)
    if rg.enabled == "1" and rg.target_node and rg.target_node ~= "_direct" and rg.target_node ~= "_block" and rg.target_node ~= "_blackhole" and rg.target_node ~= "_default" then
        if not needed_nodes[rg.target_node] then
            local nd = get_node_data(rg.target_node, socks_port)
            if nd then needed_nodes[rg.target_node] = nd end
        end
    end
end)

-- Record server IPs (resolved) and hostnames to bypass loops in nftables and dnsmasq
local nixio = require("nixio")
local f_ip = io.open(conf_dir .. "/server_ips", "w")
local f_dom = io.open(conf_dir .. "/node_domains", "w")

for _, nd in pairs(needed_nodes) do
    if nd.address then
        if nd.address:match("^%d+%.%d+%.%d+%.%d+$") then
            if f_ip then f_ip:write(nd.address .. "\n") end
        else
            if f_dom then f_dom:write(nd.address .. "\n") end
            local res = nixio.getaddrinfo(nd.address, "inet")
            if res and f_ip then
                for _, r in ipairs(res) do
                    if r.address then f_ip:write(r.address .. "\n") end
                end
            end
        end
    end
end
if f_ip then f_ip:close() end
if f_dom then f_dom:close() end

-- Record LAN bypass IPs
local f_lan = io.open(conf_dir .. "/lan_bypass", "w")
if f_lan then
    local bypass_lan = uci:get("xray-rust", "main", "bypass_lan_ips") or {}
    if type(bypass_lan) == "string" then bypass_lan = { bypass_lan } end
    for _, ip in ipairs(bypass_lan) do
        f_lan:write(ip .. "\n")
    end
    f_lan:close()
end

-- Default routing mode: direct vs proxy
local default_routing_mode = uci:get("xray-rust", "main", "default_routing_mode") or "direct"
local default_tag = (default_routing_mode == "proxy") and "proxy" or "direct"

-- Build outbounds: order first outbound according to default_routing_mode
local outbounds = {}
if default_tag == "proxy" then
    table.insert(outbounds, build_outbound("proxy", active_node_data))
    table.insert(outbounds, { tag = "direct", protocol = "freedom" })
else
    table.insert(outbounds, { tag = "direct", protocol = "freedom" })
    table.insert(outbounds, build_outbound("proxy", active_node_data))
end
table.insert(outbounds, { tag = "block", protocol = "blackhole" })

for nid, nd in pairs(needed_nodes) do
    if nid ~= active_node then
        table.insert(outbounds, build_outbound(nid, nd))
    end
end

-- Build routing rules
local routing_rules = {
    {
        type = "field",
        ip = { "geoip:private", "127.0.0.0/8", "10.0.0.0/8", "192.168.0.0/16" },
        outboundTag = "direct"
    },
    {
        type = "field",
        ip = { "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1" },
        outboundTag = "proxy"
    }
}

-- Process Rule Groups
uci:foreach("xray-rust", "rule_group", function(rg)
    if rg.enabled == "1" then
        local target_tag = "proxy"
        if rg.target_node == "_direct" then
            target_tag = "direct"
        elseif rg.target_node == "_block" or rg.target_node == "_blackhole" then
            target_tag = "block"
        elseif rg.target_node and rg.target_node ~= "_default" and needed_nodes[rg.target_node] then
            target_tag = rg.target_node
        end

        local domains = rg.domain_list
        if domains and type(domains) == "string" then domains = { domains } end
        local ips = rg.ip_list
        if ips and type(ips) == "string" then ips = { ips } end

        local net = (rg.network and rg.network ~= "" and rg.network ~= "tcp,udp") and rg.network or nil
        local prt = (rg.port and rg.port ~= "") and rg.port or nil

        -- Crucial: separate domain rules and IP rules into distinct routing rules!
        -- In Xray, multiple criteria inside a single rule are combined with logical AND.
        -- If domain and IP are in the same rule, both must match simultaneously,
        -- which breaks domain-only connections and IP-only connections (like Telegram).
        if domains and #domains > 0 then
            local r_dom = {
                type = "field",
                outboundTag = target_tag,
                domain = domains
            }
            if net then r_dom.network = net end
            if prt then r_dom.port = prt end
            table.insert(routing_rules, r_dom)
        end

        if ips and #ips > 0 then
            local r_ip = {
                type = "field",
                outboundTag = target_tag,
                ip = ips
            }
            if net then r_ip.network = net end
            if prt then r_ip.port = prt end
            table.insert(routing_rules, r_ip)
        end

        if (not domains or #domains == 0) and (not ips or #ips == 0) then
            if net or prt then
                local r_misc = {
                    type = "field",
                    outboundTag = target_tag
                }
                if net then r_misc.network = net end
                if prt then r_misc.port = prt end
                table.insert(routing_rules, r_misc)
            end
        end
    end
end)

-- Custom domain and ip overrides
local direct_domains = uci:get("xray-rust", "main", "direct_domain")
if direct_domains then
    if type(direct_domains) == "string" then direct_domains = { direct_domains } end
    if #direct_domains > 0 then
        table.insert(routing_rules, { type = "field", domain = direct_domains, outboundTag = "direct" })
    end
end

local proxy_domains = uci:get("xray-rust", "main", "proxy_domain")
if proxy_domains then
    if type(proxy_domains) == "string" then proxy_domains = { proxy_domains } end
    if #proxy_domains > 0 then
        table.insert(routing_rules, { type = "field", domain = proxy_domains, outboundTag = "proxy" })
    end
end

local direct_ips = uci:get("xray-rust", "main", "direct_ip")
if direct_ips then
    if type(direct_ips) == "string" then direct_ips = { direct_ips } end
    if #direct_ips > 0 then
        table.insert(routing_rules, { type = "field", ip = direct_ips, outboundTag = "direct" })
    end
end

-- Fallback rule: any unrouted TCP/UDP traffic defaults to default_tag
table.insert(routing_rules, {
    type = "field",
    network = "tcp,udp",
    outboundTag = default_tag
})

-- Performance and memory tuning policy for embedded routers
local handshake = tonumber(uci:get("xray-rust", "main", "handshake")) or 4
local conn_idle = tonumber(uci:get("xray-rust", "main", "conn_idle")) or 30
local uplink_only = tonumber(uci:get("xray-rust", "main", "uplink_only")) or 2
local downlink_only = tonumber(uci:get("xray-rust", "main", "downlink_only")) or 4
local buffer_size = tonumber(uci:get("xray-rust", "main", "buffer_size")) or 16

local policy = {
    levels = {
        ["0"] = {
            handshake = handshake,
            connIdle = conn_idle,
            uplinkOnly = uplink_only,
            downlinkOnly = downlink_only,
            bufferSize = buffer_size
        }
    }
}

local config = {
    policy = policy,
    inbounds = {
        {
            tag = "socks-in",
            protocol = "socks",
            listen = "127.0.0.1",
            port = socks_port,
            settings = { auth = "noauth", udp = true },
            sniffing = {
                enabled = true,
                destOverride = { "http", "tls", "quic" },
                routeOnly = false
            }
        }
    },
    outbounds = outbounds,
    routing = {
        domainStrategy = "AsIs",
        rules = routing_rules
    }
}

local f = io.open(out_file, "w")
if f then
    f:write(json.stringify(config, true))
    f:close()
    print("Config written to " .. out_file)
else
    io.stderr:write("Failed to open " .. out_file .. " for writing\n")
    os.exit(1)
end
