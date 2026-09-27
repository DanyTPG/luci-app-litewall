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

local config_type = uci:get("xray-rust", "main", "config_type") or "link"
local socks_port = uci:get("xray-rust", "main", "socks_port") or 10808
local out_file = arg[1] or "/var/etc/xray-rust/config.json"

local cfg_str = nil
if config_type == "custom" then
    cfg_str = uci:get("xray-rust", "main", "custom_json")
else
    local link = uci:get("xray-rust", "main", "share_link") or ""
    if link ~= "" then
        local cfg, err = parse_vless(link, socks_port)
        if cfg then
            cfg_str = json.stringify(cfg, true)
        else
            io.stderr:write("Error parsing link: " .. tostring(err) .. "\n")
            os.exit(1)
        end
    else
        io.stderr:write("No link provided\n")
        os.exit(1)
    end
end

if cfg_str then
    local f = io.open(out_file, "w")
    if f then
        f:write(cfg_str)
        f:close()
        print("Config written to " .. out_file)
    else
        io.stderr:write("Failed to open " .. out_file .. " for writing\n")
        os.exit(1)
    end
end
