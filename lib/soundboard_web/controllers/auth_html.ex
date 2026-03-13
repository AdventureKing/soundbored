defmodule SoundboardWeb.AuthHTML do
  use SoundboardWeb, :html

  def not_in_guild(assigns) do
    ~H"""
    <section class="min-h-screen flex items-center justify-center p-6">
      <div class="max-w-lg w-full bg-white rounded-lg shadow-lg p-8 space-y-4">
        <h1 class="text-2xl font-semibold text-gray-900">Access denied</h1>
        <p class="text-gray-700">
          Your Discord account is not in the required guild for this soundboard.
        </p>
        <p :if={@guild_id} class="text-sm text-gray-600">
          Required guild ID: <span class="font-mono text-gray-800">{@guild_id}</span>
        </p>
        <p class="text-sm text-gray-600">
          Join the server first, then sign in again.
        </p>
        <div class="pt-2">
          <.link
            href={~p"/auth/discord"}
            class="inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
          >
            Try Discord sign-in again
          </.link>
        </div>
      </div>
    </section>
    """
  end
end
