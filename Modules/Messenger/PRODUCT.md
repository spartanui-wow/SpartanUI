# Product

<!-- impeccable:product-schema 1 -->

## Platform

native: World of Warcraft addon UI (Lua on FrameXML widgets, Retail 12.x plus the Classic flavors SpartanUI supports). Not web; the Impeccable HTML detector does not apply.

## Users

SpartanUI players who talk to people while they play: friends, guildmates, group members, trade contacts. They are usually mid-activity (questing, in a queue, between pulls) and read or answer in short bursts, often while the game world is moving behind the window.

## Product Purpose

Messenger turns whispers (and any other chat type the player chooses) into instant-messenger style conversations: one window with a conversation list and a chat view, with any conversation able to tear off into its own small window. Success means a player never loses a whisper in a busy chat window, always knows who they are about to send to, and can pick a conversation back up hours or days later.

## Positioning

An upgrade to the SpartanUI chat, built to feel like part of the game rather than a web app pasted over it. It uses the game's own chat colors as its language, so a conversation's kind is recognizable at a glance, and it keeps messages that arrive during combat restrictions instead of dropping them.

## Operating Context

- Ships inside SpartanUI as a module first. The code is kept independent of SpartanUI internals (one host adapter file) so it can later ship as its own `Libs-Messenger` addon.
- Opened from the SpartanUI chat header, a key binding, a slash command, player right-click menus, or a toast.
- WoW 12.0 "chat messaging lockdown" hides message text and sender from addons during some encounters. Channel, message ID and GM flags stay readable.

## Capabilities and Constraints

- Conversation sources are chosen by the player per chat type: whispers, Battle.net whispers, guild, officer, party, raid, instance, say, yell, emote, and numbered channels (Trade, General, custom).
- For each captured type the player decides whether it still shows in the normal chat window; the default is to hide it there.
- Messages that arrive while restricted stay in the normal chat window and are added to Messenger once the restriction lifts.
- Must never touch Blizzard's chat edit box state (taint could block the player's own chat during an encounter).
- No emoji or Unicode symbols (the game cannot render them); icons are drawn textures.
- Lua 5.1 only.

## Brand Commitments

- Lives in the SpartanUI family: dark translucent panels matching the SpartanUI chat skin, flat and square.
- User-facing text at a 6th grade reading level, consequence-focused, no references to other addons.

## Evidence on Hand

No screenshots, testimonials or usage data exist yet. Reference material studied (not copied): two existing whisper managers in `OneDrive\WoW\Examples`.

## Product Principles

1. Color tells you where your words go. The composer always wears the color of the chat you are sending to.
2. Never lose a message. When unsure whether Messenger captured something, leave it in the normal chat too.
3. Stay out of the way in combat: hold alerts, keep capturing, summarize afterwards.
4. Respect the player's setup. Nothing is hidden from the normal chat without a visible way to bring it back.
5. Portable by design. Core code never reaches into SpartanUI; only the host adapter does.
