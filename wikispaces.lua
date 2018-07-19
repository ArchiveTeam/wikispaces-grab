dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local ids = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered_users = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%)]")
      or string.match(url, "//$") then
    return false
  end

  if string.match(url, "^https?://[^/]+wikispaces%.com/user/view/[^/]+$") then
    local username = string.match(url, "^https?://[^/]+wikispaces%.com/user/view/([^/]+)$")
    discovered_users[username] = true
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 2 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  local path = string.match(url, "^https?://[^/]+(/.*)")
  if path ~= nil and (string.match(path, "^/space/subscribe/")
      or string.match(path, "^/page/edit/")
      or string.match(path, "^/page/pdf/")
      or string.match(path, "^/page/rss/")
      or string.match(path, "^/page/code/")
      or string.match(path, "^/page/menu/")
      or string.match(path, "^/page/diff/")
      or string.match(path, "^/page/microsummary/")
      or string.match(path, "^/page/xmlm?/")
      or string.match(path, "^/message/xml/")
      or string.match(path, "^/wiki/changes%?")
      or string.match(path, "%?f=print$")
      or string.match(path, "^/wiki/notify$")
      or string.match(path, "orderBy=")
      or string.match(path, "^/file/detail/[^%?]+%?utable=WikiTablePageList&ut_csv=1")
      or string.match(path, "^/file/links/[^%?]+%?utable=WikiTableLinkList&ut_csv=1")
      or string.match(path, "^/page/links/[^%?]+%?utable=WikiTableLinkList&ut_csv=1")
      or string.match(path, "^/file/history/[^%?]+%?utable=WikiTablePageHistoryList&ut_csv=1")
      or string.match(path, "^/page/history/[^%?]+%?utable=WikiTablePageHistoryList&ut_csv=1")
      or string.match(path, "^/file/messages/[^%?]+%?utable=WikiTableMessageList&ut_csv=1")
      or string.match(path, "^/page/messages/[^%?]+%?utable=WikiTableMessageList&ut_csv=1")
      or string.match(path, "^/wiki/addmonitor%?")
      or string.match(path, "^/file/rss/")
      or string.match(path, "^/file/menu/")
      or string.match(path, "^/file/xmlm?/")
      or string.match(path, "^/wiki/xmla%?")
      or string.match(path, "^/navbar/update/")
      or string.match(path, "^/navbar/tag")) then
    return false
  end

  if string.match(url, "^https?://([^%.]+)") == item_value then
    return true
  end

  return false
end

testtoken = function(testurl)
  if string.match(testurl, ".responseToken=") then
    local testurl = "token" .. string.gsub(testurl, "responseToken=[0-9a-f]+", "")
    if downloaded[testurl] then
      return false
    end
  end

  return true
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if not testtoken(url) then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
      and (allowed(url, parent["url"]) or html == 0)
      and not (string.match(parent["url"], "^https?://[^/]+/file/history/")
      or string.match(parent["url"], "^https?://[^/]+/page/history/")) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(url, "&amp;", "&")
    if downloaded[url_] ~= true and addedtolist[url_] ~= true
       and allowed(url_, origurl) and testtoken(url_) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url) and not (string.match(url, "^https?://[^/]+/file/view/")
      or string.match(url, "^https?://[^/]+/file/history/")
      or string.match(url, "^https?://[^/]+/page/history/")) then
    html = read_file(file)
    if string.match(url, "^https?://[^/]+/space/content%?utable=WikiTablePageList&ut_csv=1$") then
      for line in string.gmatch(html, "(.-)\n") do
        sort, urlnew = string.match(line, '^%s*"([^"]+)"%s*,%s*"([^"]+)"')
        if urlnew ~= nil then
          urlnew = string.gsub(urlnew, "%?", "%%3F")
          if sort == "page" then
            checknewurl("/" .. urlnew)
          elseif sort == "file" then
            checknewurl("/file/detail/" .. urlnew)
          else
            abortgrab = true
          end
        end
      end
    end
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if status_code == 200 and string.match(url["url"], ".responseToken=") then
    local testurl = "token" .. string.gsub(url["url"], "responseToken=[0-9a-f]+", "")
    downloaded[testurl] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"]) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir..'/'..warc_file_base..'_data.txt', 'w')
  if item_type == "wiki" then
    for user, _ in pairs(discovered_users) do
      file:write("user:" .. user .. "\n")
    end
  end
  file:close()
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
