--[[
LuCI - Lua Configuration Interface

Copyright 2017 Tony Ambardar

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

module("luci.tools.sqm", package.seeall)

local cbi = require "luci.cbi"
local i18n = require "luci.i18n"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local net = require "luci.model.network".init()
local util = require "luci.util"
local json = require "luci.jsonc"
local qdisc_caps_helper = "/usr/lib/sqm/get-qdisc-caps"


-- Provide an AbstractValue.write() replacement that conditionally enables
-- the related init script. This is used on the advice of Jo-Philipp Wich
-- and following the example of the luci-app-minidlna CBI model, to help
-- users by enabling sqm's init script if even a single sqm instance is
-- enabled and state is saved ("Save & Apply" or "Save"). 
-- This version additionally checks that the init script is not already
-- enabled, to avoid spamming the GUI with notifications.

function write_enable_init(cbi_obj, init)
	assert(util.instanceof(cbi_obj, cbi.AbstractValue),
		"Object not in AbstractValue class")

	local old_write = cbi_obj.write
	return function(self, section, value)
			if value == "1" and not sys.init.enabled(init) then
				sys.init.enable(init)
				self.map.message = i18n.translate("The GUI has just enabled "
				.. "the " .. init .. " initscript on your behalf. Remember to "
				.. "disable the sqm initscript manually under System Startup "
				.. "menu in case this change was not wished for.")
			end
			return old_write(self, section, value)
		end
end


-- Return the network names associated with a given physical interface.
-- e.g. get_nets_from_int("eth0.2") -> "wan,wan6"

function get_nets_from_int(int)
	local nets = net:get_interface(int)
	nets = nets and nets:get_networks() or {}
	for k, v in pairs(nets) do
		nets[k] = nets[k].sid
	end
	return table.concat(nets, ",")
end


-- Implement a "variant" form of taboption to handle complex dependencies,
-- which allows for varying the displayed option values based on dependencies

function cbi.AbstractSection.varianttaboption(self, vars, ...)
	assert(type(vars) == "table" and #vars > 0,
		"Cannot use variant option without table of variants")

	-- The master/template UCI option which is never displayed but
	-- whose functions we borrow
	local o = cbi.AbstractSection.taboption(self, ...)
	o:depends("_nosuchoption", "_nosuchvalue")
	o.optional = true

	-- Sub-option variants read/write the same master UCI option but at most
	-- a single variant should be visible. Visibility is determined by the
	-- variants' depends() calls, and the programmer MUST set these up to be
	-- mutually exclusive.
	o.variants = {}
	local tab, class, opt, desc = select(1,...)
	for _, v in ipairs(vars) do
		o.variants[v] = cbi.AbstractSection.taboption(self, tab, class,
			"_%s_%s" % {v, opt}, desc)
		o.variants[v].optional = true
		o.variants[v].cfgvalue = function(s, sc) return o:cfgvalue(sc) end
		o.variants[v].write = function(s, sc, vl) return o:write(sc, vl) end
-- Comment is explicit reminder against accidentally removing main option
--		o.variants[v].remove = function(s, sc) return o:remove(sc) end
	end

	-- Iterator over (variant,sub-option) pairs
	o.vpairs = function() return pairs(o.variants) end
	return o
end


-- Read qdisc and shaper capabilities, and cache within a GUI page load

local caps_cache = {}
local has_qdisc_helper = fs.access(qdisc_caps_helper)

function read_caps(map, section)
	assert(has_qdisc_helper,
		"Helper " .. qdisc_caps_helper .. " missing from sqm-scripts install")

	local option = "script"
	local cbid = "cbid." .. map.config .. "." .. section .. "." .. option
	local script = map:formvalue(cbid) or map:get(section, option) or ""
	local cmd = "%s %s" % {qdisc_caps_helper, script}

	if caps_cache[script] then
		return caps_cache[script]
	else
		local caps = json.parse(sys.exec(cmd)) or {}
		caps_cache[script] = caps
		return caps
	end
end


-- Use capability filter to iterate over qdisc list or capability list

function match_caps_pairs(t,m)
	local k, v = nil, nil
	return function ()
		k, v = next(t, k)
		while k do
			if type(v) == "table" then
				v = table.concat(v," ")
			end
			if string.find(v, m) then
				return k, t[k]
			end
			k, v = next(t, k)
		end
	end
end


-- Extract details of 3-tuple capabilities, including type, variable values
-- and related descriptive text

function parse_tuple_caps(q, m)
	local type_data, qdiscs_with_type = {}, {}
	for k, c in match_caps_pairs(q, m) do
		type_data[k] = {}
		table.insert(qdiscs_with_type, k)
		for _, s in match_caps_pairs(c, m) do
			local _, v, d = string.match(s, "(%S+):(%S+):(%S+)")
			table.insert(type_data[k], { val = v, desc = d:gsub("_", " ") })
		end
	end
	return qdiscs_with_type, type_data
end


-- Generate raw HTML text with conditional tooltip text.

function text_cond_tooltip(text,cond,tip)
	return cond and "<abbr title=\"%s\">%s</abbr>" % {tip, text} or text
end


-- Helper function to lookup the qdisc capability description associated
-- with a given UCI option.
-- e.g. get_tuple_desc(self, sec, "cake", "diffserv_ingress", "diffserv")
--        -> "3-Tier [diffserv3]"

function get_tuple_desc(self, section, qdisc, tuple_opt, tuple_type)
	local tup = self.map:get(section, tuple_opt) or ""
	local desc = ""

	if #tup > 0 then
		local all_qdiscs = read_caps(self.map, section)
		local _, tuple_data = parse_tuple_caps(all_qdiscs, tuple_type)
		for _, d in ipairs(tuple_data[qdisc] or {}) do
			if d.val == tup then
				desc = d.desc
			end
		end
	end
	return desc
end
