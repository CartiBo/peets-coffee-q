-- Moveset data: DATA ONLY. No Instances, remotes, connections or auto-start.
-- Built 2026-10-15 from:
--   JujutsuAdaptiveCombat/current.luau (moveRules, counterNames, observedSpecial, bot timing config)
--   JujutsuAdaptiveCombat/opponent_knowledge.json (matchups: our move vs enemy moveset; knowledge: enemy profiles)
-- Field meaning:
--   range: studs used by the bot rules (code), rangeSource says where it came from.
--   observed.maxHitDistance: largest distance where a hit was recorded. 0 = not recorded (melee often is).
--   observed.hitRate = hits/uses; damage per hit = observed.damage/hits.
--   confirmed: true only when the move has >= 3 recorded hits. Otherwise consumers must ignore it.
--   Historical named moves have no measured startup. Runtime animationTimings/measuredMelee
--   contain observed marker/contact samples; the adapter restores pvp/measured_timings.json.
--   Observed maxContactDistance is a lower bound, not a complete damage area.
--   holdDuration/perfectPhase: native variant timing from code comments, not a wind-up.
--   threats.duration: how long the special is treated as a threat window (code), not measured wind-up.
-- dynamic.luau: target.move.confirmed=false is ignored; windup absent means no parry window.

local MovesetData = { version = "1.1.0", generated = "2026-10-15" }

-- Moves that counter (counterNames in current.luau).
MovesetData.counters = {
    ["manji kick"] = true,
    ["door guard"] = true,
    ["parry"] = true,
    ["head splitter"] = true,
    ["supernova"] = true,
    ["brothers"] = true,
    ["domain amplification"] = true,
    ["vengeance"] = true,
    ["i had no idea.."] = true,
    ["shut up!"] = true,
    ["eye catching"] = true,
    ["foresight"] = true,
    ["miracle"] = true,
}

-- Our moves: rule data plus totals across all recorded matchups.
MovesetData.moves = {
    ["appetizer"] = { range = 8.5, priority = 4, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 30, hits = 18, hitRate = 0.6, damage = 205.769, maxHitDistance = 25.293 }, confirmed = true, windupMeasured = false },
    ["backstab"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 1, hitRate = 0.5, damage = 0.967, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["bird control"] = { counter = false, rangeSource = "none", observed = { uses = 163, hits = 60, hitRate = 0.368, damage = 280.652, maxHitDistance = 43.275 }, confirmed = true, windupMeasured = false },
    ["black mucus"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 3, hitRate = 0.75, damage = 14.173, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["bleedout"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 1, hitRate = 0.5, damage = 2.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["blind rage"] = { range = 38, priority = 2, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["blood edge"] = { range = 8, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 4, hits = 1, hitRate = 0.25, damage = 6.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["body disfigure"] = { counter = false, rangeSource = "none", observed = { uses = 11, hits = 6, hitRate = 0.545, damage = 46.912, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["body repel"] = { counter = false, rangeSource = "none", observed = { uses = 11, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["boost on"] = { counter = false, rangeSource = "none", observed = { uses = 5, hits = 3, hitRate = 0.6, damage = 30.483, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["chokehold"] = { range = 7.8, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 84, hits = 41, hitRate = 0.488, damage = 66.817, maxHitDistance = 28.462 }, confirmed = true, windupMeasured = false },
    ["circling"] = { counter = false, rangeSource = "none", observed = { uses = 89, hits = 44, hitRate = 0.494, damage = 396.07, maxHitDistance = 31.213 }, confirmed = true, windupMeasured = false },
    ["cleave"] = { range = 8.5, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["clever"] = { counter = false, rangeSource = "none", observed = { uses = 5, hits = 2, hitRate = 0.4, damage = 43.883, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["copy"] = { counter = false, rangeSource = "none", observed = { uses = 52, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["crushing blow"] = { range = 8.2, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 193, hits = 101, hitRate = 0.523, damage = 538.081, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["crushing jaws"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["cursed buds"] = { counter = false, rangeSource = "none", observed = { uses = 5, hits = 4, hitRate = 0.8, damage = 26.933, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["cursed strikes"] = { range = 7.8, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 228, hits = 80, hitRate = 0.351, damage = 438.028, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["custom"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["decisive strike"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 2, hitRate = 1, damage = 9.967, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["defense response"] = { counter = false, rangeSource = "none", observed = { uses = 12, hits = 6, hitRate = 0.5, damage = 67.597, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["despair"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["detach"] = { range = 9, priority = 3, counter = false, rangeSource = "code_rule", observed = { uses = 85, hits = 37, hitRate = 0.435, damage = 48.606, maxHitDistance = 37.668 }, confirmed = true, windupMeasured = false },
    ["dismantle"] = { range = 25, priority = 2, counter = false, rangeSource = "code_rule", observed = { uses = 26, hits = 10, hitRate = 0.385, damage = 115.085, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["divergent fist"] = { range = 6.8, priority = 3, useTwice = 0.34, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 113, hits = 56, hitRate = 0.496, damage = 513.172, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["divine dog: totality"] = { range = 60, priority = 1, counter = false, rangeSource = "code_rule", observed = { uses = 103, hits = 40, hitRate = 0.388, damage = 278.201, maxHitDistance = 42.51 }, confirmed = true, windupMeasured = false },
    ["divine pummel"] = { counter = false, rangeSource = "none", observed = { uses = 9, hits = 1, hitRate = 0.111, damage = 2, maxHitDistance = 12.14 }, confirmed = false, windupMeasured = false },
    ["earthquake"] = { holdDuration = 0.85, perfectPhase = "Crush2", counter = false, rangeSource = "none", observed = { uses = 6, hits = 2, hitRate = 0.333, damage = 15.467, maxHitDistance = 23.46 }, confirmed = false, windupMeasured = false },
    ["execution"] = { range = 8, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 4, hits = 1, hitRate = 0.25, damage = 1.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["eye catching"] = { counter = true, rangeSource = "none", observed = { uses = 9, hits = 2, hitRate = 0.222, damage = 24.467, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["festering strikes"] = { range = 8.2, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 63, hits = 31, hitRate = 0.492, damage = 63.699, maxHitDistance = 24.311 }, confirmed = true, windupMeasured = false },
    ["garuda rebound"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 1, hitRate = 1, damage = 1.5, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["garuda stab"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 1, hitRate = 0.5, damage = 14.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["granite blast"] = { range = 65, priority = 1, holdDuration = 0.68, perfectPhase = "FireHard", counter = false, rangeSource = "code_rule", observed = { uses = 122, hits = 44, hitRate = 0.361, damage = 201.869, maxHitDistance = 36.822 }, confirmed = true, windupMeasured = false },
    ["great serpent"] = { range = 26, priority = 3, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["ground pitch"] = { counter = false, rangeSource = "none", observed = { uses = 17, hits = 7, hitRate = 0.412, damage = 25.419, maxHitDistance = 23.117 }, confirmed = true, windupMeasured = false },
    ["heat emission"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 2, hitRate = 1, damage = 16.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["hollow purple"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["impetus updraft"] = { counter = false, rangeSource = "none", observed = { uses = 81, hits = 17, hitRate = 0.21, damage = 140.685, maxHitDistance = 18.907 }, confirmed = true, windupMeasured = false },
    ["judgement's reach"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["justice served"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["kamehameha"] = { range = 65, priority = 1, holdDuration = 0.65, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["ki spam"] = { range = 45, priority = 2, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["lapse blue"] = { counter = false, rangeSource = "none", observed = { uses = 263, hits = 127, hitRate = 0.483, damage = 566.81, maxHitDistance = 30.698 }, confirmed = true, windupMeasured = false },
    ["lapse blue max"] = { counter = false, rangeSource = "none", observed = { uses = 6, hits = 2, hitRate = 0.333, damage = 26.567, maxHitDistance = 11.351 }, confirmed = false, windupMeasured = false },
    ["malevolent shrine"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["manji kick"] = { range = 7.5, counter = true, rangeSource = "code_rule", observed = { uses = 58, hits = 23, hitRate = 0.397, damage = 160.278, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["max elephant"] = { range = 38, priority = 1, counter = false, rangeSource = "code_rule", observed = { uses = 3, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["miracle cannon"] = { range = 65, priority = 1, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["murmurate"] = { counter = false, rangeSource = "none", observed = { uses = 75, hits = 34, hitRate = 0.453, damage = 259.574, maxHitDistance = 30.684 }, confirmed = true, windupMeasured = false },
    ["nue"] = { range = 38, priority = 2, counter = false, rangeSource = "code_rule", observed = { uses = 124, hits = 36, hitRate = 0.29, damage = 214.513, maxHitDistance = 27.217 }, confirmed = true, windupMeasured = false },
    ["open"] = { counter = false, rangeSource = "none", observed = { uses = 11, hits = 3, hitRate = 0.273, damage = 8.85, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["outburst"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 1, hitRate = 0.25, damage = 5, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["pebble throw"] = { counter = false, rangeSource = "none", observed = { uses = 8, hits = 5, hitRate = 0.625, damage = 23.934, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["piercing blood"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 2, hitRate = 1, damage = 9.5, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["rabbit escape"] = { range = 40, counter = false, rangeSource = "code_rule", observed = { uses = 120, hits = 87, hitRate = 0.725, damage = 334.166, maxHitDistance = 28.737 }, confirmed = true, windupMeasured = false },
    ["rapid punches"] = { range = 8, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 165, hits = 71, hitRate = 0.43, damage = 120.78, maxHitDistance = 18.306 }, confirmed = true, windupMeasured = false },
    ["ratio technique"] = { range = 8, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["reserve balls"] = { counter = false, rangeSource = "none", observed = { uses = 7, hits = 4, hitRate = 0.571, damage = 25.459, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["resolute slash"] = { counter = false, rangeSource = "none", observed = { uses = 10, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["reversal red"] = { counter = false, rangeSource = "none", observed = { uses = 195, hits = 95, hitRate = 0.487, damage = 852.033, maxHitDistance = 23.593 }, confirmed = true, windupMeasured = false },
    ["reversal red max"] = { counter = false, rangeSource = "none", observed = { uses = 5, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["revolve"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["rika smash"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 1, hitRate = 1, damage = 10, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["rising rage"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 1, hitRate = 0.25, damage = 12.984, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["roach swarm"] = { range = 35, priority = 4, counter = false, rangeSource = "code_rule", observed = { uses = 142, hits = 74, hitRate = 0.521, damage = 375.328, maxHitDistance = 36.149 }, confirmed = true, windupMeasured = false },
    ["root swarm"] = { counter = false, rangeSource = "none", observed = { uses = 6, hits = 3, hitRate = 0.5, damage = 21.648, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["rough energy"] = { range = 8.5, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["rush"] = { counter = false, rangeSource = "none", observed = { uses = 11, hits = 8, hitRate = 0.727, damage = 34.15, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["sacrilege"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 2, hitRate = 0.5, damage = 9.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["second helping"] = { range = 35, priority = 3, counter = false, rangeSource = "code_rule", observed = { uses = 65, hits = 42, hitRate = 0.646, damage = 455.666, maxHitDistance = 30.81 }, confirmed = true, windupMeasured = false },
    ["second wind"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["severing path"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["shadow swarm"] = { range = 18, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 6, hits = 2, hitRate = 0.333, damage = 5.983, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["shutter doors"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["sky distortion"] = { range = 55, priority = 1, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["soul fire"] = { range = 8, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 1, hits = 1, hitRate = 1, damage = 30, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["stockpile"] = { range = 9, priority = 1, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 4, hits = 2, hitRate = 0.5, damage = 60, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["supernova"] = { range = 14, priority = 3, comboPreferred = true, counter = true, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["surging thorns"] = { counter = false, rangeSource = "none", observed = { uses = 1, hits = 1, hitRate = 1, damage = 4, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["swift kick"] = { counter = false, rangeSource = "none", observed = { uses = 4, hits = 1, hitRate = 0.25, damage = 7.984, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["takedown"] = { counter = false, rangeSource = "none", observed = { uses = 5, hits = 1, hitRate = 0.2, damage = 11.483, maxHitDistance = 29.07 }, confirmed = false, windupMeasured = false },
    ["thin ice breaker"] = { range = 16, priority = 3, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["toad"] = { range = 24, priority = 3, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 103, hits = 37, hitRate = 0.359, damage = 310.828, maxHitDistance = 30.373 }, confirmed = true, windupMeasured = false },
    ["trip"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 1, hitRate = 0.5, damage = 2.984, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["twofold kick"] = { counter = false, rangeSource = "none", observed = { uses = 146, hits = 51, hitRate = 0.349, damage = 389.076, maxHitDistance = 22.348 }, confirmed = true, windupMeasured = false },
    ["ultra cannon"] = { range = 65, priority = 1, holdDuration = 0.65, counter = false, rangeSource = "code_rule", observed = nil, confirmed = false, windupMeasured = false },
    ["ultra spin"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["unsatisfied"] = { range = 18, priority = 2, comboPreferred = true, counter = false, rangeSource = "code_rule", observed = { uses = 41, hits = 15, hitRate = 0.366, damage = 129.318, maxHitDistance = 20.142 }, confirmed = true, windupMeasured = false },
    ["what are you after?"] = { counter = false, rangeSource = "none", observed = { uses = 3, hits = 3, hitRate = 1, damage = 20.983, maxHitDistance = 0 }, confirmed = true, windupMeasured = false },
    ["wing throw"] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 1, hitRate = 0.5, damage = 3, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
    ["you weren't invited."] = { counter = false, rangeSource = "none", observed = { uses = 2, hits = 0, hitRate = 0, damage = 0, maxHitDistance = 0 }, confirmed = false, windupMeasured = false },
}

-- Our move usage per enemy moveset: { uses, hits }.
MovesetData.byEnemy = {
    ["Charles"] = { ["crushing blow"] = { 2, 1 }, ["cursed strikes"] = { 3, 1 }, ["dismantle"] = { 2, 1 }, ["divergent fist"] = { 4, 4 }, ["divine dog: totality"] = { 23, 6 }, ["malevolent shrine"] = { 1, 0 }, ["nue"] = { 25, 5 }, ["open"] = { 1, 0 }, ["rabbit escape"] = { 23, 16 }, ["rush"] = { 1, 0 }, ["toad"] = { 22, 4 } },
    ["Choso"] = { ["bird control"] = { 4, 2 }, ["circling"] = { 2, 2 }, ["clever"] = { 2, 1 }, ["crushing blow"] = { 13, 8 }, ["cursed strikes"] = { 12, 4 }, ["divergent fist"] = { 10, 3 }, ["divine dog: totality"] = { 9, 5 }, ["divine pummel"] = { 4, 1 }, ["earthquake"] = { 2, 1 }, ["execution"] = { 3, 1 }, ["ground pitch"] = { 3, 1 }, ["impetus updraft"] = { 2, 2 }, ["lapse blue"] = { 2, 0 }, ["nue"] = { 18, 7 }, ["rabbit escape"] = { 17, 15 }, ["rapid punches"] = { 2, 0 }, ["shadow swarm"] = { 4, 1 }, ["shutter doors"] = { 2, 0 }, ["takedown"] = { 2, 1 }, ["toad"] = { 10, 4 }, ["twofold kick"] = { 2, 0 } },
    ["Gojo"] = { ["appetizer"] = { 10, 2 }, ["bird control"] = { 4, 0 }, ["copy"] = { 21, 0 }, ["crushing blow"] = { 42, 15 }, ["cursed strikes"] = { 61, 7 }, ["defense response"] = { 1, 1 }, ["dismantle"] = { 2, 2 }, ["divergent fist"] = { 13, 3 }, ["divine dog: totality"] = { 7, 2 }, ["divine pummel"] = { 1, 0 }, ["granite blast"] = { 32, 12 }, ["ground pitch"] = { 3, 1 }, ["impetus updraft"] = { 2, 0 }, ["lapse blue"] = { 4, 4 }, ["manji kick"] = { 4, 3 }, ["nue"] = { 10, 2 }, ["open"] = { 1, 1 }, ["pebble throw"] = { 1, 0 }, ["rabbit escape"] = { 12, 10 }, ["rapid punches"] = { 2, 0 }, ["reversal red"] = { 4, 4 }, ["rising rage"] = { 2, 1 }, ["rush"] = { 1, 1 }, ["sacrilege"] = { 4, 2 }, ["second helping"] = { 14, 10 }, ["takedown"] = { 1, 0 }, ["toad"] = { 11, 4 }, ["twofold kick"] = { 2, 0 }, ["unsatisfied"] = { 10, 2 } },
    ["Hakari"] = { ["bird control"] = { 2, 0 }, ["crushing blow"] = { 18, 7 }, ["cursed strikes"] = { 11, 2 }, ["dismantle"] = { 2, 1 }, ["divergent fist"] = { 13, 5 }, ["divine dog: totality"] = { 1, 0 }, ["lapse blue"] = { 16, 6 }, ["malevolent shrine"] = { 1, 0 }, ["manji kick"] = { 9, 4 }, ["nue"] = { 1, 0 }, ["open"] = { 1, 0 }, ["rabbit escape"] = { 2, 2 }, ["rapid punches"] = { 7, 4 }, ["reversal red"] = { 16, 9 }, ["rush"] = { 1, 1 }, ["toad"] = { 1, 1 }, ["twofold kick"] = { 14, 8 } },
    ["Hanami"] = { ["bird control"] = { 8, 2 }, ["circling"] = { 8, 2 }, ["granite blast"] = { 30, 18 }, ["impetus updraft"] = { 4, 0 }, ["murmurate"] = { 4, 2 }, ["second helping"] = { 8, 4 }, ["unsatisfied"] = { 6, 0 } },
    ["Haruta"] = { ["bird control"] = { 2, 2 }, ["body repel"] = { 2, 0 }, ["boost on"] = { 2, 1 }, ["chokehold"] = { 1, 0 }, ["circling"] = { 2, 2 }, ["crushing blow"] = { 4, 4 }, ["crushing jaws"] = { 1, 0 }, ["cursed buds"] = { 1, 1 }, ["cursed strikes"] = { 2, 1 }, ["defense response"] = { 1, 0 }, ["divergent fist"] = { 1, 0 }, ["divine dog: totality"] = { 8, 1 }, ["impetus updraft"] = { 2, 0 }, ["murmurate"] = { 2, 2 }, ["nue"] = { 5, 1 }, ["open"] = { 1, 0 }, ["outburst"] = { 2, 1 }, ["rabbit escape"] = { 6, 5 }, ["resolute slash"] = { 9, 0 }, ["rising rage"] = { 1, 0 }, ["root swarm"] = { 1, 1 }, ["toad"] = { 6, 2 }, ["twofold kick"] = { 2, 1 }, ["unsatisfied"] = { 1, 1 } },
    ["Heian"] = { ["bird control"] = { 14, 6 }, ["circling"] = { 8, 4 }, ["impetus updraft"] = { 4, 2 }, ["murmurate"] = { 4, 0 } },
    ["Hiromi"] = { ["bird control"] = { 2, 0 }, ["chokehold"] = { 2, 2 }, ["crushing blow"] = { 3, 1 }, ["cursed strikes"] = { 2, 1 }, ["dismantle"] = { 1, 0 }, ["divergent fist"] = { 2, 1 }, ["divine dog: totality"] = { 2, 0 }, ["lapse blue"] = { 18, 6 }, ["nue"] = { 3, 1 }, ["open"] = { 1, 0 }, ["rabbit escape"] = { 1, 1 }, ["rapid punches"] = { 12, 10 }, ["reversal red"] = { 12, 6 }, ["roach swarm"] = { 10, 6 }, ["rush"] = { 1, 0 }, ["toad"] = { 1, 1 }, ["twofold kick"] = { 8, 2 } },
    ["Itadori"] = { ["bird control"] = { 7, 2 }, ["black mucus"] = { 1, 1 }, ["body disfigure"] = { 3, 2 }, ["body repel"] = { 5, 0 }, ["boost on"] = { 2, 2 }, ["chokehold"] = { 24, 12 }, ["clever"] = { 1, 1 }, ["crushing blow"] = { 17, 7 }, ["cursed buds"] = { 4, 3 }, ["cursed strikes"] = { 17, 8 }, ["custom"] = { 2, 0 }, ["defense response"] = { 5, 3 }, ["detach"] = { 16, 4 }, ["dismantle"] = { 4, 1 }, ["divergent fist"] = { 8, 5 }, ["divine dog: totality"] = { 8, 4 }, ["festering strikes"] = { 12, 2 }, ["garuda stab"] = { 2, 1 }, ["ground pitch"] = { 1, 1 }, ["lapse blue"] = { 5, 1 }, ["lapse blue max"] = { 2, 0 }, ["malevolent shrine"] = { 1, 0 }, ["manji kick"] = { 8, 4 }, ["max elephant"] = { 1, 0 }, ["nue"] = { 7, 2 }, ["open"] = { 1, 0 }, ["outburst"] = { 1, 0 }, ["pebble throw"] = { 1, 1 }, ["piercing blood"] = { 2, 2 }, ["rabbit escape"] = { 4, 3 }, ["rapid punches"] = { 5, 1 }, ["resolute slash"] = { 1, 0 }, ["reversal red"] = { 5, 3 }, ["reversal red max"] = { 2, 0 }, ["rising rage"] = { 1, 0 }, ["roach swarm"] = { 20, 14 }, ["root swarm"] = { 2, 1 }, ["shadow swarm"] = { 2, 1 }, ["swift kick"] = { 1, 0 }, ["toad"] = { 4, 1 }, ["twofold kick"] = { 9, 8 }, ["ultra spin"] = { 1, 0 }, ["unsatisfied"] = { 4, 4 } },
    ["Kurourushi"] = { ["crushing blow"] = { 5, 3 }, ["cursed strikes"] = { 6, 3 }, ["dismantle"] = { 1, 0 }, ["divergent fist"] = { 3, 3 }, ["festering strikes"] = { 2, 0 }, ["manji kick"] = { 2, 2 }, ["roach swarm"] = { 2, 0 }, ["rush"] = { 1, 1 }, ["twofold kick"] = { 2, 0 } },
    ["Locust"] = { ["manji kick"] = { 4, 1 }, ["nue"] = { 1, 0 }, ["rabbit escape"] = { 1, 0 }, ["toad"] = { 1, 1 } },
    ["Mahito"] = { ["black mucus"] = { 2, 1 }, ["body disfigure"] = { 3, 2 }, ["crushing blow"] = { 33, 19 }, ["cursed strikes"] = { 52, 24 }, ["dismantle"] = { 10, 3 }, ["divergent fist"] = { 24, 12 }, ["divine dog: totality"] = { 10, 2 }, ["justice served"] = { 2, 0 }, ["lapse blue"] = { 12, 6 }, ["malevolent shrine"] = { 1, 0 }, ["manji kick"] = { 6, 0 }, ["nue"] = { 9, 0 }, ["open"] = { 3, 1 }, ["outburst"] = { 1, 0 }, ["rabbit escape"] = { 9, 6 }, ["rapid punches"] = { 2, 0 }, ["reserve balls"] = { 4, 3 }, ["reversal red"] = { 4, 0 }, ["roach swarm"] = { 2, 0 }, ["rush"] = { 6, 5 }, ["stockpile"] = { 1, 0 }, ["swift kick"] = { 3, 1 }, ["toad"] = { 8, 1 }, ["twofold kick"] = { 3, 0 } },
    ["Mahoraga"] = { ["crushing blow"] = { 1, 0 }, ["cursed strikes"] = { 1, 1 }, ["dismantle"] = { 2, 1 }, ["divergent fist"] = { 1, 1 }, ["lapse blue max"] = { 1, 1 }, ["nue"] = { 1, 0 }, ["open"] = { 1, 1 }, ["rabbit escape"] = { 1, 0 }, ["toad"] = { 1, 0 } },
    ["Megumi"] = { ["crushing blow"] = { 10, 8 }, ["cursed strikes"] = { 9, 7 }, ["divergent fist"] = { 6, 4 }, ["divine dog: totality"] = { 3, 3 }, ["divine pummel"] = { 1, 0 }, ["earthquake"] = { 1, 0 }, ["granite blast"] = { 2, 0 }, ["ground pitch"] = { 1, 0 }, ["lapse blue"] = { 2, 2 }, ["manji kick"] = { 2, 1 }, ["nue"] = { 6, 2 }, ["rabbit escape"] = { 5, 2 }, ["reversal red"] = { 2, 0 }, ["second helping"] = { 2, 2 }, ["takedown"] = { 1, 0 }, ["toad"] = { 4, 1 } },
    ["MeiMei"] = { ["lapse blue"] = { 11, 8 }, ["nue"] = { 2, 0 }, ["rapid punches"] = { 3, 2 }, ["reversal red"] = { 6, 4 }, ["twofold kick"] = { 4, 2 } },
    ["Nanami"] = { ["crushing blow"] = { 7, 3 }, ["cursed strikes"] = { 11, 2 }, ["divergent fist"] = { 5, 2 }, ["divine dog: totality"] = { 2, 0 }, ["hollow purple"] = { 1, 0 }, ["lapse blue"] = { 31, 14 }, ["lapse blue max"] = { 1, 1 }, ["manji kick"] = { 12, 3 }, ["nue"] = { 3, 0 }, ["rabbit escape"] = { 3, 1 }, ["rapid punches"] = { 19, 3 }, ["reversal red"] = { 21, 12 }, ["reversal red max"] = { 1, 0 }, ["toad"] = { 3, 1 }, ["twofold kick"] = { 17, 4 } },
    ["Naoya"] = { ["backstab"] = { 2, 1 }, ["bleedout"] = { 2, 1 }, ["blood edge"] = { 4, 1 }, ["body repel"] = { 2, 0 }, ["crushing blow"] = { 7, 2 }, ["cursed strikes"] = { 14, 6 }, ["decisive strike"] = { 2, 2 }, ["defense response"] = { 2, 0 }, ["divergent fist"] = { 5, 3 }, ["divine dog: totality"] = { 1, 0 }, ["divine pummel"] = { 1, 0 }, ["earthquake"] = { 1, 1 }, ["execution"] = { 1, 0 }, ["eye catching"] = { 7, 2 }, ["festering strikes"] = { 1, 1 }, ["ground pitch"] = { 4, 2 }, ["lapse blue"] = { 6, 2 }, ["lapse blue max"] = { 2, 0 }, ["manji kick"] = { 7, 4 }, ["nue"] = { 1, 1 }, ["pebble throw"] = { 3, 2 }, ["rabbit escape"] = { 1, 1 }, ["rapid punches"] = { 7, 2 }, ["reversal red"] = { 6, 4 }, ["reversal red max"] = { 2, 0 }, ["revolve"] = { 2, 0 }, ["second helping"] = { 1, 0 }, ["second wind"] = { 1, 0 }, ["severing path"] = { 2, 0 }, ["toad"] = { 1, 1 }, ["trip"] = { 2, 1 }, ["twofold kick"] = { 6, 4 } },
    ["Reggie"] = { ["appetizer"] = { 8, 8 }, ["body disfigure"] = { 2, 0 }, ["boost on"] = { 1, 0 }, ["circling"] = { 1, 0 }, ["clever"] = { 1, 0 }, ["crushing blow"] = { 1, 0 }, ["crushing jaws"] = { 1, 0 }, ["despair"] = { 1, 0 }, ["dismantle"] = { 1, 1 }, ["eye catching"] = { 1, 0 }, ["granite blast"] = { 26, 8 }, ["impetus updraft"] = { 1, 1 }, ["judgement's reach"] = { 1, 0 }, ["reserve balls"] = { 1, 0 }, ["rika smash"] = { 1, 1 }, ["roach swarm"] = { 2, 0 }, ["root swarm"] = { 2, 0 }, ["second helping"] = { 14, 8 }, ["soul fire"] = { 1, 1 }, ["stockpile"] = { 1, 0 }, ["toad"] = { 1, 0 }, ["twofold kick"] = { 1, 0 }, ["unsatisfied"] = { 8, 2 }, ["what are you after?"] = { 2, 2 } },
    ["Ryu"] = { ["bird control"] = { 14, 0 }, ["black mucus"] = { 1, 1 }, ["body disfigure"] = { 3, 2 }, ["chokehold"] = { 7, 3 }, ["clever"] = { 1, 0 }, ["copy"] = { 31, 0 }, ["crushing blow"] = { 6, 4 }, ["cursed strikes"] = { 2, 1 }, ["detach"] = { 7, 3 }, ["divergent fist"] = { 2, 1 }, ["eye catching"] = { 1, 0 }, ["festering strikes"] = { 4, 2 }, ["garuda rebound"] = { 1, 1 }, ["heat emission"] = { 2, 2 }, ["lapse blue"] = { 12, 10 }, ["max elephant"] = { 2, 0 }, ["murmurate"] = { 1, 0 }, ["rapid punches"] = { 10, 2 }, ["reserve balls"] = { 2, 1 }, ["reversal red"] = { 11, 8 }, ["roach swarm"] = { 24, 16 }, ["root swarm"] = { 1, 1 }, ["stockpile"] = { 2, 2 }, ["surging thorns"] = { 1, 1 }, ["twofold kick"] = { 10, 4 }, ["ultra spin"] = { 1, 0 }, ["what are you after?"] = { 1, 1 }, ["wing throw"] = { 2, 1 }, ["you weren't invited."] = { 2, 0 } },
    ["Todo"] = { ["bird control"] = { 10, 0 }, ["circling"] = { 6, 4 }, ["crushing blow"] = { 2, 1 }, ["cursed strikes"] = { 3, 2 }, ["divergent fist"] = { 3, 2 }, ["divine dog: totality"] = { 9, 5 }, ["granite blast"] = { 2, 2 }, ["impetus updraft"] = { 6, 0 }, ["manji kick"] = { 4, 1 }, ["murmurate"] = { 4, 4 }, ["nue"] = { 12, 7 }, ["rabbit escape"] = { 12, 8 }, ["toad"] = { 9, 5 } },
    ["Unknown"] = { ["appetizer"] = { 2, 2 }, ["bird control"] = { 38, 30 }, ["chokehold"] = { 20, 14 }, ["circling"] = { 24, 18 }, ["crushing blow"] = { 15, 15 }, ["cursed strikes"] = { 12, 8 }, ["detach"] = { 14, 12 }, ["divergent fist"] = { 9, 5 }, ["divine dog: totality"] = { 15, 12 }, ["divine pummel"] = { 2, 0 }, ["earthquake"] = { 2, 0 }, ["festering strikes"] = { 12, 6 }, ["granite blast"] = { 8, 2 }, ["ground pitch"] = { 1, 0 }, ["impetus updraft"] = { 22, 6 }, ["lapse blue"] = { 28, 22 }, ["murmurate"] = { 22, 14 }, ["nue"] = { 10, 2 }, ["rabbit escape"] = { 17, 14 }, ["rapid punches"] = { 30, 27 }, ["reversal red"] = { 35, 29 }, ["roach swarm"] = { 20, 8 }, ["second helping"] = { 10, 10 }, ["takedown"] = { 1, 0 }, ["toad"] = { 12, 8 }, ["twofold kick"] = { 22, 14 }, ["unsatisfied"] = { 2, 0 } },
    ["Uro"] = { ["appetizer"] = { 10, 6 }, ["bird control"] = { 44, 16 }, ["chokehold"] = { 16, 4 }, ["circling"] = { 32, 12 }, ["detach"] = { 22, 8 }, ["festering strikes"] = { 22, 14 }, ["granite blast"] = { 22, 2 }, ["impetus updraft"] = { 26, 6 }, ["lapse blue"] = { 64, 8 }, ["murmurate"] = { 28, 10 }, ["rapid punches"] = { 38, 10 }, ["reversal red"] = { 45, 4 }, ["roach swarm"] = { 44, 14 }, ["second helping"] = { 16, 8 }, ["twofold kick"] = { 26, 2 }, ["unsatisfied"] = { 10, 6 } },
    ["Yuki"] = { ["body repel"] = { 2, 0 }, ["defense response"] = { 3, 2 }, ["divine dog: totality"] = { 3, 0 }, ["ground pitch"] = { 4, 2 }, ["nue"] = { 6, 4 }, ["pebble throw"] = { 3, 2 }, ["rabbit escape"] = { 3, 1 }, ["toad"] = { 4, 2 } },
    ["Yuta"] = { ["bird control"] = { 14, 0 }, ["chokehold"] = { 14, 6 }, ["circling"] = { 6, 0 }, ["crushing blow"] = { 7, 3 }, ["cursed strikes"] = { 10, 2 }, ["detach"] = { 26, 10 }, ["dismantle"] = { 1, 0 }, ["divergent fist"] = { 4, 2 }, ["divine dog: totality"] = { 2, 0 }, ["festering strikes"] = { 10, 6 }, ["impetus updraft"] = { 12, 0 }, ["lapse blue"] = { 52, 38 }, ["murmurate"] = { 10, 2 }, ["nue"] = { 4, 2 }, ["open"] = { 1, 0 }, ["rabbit escape"] = { 3, 2 }, ["rapid punches"] = { 28, 10 }, ["reversal red"] = { 28, 12 }, ["roach swarm"] = { 18, 16 }, ["toad"] = { 4, 0 }, ["twofold kick"] = { 18, 2 } },
}

-- Enemy profiles by moveset (sum of tracked opponents).
-- approach/dash counts show where attacks and dashes come from and where they go.
MovesetData.enemies = {
    ["Charles"] = { attacks = 608, successfulHits = 306, blocks = 239, dashes = 1329, samples = 32430, averageAttackDistance = 105.377, averageAttackHeight = -2.617, attackApproaches = { front = 269, right = 147, left = 145, back = 47 }, dashDirections = { toward = 505, away = 401, left = 217, right = 206 }, reactions = { attackAfterOurMove = 51, blockAfterOurMove = 31, dashAfterOurMove = 50 } },
    ["Choso"] = { attacks = 911, successfulHits = 423, blocks = 283, dashes = 2581, samples = 60919, averageAttackDistance = 133.9, averageAttackHeight = 4.984, attackApproaches = { front = 291, right = 232, left = 282, back = 81 }, dashDirections = { toward = 1037, away = 785, left = 360, right = 399 }, reactions = { attackAfterOurMove = 52, blockAfterOurMove = 27, dashAfterOurMove = 65 } },
    ["Gojo"] = { attacks = 1923, successfulHits = 785, blocks = 389, dashes = 4718, samples = 117554, averageAttackDistance = 244.783, averageAttackHeight = 9.841, attackApproaches = { front = 633, right = 438, left = 522, back = 264 }, dashDirections = { toward = 1731, away = 1579, left = 660, right = 748 }, reactions = { attackAfterOurMove = 112, blockAfterOurMove = 41, dashAfterOurMove = 105 } },
    ["Hakari"] = { attacks = 2830, successfulHits = 241, blocks = 409, dashes = 4729, samples = 118397, averageAttackDistance = 509.303, averageAttackHeight = 25.162, attackApproaches = { front = 657, right = 882, left = 998, back = 265 }, dashDirections = { toward = 1827, away = 1392, left = 734, right = 776 }, reactions = { attackAfterOurMove = 88, blockAfterOurMove = 24, dashAfterOurMove = 46 } },
    ["Hanami"] = { attacks = 640, successfulHits = 25, blocks = 190, dashes = 2466, samples = 55790, averageAttackDistance = 263.309, averageAttackHeight = -3.171, attackApproaches = { front = 171, right = 204, left = 183, back = 82 }, dashDirections = { toward = 950, away = 727, left = 403, right = 386 }, reactions = { attackAfterOurMove = 5, blockAfterOurMove = 2, dashAfterOurMove = 14 } },
    ["Haruta"] = { attacks = 130, successfulHits = 61, blocks = 41, dashes = 212, samples = 12111, averageAttackDistance = 54.987, averageAttackHeight = -7.079, attackApproaches = { front = 64, right = 24, left = 31, back = 11 }, dashDirections = { toward = 78, away = 82, left = 28, right = 24 }, reactions = { attackAfterOurMove = 12, blockAfterOurMove = 11, dashAfterOurMove = 5 } },
    ["Heian"] = { attacks = 33, successfulHits = 7, blocks = 8, dashes = 279, samples = 5339, averageAttackDistance = 799.678, averageAttackHeight = 145.214, attackApproaches = { front = 5, right = 12, left = 13, back = 3 }, dashDirections = { toward = 87, away = 103, left = 44, right = 45 }, reactions = { attackAfterOurMove = 0, blockAfterOurMove = 0, dashAfterOurMove = 7 } },
    ["Hiromi"] = { attacks = 1212, successfulHits = 129, blocks = 392, dashes = 2955, samples = 61225, averageAttackDistance = 326.469, averageAttackHeight = 4.651, attackApproaches = { front = 312, right = 429, left = 313, back = 158 }, dashDirections = { toward = 998, away = 993, left = 456, right = 508 }, reactions = { attackAfterOurMove = 19, blockAfterOurMove = 13, dashAfterOurMove = 20 } },
    ["Itadori"] = { attacks = 4558, successfulHits = 408, blocks = 1240, dashes = 9967, samples = 229012, averageAttackDistance = 213.309, averageAttackHeight = -6.154, attackApproaches = { front = 1150, right = 1282, left = 1487, back = 635 }, dashDirections = { toward = 3736, away = 3092, left = 1570, right = 1569 }, reactions = { attackAfterOurMove = 96, blockAfterOurMove = 51, dashAfterOurMove = 78 } },
    ["Kurourushi"] = { attacks = 1104, successfulHits = 134, blocks = 137, dashes = 1215, samples = 35753, averageAttackDistance = 234.91, averageAttackHeight = 2.966, attackApproaches = { front = 342, right = 300, left = 358, back = 104 }, dashDirections = { toward = 450, away = 366, left = 197, right = 202 }, reactions = { attackAfterOurMove = 21, blockAfterOurMove = 0, dashAfterOurMove = 12 } },
    ["Locust"] = { attacks = 506, successfulHits = 26, blocks = 130, dashes = 1055, samples = 25374, averageAttackDistance = 225.438, averageAttackHeight = 11.886, attackApproaches = { front = 98, right = 211, left = 136, back = 61 }, dashDirections = { toward = 426, away = 353, left = 130, right = 146 }, reactions = { attackAfterOurMove = 2, blockAfterOurMove = 0, dashAfterOurMove = 5 } },
    ["Mahito"] = { attacks = 3125, successfulHits = 636, blocks = 639, dashes = 6188, samples = 139502, averageAttackDistance = 154.697, averageAttackHeight = -6.937, attackApproaches = { front = 1117, right = 801, left = 815, back = 387 }, dashDirections = { toward = 2253, away = 2060, left = 934, right = 941 }, reactions = { attackAfterOurMove = 152, blockAfterOurMove = 54, dashAfterOurMove = 157 } },
    ["Mahoraga"] = { attacks = 220, successfulHits = 30, blocks = 10, dashes = 537, samples = 9574, averageAttackDistance = 381.67, averageAttackHeight = 1.152, attackApproaches = { front = 50, right = 76, left = 62, back = 32 }, dashDirections = { toward = 179, away = 217, left = 80, right = 61 }, reactions = { attackAfterOurMove = 1, blockAfterOurMove = 0, dashAfterOurMove = 7 } },
    ["Mechamaru"] = { attacks = 647, successfulHits = 1, blocks = 209, dashes = 1890, samples = 30367, averageAttackDistance = 262.943, averageAttackHeight = -54.729, attackApproaches = { front = 126, right = 228, left = 194, back = 99 }, dashDirections = { toward = 657, away = 632, left = 311, right = 290 }, reactions = { attackAfterOurMove = 0, blockAfterOurMove = 0, dashAfterOurMove = 0 } },
    ["Megumi"] = { attacks = 2020, successfulHits = 292, blocks = 327, dashes = 5536, samples = 96983, averageAttackDistance = 327.164, averageAttackHeight = 3.931, attackApproaches = { front = 491, right = 686, left = 564, back = 237 }, dashDirections = { toward = 1931, away = 1780, left = 979, right = 846 }, reactions = { attackAfterOurMove = 11, blockAfterOurMove = 9, dashAfterOurMove = 21 } },
    ["MeiMei"] = { attacks = 121, successfulHits = 8, blocks = 30, dashes = 700, samples = 12630, averageAttackDistance = 168.685, averageAttackHeight = 28.979, attackApproaches = { front = 45, right = 36, left = 25, back = 15 }, dashDirections = { toward = 242, away = 218, left = 118, right = 122 }, reactions = { attackAfterOurMove = 12, blockAfterOurMove = 0, dashAfterOurMove = 8 } },
    ["Nanami"] = { attacks = 1272, successfulHits = 366, blocks = 271, dashes = 1536, samples = 34138, averageAttackDistance = 123.419, averageAttackHeight = -2.058, attackApproaches = { front = 543, right = 269, left = 249, back = 137 }, dashDirections = { toward = 578, away = 500, left = 232, right = 226 }, reactions = { attackAfterOurMove = 108, blockAfterOurMove = 40, dashAfterOurMove = 84 } },
    ["Naoya"] = { attacks = 1420, successfulHits = 548, blocks = 192, dashes = 2855, samples = 55315, averageAttackDistance = 107.394, averageAttackHeight = -0.948, attackApproaches = { front = 665, right = 324, left = 307, back = 123 }, dashDirections = { toward = 1182, away = 806, left = 412, right = 455 }, reactions = { attackAfterOurMove = 108, blockAfterOurMove = 14, dashAfterOurMove = 54 } },
    ["Reggie"] = { attacks = 1034, successfulHits = 445, blocks = 272, dashes = 2827, samples = 66355, averageAttackDistance = 216.228, averageAttackHeight = 5.585, attackApproaches = { front = 244, right = 333, left = 314, back = 143 }, dashDirections = { toward = 1066, away = 898, left = 428, right = 435 }, reactions = { attackAfterOurMove = 20, blockAfterOurMove = 5, dashAfterOurMove = 36 } },
    ["Ryu"] = { attacks = 921, successfulHits = 235, blocks = 184, dashes = 3051, samples = 74024, averageAttackDistance = 230.636, averageAttackHeight = -1.127, attackApproaches = { front = 287, right = 250, left = 261, back = 123 }, dashDirections = { toward = 1227, away = 897, left = 483, right = 444 }, reactions = { attackAfterOurMove = 52, blockAfterOurMove = 10, dashAfterOurMove = 71 } },
    ["Todo"] = { attacks = 2251, successfulHits = 111, blocks = 523, dashes = 5873, samples = 126808, averageAttackDistance = 229.496, averageAttackHeight = -8.392, attackApproaches = { front = 569, right = 685, left = 734, back = 263 }, dashDirections = { toward = 2094, away = 1907, left = 882, right = 990 }, reactions = { attackAfterOurMove = 28, blockAfterOurMove = 17, dashAfterOurMove = 35 } },
    ["Unknown"] = { attacks = 24, successfulHits = 83, blocks = 60, dashes = 3567, samples = 249167, averageAttackDistance = 16.499, averageAttackHeight = -0.221, attackApproaches = { front = 5, right = 5, left = 14, back = 0 }, dashDirections = { toward = 1281, away = 1104, left = 580, right = 602 }, reactions = { attackAfterOurMove = 4, blockAfterOurMove = 0, dashAfterOurMove = 21 } },
    ["Uro"] = { attacks = 14517, successfulHits = 469, blocks = 3516, dashes = 32287, samples = 650968, averageAttackDistance = 296.39, averageAttackHeight = -8.115, attackApproaches = { front = 3120, right = 4757, left = 4390, back = 2250 }, dashDirections = { toward = 12073, away = 9922, left = 5275, right = 5017 }, reactions = { attackAfterOurMove = 90, blockAfterOurMove = 43, dashAfterOurMove = 137 } },
    ["Yuki"] = { attacks = 387, successfulHits = 26, blocks = 65, dashes = 667, samples = 20799, averageAttackDistance = 284.526, averageAttackHeight = 2.93, attackApproaches = { front = 92, right = 127, left = 131, back = 29 }, dashDirections = { toward = 218, away = 254, left = 98, right = 97 }, reactions = { attackAfterOurMove = 14, blockAfterOurMove = 2, dashAfterOurMove = 13 } },
    ["Yuta"] = { attacks = 2600, successfulHits = 398, blocks = 464, dashes = 7607, samples = 167289, averageAttackDistance = 401.494, averageAttackHeight = 20.72, attackApproaches = { front = 679, right = 882, left = 679, back = 343 }, dashDirections = { toward = 2990, away = 2410, left = 1122, right = 1085 }, reactions = { attackAfterOurMove = 66, blockAfterOurMove = 24, dashAfterOurMove = 72 } },
}

-- Special threat windows the bot already tracks (current.luau observedSpecial).
MovesetData.threats = {
    ["BlindRageService"] = { kind = "uro_blind_rage", range = 38, duration = 1.45 },
    ["SkyDistortionService"] = { kind = "uro_sky_distortion", range = 65, duration = 1.35 },
    ["ThinIceBreakerService"] = { kind = "uro_thin_ice", range = 24, duration = 1.2 },
    ["ReversalRedService"] = { kind = "gojo_red", range = 45, duration = 1.4 },
    ["ReversalRedMaxService"] = { kind = "gojo_red_max", range = 60, duration = 1.5 },
    ["LapseBlueService"] = { kind = "gojo_blue", range = 50, duration = 1.5 },
    ["LapseBlueMaxService"] = { kind = "gojo_blue_max", range = 60, duration = 1.6 },
    ["HollowPurpleService"] = { kind = "gojo_hollow_purple", range = 80, duration = 2.0 },
    ["InfiniteVoidService"] = { kind = "gojo_infinite_void", range = 70, duration = 2.2 },
    ["ChosoService"] = { kind = "choso_piercing", range = 60, duration = 1.4 },
    ["PiercingBloodService"] = { kind = "choso_piercing", range = 60, duration = 1.4 },
    ["SupernovaService"] = { kind = "choso_supernova", range = 25, duration = 1.3 },
    ["BloodRainService"] = { kind = "choso_blood_rain", range = 45, duration = 1.5 },
    ["DecisiveStrikeService"] = { kind = "naoya_decisive", range = 30, duration = 1.2 },
    ["ProjectionBreakerService"] = { kind = "naoya_projection", range = 35, duration = 1.3 },
    ["BleedoutService"] = { kind = "naoya_bleedout", range = 20, duration = 1.1 },
    ["CrushingBlowService"] = { kind = "itadori_crushing", range = 18, duration = 1.2 },
    ["DivergentFistService"] = { kind = "itadori_divergent", range = 16, duration = 1.1 },
    ["DismantleService"] = { kind = "sukuna_dismantle", range = 45, duration = 1.2 },
    ["DismantleV2Service"] = { kind = "sukuna_dismantle_v2", range = 55, duration = 1.3 },
    ["FlameArrowService"] = { kind = "sukuna_fire_arrow", range = 65, duration = 1.8 },
    ["MalevolantShrineService"] = { kind = "sukuna_shrine", range = 75, duration = 2.5 },
    ["CleaveRushService"] = { kind = "sukuna_cleave", range = 25, duration = 1.3 },
    ["FesteringStrikesService"] = { kind = "kuro_festering", range = 20, duration = 1.2 },
    ["ChokeholdService"] = { kind = "kuro_chokehold", range = 18, duration = 1.2 },
    ["RoachSwarmService"] = { kind = "kuro_roach_swarm", range = 45, duration = 1.5 },
    ["DetachService"] = { kind = "kuro_detach", range = 35, duration = 1.3 },
    ["GarudaReboundService"] = { kind = "yuki_rebound", range = 35, duration = 1.3 },
    ["GarudaStabService"] = { kind = "yuki_stab", range = 20, duration = 1.2 },
    ["RisingRageService"] = { kind = "yuki_rising_rage", range = 18, duration = 1.2 },
    ["MassBreakerService"] = { kind = "yuki_mass_breaker", range = 22, duration = 1.3 },
    ["GraniteBlastService"] = { kind = "ryu_granite_blast", range = 65, duration = 1.6 },
    ["UltraCannonService"] = { kind = "ryu_granite_blast", range = 65, duration = 1.6 },
    ["PlasmaWaveService"] = { kind = "ryu_plasma_wave", range = 40, duration = 1.3 },
    ["GreatSerpentService"] = { kind = "megumi_serpent", range = 38, duration = 1.4 },
    ["DivineDogService"] = { kind = "megumi_dog", range = 35, duration = 1.2 },
    ["ToadService"] = { kind = "megumi_toad", range = 35, duration = 1.3 },
    ["NueService"] = { kind = "megumi_nue", range = 45, duration = 1.4 },
    ["MaxElephantService"] = { kind = "megumi_elephant", range = 40, duration = 1.5 },
    ["RabbitEscapeService"] = { kind = "megumi_rabbit", range = 30, duration = 1.2 },
    ["ShutterDoorService"] = { kind = "hakari_doors", range = 30, duration = 1.2 },
    ["RoughEnergyService"] = { kind = "hakari_rough_energy", range = 20, duration = 1.2 },
    ["RootSwarmService"] = { kind = "hanami_root_swarm", range = 35, duration = 1.3 },
    ["FlowerBeamService"] = { kind = "hanami_flower_beam", range = 55, duration = 1.5 },
    ["SoulfireService"] = { kind = "mahito_soulfire", range = 25, duration = 1.2 },
    ["StockpileService"] = { kind = "mahito_stockpile", range = 22, duration = 1.2 },
    ["BodyRepelService"] = { kind = "mahito_body_repel", range = 30, duration = 1.2 },
    ["ResoluteSlashService"] = { kind = "yuta_resolute", range = 25, duration = 1.2 },
    ["EnergyRippleService"] = { kind = "yuta_energy_ripple", range = 35, duration = 1.3 },
    ["LoveBeamService"] = { kind = "yuta_love_beam", range = 70, duration = 2.0 },
    ["PianoDropService"] = { kind = "reggie_piano", range = 45, duration = 1.5 },
    ["HomerunService"] = { kind = "reggie_homerun", range = 25, duration = 1.2 },
    ["DroneStrikeService"] = { kind = "reggie_drone", range = 50, duration = 1.5 },
    ["BirdControlService"] = { kind = "meimei_bird_strike", range = 60, duration = 1.5 },
    ["CrushJawService"] = { kind = "yuki_crush_jaw", range = 30, duration = 1.2 },
    ["EarthquakeService"] = { kind = "earthquake", range = 35, duration = 1.4 },
    ["SwiftKickService"] = { kind = "todo_swift_kick", range = 20, duration = 1.1 },
    ["PebbleThrowService"] = { kind = "todo_pebble", range = 35, duration = 1.2 },
    ["CleavingWhirlService"] = { kind = "nanami_cleaving", range = 22, duration = 1.2 },
    ["RatioBreakerService"] = { kind = "nanami_ratio", range = 24, duration = 1.3 },
}

-- Current reaction latency of the bot (seconds). These are the bot own timings,
-- NOT the game wind-up. Use them to see how late the bot reacts.
MovesetData.botLatency = {
    decisionInterval = 0.020, blockGap = 0.21, blockBaseDuration = 0.18, blockQuietTime = 0.12,
    blockMaxDuration = 0.7, blockRearmGap = 0.22, escapeFacingDuration = 0.42, evadeBuffer = 0.9,
    holdReleaseDelay = 0.24, actionGap = 0.09, m1Gap = 0.025, nextM1ChainGap = 0.62,
    specialFollowupGap = 1.15, sideDashGap = 0.92, forwardDashGap = 3.2, telemetryInterval = 0.1,
}

-- Helpers. Lookups are by lowercase move name, the same key used in current.luau.
function MovesetData.move(name)
    return MovesetData.moves[string.lower(tostring(name or ""))]
end

function MovesetData.isCounter(name)
    return MovesetData.counters[string.lower(tostring(name or ""))] == true
end

function MovesetData.enemy(moveset)
    return MovesetData.enemies[tostring(moveset or "")]
end
-- Runtime evidence is keyed by animation, not by a character or guessed move.
-- A marker measures authored contact timing, not successful damage or parry.
MovesetData.animationTimings={}
MovesetData.measuredMelee={}
function MovesetData.recordTiming(id,windup,source,opponent,speed)
    if type(id)~="string" or id=="" or type(windup)~="number" or windup~=windup
        or windup<.01 or windup>3 or type(source)~="string" then return false end
    local bucket=MovesetData.animationTimings[id]
    if not bucket then bucket={samples={},source=source,opponent=opponent,speed=speed or 1};MovesetData.animationTimings[id]=bucket end
    if math.abs((speed or 1)-bucket.speed)>.05 then return false end
    for _,sample in ipairs(bucket.samples) do if sample==windup then return false end end
    bucket.samples[#bucket.samples+1]=windup
    if #bucket.samples>12 then table.remove(bucket.samples,1) end
    local values=table.clone(bucket.samples)
    table.sort(values)
    bucket.windup=values[math.ceil(#values/2)]
    bucket.spread=values[#values]-values[1]
    bucket.windupMeasured=true
    bucket.damageConfirmed=false
    return true
end
function MovesetData.recordContact(name,id,windup,distance,source,opponent,speed)
    if not MovesetData.recordTiming(id,windup,source,opponent,speed) then return false end
    local bucket=MovesetData.animationTimings[id]
    bucket.moveName=name
    if name=="native melee" then MovesetData.measuredMelee[id]=bucket end
    bucket.maxContactDistance=math.max(bucket.maxContactDistance or 0,distance)
    local move=MovesetData.moves[name]
    if move then
        move.windupMeasured=true
        move.windup=bucket.windup
        move.windupSource=source
        move.windupSamples=#bucket.samples
        move.contactDistance=bucket.maxContactDistance
    end
    return true
end
function MovesetData.timingFor(id,speed)
    local b=MovesetData.animationTimings[id]
    -- Require repeated stable observations before scheduling any defense.
    if b and #b.samples>=3 and b.spread<=.08 and (not speed or math.abs(speed-b.speed)<=.05) then return b end
end
function MovesetData.timingReport()
    local measured,usable,count=0,0,0
    for id,b in pairs(MovesetData.animationTimings) do
        measured+=1;count+=#b.samples
        if MovesetData.timingFor(id) then usable+=1 end
    end
    return {measuredAnimations=measured,usableAnimations=usable,samples=count,
        source="observed_markers_or_native_contact",damageConfirmed=false}
end

return MovesetData
