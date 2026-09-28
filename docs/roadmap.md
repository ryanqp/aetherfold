# Roadmap

Aetherfold is a fan Commander table: a real rules kernel plus a 1v1 screen. The long-term shape is a small **Commander arena** — several players at one table, each seeing only their own hand, with the host running the rules.

## What already plays

- Zones, stack, priority, combat (including blockers and choosing who you attack), mana, and a growing list of spell effects.
- A Talrand bot that reads those effects instead of a hardcoded name list.
- Deck import, a main menu, and a LAN room for up to six players with a ready-up.

## What the arena still needs

1. **One simulation.** The host applies every action and sends each seat a view that hides other players' hands. Clients do not each rerun the game.
2. **A seat for every player.** The table screen still draws two sides. A 3–6 player match needs one play area per living player, from that player's seat.
3. **More of the rules players expect.** Multiple blockers, trample, and the long tail of keyword actions. New cards stay data in `engine/cards/ir/`, not new branches in the UI.
4. **The table as a place.** Life, the stack, graveyards, and the command zone should be readable without guessing. Sound and the menu should match the buttons on the table.

Card names and art stay Wizards of the Coast's. The code in this repo is MIT.
