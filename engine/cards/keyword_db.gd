class_name KeywordDb
extends RefCounted

## Reference table of keyword abilities and keyword actions, looked up by name when a card is loaded.
## `status` says what the engine does with it today:
##   ENFORCED  the engine applies the rule itself (combat, damage, targeting ...); nothing to read
##   READ      OracleIr turns it into an ability (equip, prowess)
##   NONE      has no effect the engine needs (devoid, partner, ascend)
##   MISSING   known, but not implemented yet; the card is listed as "not coded" with the keyword's name
## Add a keyword here once the engine does something with it, then change its status.

const KEYWORDS := {
	"flying": {"status": "ENFORCED", "cr": "702.9", "note": "Can be blocked only by creatures with flying or reach."},
	"reach": {"status": "ENFORCED", "cr": "702.17", "note": "Can block creatures with flying."},
	"menace": {"status": "ENFORCED", "cr": "702.110", "note": "Can't be blocked except by two or more creatures."},
	"first strike": {"status": "ENFORCED", "cr": "702.7", "note": "Deals combat damage before creatures without first strike."},
	"double strike": {"status": "ENFORCED", "cr": "702.4", "note": "Deals first-strike and regular combat damage."},
	"trample": {"status": "ENFORCED", "cr": "702.19", "note": "Excess combat damage goes to the player."},
	"deathtouch": {"status": "ENFORCED", "cr": "702.2", "note": "Any damage it deals to a creature is lethal."},
	"lifelink": {"status": "ENFORCED", "cr": "702.15", "note": "Damage dealt also gains you that much life."},
	"indestructible": {"status": "ENFORCED", "cr": "702.12", "note": "Not destroyed by lethal damage or destroy effects."},
	"hexproof": {"status": "ENFORCED", "cr": "702.11", "note": "Can't be the target of spells or abilities your opponents control."},
	"shroud": {"status": "ENFORCED", "cr": "702.18", "note": "Can't be the target of spells or abilities."},
	"haste": {"status": "ENFORCED", "cr": "702.10", "note": "Can attack and use {T} abilities the turn it arrives."},
	"defender": {"status": "ENFORCED", "cr": "702.3", "note": "Can't attack."},
	"flash": {"status": "ENFORCED", "cr": "702.8", "note": "Can be cast any time you could cast an instant."},
	"protection from": {"status": "ENFORCED", "cr": "702.16", "note": "Colors only: can't be damaged, enchanted, blocked or targeted by that color."},
	"equip": {"status": "READ", "cr": "702.6", "note": "Attach to a creature you control, at sorcery speed."},
	"prowess": {"status": "READ", "cr": "702.108", "note": "Gets +1/+1 until end of turn whenever you cast a noncreature spell."},
	"devoid": {"status": "NONE", "cr": "702.114", "note": "Colorless."},
	"partner": {"status": "NONE", "cr": "702.124", "note": "Deck building only."},
	"ascend": {"status": "NONE", "cr": "702.131", "note": "City's blessing at ten permanents."},
	"ward": {"status": "ENFORCED", "cr": "702.21", "note": "Counter a spell or ability that targets it unless its controller pays the ward cost (mana or life)."},
	"kicker": {"status": "ENFORCED", "cr": "702.33", "note": "Optional extra cost when casting; if it was kicked effects are read."},
	"multikicker": {"status": "ENFORCED", "cr": "702.33c", "note": "Optional extra cost, paid 1 to 3 times from the cast menu."},
	"cycling": {"status": "ENFORCED", "cr": "702.29", "note": "Pay the cost and discard this card from hand: draw a card (special action on the hand card)."},
	"landcycling": {"status": "ENFORCED", "cr": "702.29", "note": "Pay the cost and discard this card: search for a land of that type."},
	"typecycling": {"status": "ENFORCED", "cr": "702.29e", "note": "Plainscycling, Dinosaurcycling ...: discard it to search for a card of that type."},
	"fight": {"status": "READ", "cr": "701.14", "note": "Each deals damage equal to its power to the other."},
	"flashback": {"status": "ENFORCED", "cr": "702.34", "note": "Cast from the graveyard for its flashback cost; exiled afterwards."},
	"crew": {"status": "ENFORCED", "cr": "702.122", "note": "Tap untapped creatures with total power N: this Vehicle becomes an artifact creature until end of turn."},
	"convoke": {"status": "ENFORCED", "cr": "702.51", "note": "Tapping creatures pays for the spell when mana runs short."},
	"hideaway": {"status": "READ", "cr": "702.75", "note": "Exile one of the top cards face down; the payoff plays it free."},
	"evolve": {"status": "READ", "cr": "702.100", "note": "+1/+1 counter when a bigger creature enters."},
	"undying": {"status": "READ", "cr": "702.93", "note": "Returns with a +1/+1 counter if it had none."},
	"persist": {"status": "READ", "cr": "702.79", "note": "Returns with a -1/-1 counter if it had none."},
	"cascade": {"status": "READ", "cr": "702.85", "note": "Cast a cheaper card from the top of your library for free."},
	"annihilator": {"status": "READ", "cr": "702.86", "note": "Defending player sacrifices permanents when it attacks."},
	"exalted": {"status": "READ", "cr": "702.83", "note": "A creature attacking alone gets +1/+1."},
	"extort": {"status": "READ", "cr": "702.101", "note": "Whenever you cast a spell, you may pay {W/B}: drain each opponent for 1."},
	"fabricate": {"status": "READ", "cr": "702.123", "note": "Counters or a Servo token on entering."},
	"proliferate": {"status": "READ", "cr": "701.34", "note": "Add one more counter of each kind already on permanents or players."},
	"explore": {"status": "READ", "cr": "701.44", "note": "Reveal the top card: land to hand, else +1/+1 counter."},
	"discover": {"status": "READ", "cr": "701.57", "note": "Exile until a cheaper nonland card: permanents enter, spells go to hand (no free cast yet)."},
	"investigate": {"status": "READ", "cr": "701.16", "note": "Create a Clue token."},
	"the monarch": {"status": "READ", "cr": "724", "note": "Draw at your end step."},
	"changeling": {"status": "ENFORCED", "cr": "702.73", "note": "Is every creature type."},
	"riot": {"status": "ENFORCED", "cr": "702.136", "note": "Enters with a +1/+1 counter or haste, your choice."},
	"myriad": {"status": "NONE", "cr": "702.116", "note": "Only matters with three or more players; in a duel it does nothing."},
	"enlist": {"status": "READ", "cr": "702.154", "note": "Tap a non-attacking creature when attacking to add its power."},
	"affinity": {"status": "ENFORCED", "cr": "702.41", "note": "Costs {1} less for each of the named permanent."},
	"toxic": {"status": "ENFORCED", "cr": "702.164", "note": "Combat damage gives poison counters."},
	"fear": {"status": "ENFORCED", "cr": "702.36", "note": "Can be blocked only by artifact and/or black creatures."},
	"intimidate": {"status": "ENFORCED", "cr": "702.13", "note": "Can be blocked only by artifact creatures and creatures sharing a color."},
	"skulk": {"status": "ENFORCED", "cr": "702.118", "note": "Can't be blocked by creatures with greater power."},
	"surveil": {"status": "READ", "cr": "701.46", "note": "Look at the top cards; lands you don't need go to the graveyard."},
	"mill": {"status": "READ", "cr": "701.17", "note": "Put the top cards of a library into its graveyard."},
	"scry": {"status": "READ", "cr": "701.22", "note": "Look at the top cards of your library."},
	"landfall": {"status": "READ", "cr": "207.2c", "note": "Ability word: triggers when a land enters under your control."},
	"battle cry": {"status": "READ", "cr": "702.91", "note": "Other attackers get +1/+0."},
	"bushido": {"status": "READ", "cr": "702.45", "note": "Gets +N/+N whenever it blocks or becomes blocked."},
	"flanking": {"status": "READ", "cr": "702.25", "note": "Blockers without flanking get -1/-1 when it becomes blocked."},
	"banding": {"status": "ENFORCED", "cr": "702.22", "note": "Attacking bands fight as one; damage dealt to a band is assigned automatically by its controller."},
	"rampage": {"status": "READ", "cr": "702.23", "note": "+N/+N for each blocker beyond the first."},
	"horsemanship": {"status": "ENFORCED", "cr": "702.31", "note": "Can be blocked only by creatures with horsemanship."},
	"shadow": {"status": "ENFORCED", "cr": "702.28", "note": "Blocks and is blocked only by shadow creatures."},
	"unblockable": {"status": "ENFORCED", "cr": "509.1b", "note": "Can't be blocked."},
	"afterlife": {"status": "READ", "cr": "702.135", "note": "Creates Spirit tokens when it dies."},
	"amass": {"status": "READ", "cr": "701.47", "note": "Army token with +1/+1 counters."},
	"bloodthirst": {"status": "READ", "cr": "702.54", "note": "Enters with +1/+1 counters if an opponent was dealt damage this turn."},
	"dash": {"status": "ENFORCED", "cr": "702.109", "note": "Alternative cost: haste, returns to hand at end of turn (cast menu)."},
	"delve": {"status": "ENFORCED", "cr": "702.66", "note": "Exile cards from your graveyard to pay generic mana when short."},
	"emerge": {"status": "ENFORCED", "cr": "702.119", "note": "Alternative cost: sacrifice a creature, cost reduced by its mana value (cast menu)."},
	"escape": {"status": "ENFORCED", "cr": "702.138", "note": "Cast from the graveyard by exiling other cards (cast menu)."},
	"madness": {"status": "ENFORCED", "cr": "702.35", "note": "A discarded card is exiled; you may cast it for its madness cost."},
	"morph": {"status": "ENFORCED", "cr": "702.37", "note": "Cast face down as a 2/2 for {3}; turn it up for its morph cost."},
	"megamorph": {"status": "ENFORCED", "cr": "702.37b", "note": "Morph, and it gets a +1/+1 counter when turned up."},
	"disguise": {"status": "ENFORCED", "cr": "702.168", "note": "Cast face down as a 2/2 with ward {2} for {3}; turn it up for its disguise cost."},
	"ninjutsu": {"status": "ENFORCED", "cr": "702.49", "note": "Return an unblocked attacker: put this onto the battlefield tapped and attacking."},
	"prowl": {"status": "ENFORCED", "cr": "702.76", "note": "Alternative cost if a creature sharing a type dealt combat damage to a player this turn."},
	"rebound": {"status": "ENFORCED", "cr": "702.88", "note": "Cast again free from exile at your next upkeep."},
	"retrace": {"status": "ENFORCED", "cr": "702.81", "note": "Cast from the graveyard by discarding a land card."},
	"suspend": {"status": "ENFORCED", "cr": "702.62", "note": "Exile with time counters; cast free (with haste) when the last is removed."},
	"vanishing": {"status": "READ", "cr": "702.63", "note": "Time counters; sacrificed when the last is removed."},
	"cumulative upkeep": {"status": "READ", "cr": "702.24", "note": "Pay more each upkeep (age counters) or sacrifice."},
	"echo": {"status": "READ", "cr": "702.30", "note": "Pay the echo cost next upkeep or sacrifice."},
	"fading": {"status": "READ", "cr": "702.32", "note": "Fade counters; sacrificed when none remain at upkeep."},
	"phasing": {"status": "ENFORCED", "cr": "702.26", "note": "Phases out and in on its controller untap steps."},
	"miracle": {"status": "ENFORCED", "cr": "702.94", "note": "Offered when drawn as the first card of the turn."},
	"renown": {"status": "READ", "cr": "702.112", "note": "+1/+1 counters on first combat damage to a player."},
	"adapt": {"status": "READ", "cr": "701.46", "note": "Put N +1/+1 counters if it has none."},
	"bolster": {"status": "READ", "cr": "701.39", "note": "Counters on the weakest creature."},
	"populate": {"status": "READ", "cr": "701.36", "note": "Copy a creature token."},
	"connive": {"status": "READ", "cr": "701.50", "note": "Draw then discard; a nonland discard adds a +1/+1 counter."},
	"learn": {"status": "READ", "cr": "701.48", "note": "Rummage (no sideboard to fetch a Lesson from)."},
	"incubate": {"status": "READ", "cr": "701.53", "note": "Incubator token that transforms for {2}."},
	"support": {"status": "READ", "cr": "701.41", "note": "+1/+1 counters on up to N other creatures you control."},
	"manifest": {"status": "READ", "cr": "701.40", "note": "Top card of your library face down as a 2/2."},
	"cloak": {"status": "READ", "cr": "701.58", "note": "Face-down 2/2 with ward {2}."},
	"suspect": {"status": "READ", "cr": "701.60", "note": "Menace and cannot block."},
	"goad": {"status": "READ", "cr": "701.15", "note": "Must attack each combat if able."},
	"fateseal": {"status": "READ", "cr": "701.29", "note": "Look at an opponent top cards and bottom any."},
	"vigilance": {"status": "ENFORCED", "cr": "702.20", "note": "Attacking doesn't cause it to tap."},
	"infect": {"status": "ENFORCED", "cr": "702.90", "note": "Damage as -1/-1 counters and poison."},
	"living weapon": {"status": "READ", "cr": "702.92", "note": "Enters with a 0/0 black Phyrexian Germ token and attaches to it."},
	"dethrone": {"status": "READ", "cr": "702.105", "note": "+1/+1 counter when it attacks the player with the most life (or tied)."},
	"encore": {"status": "ENFORCED", "cr": "702.141", "note": "From the graveyard: exile it for token copies that attack each opponent with haste, sacrificed at the end step."},
	"eternalize": {"status": "ENFORCED", "cr": "702.129", "note": "From the graveyard: exile it for a 4/4 black Zombie token copy with no mana cost."},
	"embalm": {"status": "ENFORCED", "cr": "702.128", "note": "From the graveyard: exile it for a white Zombie token copy with no mana cost."},
	"escalate": {"status": "ENFORCED", "cr": "702.120", "note": "Pay the escalate cost for each mode beyond the first (cast menu)."},
	"demonstrate": {"status": "READ", "cr": "702.144", "note": "When cast you may copy it; if you do, an opponent also copies it."},
	"gift": {"status": "ENFORCED", "cr": "702.174", "note": "Promise an opponent a gift as you cast it (cast menu); \"if the gift was promised\" effects then happen."},
	"impending": {"status": "ENFORCED", "cr": "702.176", "note": "Alternative cost: enters with N time counters and isn't a creature until the last is removed at your end step."},
	"improvise": {"status": "ENFORCED", "cr": "702.126", "note": "Tapping artifacts pays for generic mana when mana runs short."},
	"read ahead": {"status": "ENFORCED", "cr": "702.155", "note": "A Saga enters with the chapter you choose; earlier chapters don't trigger."},
	"enchant": {"status": "ENFORCED", "cr": "702.5", "note": "An Aura spell targets what it will enchant and enters attached to it."},
	"protection": {"status": "ENFORCED", "cr": "702.16", "note": "From colors: can't be damaged, blocked or targeted by that color."},
	"behold": {"status": "READ", "cr": "701.4", "note": "Choose a permanent you control or reveal a card from your hand with that quality."},
	"clash": {"status": "READ", "cr": "701.23", "note": "Each player reveals their top card and keeps it on top or bottoms it; the higher mana value wins."},
	"empower": {"status": "READ", "cr": "701.68", "note": "Loyalty counters on your Jace token (made first if you have none)."},
	"double": {"status": "READ", "cr": "701.10", "note": "Double power and toughness until end of turn."},
	"eminence": {"status": "READ", "cr": "207.2c", "note": "Ability word: also works while the commander is in the command zone."},
	"celebration": {"status": "READ", "cr": "207.2c", "note": "Ability word: two or more nonland permanents entered under your control this turn."},
	"corrupted": {"status": "READ", "cr": "207.2c", "note": "Ability word: an opponent has three or more poison counters."},
	"imprint": {"status": "READ", "cr": "207.2c", "note": "Ability word: the card exiled with this permanent."},
	"pack tactics": {"status": "READ", "cr": "207.2c", "note": "Ability word: you attacked with total power 6 or greater this combat."},
	"probing telepathy": {"status": "READ", "cr": "207.2c", "note": "Copies enter triggers of creatures entering under an opponent's control."},
	"lieutenant": {"status": "READ", "cr": "207.2c", "note": "Ability word: you control your commander."},
	"ferocious": {"status": "READ", "cr": "207.2c", "note": "Ability word: you control a creature with power 4 or greater."},
	"formidable": {"status": "READ", "cr": "207.2c", "note": "Ability word: creatures you control have total power 8 or greater."},
	"enrage": {"status": "READ", "cr": "207.2c", "note": "Ability word: whenever this creature is dealt damage."},
	"loyalty": {"status": "ENFORCED", "cr": "606", "note": "Planeswalker loyalty abilities: once per turn, as a sorcery; damage removes loyalty."},
	"saga": {"status": "ENFORCED", "cr": "714", "note": "Lore counters each precombat main phase trigger chapters; sacrificed after the last."},
	"activate": {"status": "NONE", "cr": "701.2", "note": "Activating abilities is how the engine uses them."},
	"attach": {"status": "READ", "cr": "701.3", "note": "Equip, Auras, fortify and reconfigure attach permanents."},
	"cast": {"status": "NONE", "cr": "701.5", "note": "Casting spells."},
	"counter": {"status": "READ", "cr": "701.6", "note": "Counter target spell or ability."},
	"create": {"status": "READ", "cr": "701.7", "note": "Creating tokens."},
	"destroy": {"status": "READ", "cr": "701.8", "note": "Destroy (regeneration and indestructible apply)."},
	"discard": {"status": "READ", "cr": "701.9", "note": "Discard cards from hand."},
	"triple": {"status": "READ", "cr": "701.11", "note": "Triple power and/or toughness until end of turn."},
	"exchange": {"status": "READ", "cr": "701.12", "note": "Exchange control of permanents or life totals."},
	"exile": {"status": "READ", "cr": "701.13", "note": "Exile objects."},
	"play": {"status": "NONE", "cr": "701.18", "note": "Play lands and cast spells."},
	"regenerate": {"status": "READ", "cr": "701.19", "note": "A regeneration shield: the next destruction taps it, removes damage and takes it out of combat instead."},
	"reveal": {"status": "NONE", "cr": "701.20", "note": "Revealing cards (shown in History)."},
	"sacrifice": {"status": "READ", "cr": "701.21", "note": "Sacrifice permanents."},
	"search": {"status": "READ", "cr": "701.23", "note": "Search a library."},
	"shuffle": {"status": "READ", "cr": "701.24", "note": "Shuffle a library."},
	"tap": {"status": "READ", "cr": "701.26", "note": "Tap and untap permanents."},
	"untap": {"status": "READ", "cr": "701.26", "note": "Tap and untap permanents."},
	"transform": {"status": "READ", "cr": "701.27", "note": "Double-faced permanents turn to their other face."},
	"convert": {"status": "READ", "cr": "701.28", "note": "Like transform, for converting double-faced cards."},
	"planeswalk": {"status": "NONE", "cr": "701.31", "note": "Planechase only; a Commander duel has no planar deck."},
	"set in motion": {"status": "NONE", "cr": "701.32", "note": "Archenemy only."},
	"abandon": {"status": "NONE", "cr": "701.33", "note": "Archenemy only."},
	"detain": {"status": "READ", "cr": "701.35", "note": "Until your next turn it can't attack or block and its activated abilities can't be activated."},
	"monstrosity": {"status": "READ", "cr": "701.37", "note": "If it isn't monstrous, N +1/+1 counters and it becomes monstrous."},
	"vote": {"status": "READ", "cr": "701.38", "note": "Each player votes; the table asks you for your vote."},
	"meld": {"status": "READ", "cr": "701.42", "note": "Exile the meld pair and put the melded card onto the battlefield."},
	"exert": {"status": "READ", "cr": "701.43", "note": "It won't untap during your next untap step; asked as it attacks."},
	"assemble": {"status": "NONE", "cr": "701.45", "note": "Unstable Contraptions are not part of these rules."},
	"venture into the dungeon": {"status": "READ", "cr": "701.49", "note": "Move your venture marker through a dungeon; room abilities trigger."},
	"open an attraction": {"status": "NONE", "cr": "701.51", "note": "Needs an Attraction deck, which a Commander duel doesn't have."},
	"roll to visit your attractions": {"status": "NONE", "cr": "701.52", "note": "Needs Attractions."},
	"the ring tempts you": {"status": "READ", "cr": "701.54", "note": "Choose your Ring-bearer; The Ring emblem grows its abilities."},
	"face a villainous choice": {"status": "READ", "cr": "701.55", "note": "The player chooses one of the two options."},
	"time travel": {"status": "READ", "cr": "701.56", "note": "Add or remove a time counter on each chosen permanent or suspended card."},
	"collect evidence": {"status": "ENFORCED", "cr": "701.59", "note": "Exile cards with total mana value N or more from your graveyard (cast menu)."},
	"forage": {"status": "READ", "cr": "701.61", "note": "Exile three cards from your graveyard or sacrifice a Food."},
	"manifest dread": {"status": "READ", "cr": "701.62", "note": "Look at the top two cards, manifest one, the other goes to the graveyard."},
	"endure": {"status": "READ", "cr": "701.63", "note": "Put N +1/+1 counters on it or create an N/N white Spirit token."},
	"harness": {"status": "READ", "cr": "701.64", "note": "It becomes harnessed; its ∞ abilities work."},
	"airbend": {"status": "READ", "cr": "701.65", "note": "Exile it; its owner may cast it for {2}."},
	"earthbend": {"status": "READ", "cr": "701.66", "note": "Target land you control becomes a 0/0 haste creature with N +1/+1 counters; it returns if it dies."},
	"waterbend": {"status": "ENFORCED", "cr": "701.67", "note": "Waterbend {N} in an ability cost or an additional cost: artifacts and creatures you control are tapped for the generic mana your lands can't pay (chosen automatically); {X} forms and \"unless you waterbend\" are not read."},
	"blight": {"status": "READ", "cr": "701.68", "note": "Put N -1/-1 counters on a creature you control."},
	"heal": {"status": "READ", "cr": "701.69", "note": "Remove marked damage."},
	"recruit": {"status": "READ", "cr": "701.70", "note": "Draw, then discard; a nonland discard makes a 1/1 Human Soldier."},
	"empower jace": {"status": "READ", "cr": "701.71", "note": "Loyalty counters on your Jace token (made first if you have none)."},
	"landwalk": {"status": "ENFORCED", "cr": "702.14", "note": "Can't be blocked while the defending player controls a land of that kind."},
	"buyback": {"status": "ENFORCED", "cr": "702.27", "note": "Pay the buyback cost and the spell returns to your hand as it resolves (cast menu)."},
	"amplify": {"status": "READ", "cr": "702.38", "note": "Reveal cards sharing a creature type as it enters: N +1/+1 counters for each."},
	"provoke": {"status": "READ", "cr": "702.39", "note": "When it attacks, target creature untaps and must block it if able."},
	"storm": {"status": "READ", "cr": "702.40", "note": "Copy it for each other spell cast before it this turn."},
	"entwine": {"status": "ENFORCED", "cr": "702.42", "note": "Pay the entwine cost to choose all modes (cast menu)."},
	"modular": {"status": "READ", "cr": "702.43", "note": "Enters with N +1/+1 counters; when it dies you may move them to an artifact creature."},
	"sunburst": {"status": "READ", "cr": "702.44", "note": "+1/+1 or charge counters for each color of mana spent to cast it."},
	"soulshift": {"status": "READ", "cr": "702.46", "note": "When it dies, return a Spirit card with mana value N or less from your graveyard."},
	"splice": {"status": "ENFORCED", "cr": "702.47", "note": "Reveal it from your hand to add its effects to an Arcane spell (cast menu)."},
	"offering": {"status": "ENFORCED", "cr": "702.48", "note": "Cast it any time you could cast an instant by sacrificing a creature of that type for its cost."},
	"epic": {"status": "READ", "cr": "702.50", "note": "For the rest of the game you can't cast spells; it's copied each upkeep."},
	"dredge": {"status": "ENFORCED", "cr": "702.52", "note": "Asked in place of each draw (the draw step and draw effects): mill N and return it to hand, or draw normally."},
	"transmute": {"status": "ENFORCED", "cr": "702.53", "note": "Discard it: search for a card with the same mana value (sorcery speed)."},
	"haunt": {"status": "READ", "cr": "702.55", "note": "Exiled haunting a creature; its effect happens again when that creature dies."},
	"replicate": {"status": "ENFORCED", "cr": "702.56", "note": "Pay the replicate cost any number of times for that many copies (cast menu)."},
	"forecast": {"status": "ENFORCED", "cr": "702.57", "note": "During your upkeep, reveal it from your hand to use its forecast ability once."},
	"graft": {"status": "READ", "cr": "702.58", "note": "Enters with N counters; may move one onto each creature that enters."},
	"recover": {"status": "ENFORCED", "cr": "702.59", "note": "When a creature goes to your graveyard, pay to return this card to hand, or exile it."},
	"ripple": {"status": "READ", "cr": "702.60", "note": "Reveal the top N cards; cast cards with the same name free."},
	"split second": {"status": "ENFORCED", "cr": "702.61", "note": "While it's on the stack, players can't cast spells or activate non-mana abilities."},
	"absorb": {"status": "ENFORCED", "cr": "702.64", "note": "Prevent N damage from each source."},
	"aura swap": {"status": "ENFORCED", "cr": "702.65", "note": "Exchange this Aura with an Aura card in your hand."},
	"fortify": {"status": "READ", "cr": "702.67", "note": "Attach this Fortification to a land you control (sorcery speed)."},
	"frenzy": {"status": "READ", "cr": "702.68", "note": "+N/+0 when it attacks and isn't blocked."},
	"gravestorm": {"status": "READ", "cr": "702.69", "note": "Copy it for each permanent put into a graveyard from the battlefield this turn."},
	"poisonous": {"status": "READ", "cr": "702.70", "note": "Combat damage to a player gives N poison counters."},
	"transfigure": {"status": "ENFORCED", "cr": "702.71", "note": "Sacrifice it: search for a creature with the same mana value (sorcery speed)."},
	"champion": {"status": "READ", "cr": "702.72", "note": "As it enters, exile another permanent of that type you control or sacrifice it; it returns when this leaves."},
	"evoke": {"status": "ENFORCED", "cr": "702.74", "note": "Alternative cost; sacrificed as it enters (cast menu)."},
	"reinforce": {"status": "ENFORCED", "cr": "702.77", "note": "Discard it: put N +1/+1 counters on target creature (instant speed)."},
	"conspire": {"status": "ENFORCED", "cr": "702.78", "note": "Tap two creatures that share a color with it to copy it (cast menu)."},
	"wither": {"status": "ENFORCED", "cr": "702.80", "note": "Damage to creatures is -1/-1 counters."},
	"devour": {"status": "READ", "cr": "702.82", "note": "As it enters, sacrifice creatures for N +1/+1 counters each."},
	"unearth": {"status": "ENFORCED", "cr": "702.84", "note": "From the graveyard with haste; exiled at the end step or if it would leave."},
	"level up": {"status": "ENFORCED", "cr": "702.87", "note": "Level counters (sorcery speed); its level bands set power, toughness and abilities."},
	"umbra armor": {"status": "ENFORCED", "cr": "702.89", "note": "If enchanted permanent would be destroyed, remove its damage and destroy this Aura instead."},
	"totem armor": {"status": "ENFORCED", "cr": "702.89", "note": "Old name of umbra armor."},
	"soulbond": {"status": "READ", "cr": "702.95", "note": "Pair with another unpaired creature; both get the paired bonus."},
	"overload": {"status": "ENFORCED", "cr": "702.96", "note": "Alternative cost: \"target\" becomes \"each\" (cast menu)."},
	"scavenge": {"status": "ENFORCED", "cr": "702.97", "note": "Exile it from your graveyard: +1/+1 counters equal to its power on target creature (sorcery speed)."},
	"unleash": {"status": "READ", "cr": "702.98", "note": "May enter with a +1/+1 counter; it can't block while it has one."},
	"cipher": {"status": "READ", "cr": "702.99", "note": "Encode it on a creature; whenever that creature deals combat damage to a player, cast a copy."},
	"fuse": {"status": "ENFORCED", "cr": "702.102", "note": "Cast both halves of a split card from your hand (cast menu)."},
	"bestow": {"status": "ENFORCED", "cr": "702.103", "note": "Cast it as an Aura for its bestow cost; it becomes a creature again when unattached."},
	"tribute": {"status": "READ", "cr": "702.104", "note": "An opponent may put N +1/+1 counters on it as it enters."},
	"hidden agenda": {"status": "NONE", "cr": "702.106", "note": "Conspiracy draft only."},
	"outlast": {"status": "ENFORCED", "cr": "702.107", "note": "Pay and tap: +1/+1 counter (sorcery speed)."},
	"exploit": {"status": "READ", "cr": "702.110", "note": "When it enters you may sacrifice a creature; \"when it exploits\" abilities trigger."},
	"awaken": {"status": "ENFORCED", "cr": "702.113", "note": "Alternative cost that also makes a land a 0/0 haste Elemental with N +1/+1 counters."},
	"ingest": {"status": "READ", "cr": "702.115", "note": "Combat damage to a player exiles the top card of their library."},
	"surge": {"status": "ENFORCED", "cr": "702.117", "note": "Alternative cost if you cast another spell this turn."},
	"melee": {"status": "READ", "cr": "702.121", "note": "+1/+1 for each opponent you attacked this combat."},
	"undaunted": {"status": "ENFORCED", "cr": "702.125", "note": "Costs {1} less for each opponent."},
	"aftermath": {"status": "ENFORCED", "cr": "702.127", "note": "The second half is cast only from your graveyard, then exiled."},
	"afflict": {"status": "READ", "cr": "702.130", "note": "When it becomes blocked, the defending player loses N life."},
	"assist": {"status": "NONE", "cr": "702.132", "note": "Another player helps pay; a duel has no teammate."},
	"jump-start": {"status": "ENFORCED", "cr": "702.133", "note": "Cast it from your graveyard by also discarding a card; exiled afterwards."},
	"mentor": {"status": "READ", "cr": "702.134", "note": "When it attacks, +1/+1 counter on target attacking creature with lesser power."},
	"spectacle": {"status": "ENFORCED", "cr": "702.137", "note": "Alternative cost if an opponent lost life this turn."},
	"companion": {"status": "NONE", "cr": "702.139", "note": "Deck building condition; companions aren't supported in imported decks."},
	"mutate": {"status": "ENFORCED", "cr": "702.140", "note": "Cast it onto a non-Human creature you own; the merged creature has every ability."},
	"boast": {"status": "ENFORCED", "cr": "702.142", "note": "Activate only if it attacked this turn, once each turn."},
	"foretell": {"status": "ENFORCED", "cr": "702.143", "note": "Pay {2} to exile it face down; cast it on a later turn for its foretell cost."},
	"daybound": {"status": "ENFORCED", "cr": "702.145", "note": "Day and night: transforms when it becomes night."},
	"nightbound": {"status": "ENFORCED", "cr": "702.145", "note": "Day and night: transforms when it becomes day."},
	"disturb": {"status": "ENFORCED", "cr": "702.146", "note": "Cast it transformed from your graveyard; exiled if it would go to a graveyard."},
	"decayed": {"status": "ENFORCED", "cr": "702.147", "note": "Can't block; when it attacks, sacrifice it at end of combat."},
	"cleave": {"status": "ENFORCED", "cr": "702.148", "note": "Alternative cost: the words in square brackets are removed."},
	"training": {"status": "READ", "cr": "702.149", "note": "When it attacks with a creature with greater power, +1/+1 counter."},
	"compleated": {"status": "ENFORCED", "cr": "702.150", "note": "Enters with two fewer loyalty counters for each Phyrexian symbol paid with life."},
	"reconfigure": {"status": "ENFORCED", "cr": "702.151", "note": "Attach to or unattach from a creature you control (sorcery speed); not a creature while attached."},
	"blitz": {"status": "ENFORCED", "cr": "702.152", "note": "Alternative cost: haste, draws a card when it dies, sacrificed at the end step."},
	"casualty": {"status": "ENFORCED", "cr": "702.153", "note": "Sacrifice a creature with power N or more as you cast it to copy it."},
	"ravenous": {"status": "READ", "cr": "702.156", "note": "Enters with X +1/+1 counters; draw a card if X is 5 or more."},
	"squad": {"status": "ENFORCED", "cr": "702.157", "note": "Pay the squad cost any number of times for token copies as it enters."},
	"space sculptor": {"status": "ENFORCED", "cr": "702.158", "note": "Creatures get sectors (alpha, beta, gamma)."},
	"visit": {"status": "NONE", "cr": "702.159", "note": "Attractions only."},
	"prototype": {"status": "ENFORCED", "cr": "702.160", "note": "Cast it with the smaller cost and power/toughness."},
	"living metal": {"status": "ENFORCED", "cr": "702.161", "note": "An artifact creature during your turn."},
	"more than meets the eye": {"status": "ENFORCED", "cr": "702.162", "note": "Cast it converted for this cost."},
	"for mirrodin!": {"status": "READ", "cr": "702.163", "note": "Creates a 2/2 red Rebel and attaches to it."},
	"backup": {"status": "READ", "cr": "702.165", "note": "N +1/+1 counters on target creature; another creature gains its other abilities until end of turn."},
	"bargain": {"status": "ENFORCED", "cr": "702.166", "note": "Sacrifice an artifact, enchantment or token as you cast it (cast menu)."},
	"craft": {"status": "ENFORCED", "cr": "702.167", "note": "Exile it and the materials: it returns transformed (sorcery speed)."},
	"solved": {"status": "ENFORCED", "cr": "702.169", "note": "A Case's solved abilities work once its to-solve condition was met at your end step."},
	"plot": {"status": "ENFORCED", "cr": "702.170", "note": "Exile it from your hand for its plot cost; cast it free on a later turn as a sorcery."},
	"saddle": {"status": "ENFORCED", "cr": "702.171", "note": "Tap creatures with total power N: saddled until end of turn (sorcery speed)."},
	"spree": {"status": "ENFORCED", "cr": "702.172", "note": "Choose any number of modes, paying each mode's extra cost (cast menu)."},
	"freerunning": {"status": "ENFORCED", "cr": "702.173", "note": "Alternative cost if an Assassin or your commander dealt combat damage to a player this turn."},
	"offspring": {"status": "ENFORCED", "cr": "702.175", "note": "Pay extra for a 1/1 token copy as it enters."},
	"exhaust": {"status": "ENFORCED", "cr": "702.177", "note": "The ability can be activated only once."},
	"max speed": {"status": "ENFORCED", "cr": "702.178", "note": "Works while your speed is 4."},
	"start your engines!": {"status": "ENFORCED", "cr": "702.179", "note": "You get speed 1; it rises once each turn when an opponent loses life during your turn."},
	"harmonize": {"status": "ENFORCED", "cr": "702.180", "note": "Cast it from your graveyard, tapping a creature to reduce the cost by its power; exiled afterwards."},
	"mobilize": {"status": "READ", "cr": "702.181", "note": "When it attacks, N 1/1 red Warriors enter tapped and attacking; sacrificed at the end step."},
	"job select": {"status": "READ", "cr": "702.182", "note": "Creates a 1/1 Hero and attaches to it."},
	"tiered": {"status": "ENFORCED", "cr": "702.183", "note": "Choose one mode and pay its extra cost (cast menu)."},
	"station": {"status": "ENFORCED", "cr": "702.184", "note": "Tap another creature: charge counters equal to its power (sorcery speed)."},
	"warp": {"status": "ENFORCED", "cr": "702.185", "note": "Cast it for its warp cost; exiled at the end step and castable later from exile."},
	"infinity": {"status": "ENFORCED", "cr": "702.186", "note": "∞ abilities work while it is harnessed."},
	"mayhem": {"status": "ENFORCED", "cr": "702.187", "note": "If you discarded it this turn, cast it from your graveyard for its mayhem cost."},
	"web-slinging": {"status": "ENFORCED", "cr": "702.188", "note": "Alternative cost: also return a tapped creature you control to its owner's hand."},
	"firebending": {"status": "READ", "cr": "702.189", "note": "When it attacks, add N {R} that lasts until end of combat."},
	"sneak": {"status": "ENFORCED", "cr": "702.190", "note": "In the declare blockers step, return an unblocked attacker to cast it entering tapped and attacking."},
	"increment": {"status": "READ", "cr": "702.191", "note": "When you spend more mana on a spell than its power or toughness, +1/+1 counter."},
	"paradigm": {"status": "READ", "cr": "702.192", "note": "After it first resolves, you may cast a copy at each of your precombat main phases."},
	"power-up": {"status": "ENFORCED", "cr": "702.193", "note": "Once only; cheaper by its mana cost the turn it entered."},
	"teamwork": {"status": "ENFORCED", "cr": "702.194", "note": "Tap creatures with total power N as you cast it (cast menu)."},
	"storied": {"status": "ENFORCED", "cr": "702.195", "note": "Three or more artifacts, Sagas and legendaries give you an enduring story."},
}


## Entries that are never a whole keyword line on their own: keyword actions are effect sentences ("Goad target
## creature.") and ability words label an ability whose text still has to be read ("Eminence — As long as ...").
const NOT_LINES := ["goad", "suspect", "support", "manifest", "cloak", "connive", "adapt", "learn", "incubate", "fateseal",
	"explore", "proliferate", "populate", "amass", "bolster", "behold", "clash", "empower", "double", "eminence",
	"celebration", "corrupted", "imprint", "pack tactics", "probing telepathy", "lieutenant", "ferocious", "formidable",
	"enrage", "landfall", "loyalty", "saga", "protection", "activate", "attach", "cast", "counter", "create", "destroy",
	"discard", "triple", "exchange", "exile", "play", "regenerate", "reveal", "sacrifice", "search", "shuffle", "tap",
	"untap", "transform", "convert", "planeswalk", "set in motion", "abandon", "detain", "monstrosity", "vote", "meld",
	"exert", "assemble", "venture into the dungeon", "open an attraction", "roll to visit your attractions",
	"the ring tempts you", "face a villainous choice", "time travel", "collect evidence", "forage", "manifest dread",
	"endure", "harness", "airbend", "earthbend", "waterbend", "blight", "heal", "recruit", "empower jace", "fight",
	"landwalk", "solved", "exhaust", "max speed", "power-up", "infinity", "boast", "forecast", "visit"]


## "Ward {2}" -> {"name": "ward", ...entry}; {} when the line doesn't start with a known keyword.
static func lookup(line: String) -> Dictionary:
	var low := line.to_lower().strip_edges()
	var best := ""
	for k in KEYWORDS:
		var key := str(k)
		if low == key or (low.begins_with(key) and key.length() > best.length() and _boundary(low, key.length())):
			best = key
	## Islandwalk, nonbasic landwalk ... are all landwalk (CR 702.14).
	if best == "" and RegEx.create_from_string("^(?:nonbasic |legendary |snow |desert )?(?:plains|island|swamp|mountain|forest|land|desert)walk$").search(low) != null:
		best = "landwalk"
	## "Plainscycling {2}", "Wizardcycling {3}" are all typecycling (CR 702.29e).
	if best == "":
		var cyc := RegEx.create_from_string("^[a-z]+cycling\\b").search(low)
		if cyc != null:
			best = "typecycling"
	if best == "":
		return {}
	var out: Dictionary = (KEYWORDS[best] as Dictionary).duplicate()
	out["name"] = best
	return out


static func _boundary(low: String, n: int) -> bool:
	if low.length() <= n:
		return true
	return low[n] in [" ", "{", "—", ","]


## Whether every comma-separated part of a line is a keyword the engine already handles (or needs none).
static func line_is_handled(line: String) -> bool:
	## "protection from white and from blue" may itself hold commas ("from white, from blue, and from black").
	var low_all := line.to_lower()
	var pi := low_all.find("protection from ")
	var parts: PackedStringArray
	if pi > 0:
		parts = line.substr(0, pi).trim_suffix(" ").trim_suffix(",").split(",")
		parts.append(line.substr(pi))
	else:
		parts = line.split(",")
	for part in parts:
		var e := lookup(str(part))
		if e.is_empty() or not str(e.get("status")) in ["ENFORCED", "READ", "NONE"]:
			return false
		## Keyword *actions* are effect sentences ("Goad target creature."), read by OracleIr, never bare keyword lines.
		if str(e.get("name")) in NOT_LINES:
			return false
		if str(e.get("name")) == "protection from" and not _color_protection(str(part)):
			return false
	return true


static func _color_protection(part: String) -> bool:
	return not protection_colors(part).is_empty()


## "Protection from white and from blue" -> ["W", "U"]; "protection from each color" -> all five.
## [] when the line is not color protection (protection from creatures, from everything ...).
static func protection_colors(line: String) -> Array:
	var low := line.to_lower().strip_edges().trim_suffix(".")
	if not low.begins_with("protection from "):
		return []
	var rest := low.trim_prefix("protection from ")
	if rest == "each color" or rest == "all colors":
		return ["W", "U", "B", "R", "G"]
	var out: Array = []
	var letters := {"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G"}
	for part in rest.replace(", and from ", ",").replace(" and from ", ",").replace(", from ", ",").replace("from ", "").split(","):
		var w := str(part).strip_edges()
		if not letters.has(w):
			return []
		out.append(letters[w])
	return out


## "Ward {1}" -> "Ward {1} (not enforced yet)" for a known but unimplemented keyword, else the line.
static func describe_unread(line: String) -> String:
	var e := lookup(line)
	if not e.is_empty() and str(e.get("status")) == "MISSING":
		return "%s (%s: not enforced yet)" % [line, str(e.get("name"))]
	return line
