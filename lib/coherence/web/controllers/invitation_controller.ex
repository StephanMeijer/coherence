defmodule Coherence.InvitationController do
  use Phoenix.Controller
  alias Coherence.{Config, Invitation}
  import Ecto.Query
  import Coherence.ControllerHelpers
  require Logger
  use Timex

  plug Coherence.ValidateOption, :invitable
  plug :scrub_params, "user" when action in [:create_user]
  plug :layout_view

  def layout_view(conn, _) do
    conn
    |> put_layout({Coherence.CoherenceView, "app.html"})
    |> put_view(Coherence.InvitationView)
  end

  def new(conn, _params) do
    changeset = Invitation.changeset(%Invitation{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"invitation" =>  invitation_params}) do
    token = random_string 48
    url = router_helpers.invitation_url(conn, :edit, token)
    params = Map.put invitation_params, "token", token
    cs = Invitation.changeset(%Invitation{}, params)
    case Config.repo.insert cs do
      {:ok, invitation} ->
        email = Coherence.UserEmail.invitation(invitation, url)
        Logger.debug fn -> "invitation email: #{inspect email}" end
        email |> Coherence.Mailer.deliver

        conn
        |> put_flash(:info, "Invitation sent.")
        |> redirect(to: logged_out_url(conn))
      {:error, changeset} ->
        render conn, "new.html", changeset: changeset
    end
  end

  def edit(conn, params) do
    token = params["id"]
    where(Invitation, [u], u.token == ^token)
    |> Config.repo.one
    |> case do
      nil ->
        conn
        |> put_flash(:error, "Invalid invitation token.")
        |> redirect(to: logged_out_url(conn))
      invite ->
        user_schema = Config.user_schema
        cs = user_schema.changeset(user_schema.__struct__,
          %{email: invite.email, name: invite.name})
        conn
        |> render(:edit, changeset: cs, token: invite.token)
    end
  end

  def create_user(conn, params) do
    token = params["token"]
    repo = Config.repo
    user_schema = Config.user_schema

    where(Invitation, [u], u.token == ^token)
    |> repo.one
    |> case do
      nil ->
        conn
        |> put_flash(:error, "Invalid Invitation. Please contact the site administrator.")
        |> redirect(to: logged_out_url(conn))
      invite ->
        changeset = user_schema.changeset(user_schema.__struct__, params["user"])
        case repo.insert changeset do
          {:ok, user} ->
            repo.delete invite
            conn
            |> put_flash(:info, "Account created.")
            |> redirect(to: logged_out_url(conn))
          {:error, changeset} ->
            render conn, "edit.html", changeset: changeset, token: token
        end
    end
  end
end
