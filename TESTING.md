# Apple Reminders — Manual Test Checklist

Run these in order. Each test is independent unless noted.
Prerequisites: Emacs running, `apple-reminders.el` loaded, at least one list exists in Apple Reminders.

---

## 1. Auto-detect default list

**Action:** `M-: (my/apple-reminders--default-list) RET`

**Expected:** Returns the name of your first Apple Reminders list as a string (e.g. `"Inbox"`). No error.

---

## 2. List all lists

**Action:** `C-c r l`

**Expected:** Echo area shows a bullet list of all your Apple Reminders lists.

---

## 3. Dashboard — open

**Action:** `C-c r d`

**Expected:** `*Apple Reminders*` buffer opens. Lists appear as `* ListName` headings, reminders as `** TODO …` subheadings. If no cache yet, it fetches first (brief delay).

---

## 4. Dashboard — refresh

**Setup:** Dashboard is open.

**Action:** Press `g`

**Expected:** "Apple Reminders: refreshing…" appears in echo area, then "Apple Reminders: ready." Buffer re-renders with fresh data from Apple.

---

## 5. Dashboard — complete a reminder

**Setup:** Dashboard open, at least one reminder visible.

**Action:** Move point onto a `** TODO` reminder heading, press `t`

**Expected:**
- Heading changes to `** DONE` immediately.
- Echo area: "Apple Reminders: completed. Press h to show done items."
- In Apple Reminders app, that item is marked complete within a few seconds.

---

## 6. Dashboard — show/hide completed

**Setup:** You just completed a reminder with `t` (test 5).

**Action:** Press `h`

**Expected:** The DONE item you completed appears at the bottom of its list section. Press `h` again — it disappears.

---

## 7. Dashboard — jump to org

**Setup:** Run `C-c r R` first to populate `reminders.org`. Then open dashboard (`C-c r d`), move to a reminder.

**Action:** Press `e`

**Expected:** `reminders.org` opens, cursor lands on that reminder's heading, subtree is expanded (org-reveal). If the reminder is not yet in the file, error message says to run `C-c r R` first.

---

## 8. Add a reminder

**Action:** `C-c r a`

**Expected:**
1. Prompted for title → type "Test reminder from Emacs"
2. Prompted for list → your list name is pre-filled; accept or change
3. Prompted for due date → press Enter to skip
4. Echo area: "Added to Apple Reminders [ListName]: Test reminder from Emacs"
5. In Apple Reminders app, the new item appears in that list.

---

## 9. Add a reminder with due date

**Action:** `C-c r a`, title "Test with due date", accept list, enter `2099-12-31` as due date.

**Expected:** Item appears in Apple Reminders with due date 31 Dec 2099.

---

## 10. Push org heading to Apple

**Setup:** Open any `.org` file and create a heading:
```
* TODO Manual push test
```
Move cursor onto that heading.

**Action:** `C-c r p`

**Expected:**
- A `REMINDER_ID` and `REMINDER_LIST` property are stamped onto the heading.
- Echo area: "Pushed to Apple Reminders [ListName]: Manual push test"
- Item appears in Apple Reminders.

**With prefix arg (`C-u C-c r p`):** Prompted to pick the target list before pushing.

---

## 11. Full bidirectional sync

**Action:** `C-c r R` (in an org buffer)

**Expected:**
- Echo area: "Reminders: syncing…" then "Reminders: N←DONE N→Apple N←Apple N updated"
- `~/org/reminders.org` is created/updated with all open reminders from Apple.
- Any new headings in `reminders.org` (no `REMINDER_ID`) were pushed to Apple.
- Items completed in Apple since last sync are now `DONE` in `reminders.org`.

---

## 12. Priority sync via standard org command

**Setup:** Open `reminders.org`, move to a TODO heading that has a `REMINDER_ID`.

**Action:** `C-c ,` → select priority A (or press `A`)

**Expected:**
- Heading gets `[#A]` prefix in org.
- Within a second or two, that reminder's priority changes to High in Apple Reminders.
- No manual save required.

---

## 13. Deadline sync via standard org command

**Setup:** Open `reminders.org`, move to a TODO heading with `REMINDER_ID`.

**Action:** `C-c C-d`, enter a date (e.g. next week).

**Expected:**
- `DEADLINE: <date>` appears under the heading.
- Due date updates in Apple Reminders automatically.

**Remove deadline:** `C-c C-d C-c C-d` (set then remove) → due date cleared in Apple too.

---

## 14. Flagged tag sync via standard org command

**Setup:** Open `reminders.org`, move to a TODO heading with `REMINDER_ID`.

**Action:** `C-c C-q`, type `flagged`, Enter

**Expected:**
- `:flagged:` tag appears on the heading.
- Reminder is flagged in Apple Reminders.

Remove tag the same way → reminder is unflagged in Apple.

---

## 15. State change sync (complete via org)

**Setup:** Open `reminders.org`, move to a TODO heading with `REMINDER_ID`.

**Action:** `C-c C-t`, select `DONE`

**Expected:**
- Heading changes to DONE in org.
- Reminder is completed in Apple Reminders within seconds.

**Reopen:** `C-c C-t` → `TODO` → reminder reopens in Apple.

---

## 16. Title/notes sync on save

**Setup:** Open `reminders.org`, find a TODO heading with `REMINDER_ID`. Change its title text.

**Action:** `C-x C-s` (save)

**Expected:**
- Echo area: "Reminders push: N new, N updated."
- The updated title appears in Apple Reminders.

---

## 17. Shift-priority (S-↑ / S-↓)

**Setup:** Open `reminders.org`, move to a TODO heading with `REMINDER_ID` and a priority.

**Action:** `S-↑` or `S-↓`

**Expected:**
- Priority cycles in org (A → B → C → none → A …).
- Priority updates in Apple Reminders automatically (same as test 12 — the advice hook fires).

---

## 18. Agenda view (Apple Reminders)

**Setup:** Dashboard has been opened at least once (populates agenda file), or `C-c r R` has been run.

**Action:** `f12` (opens org-agenda), then `A`

**Expected:** Agenda buffer shows "Apple Reminders" as the header, lists all open reminders as TODO entries with deadlines where set.

---

## 19. Org capture

**Action:** `C-c c A`

**Expected:**
1. Capture buffer opens with `* TODO` template.
2. Type a title, `C-c C-c` to file.
3. Entry is saved to `reminders.org`.
4. On next save of `reminders.org` (or `C-c r R`), it appears in Apple Reminders.

---

## 20. Background auto-pull

**Setup:** Add a reminder manually in the Apple Reminders app (not via Emacs).

**Wait:** Up to 5 minutes (auto-pull interval).

**Expected:** The new reminder appears in `reminders.org` and in the dashboard (press `g` to see it immediately in the dashboard).

---

## 21. Auto-pull on startup (3-second idle)

**Action:** Restart Emacs. Wait 3 seconds without typing.

**Expected:** Background pull fires silently. `~/org/reminders-agenda.org` is updated. No error messages.

---

## 22. reminders-cli missing

**Setup:** Temporarily rename the binary: `sudo mv $(which reminders) $(which reminders).bak`

**Action:** `C-c r a` (or any CLI-backed command)

**Expected:** Error message: "reminders-cli not installed. Run: brew install keith/formulae/reminders-cli"

Restore: `sudo mv $(which reminders).bak $(which reminders)`

---

## 23. Custom list pinning

**Action:** Add to your config:
```elisp
(setq my/apple-reminders-sync-list "Work")
```
Then `C-c r R`.

**Expected:** Sync targets the "Work" list specifically. Dashboard still shows all lists.

Remove the `setq` to revert to auto-detect.
