--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

module("luci.controller.sqm", package.seeall)

local disp = require "luci.dispatcher"
local i18n = require "luci.i18n"

local app_title = "Smart Queue Management"

function index()
    -- If no config create an empty one
	if not nixio.fs.access("/etc/config/sqm") then
		nixio.fs.writefile("/etc/config/sqm", "")
	end

	local page

	page = entry({"admin", "network", "sqm"}, cbi("sqm/overview"), _("SQM QoS"))
	page.dependent = true
	page = entry({"admin", "network", "sqm", "detail"}, cbi("sqm/detail"), nil)
	page.dependent = true
	page.leaf = true
end

function app_description()
	return i18n.translate([[<abbr title="Smart Queue Management">SQM</abbr> ]]
		.. [[can enable traffic shaping, better mixing (Fair Queueing), ]]
		.. [[active queue length management (AQM) and prioritisation on one ]]
		.. [[network interface.<br />LEDE Documentation: ]]
		.. [[<a href="https://lede-project.org/docs/user-guide/sqm" ]]
		.. [[target="_blank">]]
		.. [[Smart Queue Management (SQM) - Minimizing Bufferbloat]]
		.. [[</a>]])
end

function app_title_back()
	return [[<a href="]]
		.. disp.build_url("admin", "network", "sqm")
		.. [[">]]
		.. i18n.translate(app_title)
		.. [[</a>]]
end

function app_title_main()
	return i18n.translate(app_title)
end
