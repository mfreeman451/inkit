defmodule InkitWeb.SecurityRegressionTest do
  use InkitWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Inkit.ImageFixture
  alias Inkit.VisualAssistant.Workflows

  test "upload filenames cannot choose storage paths or traverse directories" do
    upload = ImageFixture.png_upload("../../../etc/passwd.png")

    assert {:ok, image, _analysis} =
             Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    upload_dir = Application.fetch_env!(:inkit, :upload_dir) |> Path.expand()
    storage_path = Path.expand(image.storage_path)

    assert image.original_filename == "passwd.png"
    assert String.starts_with?(storage_path, upload_dir <> "/")
    refute Path.basename(storage_path) == "passwd.png"
  end

  test "upload validation rejects files whose bytes do not match their extension" do
    path = Path.join(System.tmp_dir!(), "inkit-fake-#{System.unique_integer([:positive])}.png")
    File.write!(path, "not actually a png")

    assert {:error, :unsupported_media_type} =
             Workflows.create_image_from_upload(path, "looks-valid.png", "image/png")
  end

  test "XSS-looking labels and prompts are escaped in the LiveView UI", %{conn: conn} do
    upload = ImageFixture.png_upload("sample.png")
    payload = ~S[<script>alert("xss")</script>]

    {:ok, image, _analysis} =
      Workflows.create_image_from_upload(upload.path, upload.filename, upload.content_type)

    assert {:ok, _image} = Workflows.update_image_label(image.public_id, payload)
    assert {:ok, _response} = Workflows.chat(image.public_id, payload)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "&lt;script&gt;"
    refute html =~ payload
  end

  test "SQLi-shaped image ids are treated as opaque identifiers", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/img_missing' OR '1'='1", Jason.encode!(%{question: "Hello?"}))

    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end

  test "browser and API responses include defensive headers", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert html_response(conn, 200) =~ ~s(<meta name="csrf-token")

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/img_missing", Jason.encode!(%{question: "Hello?"}))

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end
end
