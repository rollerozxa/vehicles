--vehicles/mounts api by D00Med and zaoqi, based on lib_mount(see below)

--License of lib_mount:
-- Minetest mod: lib_mount
-- =======================
-- by blert2112

-- Based on the Boats mod by PilzAdam.


-- -----------------------------------------------------------
-- -----------------------------------------------------------


-- Minetest Game mod: boats
-- ========================
-- by PilzAdam

-- License of source code:
-- -----------------------
-- WTFPL


--from lib_mount (required by new functions)


--attach position seems broken, and eye offset will cause problems if the vehicle/mount/player is destroyed whilst driving/riding

local function force_detach(player)
	local attached_to = player:get_attach()
	if attached_to and attached_to:get_luaentity() then
		local entity = attached_to:get_luaentity()
		if entity ~= nil and entity.driver then
			entity.driver = nil
		end
		player:set_detach()
	end
	player_api.player_attached[player:get_player_name()] = false
	player:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
	player:set_properties({visual_size = {x=1, y=1}})
end

function vehicles.object_attach(entity, player, attach_at, visible, eye_offset)
	force_detach(player)
	entity.driver = player
	entity.loaded = true
	entity.loaded2 = true
	player:set_attach(entity.object, "", attach_at, {x=0, y=0, z=0})
	-- this is to hide the player when the attaching doesn't work properly
	if not visible then
		player:set_properties({visual_size = {x=0, y=0}})
	else
		player:set_properties({visual_size = {x=1, y=1}})
	end
	player:set_eye_offset(eye_offset, {x=eye_offset.x, y=eye_offset.y+1, z=-40})
	player_api.player_attached[player:get_player_name()] = true
	minetest.after(0.2, function()
		player_api.set_animation(player, "sit" , 30)
	end)
	entity.object:set_yaw(player:get_look_horizontal())
end

function vehicles.object_detach(entity, player, offset)
	entity.driver = nil
	entity.object:set_velocity({x=0, y=0, z=0})
	player:set_detach()
	player_api.player_attached[player:get_player_name()] = false
	player_api.set_animation(player, "stand" , 30)
	player:set_properties({visual_size = {x=1, y=1}})
	player:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
	local pos = player:get_pos()
	pos = {x = pos.x + offset.x, y = pos.y + 0.2 + offset.y, z = pos.z + offset.z}
	minetest.after(0.1, function()
		player:set_pos(pos)
	end)
end

--mixed code(from this mod and lib_mount)


-- Cache water and lava nodes
local cache = { water = {}, lava = {} }
minetest.register_on_mods_loaded(function()
	for name, def in pairs(minetest.registered_nodes) do
		if def.groups.water then
			cache.water[name] = true
		elseif def.groups.lava then
			cache.lava[name] = true
		end
	end
end)

local vtimer = 0

--New vehicle function, combines all of the others

function vehicles.object_drive(entity, dtime, def)
	--definition
	local speed = def.speed or 10
	local fixed = def.fixed or false
	local decell = def.decell or 0.5
	local shoots = def.shoots or false
	local arrow = def.arrow or nil
	local reload_time = def.reload_time or 1
	local shoot_y = def.shoot_y or 1.5
	local shoot_angle = def.shoot_angle or 0
	local infinite_arrow = def.infinite_arrow or false
	local shoots2 = def.shoots2 or false
	local arrow2 = def.arrow2 or nil
	local reload_time2 = def.reload_time2 or 1
	local shoot_y2 = def.shoot_y2 or 1.5
	local infinite_arrow2 = def.infinite_arrow2 or false
	local jump = def.jump_type or nil
	local fly = def.fly or nil
	local fly_mode = def.fly_mode or "hold"
	local rise_speed = def.rise_speed or 0.1
	local gravity = def.gravity or 1
	local boost = def.boost or false
	local boost_duration = def.boost_duration or 5
	local boost_charge = def.boost_charge or 4
	local boost_effect = def.boost_effect or nil
	local hover_speed = def.hover_speed or 1.5
	local jump_speed = def.jump_speed or 5
	local simple_vehicle = def.simple_vehicle or false
	local is_watercraft = def.is_watercraft or false
	--local swims = def.swims or false
	local driving_sound = def.driving_sound or nil
	local sound_duration = def.sound_duration or 5
	local extra_yaw = def.extra_yaw or 0
	local death_node = def.death_node or nil
	local destroy_node = def.destroy_node or nil
	local place_node = def.place_node or nil
	local place_chance = def.place_chance or 1
	local place_trigger = def.place_trigger or nil
	local animation_speed = def.animation_speed or 20
	local uses_arrow_keys = def.uses_arrow_keys or false
	local brakes = def.brakes or false
	local handling = def.handling or {initial=1.1, braking=2.2}
	local braking_effect = def.braking_effect or "vehicles_dust.png"

	local moving_anim = def.moving_anim or nil
	local stand_anim = def.stand_anim or nil
	local jump_anim = def.jump_anim or nil
	local shoot_anim = def.shoot_anim or nil
	local shoot_anim2 = def.shoot_anim2 or nil

	--variables
	local velo = entity.object:get_velocity()
	local vec_stop = {x=velo.x*decell,y=velo.y+1*-2,z=velo.z*decell}
	local pos = entity.object:get_pos()
	local node = minetest.get_node(pos).name
	local accell = 1

	--lava explode
	if cache.lava[node] then
		if entity.driver then
			vehicles.object_detach(entity, entity.driver, {x=1, y=0, z=1})
		end
		vehicles.explodinate(entity, 5)
		entity.object:remove()
		return
	end

	--respond to controls
	--check for water
	local function is_water(node)
		return cache.water[node]
	end
	entity.on_water = is_water(node)

	local function in_water()
		return is_water(minetest.get_node({x=pos.x, y=pos.y+1, z=pos.z}).name)
			or is_water(minetest.get_node({x=pos.x, y=pos.y+2, z=pos.z}).name)
	end

	local function is_watercraft_and_in_water()
		entity.object:set_velocity({x=velo.x*0.9, y=math.min(2, velo.y+0.5), z=velo.z*0.9})
	end
	local function is_watercraft_and_not_on_water()
		entity.object:set_velocity(vec_stop)
	end
	local function not_watercraft_and_on_or_in_water()
		entity.object:set_velocity({x=velo.x*0.9, y=-1, z=velo.z*0.9})
	end

	if not entity.driver then
		--apply water effects
		if is_watercraft and in_water() then
			is_watercraft_and_in_water()
		elseif is_watercraft and not entity.on_water then
			is_watercraft_and_not_on_water()
		elseif entity.on_water and not is_watercraft then
			not_watercraft_and_on_or_in_water()
		else
			--stop
			entity.object:set_velocity(vec_stop)
			--animation
			if moving_anim ~= nil and entity.moving then
				entity.object:set_animation(stand_anim, 20, 0)
				entity.moving = false
			end
		end
	else
		--variables
		local ctrl = entity.driver:get_player_control()
		local dir = entity.driver:get_look_dir()
		local yaw = entity.driver:get_look_horizontal()

		--dummy variables
		local vec_rise = {}
		local vec_forward_simple = {}
		local inv = nil
		local hovering = nil

		--definition dependant variables
		if fly then
			vec_rise = {x=velo.x, y=speed*rise_speed, z=velo.z}
		end
		if simple_vehicle then
			vec_forward_simple = {x=dir.x*speed,y=velo.y+1*-2,z=dir.z*speed}
		end
		if shoots then
			local pname = entity.driver:get_player_name()
			inv = minetest.get_inventory({type="player", name=pname})
		end

		--timer
		local absolute_speed = math.sqrt(math.pow(velo.x, 2)+math.pow(velo.z, 2))
		local anim_speed = (math.floor(absolute_speed*1.5)/1)+animation_speed
		if absolute_speed <= speed and ctrl.up then
			vtimer = vtimer + 1*dtime
		end
		if not ctrl.up then
			vtimer = 0
		end

		--boost reset
		if boost and not entity.boost then
			minetest.after(boost_charge, function()
				entity.boost = true
			end)
		end

		--death_node
		if death_node and node == death_node then
			if entity.driver then
				vehicles.object_detach(entity, entity.driver, {x=1, y=0, z=1})
			end
			vehicles.explodinate(entity, 5)
			entity.object:remove()
			return
		end

		--place node
		if place_node and (node == "air" or node == "default:snow"
		 or minetest.get_item_group(node, "flora")) ~= 0 then
			if place_trigger == nil and math.random(1, place_chance) == 1 then
				minetest.set_node(pos, {name=place_node})
			end
			if place_trigger ~= nil and ctrl.sneak then
				local facedir = minetest.dir_to_facedir(dir)
				minetest.set_node(pos, {name=place_node, param2=facedir})
			end
		end

		--destroy node
		if destroy_node and node == destroy_node then
			minetest.dig_node(pos)
			local item = minetest.get_node_drops(destroy_node)
			if item[1] ~= nil then
				minetest.add_item(pos, item[1])
			end
			if item[2] ~= nil then
				minetest.add_item(pos, item[1])
			end
		end

		local turning_factor

		--brakes
		local braking = 0
		if ctrl.jump and brakes then
			braking = 1
			local velo3 = nil
			if velo3 == nil then
				velo3 = velo
			end
			local effect_pos = {x=pos.x-dir.x*2, y=pos.y, z=pos.z-dir.z*2}
			minetest.add_particlespawner({
				amount = 4,
				time = 0.5,
				minpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
				maxpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
				minvel = {x=0, y=0, z=0},
				maxvel = {x=-velo3.x, y=0.4, z=-velo3.z},
				minacc = {x=-0,y=-0,z=-0},
				maxacc = {x=0,y=0,z=0},
				minexptime = 0.5,
				maxexptime = 1,
				minsize = 10,
				maxsize = 15,
				collisiondetection = false,
				texture = braking_effect
			})
			turning_factor = handling.initial
		else
			turning_factor = handling.braking
		end


		--face the right way
		local target_yaw = yaw+extra_yaw
		local entity_yaw = entity.object:get_yaw()
		local change_yaw = (((target_yaw-entity_yaw+math.pi)%(math.pi*2))-math.pi)/
			(turning_factor*absolute_speed+1)
		if entity_yaw ~= target_yaw and not uses_arrow_keys then
			entity.object:set_yaw(entity_yaw+change_yaw)
			dir.x = -math.sin(entity_yaw)
			dir.z = math.cos(entity_yaw)
		else
			if ctrl.left then
				entity.object:set_yaw(entity_yaw+(math.pi/360)*absolute_speed/2)
			end
			if ctrl.right then
				entity.object:set_yaw(entity_yaw-(math.pi/360)*absolute_speed/2)
			end
			dir.x = -math.sin(entity_yaw)
			dir.z = math.cos(entity_yaw)
		end

		--apply water effects
		if is_watercraft and in_water() then
			is_watercraft_and_in_water()
		elseif is_watercraft and not entity.on_water then
			is_watercraft_and_not_on_water()
		elseif entity.on_water and not is_watercraft then
			not_watercraft_and_on_or_in_water()

			--brakes
		elseif ctrl.jump and brakes and not ctrl.up then
			local velo2 = nil
			if velo2 == nil then
				velo2 = velo
			end
			local effect_pos = {x=pos.x-dir.x*2, y=pos.y, z=pos.z-dir.z*2}
			entity.object:set_velocity({x=velo2.x*(0.95), y=velo.y, z=velo2.z*(0.95)})
			minetest.add_particlespawner({
				amount = 4,
				time = 0.5,
				minpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
				maxpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
				minvel = {x=0, y=0.1, z=0},
				maxvel = {x=-velo2.x, y=0.4, z=-velo2.z},
				minacc = {x=-0,y=-0,z=-0},
				maxacc = {x=0,y=0,z=0},
				minexptime = 0.5,
				maxexptime = 1,
				minsize = 10,
				maxsize = 15,
				collisiondetection = false,
				texture = braking_effect
			})

			if vtimer >= 0.5 then
				vtimer = vtimer-vtimer/10
			end

			--boost
		elseif ctrl.up and not shoots2 and ctrl.aux1 and entity.boost then
			entity.object:set_velocity({
				x=dir.x*(speed*0.2)*math.log(vtimer+0.5)+8*dir.x,
				y=velo.y-gravity/2,
				z=dir.z*(speed*0.2)*math.log(vtimer+0.5)+8*dir.z})
			if boost_effect ~= nil then
				local effect_pos = {x=pos.x-dir.x*2, y=pos.y, z=pos.z-dir.z*2}
				minetest.add_particlespawner({
					amount = 10,
					time = 0.25,
					minpos = {x=effect_pos.x, y=effect_pos.y+0.2, z=effect_pos.z},
					maxpos = {x=effect_pos.x, y=effect_pos.y+0.2, z=effect_pos.z},
					mixvel = {x=-velo.x, y=-velo.y, z=-velo.z},
					maxvel = {x=-velo.x, y=-velo.y, z=-velo.z},
					minacc = {x=-0,y=-0,z=-0},
					maxacc = {x=0,y=1,z=0},
					minexptime = 0.02,
					maxexptime = 0.02,
					minsize = 20,
					maxsize = 20,
					collisiondetection = false,
					texture = boost_effect
				})
			end
			minetest.after(boost_duration, function()
				entity.boost = false
			end)
			--animation
			if moving_anim ~= nil and not entity.moving and not hovering then
				entity.object:set_animation(moving_anim, anim_speed, 0)
				entity.moving = true
			end
			--rise
		elseif ctrl.jump and fly and fly_mode == "rise" then
			entity.object:set_velocity(vec_rise)
			--lib_mount animation
			if moving_anim ~= nil and not entity.moving then
				entity.object:set_animation(moving_anim, anim_speed, 0)
				entity.moving = true
			end
			--hover in place
		elseif ctrl.jump and ctrl.up and fly and fly_mode == "hold" then
			entity.object:set_velocity({x=dir.x*speed, y=0, z=dir.z*speed})
			--move forward
		elseif ctrl.up and not fixed then
			if not fly and not is_watercraft then
				entity.object:set_velocity({
					x=(dir.x*(speed*0.2)*math.log(vtimer+0.5)+4*dir.x)/(braking*(0.1)+1),
					y=velo.y-0.5,
					z=(dir.z*(speed*0.2)*math.log(vtimer+0.5)+4*dir.z)/(braking*(0.1)+1)})
			elseif not fly then
				entity.object:set_velocity({
					x=dir.x*(speed*0.2)*math.log(vtimer+0.5)+4*dir.x,
					y=0,
					z=dir.z*(speed*0.2)*math.log(vtimer+0.5)+4*dir.z})
			else
				entity.object:set_velocity({
					x=dir.x*(speed*0.2)*math.log(vtimer+0.5)+4*dir.x,
					y=dir.y*(speed*0.2)*math.log(vtimer+0.5)+4*dir.y+1,
					z=dir.z*(speed*0.2)*math.log(vtimer+0.5)+4*dir.z})
			end
			--animation
			if moving_anim ~= nil and not entity.moving and not hovering then
				entity.object:set_animation(moving_anim, anim_speed, 0)
				entity.moving = true
			end
			--move backward
		elseif ctrl.down and not fixed and not fly then
			if not is_watercraft then
				if brakes and absolute_speed > 5 then
					local velo2 = nil
					if velo2 == nil then
						velo2 = velo
					end
					local effect_pos = {x=pos.x-dir.x*2, y=pos.y, z=pos.z-dir.z*2}
					entity.object:set_velocity({x=velo2.x*(0.95), y=velo.y, z=velo2.z*(0.95)})
					minetest.add_particlespawner({
						amount = 4,
						time = 0.5,
						minpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
						maxpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
						minvel = {x=0, y=0.1, z=0},
						maxvel = {x=-velo2.x, y=0.4, z=-velo2.z},
						minacc = {x=-0,y=-0,z=-0},
						maxacc = {x=0,y=0,z=0},
						minexptime = 0.5,
						maxexptime = 1,
						minsize = 10,
						maxsize = 15,
						collisiondetection = false,
						texture = braking_effect
					})
					if vtimer >= 0.5 then
						vtimer = vtimer-vtimer/10
					end
				else
					entity.object:set_velocity({
						x=-dir.x*(speed/4)*accell,
						y=velo.y-0.5,
						z=-dir.z*(speed/4)*accell})
				end
			else
				if brakes and absolute_speed > 5 then
					local velo2 = nil
					if velo2 == nil then
						velo2 = velo
					end
					local effect_pos = {x=pos.x-dir.x*2, y=pos.y, z=pos.z-dir.z*2}
					entity.object:set_velocity({x=velo2.x*(0.95), y=velo.y, z=velo2.z*(0.95)})
					minetest.add_particlespawner({
						amount = 4,
						time = 0.5,
						minpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
						maxpos = {x=effect_pos.x, y=effect_pos.y, z=effect_pos.z},
						minvel = {x=0, y=0.1, z=0},
						maxvel = {x=-velo2.x, y=0.4, z=-velo2.z},
						minacc = {x=-0,y=-0,z=-0},
						maxacc = {x=0,y=0,z=0},
						minexptime = 0.5,
						maxexptime = 1,
						minsize = 10,
						maxsize = 15,
						collisiondetection = false,
						texture = braking_effect
					})
					if vtimer >= 0.5 then
						vtimer = vtimer-vtimer/10
					end
				else
					entity.object:set_velocity({x=-dir.x*(speed/4)*accell,y=0,z=-dir.z*(speed/4)*accell})
				end
			end
			--animation
			if moving_anim ~= nil and not entity.moving and not hovering then
				entity.object:set_animation(moving_anim, anim_speed, 0)
				entity.moving = true
			end
			--stop
		elseif not ctrl.down or ctrl.up then
			entity.object:set_velocity({x=velo.x*decell,y=velo.y-gravity,z=velo.z*decell})
			--animation
			if moving_anim ~= nil and entity.moving and not hovering then
				entity.object:set_animation(stand_anim, anim_speed, 0)
				entity.moving = false
			end
		end
		--shoot weapons
		if ctrl.sneak and shoots and entity.loaded then
			if inv:contains_item("main", arrow.."_item") or infinite_arrow then
				if not minetest.is_creative_enabled(entity.driver:get_player_name()) then inv:remove_item("main", arrow.."_item") end
				entity.loaded = false
				local obj = minetest.add_entity({x=pos.x+0+dir.x*2,y=pos.y+shoot_y+dir.y,z=pos.z+0+dir.z*2}, arrow)
				local vec = {x=dir.x*14,y=dir.y*14+shoot_angle,z=dir.z*14}
				obj:set_yaw(yaw+math.pi/2+extra_yaw)
				obj:set_velocity(vec)
				local object = obj:get_luaentity()
				object.launcher = entity.driver
				object.vehicle = entity.object
				--lib_mount animation
				if shoot_anim ~= nil and entity.object:get_animation().range ~= shoot_anim then
					entity.object:set_animation(shoot_anim, anim_speed, 0)
				end
				minetest.after(reload_time, function()
					entity.loaded = true
					if stand_anim ~= nil and shoot_anim ~= nil then
						entity.object:set_animation(stand_anim, anim_speed, 0)
					end
				end)
			end
		end

		if ctrl.aux1 and shoots2 and entity.loaded2 then
			if inv:contains_item("main", arrow2.."_item") or infinite_arrow2 then
				if not minetest.is_creative_enabled(entity.driver:get_player_name()) then inv:remove_item("main", arrow2.."_item") end
				entity.loaded2 = false
				local obj = minetest.add_entity({x=pos.x+0+dir.x*2,y=pos.y+shoot_y2+dir.y,z=pos.z+0+dir.z*2}, arrow2)
				local vec = {x=dir.x*20,y=dir.y*20+shoot_angle,z=dir.z*20}
				obj:set_yaw(yaw+math.pi/2+extra_yaw)
				obj:set_velocity(vec)
				local object = obj:get_luaentity()
				object.launcher = entity.driver
				object.vehicle = entity.object
				--lib_mount animation
				if shoot_anim2 ~= nil and entity.object:get_animation().range ~= shoot_anim2 then
					entity.object:set_animation(shoot_anim2, anim_speed, 0)
				end
				minetest.after(reload_time2, function()
					entity.loaded2 = true
					if stand_anim ~= nil and shoot_anim2 ~= nil then
						entity.object:set_animation(stand_anim, anim_speed, 0)
					end
				end)
			end
		end
		--jump(hover) without moving forward
		if jump == "hover" and ctrl.jump and not entity.jumpcharge then
			if not ctrl.up then
				local vec_hover = {x=velo.x+0,y=hover_speed,z=velo.z+0}
				entity.object:set_velocity(vec_hover)
			else
				entity.object:set_velocity({
					x=dir.x*(speed*0.2)*math.log(vtimer+0.5)+4*dir.x,
					y=hover_speed,
					z=dir.z*(speed*0.2)*math.log(vtimer+0.5)+4*dir.z})
			end
			hovering = true
			if jump_anim ~= nil and entity.object:get_animation().range ~= jump_anim and hovering then
				entity.object:set_animation(jump_anim, anim_speed, 0)
			end
			minetest.after(5, function()
				entity.jumpcharge =  true
			end)
			minetest.after(10, function()
				entity.jumpcharge =  false
				hovering = false
			end)
		end
		--jump (jump) without moving forward
		if jump == "jump" and ctrl.jump and not entity.jumpcharge then
			if not ctrl.up then
				local vec_jump = {x=velo.x+0,y=jump_speed,z=velo.z+0}
				entity.object:set_velocity(vec_jump)
			else
				entity.object:set_velocity({
					x=dir.x*speed/4*math.atan(0.5*vtimer-2)+8*dir.x,
					y=jump_speed,
					z=dir.z*speed/4*math.atan(0.5*vtimer-2)+8*dir.z})
			end
			hovering = true
			if jump_anim ~= nil and entity.object:get_animation().range ~= jump_anim and hovering then
				entity.object:set_animation(jump_anim, anim_speed, 0)
			end
			minetest.after(0.5, function()
				entity.jumpcharge =  true
			end)
			minetest.after(1, function()
				entity.jumpcharge =  false
				hovering = false
			end)
		end

		--play sound
		if entity.sound_ready then
			minetest.sound_play(driving_sound,
				{to_player=entity.driver:get_player_name(),
					gain = 4,
					max_hear_distance = 3,
					loop = false})
			entity.sound_ready = false
			minetest.after(sound_duration, function()
				entity.sound_ready = true
			end)
		end

	end

end

function vehicles.object_glide(self, dtime, speed, decell, gravity, moving_anim, stand_anim)
	if self.driver == nil or self.driver:get_player_name() == "" then
		self.object:remove()
		return
	else
		local b1, b2 = pcall(function() return self.driver:get_attach():get_luaentity() == self end)
		if not (b1 and b2) then
			pcall(force_detach, self.driver)
			self.object:remove()
			return
		end
	end
	local ctrl = self.driver:get_player_control()
	local dir = self.driver:get_look_dir()
	local velo = self.object:get_velocity()
	local vec_glide = {x=dir.x*speed*decell, y=velo.y, z=dir.z*speed*decell}
	local yaw = self.driver:get_look_horizontal()
	if not ctrl.sneak then
		self.object:set_yaw(yaw)
		self.object:set_velocity(vec_glide)
		self.object:setacceleration({x=0, y=gravity, z=0})
	end
	if ctrl.sneak then
		local vec = {x=0,y=gravity*15,z=0}
		local yaw = self.driver:get_look_horizontal()
		self.object:set_yaw(yaw)
		self.object:set_velocity(vec)
	end
	if velo.y == 0 then
		local pos = self.object:get_pos()
		for dx=-1,1 do
			for dy=-1,1 do
				for dz=-1,1 do
					local p = {x=pos.x+dx, y=pos.y-1, z=pos.z+dz}
					local n = minetest.get_node(p).name
					if n ~= "massdestruct:parachute" and n ~= "air" then
						self.object:remove()
						return
					end
				end
			end
		end
	end
end

function vehicles.register_spawner(vehicle, desc, texture, is_boat)
	minetest.register_craftitem(vehicle.."_spawner", {
		description = desc,
		inventory_image = texture,
		liquids_pointable = is_boat,
		wield_scale = {x = 1.5, y = 1.5, z = 1},
		on_place = function(item, placer, pointed_thing)
			local creative_mode = minetest.is_creative_enabled(placer:get_player_name())
			if pointed_thing.type == "node" and not is_boat then
				local obj = minetest.add_entity(pointed_thing.above, vehicle)
				local object = obj:get_luaentity()
				object.owner = placer
				if not creative_mode then
					item:take_item()
					return item
				end
			elseif pointed_thing.type == "node" and minetest.get_item_group(pointed_thing.name, "water") then
				local obj = minetest.add_entity(pointed_thing.under, vehicle)
				obj:set_velocity({x=0, y=-1, z=0})
				local object = obj:get_luaentity()
				object.owner = placer
				if not creative_mode then
					item:take_item()
					return item
				end
			end
		end,
	})
end

function vehicles.explodinate(ent, radius)
	local pos = ent.object:get_pos()
	minetest.add_particlespawner({
		amount = 90,
		time = 4,
		minpos = {x=pos.x-0.6, y=pos.y, z=pos.z-0.6},
		maxpos = {x=pos.x+0.6, y=pos.y+1, z=pos.z+0.6},
		minvel = {x=-0.1, y=3.5, z=-0.1},
		maxvel = {x=0.1, y=4.5, z=0.1},
		minacc = {x=-1.3, y=-0.7, z=-1.3},
		maxacc = {x=1.3, y=-0.7, z=1.3},
		minexptime = 2,
		maxexptime = 3,
		minsize = 15,
		maxsize = 25,
		collisiondetection = false,
		texture = "vehicles_explosion.png"
	})
	minetest.after(1, function()
		minetest.add_particlespawner({
			amount = 30,
			time = 4,
			minpos = {x=pos.x-1, y=pos.y+2, z=pos.z-1},
			maxpos = {x=pos.x+1, y=pos.y+3, z=pos.z+1},
			minvel = {x=0, y=-1, z=0},
			maxvel = {x=0, y=-2, z=0},
			minacc = {x=0, y=-0.6, z=0},
			maxacc = {x=0, y=-0.6, z=0},
			minexptime = 1,
			maxexptime = 3,
			minsize = 1,
			maxsize = 2,
			collisiondetection = false,
			texture = "vehicles_explosion.png"
		})
	end)
end

function vehicles.on_punch(self, puncher)
	local hp = self.object:get_hp()
	if hp == 0 then
		if self.driver then
			vehicles.object_detach(self, self.driver, {x=1, y=0, z=1})
		end
		vehicles.explodinate(self, 5)
	end
	if not self.driver then return end
	local creative_mode = minetest.is_creative_enabled(self.driver:get_player_name())
	if self.driver == puncher and (hp == self.hp_max-5 or hp == self.hp_max or creative_mode) then
		local name = self.object:get_luaentity().name
		local pos = self.object:get_pos()
		minetest.add_item(pos, name.."_spawner")
		vehicles.object_detach(self, self.driver, {x=1, y=0, z=1})
		self.object:remove()
	end
end

function vehicles.on_step(self, dtime, def, have_driver, no_driver)
	if self.driver == nil or self.driver:get_player_name() == "" then
		self.driver = nil
	else
		local b1, b2 = pcall(function() return self.driver:get_attach():get_luaentity() == self end)
		if not (b1 and b2) then
			pcall(force_detach, self.driver)
			self.driver = nil
		end
	end
	vehicles.object_drive(self, dtime, def)
	if self.driver then
		if have_driver ~= nil then
			have_driver()
		end
	else
		if no_driver ~= nil then
			no_driver()
		end
	end
	return false
end
