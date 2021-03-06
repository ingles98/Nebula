/mob/new_player
	universal_speak = TRUE

	invisibility = 101

	density = 0
	stat = DEAD

	movement_handlers = list()
	anchored = 1	//  don't get pushed around

	virtual_mob = null // Hear no evil, speak no evil

/mob/new_player/new_player_panel(force = FALSE)
	if(!SScharacter_setup.initialized && !force)
		return // Not ready yet.
	var/output = list()
	output += "<div align='center'>"
	if(GAME_STATE < RUNLEVEL_GAME)
		output += "<span class='average'><b>The Game Is Loading!</b></span><br><br>"
	output += "<i>[GLOB.using_map.get_map_info()]</i>"
	output +="<hr>"
	output += "<a href='byond://?src=\ref[src];setupCharacter=1'>Set up character</A> "
	output += "<a href='byond://?src=\ref[src];joinGame=1'>Join game</a><br><br>"

	if(check_rights(R_DEBUG, 0, client))
		output += "<a href='byond://?src=\ref[src];observeGame=1'>Observe</a><br><br>"
	output += "<a href='byond://?src=\ref[src];refreshPanel=1'>Refresh</a><br><br>"
	output += "</div>"

	panel = new(src, "Welcome","Welcome to [GLOB.using_map.full_name]", 560, 280, src)
	panel.set_window_options("can_close=0")
	panel.set_content(JOINTEXT(output))
	panel.open()

/mob/new_player/Stat()
	. = ..()

	if(statpanel("Lobby"))
		stat("Players : [GLOB.player_list.len]")

/mob/new_player/Topic(href, href_list) // This is a full override; does not call parent.
	if(usr != src)
		return TOPIC_NOACTION
	if(!client)
		return TOPIC_NOACTION

	if(href_list["setupCharacter"])
		newCharacterPanel()
		return 0

	if(href_list["joinGame"])
		joinGame()
		return 0

	if(href_list["observeGame"])
		transition_to_game()
		var/mob/observer/ghost/observer = new()
		observer.started_as_observer = 1
		var/turf/spawn_turf
		for(var/obj/machinery/cryopod/C in SSmachines.machinery)
			spawn_turf = locate(C.x, C.y, C.z)
		if(!spawn_turf)
			spawn_turf = locate(100,100,1)
		observer.forceMove(spawn_turf)
		observer.ckey = ckey
		qdel(src)
		return

	if(href_list["refreshPanel"])
		panel.close()
		new_player_panel()

/mob/new_player/proc/newCharacterPanel()
	for(var/mob/M in SSmobs.mob_list)
		if(M.loc && !istype(M, /mob/new_player) && (M.saved_ckey == ckey || M.saved_ckey == "@[ckey]"))
			to_chat(src, SPAN_NOTICE("You already have a character in game!"))
			return
	client.prefs.ShowChoices(src)
	return

/mob/new_player/proc/joinGame()
	if(GAME_STATE < RUNLEVEL_GAME)
		to_chat(src, SPAN_NOTICE("Wait until the round starts to join."))
		return
	if(!config.enter_allowed)
		to_chat(usr, SPAN_NOTICE("There is an administrative lock on entering the game!"))
		return
	if(spawning)
		return
	for(var/mob/M in GLOB.living_mob_list_)   // A mob with a matching saved_ckey is already in the game, put the player back where they were.
		if(M.loc && !istype(M, /mob/new_player) && (M.saved_ckey == ckey || M.saved_ckey == "@[ckey]"))
			transition_to_game()
			to_chat(src, SPAN_NOTICE("A character is already in game."))
			spawning = TRUE
			M.key = key
			qdel(src)
			return

	create_character()	// Creating a new character based off the player's preferences.
	qdel(src)

/mob/new_player/create_character()
	spawning = TRUE
	transition_to_game()
	var/turf/spawn_turf

	var/used_chargen = FALSE
	if(chargen_spawns && length(chargen_spawns))
		spawn_turf = SSchargen.get_spawn_turf()
		used_chargen = TRUE
	else
		for(var/turf/T in GLOB.latejoin_cryo)
			if(locate(/mob) in T)
				continue
			spawn_turf = T

	var/mob/living/carbon/human/new_character
	var/decl/species/chosen_species
	if(client.prefs.species)
		chosen_species = all_species[client.prefs.species]

	if(chosen_species)
		if(!check_species_allowed(chosen_species))
			spawning = FALSE //abort
			return null
		new_character = new(spawn_turf, chosen_species.name)
		if(chosen_species.has_organ[BP_POSIBRAIN] && client && client.prefs.is_shackled)
			var/obj/item/organ/internal/posibrain/B = new_character.internal_organs_by_name[BP_POSIBRAIN]
			if(B)	B.shackle(client.prefs.get_lawset())

	if(!new_character)
		new_character = new(spawn_turf)
		if(used_chargen)
			SSchargen.assign_spawn_pod(new_character, spawn_turf)

	new_character.lastarea = get_area(spawn_turf)
	client.prefs.copy_to(new_character)

	if(mind)
		mind.active = 0 //we wish to transfer the key manually
		mind.original = new_character
		if(client.prefs.memory)
			mind.StoreMemory(client.prefs.memory)
		mind.transfer_to(new_character)					//won't transfer key since the mind is not active

	var/datum/job/job = SSjobs.get_by_path(/datum/job/colonist) // Hacky way to get players equipped with a basic uniform and their accounts set up.
	job.setup_account(new_character)
	job.equip(new_character)

	var/datum/skillset/SS = new_character.skillset 	// Populate the skill_list of the player's skillset so that they can be properly adjusted during gameplay.
	SS.set_skillset_min()

	new_character.dna.ready_dna(new_character)
	new_character.dna.b_type = client.prefs.b_type
	new_character.sync_organ_dna()
	if(client.prefs.disabilities)
		// Set defer to 1 if you add more crap here so it only recalculates struc_enzymes once. - N3X
		new_character.dna.SetSEState(GLOB.GLASSESBLOCK,1,0)
		new_character.disabilities |= NEARSIGHTED

	// Do the initial caching of the player's body icons.
	new_character.force_update_limbs()
	new_character.update_eyes()
	new_character.regenerate_icons()

	new_character.key = key		//Manually transfer the key to log them in

	
/mob/new_player/Move()
	return 0

/mob/new_player/get_species()
	var/decl/species/chosen_species
	if(client.prefs.species)
		chosen_species = all_species[client.prefs.species]

	if(!chosen_species || !check_species_allowed(chosen_species, 0))
		return SPECIES_HUMAN

	return chosen_species.name

/mob/new_player/get_gender()
	if(!client || !client.prefs) ..()
	return client.prefs.gender

/mob/new_player/is_ready()
	return ready && ..()

/mob/new_player/proc/transition_to_game()
	close_spawn_windows()
	sound_to(src, sound(null, repeat = 0, wait = 0, volume = 85, channel = GLOB.lobby_sound_channel)) // stops lobby music

/mob/new_player/close_spawn_windows()
	close_browser(src, "window=latechoices") //closes late choices window
	panel.close()

// Taken and adjusted from jobs.dm to reduce dependencies on subsystems for Persistence. Available gear can be adjusted using loadout_blacklist for the map.
/proc/apply_custom_loadout(var/mob/living/carbon/human/H)

	if(!H || !H.client)
		return

	// Equip custom gear loadout.
	var/list/spawn_in_storage = list()
	var/list/loadout_taken_slots = list()
	if(H.client.prefs.Gear())
		for(var/thing in H.client.prefs.Gear())
			var/datum/gear/G = gear_datums[thing]
			if(G)
				var/permitted = 1

				if(G.whitelisted && (!(H.species.name in G.whitelisted)))
					permitted = 0

				if(!permitted)
					to_chat(H, SPAN_WARNING("Your current species or whitelist status does not permit you to spawn with [thing]!"))
					continue

				if(!G.slot || (G.slot in loadout_taken_slots) || !G.spawn_on_mob(H, H.client.prefs.Gear()[G.display_name]))
					spawn_in_storage.Add(G)
				else
					loadout_taken_slots.Add(G.slot)

	if(spawn_in_storage)
		for(var/datum/gear/G in spawn_in_storage)
			G.spawn_in_storage_or_drop(H, H.client.prefs.Gear()[G.display_name])