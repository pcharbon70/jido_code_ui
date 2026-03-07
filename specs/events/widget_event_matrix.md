# Widget Event Matrix

Widget-to-event baseline for built-in catalog coverage.

| Widget ID | Standard Event Types |
|---|---|
| `block` | None |
| `button` | `unified.button.clicked` |
| `label` | None |
| `list` | `unified.item.selected`, `unified.item.toggled` |
| `pick_list` | `unified.item.selected`, `unified.overlay.closed` |
| `progress` | None |
| `text_input_primitive` | `unified.input.changed`, `unified.form.submitted` |
| `alert_dialog` | `unified.overlay.confirmed`, `unified.overlay.closed` |
| `bar_chart` | `unified.chart.point_selected` (optional) |
| `canvas` | `unified.canvas.pointer.changed` |
| `cluster_dashboard` | `unified.item.selected`, `unified.view.changed` |
| `command_palette` | `unified.input.changed`, `unified.command.executed`, `unified.overlay.closed` |
| `context_menu` | `unified.menu.action_selected`, `unified.overlay.closed` |
| `dialog` | `unified.overlay.confirmed`, `unified.overlay.closed` |
| `form_builder` | `unified.input.changed`, `unified.form.submitted`, `unified.item.toggled` |
| `gauge` | None |
| `line_chart` | `unified.chart.point_selected` (optional) |
| `log_viewer` | `unified.scroll.changed`, `unified.item.selected` |
| `markdown_viewer` | `unified.link.clicked` (optional) |
| `menu` | `unified.menu.action_selected` |
| `process_monitor` | `unified.item.selected`, `unified.action.requested` |
| `scroll_bar` | `unified.scroll.changed` |
| `sparkline` | `unified.chart.point_selected` (optional) |
| `split_pane` | `unified.split.resized`, `unified.split.collapse_changed` |
| `stream_widget` | `unified.item.selected` (optional) |
| `supervision_tree_viewer` | `unified.tree.node_selected`, `unified.tree.node_toggled` |
| `table` | `unified.table.row_selected`, `unified.table.sorted` |
| `tabs` | `unified.tab.changed` |
| `text_input` | `unified.input.changed`, `unified.form.submitted` |
| `toast` | `unified.toast.dismissed` |
| `toast_manager` | `unified.toast.dismissed`, `unified.toast.cleared` |
| `tree_view` | `unified.tree.node_selected`, `unified.tree.node_toggled` |
| `viewport` | `unified.scroll.changed`, `unified.viewport.resized` |
