# F103 — Multi-select

## Summary

Ctrl-click selects items in a live view. While something is selected the window is in selection mode: a click toggles an item, right-click opens the actions menu, and a bar shows the count and the actions.

## Context

- Ctrl-click on a bag item normally opens the dressing room; inside the bag window that is given up. Shift-click keeps splitting and linking.
- The catcher frame is shown while Ctrl or Alt is held (`MODIFIER_STATE_CHANGED`) or the selection is not empty, and only over a live view.

## Scope

- `AuctionHelper_BagSelect.lua`: the selection of the window, the catcher frame, the selection bar ("3 selected", Actions, Clear; "Destroy next" once Destroy was chosen). Actions opens the same menu as right-click
- Selected slots get a gold wash
- The selection is pruned on every redraw and cleared by Clear and by a change of tab or view (Escape closes the window, as before)

## Acceptance criteria

- [ ] Ctrl-click toggles an item; the bar appears with the first and goes with the last
- [ ] With a selection, a plain click toggles and right-click opens the menu
- [ ] With no selection and no modifier held, slots behave exactly as before
- [ ] Read-only views cannot select
- [ ] A selected stack that is moved, sold or used drops out of the selection

## Verification

```bash
npm test
```

In-game: select, clear, switch tab, close and reopen.

## Dependencies

- F100, F92

## Out of scope

- Shift-click range selection, select all
