defmodule BriskulaWeb.GameLive.Index do
  use BriskulaWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
      {@page_title}
      </.header>

      <.form
        for={@form}
        id="home-form"
        phx-change="change"
        phx-submit="save"
      >
        <.input field={@form[:username]} type="text" label="Username*" minlength="2" maxlength="15" placeholder={@username_placeholder} required/>

        <br>

        <.input field={@form[:room_code]} type="text" label="Room Code" />


        <.button phx-disable-with="Starting" variant="primary">{@btn_text}</.button>

      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do

    form = %{
      "username" => "",
      "room_code" => ""
    }

    {
      :ok,
      socket
      # random username placeholder
      |> assign(:username_placeholder, Faker.Person.name())
      |> assign(:btn_text, "Start a game")


      |> assign(:page_title, "Briškula")
      |> assign(form: to_form(form))
    }
  end

  @impl true
  def handle_event("change", %{"room_code" => room_code}, socket) do
    IO.inspect(room_code)

    {
      :noreply,
      socket
      |> assign(:btn_text, blank?(room_code) && "Start a game" || "Join the game")
    }
  end

  @impl true
  def handle_event("save", form_data, socket) do

    IO.inspect(form_data)



    {:noreply, socket}
  end

  defp blank?(str_or_nil),
    do: "" == str_or_nil |> to_string() |> String.trim()

  defp sanitize(input) do
    input
    |> String.trim(" ")
    |> String.trim("\n")
  end

end
