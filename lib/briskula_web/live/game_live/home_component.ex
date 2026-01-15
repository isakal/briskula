defmodule BriskulaWeb.GameLive.HomeComponent do
  use BriskulaWeb, :live_component

  alias Briskula.GameServer

  import Briskula.Flash, only: [put_flash!: 3]
  import BriskulaWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-view max-w-md mx-auto mt-10 place-items-center">
      <.header>
        Briškula
      </.header>
      <.form
        for={@form}
        id="home-form"
        phx-change="change"
        phx-submit="start"
        phx-target={@myself}
        class="mt-8 grid"
      >
        <.input
          field={@form[:username]}
          type="text"
          label="Username*"
          minlength="2"
          maxlength="15"
          placeholder={@username_placeholder}
          required
        />

        <.input
          field={@form[:room_code]}
          type="text"
          label="Room Code (optional)"
          placeholder="Leave empty to create new game"
        />

        <.button type="submit" variant="primary" phx-disable-with="Starting...">
          {@btn_text}
        </.button>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
    socket
     |> assign(:username_placeholder, Faker.Person.name())}
  end

  @impl true
  def update(assigns, socket) do
    # Get room_code from assigns (might be prefilled from URL)
    room_code = Map.get(assigns, :room_code, "")

    # Create form
    form = %{"username" => "", "room_code" => room_code}

    # Set button text based on room_code
    btn_text = if blank?(room_code), do: "Start a game", else: "Join the game"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(form))
     |> assign(:btn_text, btn_text)}
  end

  @impl true
  def handle_event("change", form, socket) do
    room_code = Map.get(form, "room_code")

    btn_text = if blank?(room_code), do: "Start a game", else: "Join the game"

    {:noreply, socket
      |> assign_form(form)
      |> assign(:btn_text, btn_text)}
  end


  @impl true
  def handle_event("start", %{"username" => username, "room_code" => room_code}, socket) do
    username = sanitize(username)

    cond do
      blank?(username) ->
        {:noreply, put_flash(socket, :error, "Username is required")}

      blank?(room_code) ->
        send(self(), {:create_game, username})
        {:noreply, socket}

      true ->
        # Join existing game - send message to parent LiveView
        case GameServer.get_game(room_code) do
          {:error, :game_not_found} ->
            {:noreply,
            socket
             |> put_flash!(:error, "Game not found")}

          _game ->
            send(self(), {:join_game, username, room_code})
            {:noreply, socket}
        end
    end
  end

  # Helper functions

  defp blank?(str_or_nil),
    do: "" == str_or_nil |> to_string() |> String.trim()

  defp sanitize(input) do
    input
    |> String.trim(" ")
    |> String.trim("\n")
  end

  defp assign_form(socket, form) do
    clean_form = Map.reject(
      form, fn {key, _val} -> String.starts_with?(key, "_") end
    )

    socket
    |> assign(:form, to_form(clean_form))
  end
end
