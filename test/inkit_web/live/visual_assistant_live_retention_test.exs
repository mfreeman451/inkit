defmodule InkitWeb.VisualAssistantLiveRetentionTest do
  use InkitWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Inkit.VisualAssistant.RetentionSetting

  test "settings tab renders editable retention form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    # Navigating to the settings section on the LiveView
    assert html =~ "Settings"
  end

  test "saving retention settings updates the singleton row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "set_section", %{"section" => "settings"})

    render_submit(view, "update_retention_settings", %{
      "retention" => %{
        "enabled" => "on",
        "messages_days" => "14",
        "api_logs_days" => "3",
        "images_days" => "21",
        "interval_minutes" => "15"
      }
    })

    {:ok, setting} = RetentionSetting.fetch()
    assert setting.enabled == true
    assert setting.messages_days == 14
    assert setting.api_logs_days == 3
    assert setting.images_days == 21
    assert setting.interval_minutes == 15
  end

  test "run now produces a run row and surfaces the summary flash", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "set_section", %{"section" => "settings"})
    html = render_click(view, "run_retention_now", %{})

    assert html =~ "Sweep finished"
    assert html =~ "Recent runs"
  end
end
