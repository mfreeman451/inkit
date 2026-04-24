defmodule Inkit.ImageFixture do
  @moduledoc false

  def png_upload(filename \\ "sample.png") do
    path = Path.join(System.tmp_dir!(), "inkit-test-#{System.unique_integer([:positive])}.png")
    File.write!(path, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "mock image bytes">>)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: "image/png"
    }
  end
end
