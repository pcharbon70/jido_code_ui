# Elm Binding Examples

```elm
type Msg
    = WidgetEvent { eventType : String, widgetId : String, data : Json.Encode.Value }
```

```elm
Html.button
    [ Html.Events.onClick
        (WidgetEvent
            { eventType = "unified.button.clicked"
            , widgetId = "save_button"
            , data = Json.Encode.object [ ( "action", Json.Encode.string "save" ) ]
            }
        )
    ]
    [ Html.text "Save" ]
```

```elm
Html.input
    [ Html.Events.onInput
        (\value ->
            WidgetEvent
                { eventType = "unified.input.changed"
                , widgetId = "search_input"
                , data = Json.Encode.object [ ( "value", Json.Encode.string value ) ]
                }
        )
    ]
    []
```

```elm
subscriptions : model -> Sub Msg
subscriptions _ =
    Browser.Events.onResize
        (\w h ->
            WidgetEvent
                { eventType = "unified.viewport.resized"
                , widgetId = "main_viewport"
                , data =
                    Json.Encode.object
                        [ ( "width", Json.Encode.int w )
                        , ( "height", Json.Encode.int h )
                        ]
                }
        )
```
