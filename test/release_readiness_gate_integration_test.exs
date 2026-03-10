defmodule JidoCodeUi.ReleaseReadinessGateIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  test "full gate happy-path integration scenarios" do
    with_temp_worktree(fn worktree ->
      {output, 0} = run_cmd(worktree, "./scripts/run_release_readiness.sh", ["--report-only"])

      assert output =~ "RELEASE_GATE_STAGE=1_specs_governance:pass"
      assert output =~ "RELEASE_GATE_STAGE=2_guides_governance:pass"
      assert output =~ "RELEASE_GATE_STAGE=3_rfc_governance:pass"
      assert output =~ "RELEASE_GATE_STAGE=4_rfc_debt_scan:pass"
      assert output =~ "RELEASE_GATE_STAGE=5_conformance:pass"
      assert output =~ "RELEASE_GATE_STAGE=6_full_tests:skipped_report_only"
      assert output =~ "CONFORMANCE_ALIGNMENT=PASS"
      assert output =~ "RELEASE_GATE_RESULT=PASS"
    end)
  end

  test "gate failure-injection integration scenarios" do
    with_temp_worktree(fn worktree ->
      conformance_test =
        Path.join(worktree, "test/conformance/scenario_catalog_conformance_test.exs")

      conformance_contents = File.read!(conformance_test)
      target_scenario_id = "SCN-" <> "008"
      missing_scenario_id = "SCNX-008"

      File.write!(
        conformance_test,
        String.replace(conformance_contents, target_scenario_id, missing_scenario_id)
      )

      {conformance_output, conformance_status} =
        run_cmd(worktree, "./scripts/run_conformance.sh", ["--report-only", "--skip-governance"])

      assert conformance_status != 0

      assert conformance_output =~
               "FAIL: scenario catalog scenarios missing from conformance tests:"

      assert conformance_output =~ target_scenario_id
      assert conformance_output =~ "CONFORMANCE_ALIGNMENT=FAIL"
    end)

    with_temp_worktree(fn worktree ->
      component_spec = Path.join(worktree, "specs/core/ui_application.md")

      File.write!(
        component_spec,
        File.read!(component_spec) <> "\n- `AC-99` governance drift injection.\n"
      )

      {release_output, release_status} =
        run_cmd(worktree, "./scripts/run_release_readiness.sh", [
          "--skip-conformance",
          "--skip-tests"
        ])

      assert release_status != 0

      assert release_output =~
               "AC-bearing component spec changes require conformance matrix updates."

      assert release_output =~ "RELEASE_GATE_STAGE=1_specs_governance:fail"
      assert release_output =~ "RELEASE_GATE_RESULT=FAIL"
    end)

    with_temp_worktree(fn worktree ->
      missing_workflow = Path.join(worktree, ".github/workflows/conformance.yml")
      assert :ok = File.rm(missing_workflow)

      {regression_output, regression_status} =
        run_cmd(worktree, "./scripts/check_release_gate_regressions.sh", [])

      assert regression_status != 0

      assert regression_output =~
               "missing release-gate dependency: .github/workflows/conformance.yml"

      assert regression_output =~ "Release gate regression checks failed."
    end)
  end

  defp with_temp_worktree(fun) do
    root = File.cwd!()
    suffix = Integer.to_string(System.unique_integer([:positive]))
    worktree = Path.join(System.tmp_dir!(), "jido_code_ui_phase8_gate_" <> suffix)

    {_, 0} =
      System.cmd("git", ["worktree", "add", "--detach", worktree, "HEAD"],
        cd: root,
        stderr_to_stdout: true
      )

    try do
      sync_workspace!(root, worktree)
      fun.(worktree)
    after
      System.cmd("git", ["worktree", "remove", "--force", worktree],
        cd: root,
        stderr_to_stdout: true
      )

      :ok
    end
  end

  defp sync_workspace!(root, worktree) do
    sync_cmd = """
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \\
        --exclude '.git' \\
        --exclude '_build' \\
        --exclude 'deps' \\
        --exclude '.elixir_ls' \\
        \"$SRC\"/ \"$DST\"/
    else
      (cd \"$SRC\" && tar --exclude='.git' --exclude='_build' --exclude='deps' --exclude='.elixir_ls' -cf - .) | \\
        (cd \"$DST\" && tar -xf -)
    fi
    """

    {_, 0} =
      System.cmd("bash", ["-lc", sync_cmd],
        env: [{"SRC", root}, {"DST", worktree}],
        stderr_to_stdout: true
      )
  end

  defp run_cmd(worktree, script, args) do
    System.cmd("bash", [script | args],
      cd: worktree,
      stderr_to_stdout: true
    )
  end
end
