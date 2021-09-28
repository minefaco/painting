-- painting - in-game painting for minetest

-- picture is drawn using a nodebox to draw the canvas
-- and an entity which has the painting as its texture.
-- this texture is created by minetests internal image
-- compositing engine (see tile.cpp).

painting = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath.."/crafts.lua")
dofile(modpath.."/functions.lua")

local hexcols = {
	white = "ffffff", yellow = "fff000",
	orange = "ff6c00", red = "ff0000",
	violet = "8a00ff", blue = "000cff",
	green = "0cff00", magenta = "fc00ff",
	cyan = "00ffea", grey = "bebebe",
	dark_grey = "7b7b7b", black = "000000",
	dark_green = "006400", brown="964b00",
	pink = "ffc0cb"
}

local colors = {}

local revcolors = {
	"white", "dark_green", "grey", "red", "brown", "cyan", "orange", "violet",
	"dark_grey", "pink", "green", "magenta", "yellow", "black", "blue"
}

local thickness = 0.1

-- picture node
local picbox = {
	type = "fixed",
	fixed = { -0.499, -0.499, 0.499, 0.499, 0.499, 0.499 - thickness }
}

local current_version = "hexcolors"
local legacy = {}

-- puts the version before the compressed data
local function get_metastring(data)
	return current_version.."(version)"..data
end

-- Initiate a white grid.
local function initgrid(res)
	local grid, a, x, y = {}, res-1
	for x = 0, a do
		grid[x] = {}
		for y = 0, a do
			grid[x][y] = hexcols["white"]
		end
	end
	return grid
end

function painting.to_imagestring(data, res)
	if not data then
		minetest.log("error", "[painting] missing data")
		return
	end
	local cols = {}
	for y = 0, res - 1 do
		local xs = data[y]
		for x = 0, res - 1 do
			local col = xs[x]
			--if col ~= "white" then
				cols[col] = cols[col] or {}
				cols[col][#cols[col]+1] = {y, x}
			--end
		end
	end
	local t,n = {},1
	local groupopen = "([combine:"..res.."x"..res
	for hexcolour,ps in pairs(cols) do
		t[n] = groupopen
		n = n+1
		for _,p in pairs(ps) do
			local y,x = unpack(p)
			t[n] = ":"..p[1]..","..p[2].."=white.png"
			n = n+1
		end
		t[n] = "^[colorize:#"..hexcolour..")^"
		n = n+1
	end
	n = n-1
	if n == 0 then
		minetest.log("error", "[painting] no texels")
		return "white.png"
	end
	t[n] = t[n]:sub(1,-2)
	--print(table.concat(t))
	return table.concat(t)
end

local function dot(v, w)	-- Inproduct.
	return	v.x * w.x + v.y * w.y + v.z * w.z
end

local function intersect(pos, dir, origin, normal)
	local t = -(dot(vector.subtract(pos, origin), normal)) / dot(dir, normal)
	return vector.add(pos, vector.multiply(dir, t))
end

local function clamp(x, min,max)
	return math.max(math.min(x, max),min)
end

minetest.register_node("painting:pic", {
	description = "Picture",
	tiles = { "white.png" },
	inventory_image = "painted.png",
	drawtype = "nodebox",
	sunlight_propagates = true,
	paramtype = "light",
	paramtype2 = "facedir",
	node_box = picbox,
	selection_box = picbox,
	groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2,
		not_in_creative_inventory=1},

	--handle that right below, don't drop anything
	drop = "",

	after_dig_node = function(pos, _, oldmetadata, digger)
		--find and remove the entity
		for _,e in pairs(minetest.get_objects_inside_radius(pos, 0.5)) do
			if e:get_luaentity().name == "painting:picent" then
				e:remove()
			end
		end

		local data = legacy.load_itemmeta(oldmetadata.fields["painting:picturedata"])

		--put picture data back into inventory item
		--[[local picture = ItemStack("painting:paintedcanvas")
		local meta = picture:get_meta()
		meta:set_int("resolution", oldmetadata.fields["resolution"])
		meta:set_string("version", oldmetadata.fields["version"])
		meta:set_string("grid", oldmetadata.fields["grid"])
		local inv = digger:get_inventory()
		if inv:room_for_item("main", picture) then
			inv:add_item("main", picture)
		else
			minetest.add_item(digger:get_pos(), picture)
		end--]]
		digger:get_inventory():add_item("main", {
			name = "painting:paintedcanvas",
			count = 1,
			metadata = get_metastring(data)
		})
	end
})

-- picture texture entity
minetest.register_entity("painting:picent", {
	collisionbox = { 0, 0, 0, 0, 0, 0 },
	visual = "upright_sprite",
	textures = { "white.png" },

	on_activate = function(self, staticdata)
		local pos = self.object:get_pos()
		local data = legacy.load_itemmeta(minetest.get_meta(pos):get_string("painting:picturedata"))
		data = minetest.deserialize(
			painting.decompress(data)
		)
		if not data
		or not data.grid then
			return
		end
		self.object:set_properties{textures = { painting.to_imagestring(data.grid, data.res) }}
		if data.version ~= current_version then
			minetest.log("legacy", "[painting] updating placed picture data")
			data.version = current_version
			data = painting.compress(
				minetest.serialize(data)
			)
			minetest.get_meta(pos):set_string("painting:picturedata", get_metastring(data))
		end
	end
})

-- Figure where it hits the canvas, in fraction given position and direction.

local function figure_paint_pos_raw(pos, d,od, ppos, l, eye_height)
	ppos.y = ppos.y + eye_height

	local normal = { x = d.x, y = 0, z = d.z }
	local p = intersect(ppos, l, pos, normal)

	local off = -0.5
	pos = vector.add(pos, {x=off*od.x, y=off, z=off*od.z})
	p = vector.subtract(p, pos)
	return math.abs(p.x + p.z), 1 - p.y
end

local dirs = {	-- Directions the painting may be.
	[0] = { x = 0, z = 1 },
	[1] = { x = 1, z = 0 },
	[2] = { x = 0, z =-1 },
	[3] = { x =-1, z = 0 }
}
-- .. idem .. given self and puncher.
local function figure_paint_pos(self, puncher)
	local x,y = figure_paint_pos_raw(self.object:get_pos(),
		dirs[self.fd], dirs[(self.fd + 1) % 4],
		puncher:get_pos(), puncher:get_look_dir(),
		puncher:get_properties().eye_height)
	return math.floor(self.res*clamp(x, 0, 1)), math.floor(self.res*clamp(y, 0, 1))
end

local function draw_input(self, hexcolor, x,y, as_line)
	local x0 = self.x0
	if as_line and x0 and vector.twoline then -- Draw line if requested *and* have a previous position.
		local y0 = self.y0
		local line = vector.twoline(x0-x, y0-y)	-- This figures how to do the line.
		for _,coord in pairs(line) do
			self.grid[x+coord[1]][y+coord[2]] = hexcolor
		end
	else	-- Draw just single point.
		self.grid[x][y] = hexcolor
	end
	self.x0, self.y0 = x, y -- Update previous position.
	-- Actually update the grid.
	self.object:set_properties{textures = { painting.to_imagestring(self.grid, self.res) }}
end

local paintbox = {
	[0] = { -0.5,-0.5,0,0.5,0.5,0 },
	[1] = { 0,-0.5,-0.5,0,0.5,0.5 }
}

-- Painting as being painted.
minetest.register_entity("painting:paintent", {
	collisionbox = { 0, 0, 0, 0, 0, 0 },
	visual = "upright_sprite",
	textures = { "white.png" },

	on_punch = function(self, puncher)
		--check for brush.
		local name = string.match(puncher:get_wielded_item():get_name(), "_([^_]*)")
		local name = puncher:get_wielded_item():get_name()
		local def = minetest.registered_items[name]
		if (not def) or (not def._painting_brush_color) then -- Not one of the brushes; can't paint.
			return
		end

		assert(self.object)
		local x,y = figure_paint_pos(self, puncher)
		draw_input(self, def._painting_brush_color, x,y, puncher:get_player_control().sneak)

		local wielded = puncher:get_wielded_item()	-- Wear down the tool.
		wielded:add_wear(65535/256)
		puncher:set_wielded_item(wielded)
	end,

	on_activate = function(self, staticdata)
		local data = minetest.deserialize(staticdata)
		if not data then
			return
		end
		self.fd = data.fd
		self.x0, self.y0 = data.x0, data.y0
		self.res = data.res
		self.version = data.version
		self.grid = data.grid
		legacy.fix_grid(self.grid, self.version)
		self.object:set_properties{ textures = { painting.to_imagestring(self.grid, self.res) }}
		if not self.fd then
			return
		end
		self.object:set_properties{ collisionbox = paintbox[self.fd%2] }
		self.object:set_armor_groups{immortal=1}
	end,

	get_staticdata = function(self)
		return minetest.serialize{fd = self.fd, res = self.res,
			grid = self.grid, x0 = self.x0, y0 = self.y0, version = self.version
		}
	end
})

-- just pure magic
local walltoface = {-1, -1, 1, 3, 0, 2}

--paintedcanvas picture inventory item
minetest.register_craftitem("painting:paintedcanvas", {
	description = "Painted Canvas",
	inventory_image = "painted.png",
	stack_max = 1,
	groups = { snappy = 2, choppy = 2, oddly_breakable_by_hand = 2, not_in_creative_inventory=1 },

	on_place = function(itemstack, placer, pointed_thing)
		--place node
		local pos = pointed_thing.above
		if minetest.is_protected(pos, placer:get_player_name()) then
			return
		end

		local under = pointed_thing.under

		local wm = minetest.dir_to_wallmounted(vector.subtract(under, pos))

		local fd = walltoface[wm + 1]
		if fd == -1 then
			return itemstack
		end

		minetest.add_node(pos, {name = "painting:pic", param2 = fd})

		--save metadata
		local data = legacy.load_itemmeta(itemstack:get_metadata())
		minetest.get_meta(pos):set_string("painting:picturedata", get_metastring(data))

		--add entity
		local dir = dirs[fd]
		local off = 0.5 - thickness - 0.01

		pos.x = pos.x + dir.x * off
		pos.z = pos.z + dir.z * off
		
		data = minetest.deserialize(painting.decompress(data))

		local obj = minetest.add_entity(pos, "painting:picent")
		obj:set_properties{ textures = { to_imagestring(data.grid, data.res) }}
		obj:set_yaw(math.pi * fd / -2)

		return ItemStack("")
	end
})

--canvas inventory items
for i = 4,6 do
	minetest.register_craftitem("painting:canvas_"..2^i, {
		description = "Canvas(" .. 2^i .. ")",
		inventory_image = "default_paper.png",
		stack_max = 99,
		_painting_canvas_resolution = 2^i,
	})
end

--canvas for drawing
local canvasbox = {
	type = "fixed",
	fixed = { -0.5, -0.5, 0, 0.5, 0.5, thickness }
}

minetest.register_node("painting:canvasnode", {
	description = "Canvas",
	tiles = { "white.png" },
	inventory_image = "painted.png",
	drawtype = "nodebox",
	sunlight_propagates = true,
	paramtype = "light",
	paramtype2 = "facedir",
	node_box = canvasbox,
	selection_box = canvasbox,
	groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2,
		not_in_creative_inventory=1},

	drop = "",

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		--get data and remove pixels
		local data = {}
		for _,e in pairs(minetest.get_objects_inside_radius(pos, 0.1)) do
			e = e:get_luaentity()
			if e.grid then
				data.grid = e.grid
				data.version = e.version
				data.res = e.res
				e.object:remove()
				break
			end
		end

		pos.y = pos.y-1
		minetest.get_meta(pos):set_int("has_canvas", 0)

		if not data.grid then
			return
		end
		legacy.fix_grid(data.grid, data.version)
		local item = ItemStack({
			name = "painting:paintedcanvas",
			count = 1,
			metadata = get_metastring(painting.compress(minetest.serialize(data)))
		})
		local item_meta = item:get_meta()
		item_meta:set_int("painting_resolution", data.res)
		digger:get_inventory():add_item("main", item)
	end
})

local easelbox = { -- Specifies 3d model.
	type = "fixed",
	fixed = {
		--feet
		{-0.4, -0.5, -0.5, -0.3, -0.4, 0.5 },
		{ 0.3, -0.5, -0.5,	0.4, -0.4, 0.5 },
		--legs
		{-0.4, -0.4, 0.1, -0.3, 1.5, 0.2 },
		{ 0.3, -0.4, 0.1,	0.4, 1.5, 0.2 },
		--shelf
		{-0.5, 0.35, -0.3, 0.5, 0.45, 0.1 }
	}
}

minetest.register_node("painting:easel", {
	description = "Easel",
	tiles = { "default_wood.png" },
	drawtype = "nodebox",
	sunlight_propagates = true,
	paramtype = "light",
	paramtype2 = "facedir",
	node_box = easelbox,
	selection_box = easelbox,

	groups = { snappy = 2, choppy = 2, oddly_breakable_by_hand = 2 },

	on_punch = function(pos, node, player)
		local wield_item = player:get_wielded_item()
		local wield_meta = wield_item:get_meta()
		local def = wield_item:get_definition()
		if (not def) or ((not def._painting_canvas_resolution) and (wield_meta:get_int("painting_resolution")==0)) then	-- Can only put the canvas on there.
			return
		end

		local meta = minetest.get_meta(pos)
		pos.y = pos.y+1
		if minetest.get_node(pos).name ~= "air" then
			-- this is not likely going to happen
			return
		end
		local fd = node.param2
		minetest.add_node(pos, { name = "painting:canvasnode", param2 = fd})

		local dir = dirs[fd]
		pos.x = pos.x - 0.01 * dir.x
		pos.z = pos.z - 0.01 * dir.z

		local obj = minetest.add_entity(pos, "painting:paintent")
		obj:set_properties{ collisionbox = paintbox[fd%2] }
		obj:set_armor_groups{immortal=1}
		obj:set_yaw(math.pi * fd / -2)
		local ent = obj:get_luaentity()
		local data = wield_item:get_metadata();
		if data and (data~="") then
			data = minetest.deserialize(painting.decompress(legacy.load_itemmeta(data)))
			ent.grid = data.grid
			ent.res = data.res
			ent.version = data.version
		else
			ent.grid = initgrid(def._painting_canvas_resolution)
			ent.res = def._painting_canvas_resolution
			ent.version = current_version
		end
		ent.fd = fd

		meta:set_int("has_canvas", 1)
		player:get_inventory():remove_item("main", wield_item:take_item())
	end,

	can_dig = function(pos)
		return minetest.get_meta(pos):get_int("has_canvas") == 0
	end
})

--brushes
local function table_copy(t)
	local t2 = {}
	for k,v in pairs(t) do
		t2[k] = v
	end
	return t2
end

local brush = {
	wield_image = "",
	tool_capabilities = {
		full_punch_interval = 1.0,
		max_drop_level=0,
		groupcaps = {}
	}
}

local textures = {
	white = "white.png", yellow = "yellow.png",
	orange = "orange.png", red = "red.png",
	violet = "violet.png", blue = "blue.png",
	green = "green.png", magenta = "magenta.png",
	cyan = "cyan.png", grey = "grey.png",
	dark_grey = "darkgrey.png", black = "black.png",
	dark_green = "darkgreen.png", brown="brown.png",
	pink = "pink.png"
}

minetest.register_craftitem("painting:brush", {
		description = "Brush",
		inventory_image = "painting_brush_stem.png^(painting_brush_head.png^[colorize:#FFFFFF:128)^painting_brush_head.png",
	})

local dye_prefix = "dye:"
if minetest.get_modpath("mcl_dye") then
	dye_prefix = "mcl_dye:"
end

local vage_revcolours = {} -- ← colours in pairs order
for color, _ in pairs(textures) do
	local brush_new = table_copy(brush)
	brush_new.description = color:gsub("^%l", string.upper).." brush"
	brush_new.inventory_image = "painting_brush_stem.png^(painting_brush_head.png^[colorize:#"..hexcols[color]..":255)^painting_brush_head.png"
	brush_new._painting_brush_color = hexcols[color]
	minetest.register_tool("painting:brush_"..color, brush_new)
	minetest.register_craft{
		output = "painting:brush_"..color,
		recipe = {
			{dye_prefix..color},
			{"painting:brush"}
		}
	}

	vage_revcolours[#vage_revcolours+1] = color
end

-- If you want to use custom pairs order, e.g. if the map is played on a
-- different pc, uncomment this line:

--print("vage_revcolours = "..dump(vage_revcolours)) error"↑"

-- then load the world with this mod on the original pc in a terminal, after
-- that put the printed thing ("vage_revcolours = […]}") here ↓



-- then the mod with the world can be used on other pc, of course you need to
-- have re-commented that line above

for i, color in ipairs(revcolors) do
	colors[color] = i
end


-- legacy

minetest.register_alias("easel", "painting:easel")
minetest.register_alias("canvas", "painting:canvas_16")

-- fixes the colours which were set by pairs
local function fix_eldest_grid(data)
	for y in pairs(data) do
		local xs = data[y]
		for x in pairs(xs) do
			-- it was done in pairs order
			xs[x] = hexcolors[vage_revcolours[xs[x]]]
		end
	end
	return data
end
local function fix_nopairs_grid(data)
	for y in pairs(data) do
		local xs = data[y]
		for x in pairs(xs) do
			-- it was done in pairs order
			xs[x] = hexcolors[revcolors[xs[x]]]
		end
	end
	return data
end

-- possibly updates grid
function legacy.fix_grid(grid, version)
	if version == current_version then
		return
	end

	minetest.log("legacy", "[painting] updating grid")
	
	if version == "nopairs" then
		fix_nopairs_grid(grid)
	else
		fix_eldest_grid(grid)
	end
end

-- gets the compressed data from meta
function legacy.load_itemmeta(data)
	local vend = data:find"(version)"
	if not vend then -- the oldest version
		local t = minetest.deserialize(data)
		if t.version then
			minetest.log("error", "[painting] this musn't happen!")
		end
		minetest.log("legacy", "[painting] updating painting meta")
		legacy.fix_grid(t.grid)
		return painting.compress(minetest.serialize(t))
	end
	local version = data:sub(1, vend-2)
	data = data:sub(vend+8)
	if version == current_version then
		return data
	end
end

--[[ allows using many colours, doesn't work
function to_imagestring(data, res)
	if not data then
		return
	end
	local t,n = {},1
	local sbc = {}
	for y = 0, res - 1 do
		for x = 0, res - 1 do
			local col = revcolors[data[x][y] ]
			sbc[col] = sbc[col] or {}
			sbc[col][#sbc[col] ] = {x,y}
		end
	end
	for col,ps in pairs(sbc) do
		t[n] = "([combine:"..res.."x"..res..":"
		n = n+1
		for _,p in pairs(ps) do
			t[n] = p[1]..","..p[2].."=white.png:"
			n = n+1
		end
		t[n-1] = string.sub(t[n-1], 1,-2)
		t[n] = "^[colorize:"..col..")^"
		n = n+1
	end
	t[n-1] = string.sub(t[n-1], 1,-2)
	return table.concat(t)
end--]]
