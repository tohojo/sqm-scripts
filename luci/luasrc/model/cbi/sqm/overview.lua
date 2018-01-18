--[[
LuCI - Lua Configuration Interface

Copyright 2017 Tony Ambardar

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local http = require "luci.http"
local disp = require "luci.dispatcher"
local sys = require "luci.sys"
local ctrl = require "luci.controller.sqm"
local sqm = require "luci.tools.sqm"

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
	translate("Network") .. "<br/>" .. translate("Interface") .. "<br/>" ..
	"<small>" ..
	translate("[device]") .. "<br/>" .. translate("[networks]") ..
	"</small>")
n.template = "sqm/overview_doubleline"

function n.set_one(self, section)
	return self.map:get(section, "interface") or ""
end

function n.set_two(self, section)
	local int = self.map:get(section, "interface") or ""
	local nets = sqm.get_nets_from_int(int)
	return ((#nets > 0) and "(%s)" % {nets} or "--")
end


-- BANDWIDTH

bw = s:option(DummyValue, "_bandwidth",
	translate("Bandwidth") .. "<br/>" ..translate("in kbit/s") .. "<br/>" ..
	"<small>" ..
	translate("[ingress]") .. "<br/>" .. translate("[egress]") ..
	"</small>")
bw.template = "sqm/overview_doubleline"

function bw.set_one(self, section)
	return self.map:get(section, "download") or ""
end

function bw.set_two(self, section)
	return self.map:get(section, "upload") or ""
end


-- QDISC, SHAPER, QDISC PRESET

qd = s:option(DummyValue, "_qdisc_shaper",
	translate("Queue") .. "<br/>" .. translate("Disciplines") .. "<br/>" ..
	"<small>" ..
	translate("[leaf]") .. "<br/>" .. translate("[shaper]") ..
	"</small>")
qd.template = "sqm/overview_doubleline"

function qd.set_one(self, section)
	local qd = self.map:get(section, "qdisc") or ""
	local desc = sqm.get_tuple_desc(self, section,
		qd, "qdisc_preset", "preset")

	return sqm.text_cond_tooltip(qd, #desc > 0, "Preset: " .. desc)
end

function qd.set_two(self, section)
	return self.map:get(section, "shaper") or ""
end


-- DSCP HANDLING

zd = s:option(DummyValue, "_zero_dscp",
	translate("DSCP") .. "<br/>" .. translate("Passthrough") .. "<br/>" ..
	"<small>" ..
	translate("[ingress]") .. "<br/>" .. translate("[egress]") ..
	"</small>")
zd.template = "sqm/overview_doubleline"

function zd.set_one(self, section)
	local lookup = self.map:get(section, "zero_dscp_ingress") or "1"
	return (lookup == "1") and "Block" or "Pass"
end

function zd.set_two(self, section)
	local lookup = self.map:get(section, "zero_dscp_egress") or "1"
	return (lookup == "1") and "Block" or "Pass"
end


pd = s:option(DummyValue, "_prio_dscp",
	translate("DSCP") .. "<br/>" .. translate("Prioritization") .. "<br/>" ..
	"<small>" ..
	translate("[ingress]") .. "<br/>" .. translate("[egress]") ..
	"</small>")
pd.template = "sqm/overview_doubleline"

function pd.set_one(self, section)
	local ign = self.map:get(section, "ignore_dscp_ingress") or "1"
	local shp =  self.map:get(section, "shaper") or ""
	local desc = sqm.get_tuple_desc(self, section,
		shp, "diffserv_ingress", "diffserv")

	return sqm.text_cond_tooltip(ign == "1" and "Single-Tier" or "Multi-Tier",
		#desc > 0, desc)
end

function pd.set_two(self, section)
	local ign = self.map:get(section, "ignore_dscp_egress") or "1"
	local shp =  self.map:get(section, "shaper") or ""
	local desc = sqm.get_tuple_desc(self, section,
		shp, "diffserv_egress", "diffserv")

	return sqm.text_cond_tooltip(ign == "1" and "Single-Tier" or "Multi-Tier",
		#desc > 0, desc)
end


-- LINKLAYER

ll = s:option(DummyValue, "_linklayer",
	translate("Link Layer") .. "<br/>" .. translate("Adaptation") .. "<br/>" ..
	"<small>" ..
	translate("[layer type]") .. "<br/>" .. translate("[overhead]") ..
	"</small>")
ll.template = "sqm/overview_doubleline"

function ll.set_one(self, section)
	local ll = self.map:get(section, "linklayer") or "none"
	local map = {["none"]="None",["ethernet"]="Ethernet w/Overhead",
		["atm"]="ATM"}

	return map[ll] or "None"
end

function ll.set_two(self, section)
	local ov = self.map:get(section, "overhead") or 0
	local ll = self.map:get(section, "linklayer") or "none"

	return ll ~= "none" and ov or "--"
end


-- CUSTOM SCRIPT

sc = s:option(DummyValue, "script",
	translate("Custom") .. "<br/>" .. translate("Script"))
sc.default = ""
sc.rmempty = true


return m
