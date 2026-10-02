# Messenger (IM-style whisper and chat manager)

> Module `Messenger`, `Modules/Messenger/`. Added 2026-09-27. Planned to ship later as its own `Libs-Messenger` addon.

Whispers, Battle.net whispers and any chat type the player picks become conversations in one window (list left, chat right). Any conversation can tear off into its own window.

## Portability rule

Nothing under `Core/`, `UI/` or `Options.lua` may reference `SUI`. Files share state through the addon's private table (`local _, ns = ...; local M = ns.Messenger`), which works the same inside SpartanUI and in a standalone addon. `Host/SpartanUI.lua` is the only adapter: it creates the SUI module, passes a host table to `M:Initialize`, registers options under `/sui > Modules > Messenger`, key bindings (`SUIMESSENGER_*` in the root `Bindings.xml`) and the chat header button.

**To ship standalone:** copy `Core/`, `UI/`, `Options.lua`, `Media/` into `Libs-Messenger/`, write a `Host/Standalone.lua` that calls `M:Initialize({ savedVariable = 'LibsMessengerDB', mediaPath = 'Interface\\AddOns\\Libs-Messenger\\Media\\', logger = LibAT.Logger.RegisterAddon('Libs-Messenger'), OpenOptions = ... })` on ADDON_LOADED and `M:Enable()` on PLAYER_LOGIN, register options with AceConfigDialog, and add the SavedVariables/bindings to its own TOC. For one release keep SpartanUI declaring `SpartanUIMessengerDB` so the standalone addon can copy history out of it on first run.

## Files

| File | Purpose |
|---|---|
| `Core/Namespace.lua` | `M`, message bus (`M:On`/`M:Fire`), multi-owner event frame, `M:Defer` next-frame coalescing |
| `Core/Util.lua` | Secret-value guards, name normalization, time labels, `Split` (link and UTF-8 safe), `Linkify`, raid icons |
| `Core/Config.lua` | `M.Kinds` (every chat type), AceDB defaults, `GetRoute`/`IsCaptured` |
| `Core/Store.lua` | Conversations: people account-wide (`db.global.people`), rooms per character (`db.char.rooms`) |
| `Core/Contacts.lua` | Friend, Battle.net and guild caches for presence, class, level, zone |
| `Core/Router.lua` | Chat events to messages, main-chat filter, restricted-line recovery |
| `Core/Rooms.lua` | Room entries for every captured chat that applies right now, history import |
| `Core/Emoji.lua` | Emoji codes, rendering (links untouched); images come from `host.emojiPath` |
| `Core/Sender.lua` | Sending, splitting, recent-target tracking for "not playing" notices |
| `Core/Messenger.lua` | Lifecycle and public API (`Open`, `OpenWhisper`, `OpenBNet`, `ReplyLast`, `PopOut`) |
| `Core/Integration.lua` | InsertLink post-hook, `Menu.ModifyMenu` player menus, `/messenger` |
| `UI/*` | Theme tokens, widgets, virtualized message log, composer, chat pane, list, deck, pop-outs, toasts, launcher |

## Conversation keys

`c:name-realm` (always lower case, always with realm), `b:battletag`, `r:GUILD` / `r:PARTY` etc, `ch:<channel base name>`. Battle.net conversations store the BattleTag; the `|K` account name token is only shown live because it changes every session.

## Key design decisions

- **Hide only what is stored.** `ShouldHide` (filter) and `OnChatEvent` (capture) share `KeyFor`/`Wanted`, so the main chat hides a line only when Messenger can read and keep it. GM/DEV lines, censored lines and anything secret stay in the main chat.
- **Restricted lines are recovered, not dropped.** Secret lines are queued by `lineID` (NeverSecret) and re-read with `C_ChatInfo.GetChatLineText/SenderName/SenderGUID` once `InChatMessagingLockdown()` is false. They show in the main chat meanwhile. `Store:Add` inserts by time so late lines land in order.
- **Outgoing whispers come from the server echo** (`_INFORM` events), so the log only shows delivered messages.
- **Taint safety.** Shift-click links use a post-hook on `ChatFrameUtil.InsertLink`/`ChatEdit_InsertLink` that inserts into Messenger's own focused box. Player menus get "Message in Messenger" through `Menu.ModifyMenu`. The keys bound to Reply are pointed at Messenger's reply with a temporary override binding.
- **Whisper takeover (the one deliberate exception, user's choice 2026-09-27).** Whispers started in the normal chat box (`/w Name`, clicking a name, the Whisper menu entry) move into Messenger, like WIM. `Core/Integration.lua` post-hooks each chat edit box's `UpdateHeader`; when the box turns into WHISPER/BN_WHISPER with focus, it waits one frame, resets the box's `chatType`/`tellTarget` attributes (and a whisper `stickyType`, which would otherwise bounce every Enter back into Messenger), runs the box's own Escape handler and opens the conversation with the typed text as a draft. This writes Blizzard edit box state from addon code, and `SendChatMessage` is restricted for addon-touched code during chat lockdown, so the normal chat box may refuse to send in some encounters until `/reload`. It never runs while `InChatMessagingLockdown()` is true and is a setting ("Whispers you start in the main chat open in Messenger") the player can turn off. If players report blocked chat in raids, this is the first suspect.
- **Composer color.** The composer label, rule and send icon use `ChatTypeInfo` colors (the player's own chat colors) and ease between them over 150 ms when the conversation changes.
- **Rooms exist before anyone talks.** `Rooms:Sync` creates an entry for each captured chat that applies (Party only in a party, Officer only with officer access, channels only while joined) on routing changes, `GROUP_ROSTER_UPDATE`, `PLAYER_GUILD_UPDATE`, `CHANNEL_UI_UPDATE` and friends. Rooms that stop applying are hidden (`Store:IsVisible`), not deleted.
- **Room history.** New rooms import the guild's server-side stream on clients with communities (`C_Club.GetMessagesBefore`, real timestamps, `CLUB_MESSAGE_HISTORY_RECEIVED` when not downloaded yet) and the lines still held by the chat windows (each history entry keeps `extraData[4]` = event and `extraData[5]` = the original event args, plus `timestamp` = `GetTime()` at arrival). Imports are quiet (`Store:Add(key, msg, true)`: no unread, no alerts) and de-duplicated by sender, text and a 30 s window.
- **Fade while moving** (`UI/Fade.lua`): windows ease to `fadeWhileMoving` (default 0.5) on `PLAYER_STARTED_MOVING`, staying solid under the mouse or while their composer has focus.
- **Emoji** are stored and sent as plain codes and only drawn locally, so other players see whatever their chat shows. The SpartanUI host points `emojiPath` at `images/chatbox/emojis`; a standalone build ships its own copy of those images.
- **Alerts in combat** are held (messages still stored) and summarized in one toast after combat.

## UX additions (2026-09-28, from a comparative audit)

- **Sizes follow the text size.** `Theme.Metrics()` gives row, header, title, composer and search heights from the font size setting; every bar re-applies them on `FONTS_CHANGED`.
- **List sizes** (`settings.listMode`, `Deck:SetListMode`): `full` (236px, two-line rows with picture), `slim` (210px, one dense line per conversation: unread chip, name capped at 45%, latest message, time; no picture, no filter buttons), `icons` (60px column of pictures, 36px rows) and `auto` (full, icons below 640px wide). The title bar list button cycles full, slim, icons; right-click picks a size (including Automatic). Hidden filters reset to All so they cannot hide conversations.
- **Undo, not confirm.** Deleting a conversation or clearing a room acts immediately and shows an Undo toast (`Store:Undo`, session only). Ignoring a player still confirms, because it changes the game's ignore list.
- **Keyboard.** Alt+Up/Down in the composer steps through the list (`Deck:Step`), saving the draft before the arrow key can pull a history line in.
- **Pin.** `settings.window.pinned` locks the deck (`win.locked`, grip hidden), removes it from `UISpecialFrames` (`W.SetEscapeCloses`) and reopens it after a reload from `db.char.deckOpen`.
- **Overlay pop-outs.** Per pop-out `overlay` and `opacity` (saved in `db.char.popouts[key]`); an OnUpdate fades the title bar, composer, grip and edges to 0 when the mouse is away and the composer has no focus.
- **Mentions.** `Router:IsMention` marks group chat lines (`msg.mn`) that say the player's name or `alerts.mentionWords` as a whole word; they get a soft amber wash and use the whisper alert settings.
- **Header name** right-click calls `SetItemRef('player:Name-Realm', ..., 'RightButton')`, which opens the game's own player menu (`FriendsFrame_ShowDropdown`).
- **Naming (2026-10-01).** Players see every group chat (Guild, Party, Say, Trade...) called a "channel": the list filter, alerts and history settings say Channels, and the settings section for numbered channels is "Joined channels". The code keeps "rooms" (`M.Rooms`, `db.char.rooms`, `r:`/`ch:` keys) so saved data never moves.
- **One box for search and new conversations (2026-10-01).** The list's search box is also the "new conversation" box (they sat in the same spot). Typing filters conversations as before, and a "Start a conversation" section under the matches offers people, channels (`Rooms:Choices`, by name or channel number), "Message <text>" and "Join this channel"; anything already in the matches is not offered twice (entries carry `key`). The whisper and join rows only appear when nothing matched or the box was opened with +, so searching old messages stays clean. The + button calls `List:StartNew()`: empty box, focus, channels that are not open yet, and the picture column widens to the slim list while it lasts (`Deck:Layout`). Enter opens the first matching conversation, otherwise starts one with exactly the typed text (`Deck:StartConversation`: a channel by name, a BattleTag, or a whisper; text with spaces and no realm dash is treated as a search). Tab completes the first person or channel. Escape or the clear button leaves new mode. `ConversationList.Create(parent, onSelect, starter)` takes the suggest/pick/start/changed callbacks, so the list itself stays free of Deck code. Picking a channel calls `M:OpenRoom`, which turns that chat on if needed (only that one closed entry comes back, unlike `RoutesChanged`). `Rooms:Join` uses `JoinPermanentChannel(name, nil, DEFAULT_CHAT_FRAME:GetID(), 1)` like `/join`, turns capture on and opens the channel when `CHANNEL_UI_UPDATE` confirms it (10 s window). It never writes the chat frame's `channelList` and refuses during chat lockdown.
- **Nicknames (2026-10-01).** `M:SetAlias(key, text)` / `M:GetAlias(key)`. People's nicknames live in `db.global.aliases` (account-wide, like the conversations), channel nicknames in `db.char.aliases`. `M:GetTitle` returns the nickname first (`M:GetRealTitle` skips it), so the list, header, toasts, pop-outs and composer follow; `M:PersonLabel(full)` gives a player's nickname on channel lines even without a conversation. The header subtitle keeps the real name under a nickname, and search matches both. Set from the list or header menu ("Set a nickname"), or by double-clicking the header name, which becomes an inline box (`Pane:EditNickname`: Enter or clicking away saves, Escape cancels, empty or the real name clears it). Fires `ALIASES_CHANGED` so open logs relabel.
- **Search jump.** Picking a conversation while the list search has text calls `Log:JumpTo(query)`, which pages in older messages if needed and highlights the match for two seconds.

## Testing

A headless LuaJIT harness (mocked WoW API, real AceDB) loads the core without SpartanUI and runs routing, filtering, restriction recovery, sending, rooms, channels, Battle.net, pop-outs, menus, link insertion and every options callback. Nothing replaces an in-game pass:

1. Whisper yourself from an alt: conversation appears, main chat hides it, toast and sound play.
2. Shift-click an item while the composer has focus.
3. Turn on Guild in settings: guild chat moves into Messenger; turn off "Hide from the main chat window" and it shows in both.
4. Pop a conversation out, `/rl`, confirm it comes back in the same place.
5. Enter an encounter with chat restrictions: whispers stay in the main chat, the amber notice shows, lines appear in Messenger after the fight.
6. Battle.net whisper to and from a friend on another game.
7. Right-click a player: "Message in Messenger" opens the conversation.
