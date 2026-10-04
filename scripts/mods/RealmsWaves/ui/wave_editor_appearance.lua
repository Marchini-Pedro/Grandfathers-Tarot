local mod = get_mod("RealmsWaves")
local UIWidget = require("scripts/managers/ui/ui_widget")
local C = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/ui/wave_editor_components")
local Schema = mod:io_dofile("RealmsWaves/scripts/mods/RealmsWaves/catalog/appearance")
local ColourView = {}
local TRACK_X, TRACK_W = 305, 760
local CHANNEL_Y = { 390, 462, 534, 606 }

local function rect(passes, id, x, y, w, h, colour, z)
	passes[#passes + 1] = { pass_type = "rect", style_id = id, style = { offset = { x, y, z or 0 }, size = { w, h }, color = C.clone_color(colour) } }
end

ColourView.definitions = function (nodes, widgets, node)
	nodes.btn_appearance = node(325, 800, 400, 44, 2)
	nodes.rw_colour_method = node(145, 214, 1040, 48, 4)
	local passes = {}
	C.button_passes(passes, "hotspot", { 0, 0, 0 }, { 1040, 48 }, "", 23)
	widgets.rw_colour_method = UIWidget.create_definition(passes, "rw_colour_method")
	nodes.rw_colour_info = node(145, 280, 1480, 90, 2)
	passes = {}
	C.text_pass(passes, "text", "text", { 0, 0, 0 }, { 1480, 90 }, 22, C.colors.text)
	passes[1].style.word_wrap = true
	widgets.rw_colour_info = UIWidget.create_definition(passes, "rw_colour_info")
	for i, channel in ipairs(Schema.CHANNELS) do
		local name = "rw_colour_" .. channel
		nodes[name] = node(145, CHANNEL_Y[i], 1080, 54, 3)
		passes = {}
		C.text_pass(passes, "label", "label", { 0, 0, 0 }, { 145, 54 }, 24, C.colors.text)
		rect(passes, "track", 160, 23, TRACK_W, 8, C.colors.frame)
		rect(passes, "fill", 160, 23, 0, 8, C.colors.gold, 1)
		passes[#passes].visibility_function = function (content) return content.show_fill == true end
		rect(passes, "handle", 156, 13, 8, 28, C.colors.text, 2)
		C.hotspot_pass(passes, "hotspot", { 150, 0, 4 }, { TRACK_W + 20, 54 }, nil, true)
		C.button_passes(passes, "number", { 940, 3, 0 }, { 140, 48 }, "", 24)
		widgets[name] = UIWidget.create_definition(passes, name)
	end
	nodes.rw_colour_swatch = node(1340, 405, 310, 250, 2)
	passes = {}
	rect(passes, "back", 0, 0, 310, 185, { 255, 58, 68, 33 })
	rect(passes, "swatch", 6, 6, 298, 173, { 255, 128, 0, 255 }, 1)
	C.text_pass(passes, "text", "text", { 0, 192, 0 }, { 310, 55 }, 22, C.colors.text, "center")
	widgets.rw_colour_swatch = UIWidget.create_definition(passes, "rw_colour_swatch")
	for i, item in ipairs({ { "rw_colour_outline", "Independent outline" }, { "rw_colour_protect", "Keep edited tint over other buffs" } }) do
		nodes[item[1]] = node(145, 835 + (i - 1) * 58, 1080, 48, 3)
		passes = {}
		C.button(passes, "hotspot", { 0, 0, 0 }, { 1080, 48 }, { label = item[2], font_size = 22, pip = true })
		widgets[item[1]] = UIWidget.create_definition(passes, item[1])
	end
	for i, method in ipairs(Schema.METHODS) do
		local name = "rw_colour_choice_" .. i
		nodes[name] = node(145, 272 + (i - 1) * 48, 1480, 46, 40)
		passes = {}
		C.button(passes, "hotspot", { 0, 0, 0 }, { 1480, 46 }, { label = method.name, font_size = 22, pip = true })
		widgets[name] = UIWidget.create_definition(passes, name)
	end
end

ColourView.install = function (View, h)
	local function part(self) return self._parts and self._parts[self._part_index] end
	local function config(self) return Schema.copy(part(self) and part(self).appearance) or Schema.copy(Schema.DEFAULT) end

	View._refresh_colour = function (self)
		local active, w, value = self._screen == "appearance", self._widgets_by_name, config(self)
		local enabled = active and not self._popup
		w.btn_appearance.visible = self._screen == "tune"
		w.btn_appearance.content.hotspot.disabled = not w.btn_appearance.visible or self._popup ~= nil
		w.btn_appearance.content.hotspot_text = mod:localize("btn_appearance")
		w.rw_colour_method.visible = active
		w.rw_colour_method.content.hotspot_text = Schema.method(value.method).name .. "   v"
		w.rw_colour_method.content.hotspot.disabled = not enabled
		w.rw_colour_info.visible = active and not self._colour_menu
		w.rw_colour_info.content.text = Schema.method(value.method).info
		for i, channel in ipairs(Schema.CHANNELS) do
			local widget = w["rw_colour_" .. channel]
			widget.visible = active
			widget.content.label = channel == "a" and "A - strength" or channel:upper()
			widget.content.number_text = tostring(value[channel])
			widget.content.show_fill = value[channel] > 0
			widget.style.fill.size[1] = TRACK_W * value[channel] / 255
			widget.style.handle.offset[1] = 156 + TRACK_W * value[channel] / 255
			widget.content.hotspot.disabled = not enabled or self._colour_menu == true
			widget.content.number.disabled = widget.content.hotspot.disabled
		end
		w.rw_colour_swatch.visible = active
		local colour = w.rw_colour_swatch.style.swatch.color
		colour[1], colour[2], colour[3], colour[4] = value.a, value.r, value.g, value.b
		w.rw_colour_swatch.content.text = "#" .. Schema.hex(value) .. "\nColour swatch"
		for i in ipairs(Schema.METHODS) do
			local choice = w["rw_colour_choice_" .. i]
			choice.visible = active and self._colour_menu == true
			choice.content.hotspot.disabled = not (enabled and choice.visible) or not Schema.METHODS[i].available
			choice.content.hotspot_on = Schema.METHODS[i].id == value.method
		end
		for _, field in ipairs({ "outline", "protect" }) do
			local toggle = w["rw_colour_" .. field]
			toggle.visible = active and not self._colour_menu
			toggle.content.hotspot.disabled = not enabled or self._colour_menu == true
			toggle.content.hotspot_on = value[field] == true
		end
		if not active or self._popup then self._colour_drag = nil end
	end

	View._create_colour_callbacks = function (self)
		local w = self._widgets_by_name
		for _, field in ipairs({ "outline", "protect" }) do w["rw_colour_" .. field].content.hotspot.pressed_callback = callback(self, "cb_colour_toggle", field) end
		w.rw_colour_method.content.hotspot.pressed_callback = callback(self, "cb_colour_dropdown")
		for i in ipairs(Schema.METHODS) do w["rw_colour_choice_" .. i].content.hotspot.pressed_callback = callback(self, "cb_colour_method", i) end
		for _, channel in ipairs(Schema.CHANNELS) do
			w["rw_colour_" .. channel].content.hotspot.pressed_callback = callback(self, "cb_colour_drag", channel)
			w["rw_colour_" .. channel].content.number.pressed_callback = callback(self, "cb_colour_number", channel)
		end
	end

	View.cb_colour_toggle = h.guarded(function (self, field)
		if self._screen ~= "appearance" or not part(self) then return end
		local value = config(self)
		value[field] = not value[field]
		part(self).appearance = value
		self:_save()
	end)
	View.cb_appearance = h.guarded(function (self)
		if not part(self) then return end
		self._screen, self._colour_menu = "appearance", false
		self:_apply_screen()
	end)
	View.cb_colour_dropdown = h.guarded(function (self)
		self._colour_menu = not self._colour_menu
		self:_refresh_colour()
	end)
	View.cb_colour_method = h.guarded(function (self, index)
		if self._screen ~= "appearance" or not part(self) then return end
		local method = Schema.METHODS[index]
		if not method or not method.available then return end
		local value = config(self)
		value.method = method.id
		part(self).appearance = value
		self._colour_menu = false
		self:_save()
	end)
	View.cb_colour_drag = h.guarded(function (self, channel)
		if self._screen == "appearance" and not self._colour_menu then self._colour_drag = channel end
	end)
	View._set_colour_channel = function (self, channel, value)
		if not part(self) then return end
		local colour = config(self)
		colour[channel] = Schema.channel(value)
		part(self).appearance = Schema.copy(colour)
		self:_save()
	end
	View.cb_colour_number = h.guarded(function (self, channel)
		h.Popup.open(self, { label = "Enemy colour: " .. channel:upper(), value = tostring(config(self)[channel]), numeric = true, min = 0, max = 255, integer = true,
			hint = "0-255. A is tint strength; RGB-only methods do not change mesh opacity.",
			set = function (value) self:_set_colour_channel(channel, value) end })
		self:_refresh_colour()
	end)
	View._update_colour = function (self, input)
		if self._screen ~= "appearance" or self._popup or self._colour_menu then self._colour_drag = nil; return end
		local channel = self._colour_drag
		if not channel then return end
		local x = self:_cursor_point(input)
		if x then
			local value = config(self)
			value[channel] = Schema.channel((x - TRACK_X) / TRACK_W * 255)
			part(self).appearance = value
			self:_refresh_colour()
		end
		if not input:get("left_hold") then self._colour_drag = nil; self:_save() end
	end
end

return ColourView
