# E19 — Colour themes

## Summary

The Tradewright windows come in several colour themes, dark and light, and a player can pick their own colours to match the rest of their UI. Whatever is picked, text stays readable.

## Context

- The pack had one fixed dark look: a single colour table in `Tradewright_Theme.lua`, applied once when a frame is built.
- Players run very different UIs. Feedback asked for a choice of background colours (grey, parchment, red, blue) and for own colours beside ready-made ones.

Decisions taken with the user:

- Own colours must not be able to make the window unreadable: the player picks few colours and the rest is worked out from them
- At least one light and one dark theme ship ready-made

## Scope

- F140: ready-made themes, a custom theme from two picked colours, applied without `/reload`

## Out of scope

- Game tooltips, dropdown menus, bag slot art, the minimap button and chat output keep the game's own colours
