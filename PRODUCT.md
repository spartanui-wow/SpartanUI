# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

(The real product is a World of Warcraft addon drawn by the game's own UI engine. HTML is used only for mockups of in-game surfaces before they are built in Lua.)

## Users

- **First-time installers:** players who just installed SpartanUI and want a good-looking, working screen quickly, then tune details later.
- **Returning players:** players who already use SpartanUI and meet setup again on an alt or a new profile. They often have many characters and may have anywhere from one to a dozen saved profiles, some last used on an old version of the addon. They want to copy or share what they already have, or get through fast.

Both groups matter equally. Setup should adapt to which one it is talking to.

## Product Purpose

SpartanUI replaces the whole World of Warcraft interface: screen art ("looks"), unit frames, action bars, minimap, status bars, and about 25 optional feature modules (auto sell, quest tools, Messenger, tooltips, and more). It runs on every current game client (Retail, WoW Forever, Mists, TBC Anniversary, Classic Era).

Success is a player who finishes setup with a screen they like, every behavior-changing feature they did not want turned off, and the confidence that anything else can be changed later.

## Positioning

One addon sets the whole screen in a single coherent look, and every look can be mixed with another look's frames, windows and bars. Setup is the first impression of that.

## Operating Context

- Setup runs inside the shared "Lib's Setup" window from Libs-AddonTools, which also hosts the setup of the author's other small addons (Lib's DataBar, Farm Assistant, Time Played, Social, Disenchant Assist, Totembar, Keystone Roulette).
- It opens on first login and on a new profile, can be reopened with /setup, and can be skipped.
- Anything that needs a UI reload is staged and applied with one reload at the end.
- Everything in setup is also available in the full settings window (/sui).
- Players run it in a live game, sometimes interrupted by combat (the window waits for combat to end).

## Capabilities and Constraints

- Lua 5.1, WoW widget API only. No emoji or arbitrary Unicode in the game font. No external links that open a browser.
- The window is drawn by a theme "kit" (colors, painted art, button styles) that follows the player's look, or a window look they pick.
- Profiles store the addon version they were last used with (`SUI.DB.Version`), so setup can tell a fresh profile from an old one.
- Card art is 512x256 per look. The three newest looks (Voyager, Grove, Observatory) have painted card art; the older looks use older screenshots.

## Brand Commitments

- Plain words at about a 6th grade reading level. Say what happens to the player's screen, not what an option does technically.
- Never mention other addons by name in player-facing text, except where the player must recognize an installed addon (importing bars from it).
- No em dashes in player-facing text.

## Product Principles

1. A great screen first; details later.
2. Behavior-changing automation (selling, accepting, taking over whispers) is something the player agrees to, not something that happens silently.
3. Respect what the player already set up; never silently overwrite it.
4. Every choice has a recommended answer and an easy way back.
