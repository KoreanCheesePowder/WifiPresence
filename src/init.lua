local log = require "log"
local capabilities = require "st.capabilities"
local driver_info = capabilities["buildbook37604.driverInformation"]
local Driver = require "st.driver"
local json = require "st.json"
local cosock = require "cosock"
local ltn12 = require "ltn12"

local DRIVER_NAME = "synology-wifi-presence"
local AUTHOR = "치즈가루"
local DRIVER_VERSION = "v1.0.3"
local DEVICE_DNI = "synology-srm-wifi-presence"
local PROFILE = "synology-wifi-presence"
local SESSION_NAME = "WiFiPresence"
local API_DEVICE = "SYNO.Core.Network.NSM.Device"
local METHOD_CANDIDATES = { "get", "list", "load", "get_list", "list_devices", "query" }
local PHONE_COMPONENTS = { "phone1", "phone2", "phone3", "phone4" }
local PHONE_PREFS = { "phone1Mac", "phone2Mac", "phone3Mac", "phone4Mac" }

local function now_s()
  return os.time()
end

local function trim(s)
  if s == nil then return "" end
  return tostring(s):match("^%s*(.-)%s*$") or ""
end

local function normalize_mac(s)
  local v = string.lower(trim(s))
  v = v:gsub("[^0-9a-f]", "")
  if #v ~= 12 then return nil end
  return v
end

local function urlencode(s)
  s = tostring(s or "")
  s = s:gsub("\n", "\r\n")
  s = s:gsub("([^%w%-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return s
end

local function pref(device, name, default)
  local v = device.preferences and device.preferences[name]
  if v == nil or v == "" then return default end
  return v
end

local function base_url(device)
  local scheme = pref(device, "useHttps", false) and "https" or "http"
  local host = trim(pref(device, "routerHost", "192.168.1.1"))
  local port = tonumber(pref(device, "routerPort", scheme == "https" and 8001 or 8000)) or 8000
  return string.format("%s://%s:%d", scheme, host, port)
end

local function http_request(device, path, query)
  local url = base_url(device) .. path
  if query and query ~= "" then url = url .. "?" .. query end
  local body_t = {}
  local use_https = pref(device, "useHttps", false)
  local mod
  if use_https then
    mod = cosock.asyncify "ssl.https"
  else
    mod = cosock.asyncify "socket.http"
  end

  local req = {
    url = url,
    sink = ltn12.sink.table(body_t),
    create = function()
      local sock = cosock.socket.tcp()
      sock:settimeout(5)
      return sock
    end,
  }
  if use_https then
    req.protocol = "tlsv1_2"
    req.verify = "none"
    req.options = "all"
  end

  local ok, code, headers, status = mod.request(req)
  local body = table.concat(body_t)
  if not ok then
    return nil, tostring(code or "request failed")
  end
  if tonumber(code) ~= 200 then
    return nil, string.format("HTTP %s %s", tostring(code), tostring(status or ""))
  end
  return body, nil
end

local function decode(body)
  if not body or body == "" then return nil, "empty response" end
  local ok, data = pcall(json.decode, body)
  if not ok then return nil, "invalid JSON: " .. tostring(data) end
  return data, nil
end

local function api_info(device, names)
  local q = "api=SYNO.API.Info&version=1&method=query&query=" .. urlencode(table.concat(names, ","))
  local body, err = http_request(device, "/webapi/query.cgi", q)
  if not body then return nil, err end
  local data, jerr = decode(body)
  if not data then return nil, jerr end
  if not data.success then return nil, "SYNO.API.Info failed" end
  return data.data or {}, nil
end

local function login(device)
  local info, ierr = api_info(device, { "SYNO.API.Auth", API_DEVICE })
  if not info then return nil, nil, ierr end
  local auth = info["SYNO.API.Auth"] or {}
  local auth_path = auth.path or "auth.cgi"
  local auth_ver = math.min(tonumber(auth.maxVersion) or 3, 3)
  local username = trim(pref(device, "username", ""))
  local password = tostring(pref(device, "password", ""))
  if username == "" or password == "" then return nil, nil, "SRM account/password not configured" end

  local q = table.concat({
    "api=SYNO.API.Auth",
    "version=" .. tostring(auth_ver),
    "method=login",
    "account=" .. urlencode(username),
    "passwd=" .. urlencode(password),
    "session=" .. urlencode(SESSION_NAME),
    "format=sid"
  }, "&")
  local body, err = http_request(device, "/webapi/" .. auth_path, q)
  if not body then return nil, nil, err end
  local data, jerr = decode(body)
  if not data then return nil, nil, jerr end
  if not data.success then
    local code = data.error and data.error.code or "?"
    return nil, nil, "SRM login failed, code=" .. tostring(code)
  end
  local sid = data.data and data.data.sid
  if not sid then return nil, nil, "SRM login response has no sid" end
  return sid, info[API_DEVICE], nil
end

local function logout(device, sid)
  if not sid then return end
  local q = table.concat({
    "api=SYNO.API.Auth",
    "version=2",
    "method=logout",
    "session=" .. urlencode(SESSION_NAME),
    "_sid=" .. urlencode(sid)
  }, "&")
  pcall(http_request, device, "/webapi/auth.cgi", q)
end

local function fetch_devices(device, sid, api_meta)
  api_meta = api_meta or {}
  local path = api_meta.path or "entry.cgi"
  local max_ver = tonumber(api_meta.maxVersion) or 1
  local cached = device:get_field("srm_device_method")
  local methods = {}
  if cached and cached ~= "" then table.insert(methods, cached) end
  for _, m in ipairs(METHOD_CANDIDATES) do
    if m ~= cached then table.insert(methods, m) end
  end

  local last_err = "no method succeeded"
  for _, method in ipairs(methods) do
    for ver = max_ver, 1, -1 do
      local q = table.concat({
        "api=" .. urlencode(API_DEVICE),
        "version=" .. tostring(ver),
        "method=" .. urlencode(method),
        "_sid=" .. urlencode(sid)
      }, "&")
      local body, err = http_request(device, "/webapi/" .. path, q)
      if body then
        local data, jerr = decode(body)
        if data and data.success then
          device:set_field("srm_device_method", method, { persist = true })
          device:set_field("srm_device_version", ver, { persist = true })
          log.info(string.format("SRM device API OK: method=%s version=%d", method, ver))
          return data.data or data, nil
        end
        local code = data and data.error and data.error.code
        last_err = string.format("method=%s v%d API error=%s %s", method, ver, tostring(code or "?"), tostring(jerr or ""))
      else
        last_err = string.format("method=%s v%d %s", method, ver, tostring(err))
      end
    end
  end
  return nil, last_err
end

local function scalar_online(v)
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  if type(v) ~= "string" then return nil end
  local s = string.lower(trim(v))
  if s == "online" or s == "connected" or s == "active" or s == "up" or s == "on" or s == "true" or s == "1" then return true end
  if s == "offline" or s == "disconnected" or s == "inactive" or s == "down" or s == "off" or s == "false" or s == "0" then return false end
  return nil
end

local MAC_KEYS = {
  mac=true, macaddr=true, mac_addr=true, macaddress=true, mac_address=true,
  hwaddr=true, hw_addr=true, hardware_address=true
}
local ONLINE_KEYS = {
  online=true, is_online=true, connected=true, is_connected=true,
  active=true, is_active=true, is_wifi_connected=true, wifi_connected=true,
  alive=true, is_alive=true
}
local STATUS_KEYS = { status=true, state=true, connection_status=true, connect_status=true }

local function object_mac(t)
  for k, v in pairs(t) do
    if type(k) == "string" and MAC_KEYS[string.lower(k)] and type(v) == "string" then
      local m = normalize_mac(v)
      if m then return m end
    end
  end
  return nil
end

local function object_online(t)
  for k, v in pairs(t) do
    if type(k) == "string" then
      local lk = string.lower(k)
      if ONLINE_KEYS[lk] then
        local b = scalar_online(v)
        if b ~= nil then return b, true end
      end
    end
  end
  for k, v in pairs(t) do
    if type(k) == "string" and STATUS_KEYS[string.lower(k)] then
      local b = scalar_online(v)
      if b ~= nil then return b, true end
    end
  end
  return nil, false
end

local function find_mac(root, target, assume_match_online, depth)
  depth = depth or 0
  if depth > 20 or type(root) ~= "table" then return false, false end
  local m = object_mac(root)
  if m and m == target then
    local on, explicit = object_online(root)
    if explicit then return on, true end
    return assume_match_online, true
  end
  for _, v in pairs(root) do
    if type(v) == "table" then
      local online, found = find_mac(v, target, assume_match_online, depth + 1)
      if found then return online, true end
    end
  end
  return false, false
end

local function emit_component(device, component_id, present)
  local event = present and capabilities.presenceSensor.presence.present() or capabilities.presenceSensor.presence.not_present()
  device:emit_component_event(device.profile.components[component_id], event)
end

local function apply_phone_state(device, idx, seen_online, found_in_payload, now)
  local component = PHONE_COMPONENTS[idx]
  local mac = normalize_mac(pref(device, PHONE_PREFS[idx], ""))
  if not mac then
    device:set_field("missing_since_" .. idx, nil, { persist = true })
    emit_component(device, component, false)
    return false, false
  end

  if seen_online then
    device:set_field("missing_since_" .. idx, nil, { persist = true })
    device:set_field("last_seen_" .. idx, now, { persist = true })
    emit_component(device, component, true)
    return true, true
  end

  local missing_key = "missing_since_" .. idx
  local missing_since = tonumber(device:get_field(missing_key))
  if not missing_since then
    missing_since = now
    device:set_field(missing_key, missing_since, { persist = true })
  end
  local grace = tonumber(pref(device, "awayGraceSeconds", 120)) or 120
  local elapsed = math.max(0, now - missing_since)
  if elapsed >= grace then
    emit_component(device, component, false)
    return false, true
  end

  -- Grace period: keep/force PRESENT. This is intentional fail-safe behavior
  -- because this state will be used to inhibit automatic door opening.
  emit_component(device, component, true)
  log.info(string.format("PHONE%d missing from SRM payload (%s), grace %d/%d sec", idx, found_in_payload and "offline" or "not-found", elapsed, grace))
  return true, true
end

local function poll(device)
  if device:get_field("poll_in_progress") then return end
  device:set_field("poll_in_progress", true)

  local ok, err = pcall(function()
    local sid, api_meta, lerr = login(device)
    if not sid then error(lerr or "login failed") end
    local payload, ferr = fetch_devices(device, sid, api_meta)
    logout(device, sid)
    if not payload then error(ferr or "device list failed") end

    local assume_online = pref(device, "assumeMatchOnline", true)
    local now = now_s()
    local any_present = false
    local configured = 0

    for i = 1, 4 do
      local mac = normalize_mac(pref(device, PHONE_PREFS[i], ""))
      if mac then
        configured = configured + 1
        local online, found = find_mac(payload, mac, assume_online)
        log.info(string.format("PHONE%d mac=%s found=%s online=%s", i, mac, tostring(found), tostring(online)))
        local effective = apply_phone_state(device, i, online, found, now)
        if effective then any_present = true end
      else
        apply_phone_state(device, i, false, false, now)
      end
    end

    if configured == 0 then
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    else
      device:emit_event(any_present and capabilities.presenceSensor.presence.present() or capabilities.presenceSensor.presence.not_present())
    end
    device:set_field("last_poll_ok", now, { persist = true })
  end)

  device:set_field("poll_in_progress", false)
  if not ok then
    -- Fail safe: never change presence to away when SRM/API itself is unavailable.
    log.error("SRM poll failed: " .. tostring(err))
  end
end

local function schedule(device)
  local old = device:get_field("poll_timer")
  if old then pcall(function() device.thread:cancel_timer(old) end) end
  local interval = tonumber(pref(device, "pollSeconds", 15)) or 15
  if interval < 10 then interval = 10 end
  local timer = device.thread:call_on_schedule(interval, function()
    poll(device)
  end, "synology wifi presence poll")
  device:set_field("poll_timer", timer)
end

local function initialize_defaults(device)
  -- Until the first successful SRM query, configured phones are treated as present.
  -- This prevents an API/router problem from creating a false-away condition.
  local any = false
  for i = 1, 4 do
    if normalize_mac(pref(device, PHONE_PREFS[i], "")) then
      emit_component(device, PHONE_COMPONENTS[i], true)
      any = true
    else
      emit_component(device, PHONE_COMPONENTS[i], false)
    end
  end
  device:emit_event(any and capabilities.presenceSensor.presence.present() or capabilities.presenceSensor.presence.not_present())
end

local function device_init(driver, device)
  device:emit_event(driver_info.author(AUTHOR))
  device:emit_event(driver_info.driverVersion(DRIVER_VERSION))
  initialize_defaults(device)
  schedule(device)
  device.thread:call_with_delay(2, function() poll(device) end, "initial SRM poll")
end

local function info_changed(driver, device, event, args)
  device:set_field("srm_device_method", nil, { persist = true })
  device:set_field("srm_device_version", nil, { persist = true })
  for i = 1, 4 do
    device:set_field("missing_since_" .. i, nil, { persist = true })
  end
  initialize_defaults(device)
  schedule(device)
  device.thread:call_with_delay(1, function() poll(device) end, "SRM poll after settings change")
end

local function refresh_handler(driver, device, command)
  device.thread:call_with_delay(0, function() poll(device) end, "manual SRM refresh")
end

local function discovery_handler(driver, opts, should_continue)
  local exists = false
  for _, d in ipairs(driver:get_devices()) do
    if d.device_network_id == DEVICE_DNI then exists = true break end
  end
  if not exists then
    driver:try_create_device({
      type = "LAN",
      device_network_id = DEVICE_DNI,
      label = "C.P Synology Wi-Fi Presence",
      profile = PROFILE,
      manufacturer = "Synology",
      model = "SRM 1.2 Wi-Fi Presence",
      vendor_provided_label = "C.P Synology Wi-Fi Presence"
    })
  end
end

log.info("Synology Wi-Fi Presence v" .. DRIVER_VERSION .. " loading")

local driver = Driver(DRIVER_NAME, {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    },
  },
})

driver:run()
