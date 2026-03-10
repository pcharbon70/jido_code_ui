defmodule JidoCodeUi.ContractsNilNormalizationTest do
  use ExUnit.Case, async: true

  alias JidoCodeUi.Contracts.CompileResult
  alias JidoCodeUi.Contracts.OrchestratorResult
  alias JidoCodeUi.Contracts.UiCommand
  alias JidoCodeUi.Contracts.UiSessionSnapshot
  alias JidoCodeUi.Contracts.UnifiedIurDocument
  alias JidoCodeUi.Contracts.UnifiedUiDslDocument
  alias JidoCodeUi.Contracts.WidgetUiEventEnvelope

  test "contract string fields preserve nil instead of literal nil strings" do
    ui_command = UiCommand.new(%{session_id: nil, correlation_id: nil, request_id: nil})
    assert ui_command.session_id == nil
    assert ui_command.correlation_id == nil
    assert ui_command.request_id == nil

    widget_event =
      WidgetUiEventEnvelope.new(%{session_id: nil, route_key: nil, render_token: nil})

    assert widget_event.session_id == nil
    assert widget_event.route_key == nil
    assert widget_event.render_token == nil

    snapshot = UiSessionSnapshot.new(%{session_id: nil, route_key: nil, active_iur_hash: nil})
    assert snapshot.session_id == nil
    assert snapshot.route_key == nil
    assert snapshot.active_iur_hash == nil

    compile_result = CompileResult.new(%{dsl_version: nil, iur_version: nil, iur_hash: nil})
    assert compile_result.dsl_version == nil
    assert compile_result.iur_version == nil
    assert compile_result.iur_hash == nil

    iur_document = UnifiedIurDocument.new(%{iur_version: nil, dsl_version: nil})
    assert iur_document.iur_version == nil
    assert iur_document.dsl_version == nil

    dsl_document =
      UnifiedUiDslDocument.new(%{dsl_version: nil, custom_nodes: [nil, :markdown_preview, " "]})

    assert dsl_document.dsl_version == nil
    assert dsl_document.custom_nodes == ["markdown_preview"]

    orchestrator_result = OrchestratorResult.new(%{route_key: nil})
    assert orchestrator_result.route_key == nil
  end
end
