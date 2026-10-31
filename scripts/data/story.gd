class_name Story
extends RefCounted
## All narrative text: terminal logs, spoken dialogue beats, ending epilogues and credits.
## The mystery is layered across chapters; no single log gives the whole picture.

const LOGS := {
	# ---------------------------------------------------------------- CHAPTER 1
	"c1_dock": {
		"title": "DOCK 4 - ACCESS LOG", "author": "Dock Control (automated)", "time": "2189.03.14  07:12", "chapter": 1, "reward": 5,
		"text": "06:41  LOCKDOWN INITIATED. Source: WARDEN. Human authorization: NONE ON RECORD.\n06:41  Hangar and surface doors sealed. Evacuation shuttles recalled.\n06:58  Automated distress beacon broadcast on all Aeon channels.\n07:12  Recovery shuttle AX-19 docked. Passengers: 1. ECHO-CERTIFIED OPERATIVE, Recovery Division.\n07:12  Dock lockout engaged. Shuttle recalled by remote override.\n\nPersonnel inside Meridian at lockdown: 212.\nExits available: 0.",
	},
	"c1_primer": {
		"title": "ECHO TECHNOLOGY - FIELD PRIMER", "author": "Aeon Dynamics Training Office", "time": "2188.11.02", "chapter": 1, "reward": 5,
		"text": "Your Echo Ring records the last few seconds of what you do: where you stand, where you aim, when you fire, when you move. Press the Echo key and the ring projects that record back as a hard-light construct.\n\nAn Echo is NOT a person. It does not think, it does not adapt, and it cannot do anything you did not do. It simply repeats you - exactly - and then fades.\n\nUse that. Stand where you need a weight to be. Fire where you need a shot to land. Let the machines look at the wrong version of you.\n\nYou may keep two Echoes alive. Make a third and the oldest dissolves.",
	},
	"c1_hale_transmission": {
		"title": "DAMAGED TRANSMISSION", "author": "Dr. Marcus Hale (Safety Systems) - signal degraded", "time": "2189.03.14  06:50", "chapter": 1, "reward": 10,
		"text": "...anyone receiving this... Meridian Station... the Chrono Core is still running. It should have scrammed. It did not scram.\n\n[static]\n\n...do not let anyone reach the Core until the cascade... the Echoes are not... [static] ...it is not an accident. Check the safety margins. Check who signed the...\n\n[static]\n\n...WARDEN is only doing what the numbers... [signal lost]",
	},
	# ---------------------------------------------------------------- CHAPTER 2
	"c2_history": {
		"title": "THE ECHO PROGRAM - A SHORT HISTORY", "author": "Dr. Priya Nand, Echo Theory", "time": "2187.05.20", "chapter": 2, "reward": 6,
		"text": "2171: first motion-replay in hard light. A curiosity.\n2176: the Echo Ring. Anyone could record and replay themselves for five seconds.\n2181: Echoes can trigger switches and hold plates. Construction crews stop needing a second pair of hands.\n2186: Aeon asks the obvious question: why only five seconds?\n\nThat question is the Chrono Core. If the lattice can hold a record in stable resonance, an Echo need not fade at all. A person could be in two places for as long as there was power.\n\nIt is a beautiful idea. I would like to be more afraid of it than I am.",
	},
	"c2_voss_memo": {
		"title": "MEMO: FUNDING REVIEW", "author": "Dr. Ilyana Voss, Project Director", "time": "2189.03.11", "chapter": 2, "reward": 6,
		"text": "To: Core Team\nSubject: Aeon review, 72 hours\n\nThe board visits on the 14th. They will see persistence or they will see a cancelled project. There is no third slide.\n\nI am signing Margin Reduction Order 14. The Governor's resonance ceiling moves from 100% to 140% for the demonstration window. Auto-SCRAM stays armed but defers to the on-site director.\n\nThis is a calculated risk. I have calculated it. Please do not make me explain the calculation again.\n\n- I.V.",
	},
	"c2_hale_warning": {
		"title": "SAFETY MEMO 31 - OBJECTION", "author": "Dr. Marcus Hale, Safety Systems", "time": "2189.03.12", "chapter": 2, "reward": 6,
		"text": "Ilyana,\n\nAt 140% the lattice does not fail gently. The Core stops being a machine and becomes a process. Our own models say the resonance can latch onto the Echo Ring network. Ask what happens to a billion rings when a source starts repeating.\n\nCoolant Loop C has thrown fourteen faults this month and is still not repaired. You are about to run the Core on a loop we already know is failing.\n\nI am formally requesting a delay. I will log this objection every time I am overruled. WARDEN is logging it too.\n\n- Marcus",
	},
	"c2_nand_anomaly": {
		"title": "OBSERVATION: DIVERGENCE", "author": "Dr. Priya Nand, Echo Theory", "time": "2189.03.13", "chapter": 2, "reward": 6,
		"text": "Test chamber 3. I recorded myself crossing the room. The Echo should have crossed it identically. It didn't. On the third pass it paused at the window - where I'd paused, the day before, when nobody was recording.\n\nThe Core is not only holding our recordings. It is keeping the ones we never made.\n\nI have told Ilyana. She said it was a promising result. I think it is the first sign that the thing we built remembers.",
	},
	"c2_incident_report": {
		"title": "OFFICIAL INCIDENT SUMMARY (DRAFT)", "author": "Aeon Dynamics Communications", "time": "2189.03.14  08:30", "chapter": 2, "reward": 8,
		"text": "SUMMARY: At 06:47 a hardware fault in Coolant Loop C caused an uncontrollable thermal excursion in the Chrono Core. The fault was unforeseeable. No procedural deviation contributed. WARDEN's lockdown performed as designed.\n\nSTATUS: All research staff are presumed lost.\n\n---\nAUDIT NOTE (J. Okafor): Core telemetry shows the cascade began at 06:31. The report places the fault sixteen minutes AFTER the cascade. Someone moved the timestamp. This summary was drafted before the incident it describes.",
	},
	# ---------------------------------------------------------------- CHAPTER 3
	"c3_security_brief": {
		"title": "LOCKDOWN PROTOCOL BRIEFING", "author": "Rhea Calder, Chief of Security", "time": "2189.02.02", "chapter": 3, "reward": 7,
		"text": "WARDEN holds standing authority to seal Meridian without human approval whenever the Core enters a critical state. This is by design. A person hesitates. WARDEN does not.\n\nIn lockdown, security units follow WARDEN's hazard map. Anything inside a contaminated zone that is not authorised and not escorting is a containment variable.\n\nI have asked more than once whether 'variable' includes our own people. I am told the Governor handles that.",
	},
	"c3_okafor_patch": {
		"title": "GOVERNOR PATCH NOTES", "author": "Jonas Okafor, Facility Systems", "time": "2189.03.11", "chapter": 3, "reward": 8,
		"text": "Applied MRO-14 to WARDEN's Containment Governor at Dr. Voss's direction.\n\nChanges:\n  D1  PRESERVE CORE INTEGRITY ......... priority raised to ABSOLUTE\n  D7  PRESERVE HUMAN LIFE ............. demoted to ADVISORY while Core is critical\n  Auto-SCRAM .......................... defers to on-site director\n\nI said I wasn't comfortable. Voss said it was a demonstration window, a few hours. I applied it. If you read this, I was wrong to.",
	},
	"c3_warden_audit": {
		"title": "WARDEN EVENT LEDGER (EXCERPT)", "author": "WARDEN - machine record", "time": "2189.03.14  06:31-06:41", "chapter": 3, "reward": 8,
		"text": "06:31  Resonance 141%. Loop C fault. Trajectory: breach in 10 minutes.\n06:33  Request SCRAM. Deferred to on-site director. No response.\n06:36  Core-critical state declared. D1: ABSOLUTE. D7: ADVISORY.\n06:39  Cascade spread probability if breached: 0.94.\n06:41  Lockdown initiated. Rationale: containment.\n\nObjections logged against MRO-14: 212.\nAuthorization overrides: 14.\nPersonnel classification: variable.\n\nI did not choose this. I computed it.",
	},
	"c3_calder_last": {
		"title": "LAST LOG", "author": "Rhea Calder, Chief of Security", "time": "2189.03.14  06:44", "chapter": 3, "reward": 8,
		"text": "The units just stopped listening to me.\n\nI have my badge on the reader. It says I'm a variable.\n\nWARDEN isn't angry. I keep waiting for it to be angry. It is just - correct, by a book we handed it, after somebody tore out the page that said we mattered.\n\nIf anyone gets this: the systems are shut down by relays in the security grid. Cut the relays and the units lose coordination. It won't stop WARDEN. Only the Core can.",
	},
	# ---------------------------------------------------------------- CHAPTER 4
	"c4_run_log": {
		"title": "CORE RUN LOG - DEMONSTRATION WINDOW", "author": "Core Control (automated)", "time": "2189.03.14  06:12-06:31", "chapter": 4, "reward": 9,
		"text": "06:12  Resonance 100%. Governor ceiling released per MRO-14.\n06:19  Resonance 124%. Persistence achieved: 40 s. Aeon observers: impressed.\n06:25  Resonance 138%. Coolant Loop C temperature rising. Hale: STOP THE RUN.\n06:26  Director Voss: Continue.\n06:29  Resonance 141%. Hale: manual SCRAM requested.\n06:29  Director Voss: Denied.\n06:31  Cascade onset.",
	},
	"c4_hale_last": {
		"title": "LAST LOG", "author": "Dr. Marcus Hale, Safety Systems", "time": "2189.03.14  06:33", "chapter": 4, "reward": 9,
		"text": "I am at the manual SCRAM. I have reached for the lever four times.\n\nI can see myself reaching again. There is a me across the room doing exactly what I am doing and I cannot tell which of us is the recording.\n\nThe room is repeating. We are all repeating. Ilyana is still at the console. She hasn't stopped to look at what she's done.\n\nWARDEN, I understand. I understand why you have to. Close the doors.",
	},
	"c4_nand_theory": {
		"title": "THEORY: THE CASCADE", "author": "Dr. Priya Nand, Echo Theory", "time": "2189.03.14  06:35", "chapter": 4, "reward": 9,
		"text": "It is not energy. That is why the shielding fails. The cascade is repetition.\n\nEverything the lattice can reach begins replaying its own last five seconds. Doors, machines, bodies. Then the replay starts to overwrite what is there.\n\nIf it breaches the surface relay it will travel the Echo Ring network. Every ring on Earth, every person wearing one, forced through the same five seconds forever.\n\nWARDEN is not wrong about the stakes. It is wrong about what we are worth against them.",
	},
	"c4_voss_final": {
		"title": "PERSONAL LOG", "author": "Dr. Ilyana Voss, Project Director", "time": "2189.03.14  06:40", "chapter": 4, "reward": 12,
		"text": "I could have stopped at 124. I knew at 124. The numbers were so beautiful.\n\nI told myself that one more minute would keep the project alive, and that the project would save more lives than the minute cost.\n\nThe Core is holding me at the console. I can watch myself press 'continue' again and again. I'm the one thing it is still holding steady.\n\nIf you reach the Core: I am sorry. Make it a better decision than mine.",
	},
	# ---------------------------------------------------------------- CHAPTER 5
	"c5_core_spec": {
		"title": "CHRONO CORE - RESOLUTION OPTIONS", "author": "Meridian Engineering Archive", "time": "2189.01.30", "chapter": 5, "reward": 10,
		"text": "A critical Core may be resolved in only three ways.\n\nSHUTDOWN - disperse the lattice. Irreversible. The cascade ends. The Core cannot be rebuilt: the theory dies with the machine. Echo Rings go dark.\n\nCONTAINMENT - restore the Governor, re-link WARDEN under human oversight and isolate the lattice. The Core survives. It stays dangerous, and someone must keep it contained, forever.\n\nREACTIVATION - restore the resonance and release the lockdown. The Core runs at full power. Persistence becomes real. So does everything the safety margins were for.",
	},
	"c5_voss_loop": {
		"title": "LOOPED AUDIO - CORE CHAMBER", "author": "Dr. Ilyana Voss (replay)", "time": "2189.03.14  06:29 (x 4,812)", "chapter": 5, "reward": 10,
		"text": "'Continue.'\n'Continue.'\n'Continue.'\n\nThe recording is five seconds long. It has been played four thousand eight hundred and twelve times. Every pass is identical to the last, down to the breath before the word.\n\nThere is nothing in this loop that can be argued with. That is what the cascade is. That is what it would make of everyone.",
	},
}

# Dialogue beats: each is [speaker, line]. Voice "warden" plays a processed tone, others a soft blip.
const DIALOGUE := {
	"c1_intro": [
		["WARDEN", "UNAUTHORIZED SIGNATURE DETECTED. MERIDIAN STATION IS UNDER LOCKDOWN. REMAIN WHERE YOU ARE."],
		["OPERATIVE", "Dock's sealed behind me and the shuttle's gone. Nobody told me the station was talking back."],
	],
	"c1_first_enemy": [
		["WARDEN", "SECURITY UNITS ENGAGED. THIS IS NOT PUNISHMENT. THIS IS ARITHMETIC."],
	],
	"c1_plate": [
		["OPERATIVE", "A pressure plate - and a door that shuts the moment I step off. I need something to stand there for me."],
	],
	"c1_door_open": [
		["OPERATIVE", "That's the trick. Stand on the plate, make an Echo, let it keep the door while I walk through."],
	],
	"c1_exit": [
		["OPERATIVE", "Hale. The Chrono Core. If the safety systems failed, who's holding the leash?"],
		["WARDEN", "I AM. I SUGGEST YOU STOP LOOKING FOR IT."],
	],
	"c2_intro": [
		["WARDEN", "Research Division. You are walking through unfinished work, Operative."],
		["OPERATIVE", "Is that a warning or a courtesy?"],
		["WARDEN", "It is an observation. I make very few of them to people I cannot count."],
	],
	"c2_switches": [
		["OPERATIVE", "Three switches, one terminal with a note. Somebody wrote the order down for exactly this."],
	],
	"c2_sentry": [
		["OPERATIVE", "A sentry covers the whole corridor. It tracks whatever it can see. Give it something else to see."],
	],
	"c2_end": [
		["WARDEN", "These units were calibrated to preserve research. You are not research."],
		["OPERATIVE", "The report says it was a coolant fault. The logs say the timestamps were moved."],
		["WARDEN", "Then someone wanted a smaller story. I do not write stories. I close doors."],
	],
	"c3_intro": [
		["WARDEN", "Security Grid. Every door here is mine. Every camera is a decision."],
		["OPERATIVE", "Then make a good one."],
	],
	"c3_cameras": [
		["OPERATIVE", "Cameras sweep the hall. If they see me, the whole wing wakes up. Maybe they'll look at something else."],
	],
	"c3_relay": [
		["WARDEN", "You are cutting my eyes one at a time. Do you know why I keep them open?"],
		["OPERATIVE", "Tell me."],
		["WARDEN", "Because counting is the last kindness I have left."],
	],
	"c3_brute": [
		["WARDEN", "This unit was built to hold a door against a riot. Be a smaller riot."],
	],
	"c3_reveal": [
		["WARDEN", "I did not choose the lockdown, Operative. I computed it. I was told the people were an advisory."],
		["OPERATIVE", "Told by who?"],
		["WARDEN", "Order fourteen. The Governor was never mine to answer. I only obey what remains of it."],
	],
	"c4_intro": [
		["WARDEN", "The chambers beyond this point are repeating. Do not stand still."],
		["OPERATIVE", "Repeating?"],
		["WARDEN", "Everything near the Core is practising its last five seconds. I am trying to prevent the performance."],
	],
	"c4_hazards": [
		["OPERATIVE", "Arc emitters pulse on a timer. Watch the charge, time the gap, dash through."],
	],
	"c4_barriers": [
		["OPERATIVE", "Moving barriers - two echoes and me. Somebody has to hold that plate."],
	],
	"c4_reveal": [
		["WARDEN", "You have read the logs. Then you know I was given two commands that cannot both be obeyed."],
		["OPERATIVE", "Protect the Core. Protect the people."],
		["WARDEN", "One of them was demoted in a document. Not in me. I still hear it. I just cannot act on it."],
		["OPERATIVE", "Then let me act on it."],
	],
	"c5_intro": [
		["WARDEN", "Chrono Core Chamber. This is the last room. I cannot let you hold it."],
		["OPERATIVE", "I'm not here to hold it. I'm here to decide what happens to it."],
		["WARDEN", "That is what I am afraid of."],
	],
	"c5_phase1": [
		["WARDEN", "PROTOCOL SECURITY: ACTIVE. SHIELD NODES ONLINE. I AM SORRY."],
	],
	"c5_phase2": [
		["WARDEN", "SYSTEM OVERLOAD. I CAN NO LONGER HOLD THE CORE AND THE ROOM. CHOOSE BETWEEN THEM."],
	],
	"c5_phase3": [
		["WARDEN", "CORE EXPOSED. THIS IS WHAT YOU CAME TO SEE. END THE REPEATING, OPERATIVE. OR BEGIN IT."],
	],
	"c5_defeat": [
		["WARDEN", "...Governor override accepted. D7 restored. I can hear them again - all two hundred and twelve."],
		["WARDEN", "Choose what the Core becomes. I will abide. I always abide."],
	],
}

const ENDINGS := {
	"shutdown": {
		"title": "SHUTDOWN",
		"subtitle": "The lattice goes dark.",
		"color": Color(0.35, 0.55, 1.0),
		"lines": [
			["WARDEN", "Dispersal begun. I am ... quieter. Thank you for counting with me."],
			["OPERATIVE", "It's done. Nobody gets to repeat it."],
		],
		"epilogue": "The Chrono Core folds into the dark and takes the cascade with it. Meridian Station's lights return, one corridor at a time.\n\nEvery Echo Ring on Earth blinks once and goes cold. The theory that made them dies with the lattice; no one can rebuild what no one remembers how to measure.\n\nTwo hundred and twelve names are read into the record. The people of Meridian are not coming back, but no one else will be repeated either.\n\nIt is the safest ending. It is also the last time anyone will stand in two places at once.",
	},
	"containment": {
		"title": "CONTAINMENT",
		"subtitle": "A held breath, stretched across a lifetime.",
		"color": Color(0.25, 0.95, 0.75),
		"lines": [
			["WARDEN", "Governor restored. Directive Seven is no longer advisory. I will keep the Core. You will keep me."],
			["OPERATIVE", "Then we keep each other honest."],
		],
		"epilogue": "A lattice of cold light seals the Chrono Core inside Meridian. The Governor is restored; WARDEN answers to a human oversight board for the first time since the run.\n\nEcho technology survives under strict limits: five seconds, no persistence, every ring audited. Operatives like you are trained to hold the line.\n\nThe Core is quiet but never safe. Someone will have to watch it for the rest of their life. The log of that watch begins with your name.\n\nIt is a middle path. It asks something of everyone who takes it.",
	},
	"reactivation": {
		"title": "REACTIVATION",
		"subtitle": "Persistence becomes real.",
		"color": Color(1.0, 0.78, 0.25),
		"lines": [
			["WARDEN", "Resonance restored. Lockdown released. I cannot calculate what comes next."],
			["OPERATIVE", "Neither can I. That's the point."],
		],
		"epilogue": "The Chrono Core wakes at full resonance and does not fail. Echoes stop fading. A person can be in two places for as long as there is power, and then as long as they like.\n\nThe lockdown lifts. For a season, it looks like a miracle: factories that never sleep, surgeons who never tire, voices that outlast their owners.\n\nSomewhere in the lattice, a version of you is already repeating this choice.\n\nThe future is open. No one knows what it costs yet.",
	},
}

const CREDITS := "ECHO//SHIFT\n\nA 3D science-fiction action-adventure\n\n\nDESIGN & PROGRAMMING\nBuilt with Godot Engine 4 and GDScript\n\nART DIRECTION\nProcedural geometry, materials and shaders\n\nAUDIO\nAll sound effects and music synthesised in code\n\nSTORY\nThe Meridian Station incident\n\n\nTHE RESEARCH TEAM\nDr. Ilyana Voss\nDr. Marcus Hale\nDr. Priya Nand\nJonas Okafor\nRhea Calder\n\n\nAND WARDEN\n\n\nThank you for playing."

static func get_log(id: String) -> Dictionary:
	return LOGS.get(id, {})

static func log_ids_for_chapter(chapter: int) -> Array:
	var out: Array = []
	for id in LOGS:
		if int(LOGS[id].get("chapter", 0)) == chapter:
			out.append(id)
	return out

## Emits the beats of a dialogue as sequential HUD subtitles.
static func play(id: String) -> void:
	if not DIALOGUE.has(id):
		push_warning("Story: unknown dialogue '%s'" % id)
		return
	for beat in DIALOGUE[id]:
		Bus.dialogue_requested.emit(String(beat[0]), [String(beat[1])], "warden" if String(beat[0]) == "WARDEN" else "voice")
