--[[
LuCI - Lua Configuration Interface

Copyright 2014 Steven Barth <steven@midlink.org>
Copyright 2014 Dave Taht <dave.taht@bufferbloat.net>
Copyright 2017 Tony Ambardar

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local http = require "luci.http"
local disp = require "luci.dispatcher"
local net = require "luci.model.network".init()
local sys = require "luci.sys"
local ctrl = require "luci.controller.sqm"
local sqm = require "luci.tools.sqm"

local function text_cond_tooltip(text,cond,tip)
	return cond and "<abbr title=\"%s\">%s</abbr>" % {tip, text} or text
end

local function get_tuple_desc(self, section, qdisc, tuple_opt, tuple_type)
	local tup = self.map:get(section, tuple_opt) or ""
	local desc = ""

	if #tup > 0 then
		local all_qdiscs = sqm.read_caps(self.map, section)
		local _, tuple_data = sqm.parse_tuple_caps(all_qdiscs, tuple_type)
		for _, d in ipairs(tuple_data[qdisc] or {}) do
			if d.val == tup then
				desc = d.desc
			end
		end
	end
	return desc
end

m = Map("sqm")
m.title	= ctrl.app_title_main()
m.description = ctrl.app_description()

s = m:section(TypedSection, "queue", translate("Queues Overview"))
s.template = "cbi/tblsection"
s.addremove = true -- set to true to allow adding SQM instances in the GUI
s.anonymous = true

-- Enable editing and creation of SQM instances
s.extedit = disp.build_url("admin", "network", "sqm", "detail", "%s")
function s.create(self, name)
	local section = AbstractSection.create(self, name)
	http.redirect(self.extedit:format(section))
end


-- OVERVIEW

e = s:option(Flag, "enabled", translate("Enabled"))
e.rmempty = false

-- Be helpful and enable sqm's init script if a sqm instance is enabled and
-- any state is saved, whether by pressing "Save" or "Save & Apply"
e.write = sqm.write_enable_init(e, "sqm")


-- INTERFACE

n = s:option(DummyValue, "_interface",
	translate("Network" .. "<br />" .. "Interface") .. "<br />" ..
	translate("(device)") .. "<br />" .. translate("(networks)"))
n.template = "sqm/overview_doubleline"

function n.set_one(self, section)
	return self.map:get(section, "interface") or ""
end

function n.set_two(self, section)
	local int = self.map:get(section, "interface") or ""
	local nets = net:get_interface(int)
	nets = nets and nets:get_networks() or {}
	for k, v in pairs(nets) do
		nets[k] = nets[k].sid
	end
	nets = table.concat(nets, ",")
	return ((#nets > 0) and "(%s)" % {nets} or iface)
end


-- BANDWIDTH

bw = s:option(DummyValue, "_bandwidth",
	translate("Bandwidth in kbit/s") .. "<br />" ..
	translate("(ingress)") .. "<br />" .. translate("(egress)"))
bw.template = "sqm/overview_doubleline"

function bw.set_one(self, section)
	return self.map:get(section, "download") or ""
end

function bw.set_two(self, section)
	return self.map:get(section, "upload") or ""
end


-- QDISC, SHAPER, QDISC PRESET

qd = s:option(DummyValue, "_qdisc_shaper",
	translate("Queue Disciplines") .. "<br />" .. translate("(leaf)") ..
	translate("(shaper)"))
qd.template = "sqm/overview_doubleline"

function qd.set_one(self, section)
	local qd = self.map:get(section, "qdisc") or ""
	local desc = get_tuple_desc(self, section, qd, "qdisc_preset", "preset")

	return text_cond_tooltip(qd, #desc > 0, "Preset: " .. desc)
end

function qd.set_two(self, section)
	return self.map:get(section, "shaper") or ""
end


-- DSCP HANDLING

zd = s:option(DummyValue, "_zero_dscp", translate("DSCP Passthrough") ..
	"<br />" .. translate("(ingress)") .. translate("(egress)"))
zd.template = "sqm/overview_doubleline"

function zd.set_one(self, section)
	local lookup = self.map:get(section, "zero_dscp_ingress") or "1"
	return (lookup == "1") and "Block" or "Pass"
end

function zd.set_two(self, section)
	local lookup = self.map:get(section, "zero_dscp_egress") or "1"
	return (lookup == "1") and "Block" or "Pass"
end


pd = s:option(DummyValue, "_prio_dscp", translate("DSCP Prioritization") ..
	"<br />" .. translate("(ingress)") .. translate("(egress)"))
pd.template = "sqm/overview_doubleline"

function pd.set_one(self, section)
	local ignore = self.map:get(section, "ignore_dscp_ingress") or "1"
	local shp =  self.map:get(section, "shaper") or ""
	local desc = get_tuple_desc(self, section,
		shp, "diffserv_ingress", "diffserv")

	return text_cond_tooltip(ignore == "1" and "Single-Tier" or "Multi-Tier",
		#desc > 0, desc)
end

function pd.set_two(self, section)
	local ignore = self.map:get(section, "ignore_dscp_egress") or "1"
	local shp =  self.map:get(section, "shaper") or ""
	local desc = get_tuple_desc(self, section,
		shp, "diffserv_egress", "diffserv")

	return text_cond_tooltip(ignore == "1" and "Single-Tier" or "Multi-Tier",
		#desc > 0, desc)
end


-- LINKLAYER

ll = s:option(DummyValue, "_linklayer", translate("Link Layer Adaptation") ..
	"<br />" .. translate("(layer type)"))

ll.rawhtml = true
ll.value = function(self, section)
	local ll = self.map:get(section, "linklayer") or "none"
	local ov = self.map:get(section, "overhead") or 0
	local map = {["none"]="None",["ethernet"]="Ethernet w/Overhead",
		["atm"]="ATM"}
	return text_cond_tooltip(map[ll] or "None", ll ~= "none",
		"Overhead: " .. ov)
end


-- CUSTOM SCRIPT

sc = s:option(DummyValue, "script", translate("Custom Script"))
sc.default = ""
sc.rmempty = true


return m
