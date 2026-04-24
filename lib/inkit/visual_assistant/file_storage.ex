defmodule Inkit.VisualAssistant.FileStorage do
  @moduledoc false

  @max_size 16 * 1024 * 1024
  @types %{
    "image/png" => [".png"],
    "image/jpeg" => [".jpg", ".jpeg"],
    "image/gif" => [".gif"]
  }

  def max_size, do: @max_size
  def allowed_extensions, do: @types |> Map.values() |> List.flatten()

  def validate_and_store(path, original_filename, claimed_content_type \\ nil) do
    with {:ok, stat} <- File.stat(path),
         :ok <- validate_size(stat.size),
         {:ok, detected_type} <- detect_content_type(path),
         :ok <- validate_extension(original_filename, detected_type),
         {:ok, sha256} <- sha256(path),
         {:ok, storage_path} <- copy_upload(path, detected_type) do
      {:ok,
       %{
         original_filename: Path.basename(original_filename || "upload"),
         content_type: detected_type || claimed_content_type,
         size: stat.size,
         storage_path: storage_path,
         sha256: sha256
       }}
    else
      {:error, :enoent} -> {:error, :missing_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_size(0), do: {:error, :empty_file}
  defp validate_size(size) when size > @max_size, do: {:error, :file_too_large}
  defp validate_size(_size), do: :ok

  defp detect_content_type(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]),
         bytes <- IO.binread(file, 16),
         :ok <- File.close(file) do
      cond do
        match?(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>, bytes) -> {:ok, "image/png"}
        match?(<<0xFF, 0xD8, 0xFF, _::binary>>, bytes) -> {:ok, "image/jpeg"}
        match?(<<"GIF87a", _::binary>>, bytes) -> {:ok, "image/gif"}
        match?(<<"GIF89a", _::binary>>, bytes) -> {:ok, "image/gif"}
        true -> {:error, :unsupported_media_type}
      end
    end
  end

  defp validate_extension(filename, content_type) do
    ext = filename |> to_string() |> Path.extname() |> String.downcase()

    if ext in Map.get(@types, content_type, []) do
      :ok
    else
      {:error, :unsupported_media_type}
    end
  end

  defp sha256(path) do
    path
    |> File.stream!(2048, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> then(&{:ok, &1})
  rescue
    File.Error -> {:error, :missing_file}
  end

  defp copy_upload(path, content_type) do
    upload_dir = upload_dir()
    File.mkdir_p!(upload_dir)

    extension = @types |> Map.fetch!(content_type) |> hd()
    filename = "#{System.system_time(:millisecond)}-#{unique_id()}#{extension}"
    storage_path = Path.join(upload_dir, filename)

    case File.cp(path, storage_path) do
      :ok -> {:ok, storage_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_dir do
    Application.get_env(:inkit, :upload_dir, Path.expand("priv/uploads"))
  end

  defp unique_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
