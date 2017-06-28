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

local wa = require "luci.tools.webadmin"
local fs = require "nixio.fs"
local net = require "luci.model.network".init()
local sys = require "luci.sys"
--local ifaces = net:get_interfaces()
local ifaces = sys.net:devices()
local path = "/usr/lib/sqm"
local qdisc_caps_path = "/tmp/run/sqm/available_qdiscs"

m = Map("sqm", translate("Smart Queue Management"),
	translate("With <abbr title=\"Smart Queue Management\">SQM</abbr> you " ..
                  "can enable traffic shaping, better mixing (Fair Queueing)," ..
                  " active queue length management (AQM) " ..
                  " and prioritisation on one " ..
                  "network interface." ..
                  "<br />LEDE Documentation: " ..
                  "<a href=\"https://lede-project.org/docs/howto/sqm\" " ..
                  "target=\"_blank\">" ..
                  "Smart Queue Management (SQM) - Minimizing Bufferbloat" ..
                  "</a>"))

s = m:section(TypedSection, "queue", translate("Queues"))
s:tab("tab_basic", translate("Basic Settings"))
s:tab("tab_qdisc", translate("Queue Discipline"))
s:tab("tab_linklayer", translate("Link Layer Adaptation"))
s.addremove = true -- set to true to allow adding SQM instances in the GUI
s.anonymous = true


-- Implement a local "variant" form of option to handle complex dependencies
-- This allows for varying the displayed option values based on dependencies

function s:varianttaboption(tab, class, opt, vars, desc)
	assert(type(vars) == "table" and #vars > 0,
		"Cannot use variant option without table of variants")
	local s = self
	local o = s:taboption(tab, class, opt, desc)
	o:depends("_nosuchoption", "_nosuchvalue")
	o.optional = true
	o.variants = {}
	for _, v in ipairs(vars) do
		o.variants[v] = s:taboption(tab, class, "_%s_%s" % {v, opt}, desc)
		o.variants[v].optional = true
		o.variants[v].cfgvalue = function(s, sc) return o:cfgvalue(sc) end
		o.variants[v].write = function(s, sc, vl) return o:write(sc, vl) end
--		o.variants[v].remove = function(s, sc) return o:remove(sc) end
		o.variants[v].yield = function(y) y(o.variants[v]) end
	end
	return o
end


-- BASIC
e = s:taboption("tab_basic", Flag, "enabled", translate("Enable this SQM instance."))
e.rmempty = false

-- sm: following jow's advise, be helpful to the user and enable
--     sqm's init script if even a single sm instance/interface
--     is enabled; this is unexpected in that the init script gets
--     enabled as soon as at least one sqm instance is enabled
--     and that state is saved, so it does not require "Save & Apply"
--     to effect the init scripts.
--     the implementation was inpired/lifted from 
--     https://github.com/openwrt/luci/blob/master/applications/luci-app-minidlna/luasrc/model/cbi/minidlna.lua
function e.write(self, section, value)
	if value == "1" then
		luci.sys.init.enable("sqm")
		m.message = translate("The SQM GUI has just enabled the sqm initscript on your behalf. Remember to disable the sqm initscript manually under System Startup menu in case this change was not wished for.")
	end
	return Flag.write(self, section, value)
end
-- TODO: inform the user what we just did...


-- Add to physical interface list a hint of the correpsonding network names,
-- used to help users better select e.g. lan or wan interface.

n = s:taboption("tab_basic", ListValue, "interface", translate("Interface name"))
-- sm lifted from luci-app-wol, the original implementation failed to show pppoe-ge00 type interface names
for _, iface in ipairs(ifaces) do
	if not (iface == "lo" or iface:match("^ifb.*")) then
		local nets = net:get_interface(iface)
		nets = nets and nets:get_networks() or {}
		for k, v in pairs(nets) do
			nets[k] = nets[k].sid
		end
		nets = table.concat(nets, ",")
		n:value(iface, ((#nets > 0) and "%s (%s)" % {iface, nets} or iface))
	end
end
n.rmempty = false


dl = s:taboption("tab_basic", Value, "download", translate("Download speed (kbit/s) (ingress) set to 0 to selectively disable ingress shaping:"))
dl.datatype = "and(uinteger,min(0))"
dl.rmempty = false

ul = s:taboption("tab_basic", Value, "upload", translate("Upload speed (kbit/s) (egress) set to 0 to selectively disable egress shaping:"))
ul.datatype = "and(uinteger,min(0))"
ul.rmempty = false

dbl = s:taboption("tab_basic", Flag, "debug_logging", translate("Create log file for this SQM instance under /var/run/sqm/${Inerface_name}.debug.log. Make sure to delete log files manually."))
dbl.rmempty = false


verb = s:taboption("tab_basic", ListValue, "verbosity", translate("Verbosity of SQM's output into the system log."))
verb:value("0", "silent")
verb:value("1", "error")
verb:value("2", "warning")
verb:value("5", "info ("..translate("default")..")")
verb:value("8", "debug")
verb:value("10", "trace")
verb.default = "5"
verb.rmempty = true


-- Read qdisc and shaper capabilities

function read_caps(path)
	local result = {}
	if fs.stat(path) then
		for fname in fs.dir(path) do
			local caps = {}
			for line in io.lines(path .. "/" .. fname) do
				for word in string.gmatch(line,"%S+") do
					table.insert(caps, word)
				end
			end
			result[fname] = caps
		end
	end
	return result
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

local all_qdiscs = read_caps(qdisc_caps_path)

local avail_leafs = {}
for k, v in match_caps_pairs(all_qdiscs,"leaf") do
	avail_leafs[k] = all_qdiscs[k]
end

local avail_shapers = {}
for k, v in match_caps_pairs(all_qdiscs,"shaper") do
	avail_shapers[k] = all_qdiscs[k]
end

-- Extract details of "diffserv" capabilities, including UCI variable values
-- and related descriptive text

local qdisc_diffserv = {}
local qdiscs_with_diffserv = {}
for k, p in match_caps_pairs(all_qdiscs, "diffserv") do
	qdisc_diffserv[k] = {}
	table.insert(qdiscs_with_diffserv, k)
	for _, s in match_caps_pairs(p, "diffserv") do
		local _, v, d = string.match(s, "(%S+):(%S+):(%S+)")
		table.insert(qdisc_diffserv[k], { val = v, desc = d:gsub("_", " ") })
	end
end

-- Extract details of "preset" capabilities, including UCI variable values
-- and related descriptive text

local qdisc_presets = {}
local qdiscs_with_presets = {}
for k, p in match_caps_pairs(all_qdiscs, "preset") do
	qdisc_presets[k] = {}
	table.insert(qdiscs_with_presets, k)
	for _, s in match_caps_pairs(p, "preset") do
		local _, v, d = string.match(s, "(%S+):(%S+):(%S+)")
		table.insert(qdisc_presets[k], { val = v, desc = d:gsub("_", " ") })
	end
end


-- QDISC

c = s:taboption("tab_qdisc", ListValue, "qdisc", translate("Queuing disciplines useable on this system. After installing a new qdisc, you need to restart the router to see updates!"))
c:value("fq_codel", "fq_codel ("..translate("default")..")")

for k, _ in pairs(avail_leafs) do
	c:value(k)
end

c.default = "fq_codel"
c.rmempty = false


-- SHAPER

shp = s:varianttaboption("tab_qdisc", ListValue, "shaper", {"tc", "cake"}, translate("Shapers useable on this system."))
shp.rmempty = false

shp.variants["tc"].yield(function(o)
		o:value("htb", "htb ("..translate("default")..")")

		for k, _ in pairs(avail_shapers) do
			if k ~= "cake" then
				o:value(k)
			end
		end

		o.default = "htb"
		o.rmempty = false

		for k, _ in pairs(avail_leafs) do
			if k ~= "cake" then
				o:depends("qdisc",k)
			end
		end
	end)

-- This implements a pseudo-shaper "cake" only usable with the cake qdisc
-- but also allow for cake as a leaf qdisc with other shapers

shp.variants["cake"].yield(function(o)
		o:value("cake", "cake ("..translate("default")..")")

		for k, _ in pairs(avail_shapers) do
			o:value(k)
		end

		o.default = "cake"
		o.rmempty = false
		o:depends("qdisc","cake")
	end)


-- QDISC PRESET

qdp = s:varianttaboption("tab_qdisc", ListValue, "qdisc_preset", qdiscs_with_presets, translate("Predefined configurations for this qdisc."))
qdp.rmempty = true

for _, q in pairs(qdiscs_with_presets) do
	qdp.variants[q].yield(function(o)
			o:value("", "<do not use>")
			for _, p in pairs(qdisc_presets[q]) do
				o:value(p.val, p.desc)
			end

			o.default = ""
			o.rmempty = false
			o:depends("qdisc", q)
		end)
end


-- ADVANCED

ad = s:taboption("tab_qdisc", Flag, "qdisc_advanced", translate("Show and Use Advanced Configuration. Advanced options will only be used as long as this box is checked."))
ad.default = false
ad.rmempty = true

zero_dscp_in = s:taboption("tab_qdisc", ListValue, "zero_dscp_ingress", translate("Pass-through DSCP on inbound packets (ingress):"))
zero_dscp_in:value("1", "DO NOT PASS ("..translate("default")..")")
zero_dscp_in:value("0", "PASS")
zero_dscp_in.default = "1"
zero_dscp_in.rmempty = true
zero_dscp_in:depends("qdisc_advanced", "1")

zero_dscp_eg = s:taboption("tab_qdisc", ListValue, "zero_dscp_egress", translate("Pass-through DSCP on outbound packets (egress):"))
zero_dscp_eg:value("1", "DO NOT PASS ("..translate("default")..")")
zero_dscp_eg:value("0", "PASS")
zero_dscp_eg.default = "1"
zero_dscp_eg.rmempty = true
zero_dscp_eg:depends("qdisc_advanced", "1")

-- Only allow configuring prioritization with classful shapers or cake,
-- i.e. qdiscs which have the 'diffserv' capability

deps_prioritize = {}
for _, v in pairs(qdiscs_with_diffserv) do
	table.insert(deps_prioritize, {["qdisc_advanced"]="1", [shp.variants["tc"].option]=v})
	table.insert(deps_prioritize, {["qdisc_advanced"]="1", [shp.variants["cake"].option]=v})
end

local function dfsrv_setup(q, var)
	return function(o)
		o:value("diffserv3", "3-Tier [diffserv3] ("..translate("default")..")")
		for _, d in pairs(qdisc_diffserv[q]) do
			o:value(d.val, d.desc)
		end

		o.default = "diffserv3"
		o.rmempty = true
		o.widget = "radio"
		o.orientation = "horizontal"

		o:depends({[var]="0", [shp.variants["tc"].option]=q})
		o:depends({[var]="0", [shp.variants["cake"].option]=q})
	end
end

ign_dscp_in = s:taboption("tab_qdisc", ListValue, "ignore_dscp_ingress", translate("Prioritize by DSCP on inbound packets (ingress):"))
ign_dscp_in:value("1", "DO NOT PRIORITIZE ("..translate("default")..")")
ign_dscp_in:value("0", "PRIORITIZE")
ign_dscp_in.default = "1"
ign_dscp_in.rmempty = true
for _, v in pairs(deps_prioritize) do
	ign_dscp_in:depends(v)
end

dfsrv_in = s:varianttaboption("tab_qdisc", ListValue, "diffserv_ingress", qdiscs_with_diffserv, translate("Priority scheme on inbound packets (ingress):"))

for _, v in pairs(qdiscs_with_diffserv) do
	dfsrv_in.variants[v].yield(dfsrv_setup(v, "ignore_dscp_ingress"))
end

ign_dscp_eg = s:taboption("tab_qdisc", ListValue, "ignore_dscp_egress", translate("Prioritize by DSCP on outbound packets (egress):"))
ign_dscp_eg:value("1", "DO NOT PRIORITIZE ("..translate("default")..")")
ign_dscp_eg:value("0", "PRIORITIZE")
ign_dscp_eg.default = "1"
ign_dscp_eg.rmempty = true
for _, v in pairs(deps_prioritize) do
	ign_dscp_eg:depends(v)
end

dfsrv_eg = s:varianttaboption("tab_qdisc", ListValue, "diffserv_egress", qdiscs_with_diffserv, translate("Priority scheme on outbound packets (egress):"))

for _, v in pairs(qdiscs_with_diffserv) do
	dfsrv_eg.variants[v].yield(dfsrv_setup(v, "ignore_dscp_egress"))
end

deps_ecn = {}
for k, _ in match_caps_pairs(avail_leafs, "ecn") do
	table.insert(deps_ecn, {["qdisc_advanced"]="1", ["qdisc"]=k})
end

iecn = s:taboption("tab_qdisc", ListValue, "ingress_ecn", translate("Explicit congestion notification (ECN) status on inbound packets (ingress):"))
iecn:value("ECN", "ECN ("..translate("default")..")")
iecn:value("NOECN")
iecn.default = "ECN"
iecn.rmempty = true
for _, v in pairs(deps_ecn) do
	iecn:depends(v)
end

eecn = s:taboption("tab_qdisc", ListValue, "egress_ecn", translate("Explicit congestion notification (ECN) status on outbound packets (egress)."))
eecn:value("NOECN", "NOECN ("..translate("default")..")")
eecn:value("ECN")
eecn.default = "NOECN"
eecn.rmempty = true
for _, v in pairs(deps_ecn) do
	eecn:depends(v)
end

ad2 = s:taboption("tab_qdisc", Flag, "qdisc_really_really_advanced", translate("Show and Use Dangerous Configuration. Dangerous options will only be used as long as this box is checked."))
ad2.default = false
ad2.rmempty = true
ad2:depends("qdisc_advanced", "1")

local qos_desc = ""
sc = s:taboption("tab_qdisc", ListValue, "script", translate("Custom setup script"))
sc:value("","<none> ("..translate("default")..")")
for file in fs.dir(path) do
	if string.find(file, ".qos$") and not fs.stat(path .. "/" .. file .. ".hidden") then
		sc:value(file)
		qos_desc = qos_desc .. "<p><b>" .. file .. ":</b><br />"
		fh = io.open(path .. "/" .. file .. ".help", "r")
		if fh then
			qos_desc = qos_desc .. fh:read("*a") .. "</p>"
		else
			qos_desc = qos_desc .. "No help text</p>"
		end
	end
end
sc.default = ""
sc.rmempty = true
sc:depends("qdisc_really_really_advanced", "1")
sc.description = qos_desc

ilim = s:taboption("tab_qdisc", Value, "ilimit", translate("Hard limit on ingress queues; leave empty for default."))
-- ilim.default = 1000
ilim.isnumber = true
ilim.datatype = "and(uinteger,min(0))"
ilim.rmempty = true
ilim:depends("qdisc_really_really_advanced", "1")

elim = s:taboption("tab_qdisc", Value, "elimit", translate("Hard limit on egress queues; leave empty for default."))
-- elim.default = 1000
elim.datatype = "and(uinteger,min(0))"
elim.rmempty = true
elim:depends("qdisc_really_really_advanced", "1")


itarg = s:taboption("tab_qdisc", Value, "itarget", translate("Latency target for ingress, e.g 5ms [units: s, ms, or  us]; leave empty for automatic selection, put in the word default for the qdisc's default."))
itarg.datatype = "string"
itarg.rmempty = true
itarg:depends("qdisc_really_really_advanced", "1")

etarg = s:taboption("tab_qdisc", Value, "etarget", translate("Latency target for egress, e.g. 5ms [units: s, ms, or  us]; leave empty for automatic selection, put in the word default for the qdisc's default."))
etarg.datatype = "string"
etarg.rmempty = true
etarg:depends("qdisc_really_really_advanced", "1")



iqdisc_opts = s:taboption("tab_qdisc", Value, "iqdisc_opts", translate("Advanced option string to pass to the ingress queueing disciplines; no error checking, use very carefully."))
iqdisc_opts.rmempty = true
iqdisc_opts:depends("qdisc_really_really_advanced", "1")

eqdisc_opts = s:taboption("tab_qdisc", Value, "eqdisc_opts", translate("Advanced option string to pass to the egress queueing disciplines; no error checking, use very carefully."))
eqdisc_opts.rmempty = true
eqdisc_opts:depends("qdisc_really_really_advanced", "1")

-- LINKLAYER
ll = s:taboption("tab_linklayer", ListValue, "linklayer", translate("Which link layer to account for:"))
ll:value("none", "none ("..translate("default")..")")
ll:value("ethernet", "Ethernet with overhead: select for e.g. VDSL2.")
ll:value("atm", "ATM: select for e.g. ADSL1, ADSL2, ADSL2+.")
ll.default = "none"

po = s:taboption("tab_linklayer", Value, "overhead", translate("Per Packet Overhead (byte):"))
po.datatype = "and(integer,min(-1500))"
po.default = 0
po.isnumber = true
po.rmempty = true
po:depends("linklayer", "ethernet")
po:depends("linklayer", "atm")


adll = s:taboption("tab_linklayer", Flag, "linklayer_advanced", translate("Show Advanced Linklayer Options, (only needed if MTU > 1500). Advanced options will only be used as long as this box is checked."))
adll.rmempty = true
adll:depends("linklayer", "ethernet")
adll:depends("linklayer", "atm")

smtu = s:taboption("tab_linklayer", Value, "tcMTU", translate("Maximal Size for size and rate calculations, tcMTU (byte); needs to be >= interface MTU + overhead:"))
smtu.datatype = "and(uinteger,min(0))"
smtu.default = 2047
smtu.isnumber = true
smtu.rmempty = true
smtu:depends("linklayer_advanced", "1")

stsize = s:taboption("tab_linklayer", Value, "tcTSIZE", translate("Number of entries in size/rate tables, TSIZE; for ATM choose TSIZE = (tcMTU + 1) / 16:"))
stsize.datatype = "and(uinteger,min(0))"
stsize.default = 128
stsize.isnumber = true
stsize.rmempty = true
stsize:depends("linklayer_advanced", "1")

smpu = s:taboption("tab_linklayer", Value, "tcMPU", translate("Minimal packet size, MPU (byte); needs to be > 0 for ethernet size tables:"))
smpu.datatype = "and(uinteger,min(0))"
smpu.default = 0
smpu.isnumber = true
smpu.rmempty = true
smpu:depends("linklayer_advanced", "1")

lla = s:taboption("tab_linklayer", ListValue, "linklayer_adaptation_mechanism", translate("Which linklayer adaptation mechanism to use; for testing only"))
lla:value("default", "default ("..translate("default")..")")
lla:value("cake")
lla:value("htb_private")
lla:value("tc_stab")
lla.default = "default"
lla.rmempty = true
lla:depends("linklayer_advanced", "1")

-- PRORITIES?

return m
