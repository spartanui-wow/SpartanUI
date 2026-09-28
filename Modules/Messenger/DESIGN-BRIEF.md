# Messenger surface brief

Scope: the Messenger deck window, its pop-out windows, toasts and first-run notice. Mode: Operate.

Audience and job: a player mid-activity reading and answering whispers and chosen group chats in short bursts. The task is "see what is new, answer the right person, get back to the game". Structure was pinned by the user: one deck (list left, chat right) plus tear-off pop-outs. The visual world is inherited from the SpartanUI chat skin, so no concept roll was run (structure pinned by the brief, world established); the direction below extends it.

## Direction contract

THESIS: Color tells you where your words go. Every conversation wears the game's own chat color for its kind (whisper pink, Battle.net cyan, guild green, party blue, raid orange), taken live from the player's chat color settings. The composer, its send label and the unread badges carry that color, so sending to the wrong place is visibly wrong before Enter. Refuses the category default of one brand accent (indigo/blue) painted on every selection, badge and button.

OWN-WORLD: The SpartanUI chat panel grown into a window. Near-black translucent panes (#0C0D0F at 94%, list pane one step lighter), flat and square, 1px hairlines at 8% white, no rounded bubbles, no gradients. Text warm off-white #E8E6E1, muted #9C9CA2, faint #6B6B70. Class-colored names. Selected row is a low-alpha wash of that conversation's chat color; unread is a solid chip in the same color. One drawn icon set, 2px strokes on a 32px grid, tinted by vertex color.

STORY: The player sees at a glance who is waiting (bold name, colored chip), opens it, reads a Slack-style log grouped by sender with day separators and a "New" divider, and answers from a composer that states "To Thrallsdad" in whisper pink. Group rooms read the same way in their own colors.

FIRST VIEWPORT: 720x460 window. 32px title strip (title, total unread, new, settings, close). Left 236px list: search, filter chips (All, Unread, People, Rooms), 46px rows with 30px round class avatar plus presence dot, name and time on line one, preview and chip on line two. Right: 46px header (avatar, name, "Level 80 Mage - Dornogal", pin, pop-out, more), message log, and a composer bar whose label, 1px top rule and send icon are the chat color. Primary action is Enter in the composer.

FORM: Deck plus pop-outs (user choice 1 of 3). Seed key: none, concept roll skipped because layout was user-pinned and the world is inherited.

Signature interaction: switching conversations recolors the composer rule, label and caret-side send button with a 150 ms color ease, so the change of destination is felt.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## States

- Empty deck: explains what lands here and offers one-click switches for Guild, Party and Raid chat, plus "Start a conversation".
- Empty conversation: "No messages with {name} yet."
- Restricted: amber strip "Some messages are hidden during this fight. They will show up here when it ends."
- Offline / AFK / DND: presence dot on avatar plus a muted system line in the log.
- Muted conversation: dimmed name, grey chip, no sound or toast.
- Pinned: pinned group at top of the list.
