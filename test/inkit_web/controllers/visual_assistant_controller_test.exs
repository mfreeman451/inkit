defmodule InkitWeb.VisualAssistantControllerTest do
  use InkitWeb.ConnCase

  alias Inkit.ImageFixture

  test "POST /upload stores an image and returns mock analysis", %{conn: conn} do
    conn = post(conn, ~p"/upload", %{"image" => ImageFixture.png_upload()})

    assert %{
             "image" => %{"id" => image_id, "content_type" => "image/png"},
             "analysis" => %{"object" => "chat.completion"}
           } = json_response(conn, 201)

    assert String.starts_with?(image_id, "img_")
  end

  test "POST /upload rejects unsupported files", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "inkit-test-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "not an image")

    upload = %Plug.Upload{path: path, filename: "bad.txt", content_type: "text/plain"}
    conn = post(conn, ~p"/upload", %{"image" => upload})

    assert %{"error" => %{"code" => "unsupported_media_type"}} = json_response(conn, 415)
  end

  test "GET /images/:image_id renders a validated upload", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn = conn |> recycle() |> get(~p"/images/#{image_id}")

    assert response(conn, 200) =~ <<0x89, "PNG">>
    assert ["image/png" <> _] = get_resp_header(conn, "content-type")
  end

  test "POST /chat/:image_id answers a question about an uploaded image", %{conn: conn} do
    image_id =
      conn
      |> post(~p"/upload", %{"image" => ImageFixture.png_upload()})
      |> json_response(201)
      |> get_in(["image", "id"])

    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/#{image_id}", Jason.encode!(%{question: "What do you notice?"}))

    assert %{
             "object" => "chat.completion",
             "choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]
           } = json_response(conn, 200)

    assert content =~ "What do you notice?"
    assert content =~ "real provider"
  end

  test "POST /chat/:image_id returns not found for unknown images", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/chat/img_missing", Jason.encode!(%{question: "Hello?"}))

    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end
end
