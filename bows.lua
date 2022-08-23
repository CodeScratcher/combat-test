function combat_test.register_bow(name, def)
	if name == nil or name == '' then
		return false
	end

	def.name = 'combat_test:' .. name
	def.name_charged = 'combat_test:' .. name .. '_charged'
	def.description = def.description or name
	def.uses = def.uses or 150

	combat_test.registered_bows[def.name_charged] = def

	-- not charged bow
	minetest.register_tool(def.name, {
		description = def.description .. '\n' .. minetest.colorize('#00FF00', 'Critical Arrow Chance: ' .. (1 / def.crit_chance) * 100 .. '%'),
		inventory_image = def.inventory_image or 'x_bows_bow_wood.png',
		-- on_use = function(itemstack, user, pointed_thing)
		-- end,
		on_place = combat_test.load,
		on_secondary_use = combat_test.load,
		groups = {bow = 1, flammable = 1},
		-- range = 0
	})

	-- charged bow
	minetest.register_tool(def.name_charged, {
		description = def.description .. '\n' .. minetest.colorize('#00FF00', 'Critical Arrow Chance: ' .. (1 / def.crit_chance) * 100 .. '%'),
		inventory_image = def.inventory_image_charged or 'x_bows_bow_wood_charged.png',
		on_use = def.on_use or x_bows.shoot,
		groups = {bow = 1, flammable = 1, not_in_creative_inventory = 1},
	})

	-- recipes
	if def.recipe then
		minetest.register_craft({
			output = def.name,
			recipe = def.recipe
		})
	end
end

function combat_test.register_arrow(name, def)
	if name == nil or name == '' then
		return false
	end

	def.name = 'combat_test:' .. name
	def.description = def.description or name

	combat_test.registered_arrows[def.name] = def

	minetest.register_craftitem("combat_test:" .. name, {
		description = def.description .. '\n' .. minetest.colorize('#00FF00', 'Damage: ' .. def.tool_capabilities.damage_groups.fleshy) .. '\n' .. minetest.colorize('#00BFFF', 'Charge Time: ' .. def.tool_capabilities.full_punch_interval .. 's'),
		inventory_image = def.inventory_image,
		groups = {arrow = 1, flammable = 1}
	})

	-- recipes
	if def.craft then
		minetest.register_craft({
			output = def.name ..' ' .. (def.craft_count or 4),
			recipe = def.craft
		})
	end
end

function combat_test.load(itemstack, user, pointed_thing)
	local time_load = minetest.get_us_time()
	local inv = user:get_inventory()
	local inv_list = inv:get_list('main')
	local bow_name = itemstack:get_name()
	local bow_def = combat_test.registered_bows[bow_name .. '_charged']
	local itemstack_arrows = {}

	if pointed_thing.under then
		local node = minetest.get_node(pointed_thing.under)
		local node_def = minetest.registered_nodes[node.name]

		if node_def and node_def.on_rightclick then
			return node_def.on_rightclick(pointed_thing.under, node, user, itemstack, pointed_thing)
		end
	end

	for k, st in ipairs(inv_list) do
		if not st:is_empty() and combat_test.registered_arrows[st:get_name()] then
			table.insert(itemstack_arrows, st)
		end
	end

	-- take 1st found arrow in the list
	local itemstack_arrow = itemstack_arrows[1]

	if itemstack_arrow and bow_def then
		local _tool_capabilities = combat_test.registered_arrows[itemstack_arrow:get_name()].tool_capabilities

		minetest.after(1,function(v_user, v_bow_name, v_time_load)
			local wielded_item = v_user:get_wielded_item()
			local wielded_item_name = wielded_item:get_name()

			if wielded_item_name == v_bow_name then
				local meta = wielded_item:get_meta()

				meta:set_string('arrow', itemstack_arrow:get_name())
				meta:set_string('time_load', tostring(v_time_load))
				wielded_item:set_name(v_bow_name .. '_charged')
				v_user:set_wielded_item(wielded_item)

				if not x_bows.is_creative(user:get_player_name()) then
					inv:remove_item('main', itemstack_arrow:get_name())
				end
			end
		end, user, bow_name, time_load)

		-- sound plays when charge time reaches full punch interval time
		-- @TODO: find a way to prevent this from playing when not fully charged
		minetest.after(_tool_capabilities.full_punch_interval, function(v_user, v_bow_name)
			local wielded_item = v_user:get_wielded_item()
			local wielded_item_name = wielded_item:get_name()

			if wielded_item_name == v_bow_name .. '_charged' then
				minetest.sound_play('x_bows_bow_loaded', {
					to_player = user:get_player_name(),
					gain = 0.6
				})
			end
		end, user, bow_name)

		minetest.sound_play('x_bows_bow_load', {
			to_player = user:get_player_name(),
			gain = 0.6
		})

		return itemstack
	end
end

function combat_test.shoot(itemstack, user, pointed_thing)
	local time_shoot = minetest.get_us_time();
	local meta = itemstack:get_meta()
	local meta_arrow = meta:get_string('arrow')
	local time_load = tonumber(meta:get_string('time_load'))
	local tflp = (time_shoot - time_load) / 1000000

	if not combat_test.registered_arrows[meta_arrow] then
		return itemstack
	end

	local bow_name_charged = itemstack:get_name()
	local bow_name = combat_test.registered_bows[bow_name_charged].name
	local uses = combat_test.registered_bows[bow_name_charged].uses
	local crit_chance = combat_test.registered_bows[bow_name_charged].crit_chance
	local _tool_capabilities = combat_test.registered_arrows[meta_arrow].tool_capabilities

	local staticdata = {
		arrow = meta_arrow,
		user_name = user:get_player_name(),
		is_critical_hit = false,
		_tool_capabilities = _tool_capabilities,
		_tflp = tflp,
	}

	-- crits, only on full punch interval
	if crit_chance and crit_chance > 1 and tflp >= _tool_capabilities.full_punch_interval then
		if math.random(1, crit_chance) == 1 then
			staticdata.is_critical_hit = true
		end
	end

	local sound_name = 'x_bows_bow_shoot'
	if staticdata.is_critical_hit then
		sound_name = 'x_bows_bow_shoot_crit'
	end

	meta:set_string('arrow', '')
	itemstack:set_name(bow_name)

	local pos = user:get_pos()
	local dir = user:get_look_dir()
	local obj = minetest.add_entity({x = pos.x, y = pos.y + 1.5, z = pos.z}, 'x_bows:arrow_entity', minetest.serialize(staticdata))

	if not obj then
		return itemstack
	end

	local lua_ent = obj:get_luaentity()
	local strength_multiplier = tflp

	if strength_multiplier > _tool_capabilities.full_punch_interval then
		strength_multiplier = 1
	end

	local strength = 30 * strength_multiplier

	obj:set_velocity(vector.multiply(dir, strength))
	obj:set_acceleration({x = dir.x * -3, y = -10, z = dir.z * -3})
	obj:set_yaw(minetest.dir_to_yaw(dir))

	if not x_bows.is_creative(user:get_player_name()) then
		itemstack:add_wear(65535 / uses)
	end

	minetest.sound_play(sound_name, {
		gain = 0.3,
		pos = user:get_pos(),
		max_hear_distance = 10
	})

	return itemstack
end

combat_test.register_bow('crossbow', {
	description = 'Crossbow',
	uses = 385,
	-- `crit_chance` 10% chance, 5 is 20% chance
	-- (1 / crit_chance) * 100 = % chance
	crit_chance = 5,
	on_use = function(itemstack, user, pointed_thing) 
    combat_test.shoot(itemstack, user, pointed_thing)
    -- x_bows.shoot(itemstack, user, pointed_thing)
    -- x_bows.shoot(itemstack, user, pointed_thing)
	end,
	inventory_image = "crossbow.png",
	inventory_image_charged = "crossbow_ready.png",
	recipe = {
		{'', 'farming:string', ''},
		{'default:stick', 'defaut:stick', 'farming:string'},
		{ '', 'farming:string', ''},
	}
})

combat_test.register_arrow('wooden_dart', {
	description = 'Wooden dart',
	inventory_image = 'wooden_dart.png',
	craft = {
		{'default:steel_ingot'},
		{'group:stick'},
		{'farming:string'}
	},
	tool_capabilities = {
		full_punch_interval = 1,
		max_drop_level = 0,
		damage_groups = {fleshy = 3}
	}
})

local bow_charged_timer = 0;

minetest.register_globalstep(function(dtime)
	bow_charged_timer = bow_charged_timer + dtime

	if bow_charged_timer > 0.5 then
		for _, player in ipairs(minetest.get_connected_players()) do
			local name = player:get_player_name()
			local stack = player:get_wielded_item()
			local item = stack:get_name()

			if not item then
				return
			end

			if not x_bows.player_bow_sneak[name] then
				x_bows.player_bow_sneak[name] = {}
			end

			if item == 'combat_test:crossbow_charged' and not x_bows.player_bow_sneak[name].sneak then
				if minetest.get_modpath('playerphysics') then
					playerphysics.add_physics_factor(player, 'speed', 'x_bows:bow_wood_charged', 0.25)
				end

				x_bows.player_bow_sneak[name].sneak = true
				player:set_fov(0.9, true, 0.4)
			elseif item ~= 'combat_test:crossbow_charged' and x_bows.player_bow_sneak[name].sneak then
				if minetest.get_modpath('playerphysics') then
					playerphysics.remove_physics_factor(player, 'speed', 'x_bows:bow_wood_charged')
				end

				x_bows.player_bow_sneak[name].sneak = false
				player:set_fov(1, true, 0.4)
			end
		end

		bow_charged_timer = 0
	end
end)
