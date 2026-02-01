defmodule InvaderWeb.SignInLive do
  @moduledoc """
  Custom sign-in page with Space Invaders arcade theme.
  Shows a setup form for the first user (admin setup) or normal sign-in options.
  """
  use InvaderWeb, :live_view

  alias Invader.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    user_count = Ash.count!(User, authorize?: false)
    needs_setup = user_count == 0
    magic_link_enabled = Application.get_env(:invader, :magic_link_enabled, false)

    {:ok,
     assign(socket,
       page_title: "Sign In",
       needs_setup: needs_setup,
       magic_link_enabled: magic_link_enabled,
       auth_method: "magic_link",
       form_error: nil,
       magic_link_sent: false
     )}
  end

  @impl true
  def handle_event("set_auth_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, auth_method: method)}
  end

  @impl true
  def handle_event("request_magic_link", %{"email" => email}, socket) do
    email = String.trim(email)

    if email == "" do
      {:noreply, assign(socket, form_error: "Email is required")}
    else
      # Check if user exists
      case User.get_by_email(email, authorize?: false, not_found_error?: false) do
        {:ok, nil} ->
          {:noreply, assign(socket, form_error: "No account found with this email")}

        {:error, _} ->
          {:noreply, assign(socket, form_error: "No account found with this email")}

        {:ok, user} ->
          # Request magic link token
          strategy = AshAuthentication.Info.strategy!(User, :magic_link)

          case AshAuthentication.Strategy.action(strategy, :request, %{"email" => user.email}) do
            :ok ->
              {:noreply, assign(socket, magic_link_sent: true, form_error: nil)}

            {:ok, _} ->
              {:noreply, assign(socket, magic_link_sent: true, form_error: nil)}

            {:error, _} ->
              {:noreply, assign(socket, form_error: "Failed to send magic link")}
          end
      end
    end
  end

  def handle_event("reset_form", _params, socket) do
    {:noreply, assign(socket, magic_link_sent: false, form_error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="arcade-container min-h-screen bg-black flex flex-col items-center justify-center relative z-10"
      role="main"
    >
      <!-- CRT Scanlines Overlay -->
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>
      
    <!-- Animated Aliens Header Decoration -->
      <div class="flex justify-center gap-4 mb-6 text-2xl">
        <span class="alien-sprite text-cyan-400"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.2s;"></span>
        <span class="alien-sprite text-green-400" style="animation-delay: 0.4s;"></span>
        <span class="alien-sprite text-cyan-400" style="animation-delay: 0.6s;"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.8s;"></span>
      </div>
      
    <!-- Title -->
      <h1 class="text-3xl md:text-4xl font-bold tracking-widest arcade-glow mb-2">
        INVADER
      </h1>
      <p class="text-cyan-500 text-[10px] tracking-wider mb-12">[ RALPH LOOP COMMAND CENTER ]</p>
      
    <!-- Sign In Panel -->
      <div class="arcade-panel p-6 sm:p-8 max-w-md w-full mx-4">
        <%= if @needs_setup do %>
          <!-- Admin Setup Form -->
          <div class="text-center mb-8">
            <h2 class="text-sm text-yellow-400 mb-2">ADMIN SETUP</h2>
            <p class="text-[8px] text-cyan-700">CREATE FIRST ADMIN ACCOUNT</p>
          </div>

          <form action="/auth/setup/create-admin" method="post" class="space-y-4">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />

            <div>
              <label class="block text-[8px] text-cyan-600 mb-1">SETUP TOKEN</label>
              <input
                type="password"
                name="token"
                placeholder="Enter setup token"
                autocomplete="off"
                required
                class="w-full bg-black border border-cyan-600 text-cyan-400 px-4 py-3 text-[10px] tracking-wider focus:border-cyan-400 focus:outline-none focus:ring-1 focus:ring-cyan-400"
              />
            </div>

            <div>
              <label class="block text-[8px] text-cyan-600 mb-1">AUTH METHOD</label>
              <div class="flex gap-2">
                <button
                  type="button"
                  phx-click="set_auth_method"
                  phx-value-method="magic_link"
                  class={"flex-1 py-2 text-[10px] border transition-colors " <> if(@auth_method == "magic_link", do: "border-cyan-400 text-cyan-400 bg-cyan-400/10", else: "border-cyan-700 text-cyan-700 hover:border-cyan-500")}
                >
                  MAGIC LINK
                </button>
                <button
                  type="button"
                  phx-click="set_auth_method"
                  phx-value-method="github"
                  class={"flex-1 py-2 text-[10px] border transition-colors " <> if(@auth_method == "github", do: "border-cyan-400 text-cyan-400 bg-cyan-400/10", else: "border-cyan-700 text-cyan-700 hover:border-cyan-500")}
                >
                  GITHUB
                </button>
              </div>
              <input type="hidden" name="auth_method" value={@auth_method} />
            </div>

            <div>
              <label class="block text-[8px] text-cyan-600 mb-1">
                {if @auth_method == "magic_link", do: "EMAIL ADDRESS", else: "GITHUB USERNAME"}
              </label>
              <input
                type={if @auth_method == "magic_link", do: "email", else: "text"}
                name="identifier"
                placeholder={
                  if @auth_method == "magic_link", do: "admin@example.com", else: "github-username"
                }
                required
                class="w-full bg-black border border-cyan-600 text-cyan-400 px-4 py-3 text-[10px] tracking-wider focus:border-cyan-400 focus:outline-none focus:ring-1 focus:ring-cyan-400"
              />
            </div>

            <button
              type="submit"
              class="arcade-btn w-full border-yellow-400 text-yellow-400 hover:bg-yellow-400 hover:text-black py-3"
            >
              <span class="text-[10px]">CREATE ADMIN</span>
            </button>
          </form>

          <div class="mt-6 text-center">
            <p class="text-[8px] text-cyan-700">
              The setup token was displayed when you ran mix setup.
            </p>
          </div>
        <% else %>
          <!-- Normal Sign In -->
          <%= if @magic_link_sent do %>
            <!-- Magic Link Sent Confirmation -->
            <div class="text-center">
              <h2 class="text-sm text-green-400 mb-4">CHECK YOUR EMAIL</h2>
              <p class="text-[10px] text-cyan-400 mb-6">
                Magic link sent! Click the link in your email to sign in.
              </p>
              <button
                type="button"
                phx-click="reset_form"
                class="text-[8px] text-cyan-600 hover:text-cyan-400"
              >
                Try a different email
              </button>
            </div>
          <% else %>
            <div class="text-center mb-8">
              <h2 class="text-sm text-cyan-400 mb-2">PLAYER LOGIN</h2>
              <p class="text-[8px] text-cyan-700">AUTHENTICATE TO ACCESS COMMAND CENTER</p>
            </div>

            <%= if @magic_link_enabled do %>
              <!-- Magic Link Form -->
              <.form for={%{}} phx-submit="request_magic_link" class="space-y-4 mb-6">
                <div>
                  <input
                    type="email"
                    name="email"
                    placeholder="Email address"
                    required
                    class="w-full bg-black border border-cyan-600 text-cyan-400 px-4 py-3 text-[10px] tracking-wider focus:border-cyan-400 focus:outline-none focus:ring-1 focus:ring-cyan-400"
                  />
                </div>

                <%= if @form_error do %>
                  <p class="text-red-500 text-[10px] text-center">{@form_error}</p>
                <% end %>

                <button
                  type="submit"
                  class="arcade-btn w-full border-cyan-400 text-cyan-400 hover:bg-cyan-400 hover:text-black py-3"
                >
                  <span class="text-[10px]">SEND MAGIC LINK</span>
                </button>
              </.form>

              <div class="flex items-center gap-4 my-6">
                <div class="flex-1 border-t border-cyan-800"></div>
                <span class="text-[8px] text-cyan-700">OR</span>
                <div class="flex-1 border-t border-cyan-800"></div>
              </div>
            <% end %>
            
    <!-- GitHub Sign In Button -->
            <a
              href="/auth/user/github"
              class="arcade-btn w-full flex items-center justify-center gap-3 border-white text-white hover:border-cyan-400 hover:text-cyan-400 py-4"
            >
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
              </svg>
              <span class="text-[10px]">SIGN IN WITH GITHUB</span>
            </a>
          <% end %>
        <% end %>
        
    <!-- Insert Coin Animation -->
        <div class="mt-8 text-center">
          <p class="text-[8px] text-cyan-600 blink">
            <%= if @needs_setup do %>
              FIRST PLAYER SETUP REQUIRED
            <% else %>
              INSERT CREDENTIALS TO CONTINUE
            <% end %>
          </p>
        </div>
      </div>
      
    <!-- Bottom Decoration -->
      <div class="mt-12 flex justify-center">
        <div class="flex items-center gap-4 text-[10px] text-cyan-600">
          <span>▂▂▂</span>
          <span class="text-green-500">SHIELDS</span>
          <span>▂▂▂</span>
          <span>▂▂▂</span>
          <span class="text-green-500">READY</span>
          <span>▂▂▂</span>
        </div>
      </div>
      
    <!-- Credit Insert -->
      <div class="text-center mt-6 text-[8px] text-cyan-700" aria-hidden="true">
        CREDIT 00
      </div>
    </main>
    """
  end
end
