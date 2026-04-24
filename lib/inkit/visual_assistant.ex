defmodule Inkit.VisualAssistant do
  @moduledoc false

  use Ash.Domain

  resources do
    resource Inkit.VisualAssistant.UploadedImage
    resource Inkit.VisualAssistant.Message
    resource Inkit.VisualAssistant.ApiLog
  end
end
