# Event Type Catalog

## Envelope Shape

```text
WidgetUiEvent {
  type: string,
  widget_id: string,
  widget_kind: string,
  correlation_id: string,
  request_id: string,
  timestamp: string,
  data: map
}
```

## Baseline Event Types

| Event Type | Typical Elm Binding | Required `data` Keys |
|---|---|---|
| `unified.button.clicked` | `Html.Events.onClick` | `action` or `button_id` or `widget_id` |
| `unified.input.changed` | `Html.Events.onInput`, `Html.Events.onCheck` | `value` plus `input_id` or `widget_id` |
| `unified.form.submitted` | `Html.Events.onSubmit` | `form_id` or `widget_id` |
| `unified.element.focused` | `Html.Events.onFocus` | `widget_id` |
| `unified.element.blurred` | `Html.Events.onBlur` | `widget_id` |
| `unified.item.selected` | `onClick` / keyboard handlers | `widget_id` plus `item_id` or `index` |

## Extended Event Types

| Event Type | Required `data` Keys |
|---|---|
| `unified.item.toggled` | `widget_id`, `selected` plus `item_id` or `index` |
| `unified.menu.action_selected` | `widget_id`, `action_id` |
| `unified.table.row_selected` | `widget_id`, `row_index` |
| `unified.table.sorted` | `widget_id`, `column`, `direction` |
| `unified.tab.changed` | `widget_id`, `tab_id` |
| `unified.tree.node_selected` | `widget_id`, `node_id` |
| `unified.tree.node_toggled` | `widget_id`, `node_id`, `expanded` |
| `unified.overlay.confirmed` | `widget_id`, `action_id` |
| `unified.overlay.closed` | `widget_id`, optional `reason` |
| `unified.scroll.changed` | `widget_id`, `position` |
| `unified.viewport.resized` | `widget_id`, `width`, `height` |

## Elm Notes

1. `onInput` reads `event.target.value` and stops propagation.
2. `onCheck` reads `event.target.checked`.
3. `onSubmit` prevents default browser submit navigation.
4. Keyboard and pointer details require custom decoders with `Html.Events.on`.
5. Global resize/visibility/drag interactions use `Browser.Events`.
