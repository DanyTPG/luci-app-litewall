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
        stream_settings.xhttpSettings = {
            host = params["host"] or host,
            path = params["path"] or "/",
            mode = params["mode"] or "auto",
            extra = extra_obj
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
    
    local config = {
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
            {
                tag = "proxy",
                protocol = "vless",
                settings = {
                    vnext = {
                        {
                            address = host,
                            port = tonumber(port),
                            users = {
                                {
                                    id = uuid,
                                    encryption = params["encryption"] or "none",
                                    flow = params["flow"] or ""
                                }
                            }
                        }
                    }
                },
                streamSettings = stream_settings
            }
        }
    }
    return config
end

local socks_port = tonumber(uci:get("xray-rust", "main", "socks_port")) or 10808
local out_file = arg[1] or "/var/etc/xray-rust/config.json"
local conf_dir = "/var/etc/xray-rust"

os.execute("mkdir -p " .. conf_dir)

local node_data = nil
local active_node = uci:get("xray-rust", "main", "active_node")

if active_node and uci:get("xray-rust", active_node) then
    local raw_link = uci:get("xray-rust", active_node, "raw_link")
    if raw_link and raw_link ~= "" then
        node_data = parse_vless(raw_link, socks_port)
    else
        local server = uci:get("xray-rust", active_node, "server")
        local port = tonumber(uci:get("xray-rust", active_node, "port")) or 443
        local uuid = uci:get("xray-rust", active_node, "uuid")
        local transport = uci:get("xray-rust", active_node, "transport") or "xhttp"
        local security = uci:get("xray-rust", active_node, "security") or "tls"
        local sni = uci:get("xray-rust", active_node, "sni") or server
        local fp = uci:get("xray-rust", active_node, "fp") or "chrome"
        local path = uci:get("xray-rust", active_node, "path") or "/"
        local mode = uci:get("xray-rust", active_node, "mode") or "auto"

        local stream_settings = { network = transport, security = security }
        if security == "tls" then
            stream_settings.tlsSettings = { serverName = sni, fingerprint = fp, alpn = {"h2", "http/1.1"} }
        elseif security == "reality" then
            stream_settings.realitySettings = {
                serverName = sni,
                fingerprint = fp,
                publicKey = uci:get("xray-rust", active_node, "pbk") or "",
                shortId = uci:get("xray-rust", active_node, "sid") or ""
            }
        end
        if transport == "xhttp" then
            stream_settings.xhttpSettings = { host = sni, path = path, mode = mode }
        end
        node_data = {
            address = server,
            port = port,
            uuid = uuid,
            encryption = "none",
            stream_settings = stream_settings
        }
    end
end

if not node_data then
    local link = uci:get("xray-rust", "main", "share_link") or ""
    if link ~= "" then
        node_data = parse_vless(link, socks_port)
    end
end

if not node_data then
    io.stderr:write("No valid node configured\n")
    os.exit(1)
end

-- Record server host/ip to bypass loop in nftables
if node_data.address then
    local f_ip = io.open(conf_dir .. "/server_ips", "w")
    if f_ip then
        f_ip:write(node_data.address .. "\n")
        f_ip:close()
    end
end

-- Build routing rules
local routing_rules = {
    {
        type = "field",
        ip = { "geoip:private", "127.0.0.0/8", "10.0.0.0/8", "192.168.0.0/16" },
        outboundTag = "direct"
    }
}

local routing_mode = uci:get("xray-rust", "main", "routing_mode") or "bypass_lan"
if routing_mode == "bypass_iran" then
    table.insert(routing_rules, {
        type = "field",
        domain = { "geosite:ir" },
        outboundTag = "direct"
    })
    table.insert(routing_rules, {
        type = "field",
        ip = { "geoip:ir" },
        outboundTag = "direct"
    })
end

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

local config = {
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
        {
            tag = "proxy",
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
        },
        {
            tag = "direct",
            protocol = "freedom",
            settings = {}
        }
    },
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
