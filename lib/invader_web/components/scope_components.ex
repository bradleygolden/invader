defmodule InvaderWeb.ScopeComponents do
  @moduledoc """
  Reusable components for scope management UI.
  """
  use Phoenix.Component

  alias Invader.Scopes.Parsers.GitHub
  alias Invader.Scopes.Parsers.Telegram

  @doc """
  Renders a dropdown select for scope presets.
  """
  attr :id, :string, default: "scope-preset-select"
  attr :name, :string, default: "scope_preset_id"
  attr :value, :string, default: nil
  attr :presets, :list, required: true
  attr :target, :any, default: nil
  attr :disabled, :boolean, default: false

  def scope_preset_select(assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-cyan-500 text-[10px] block">SCOPE PRESET</label>
      <select
        id={@id}
        name={@name}
        phx-change="select_preset"
        phx-target={@target}
        disabled={@disabled}
        class="w-full bg-black border-2 border-cyan-700 text-white p-3 focus:border-cyan-400 focus:outline-none disabled:opacity-50"
      >
        <option value="">-- Custom Scopes --</option>
        <%= for preset <- @presets do %>
          <option value={preset.id} selected={to_string(@value) == to_string(preset.id)}>
            {preset.name}
            <%= if preset.is_system do %>
              (System)
            <% end %>
          </option>
        <% end %>
      </select>
      <p :if={@value} class="text-cyan-700 text-[8px]">
        Using preset scopes. Clear to customize.
      </p>
    </div>
    """
  end

  @doc """
  Renders a grouped checklist for selecting individual scopes.
  """
  attr :id, :string, default: "scope-checklist"
  attr :selected_scopes, :list, default: []
  attr :target, :any, default: nil
  attr :disabled, :boolean, default: false

  def scope_checklist(assigns) do
    all_scopes = GitHub.all_scopes()
    grouped = GitHub.group_by_category(all_scopes)
    assigns = assign(assigns, :grouped, grouped)

    ~H"""
    <div class="space-y-4">
      <label class="text-cyan-500 text-[10px] block">CUSTOM SCOPES</label>

      <div :for={{category, scopes} <- Enum.sort(@grouped)} class="space-y-2">
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="toggle_category"
            phx-value-category={category}
            phx-target={@target}
            disabled={@disabled}
            class={"arcade-btn text-[8px] py-1 px-2 #{if category_selected?(category, @selected_scopes), do: "border-cyan-400 text-cyan-400 bg-cyan-900/30", else: "border-cyan-800 text-cyan-600"} disabled:opacity-50"}
          >
            {String.upcase(category)}
          </button>
          <span class="text-cyan-700 text-[8px]">
            ({count_selected(scopes, @selected_scopes)}/{map_size(scopes)})
          </span>
        </div>

        <div class="ml-4 grid grid-cols-2 gap-1">
          <%= for {scope, info} <- Enum.sort(scopes) do %>
            <label class={"flex items-center gap-2 cursor-pointer text-[10px] #{if @disabled, do: "opacity-50"}"}>
              <input
                type="checkbox"
                name="scopes[]"
                value={scope}
                checked={scope in @selected_scopes}
                phx-click="toggle_scope"
                phx-value-scope={scope}
                phx-target={@target}
                disabled={@disabled}
                class="w-3 h-3 bg-black border border-cyan-700 text-cyan-400 focus:ring-cyan-500"
              />
              <span class={"#{if scope in @selected_scopes, do: "text-cyan-400", else: "text-cyan-600"}"}>
                {extract_action(scope)}
              </span>
              <span class="text-cyan-800 text-[8px]">
                ({info.category})
              </span>
            </label>
          <% end %>
        </div>
      </div>

      <div :if={@selected_scopes != []} class="pt-2 border-t border-cyan-900">
        <p class="text-cyan-500 text-[8px]">
          Selected: {@selected_scopes |> Enum.join(", ")}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a preview of the CLI help that will be generated from scopes.
  """
  attr :scopes, :list, default: []

  def scope_preview(assigns) do
    help_text = generate_preview_text(assigns.scopes)
    assigns = assign(assigns, :help_text, help_text)

    ~H"""
    <div class="space-y-2">
      <label class="text-cyan-500 text-[10px] block">CLI PREVIEW</label>
      <div class="bg-gray-900 border border-cyan-800 p-3 font-mono text-[10px] text-green-400 max-h-48 overflow-y-auto">
        <pre class="whitespace-pre-wrap">{@help_text}</pre>
      </div>
      <p class="text-cyan-700 text-[8px]">
        This is what the sprite will see when running `invader --help`
      </p>
    </div>
    """
  end

  @doc """
  Renders a small badge showing scope count.
  """
  attr :count, :integer, required: true
  attr :label, :string, default: "scopes"

  def scope_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[8px] border border-cyan-700 text-cyan-500">
      <span class="font-bold">{@count}</span>
      <span>{@label}</span>
    </span>
    """
  end

  # Private helpers

  defp category_selected?(category, selected_scopes) do
    Enum.any?(selected_scopes, &String.starts_with?(&1, "github:#{category}:"))
  end

  defp count_selected(category_scopes, selected_scopes) do
    category_scopes
    |> Map.keys()
    |> Enum.count(&(&1 in selected_scopes))
  end

  defp extract_action(scope) do
    scope
    |> String.split(":")
    |> List.last()
  end

  defp generate_preview_text(scopes) when scopes in [nil, []] do
    """
    Invader CLI Commands

    No commands configured. Select scopes above or choose a preset.
    """
  end

  defp generate_preview_text(["*"]) do
    """
    Invader CLI Commands

    Usage: invader <command> [args...]

    GitHub Commands (invader gh):
      pr          Work with pull requests
      issue       Work with issues
      repo        Work with repositories

    Telegram Commands (invader telegram):
      ask         Send a blocking prompt and wait for reply
      notify      Send a fire-and-forget notification

    (Full access - all commands available)
    """
  end

  defp generate_preview_text(scopes) do
    github_allowed = GitHub.filter_scopes(scopes)
    github_grouped = GitHub.group_by_category(github_allowed)
    telegram_allowed = Telegram.filter_scopes(scopes)

    has_github = map_size(github_allowed) > 0
    has_telegram = map_size(telegram_allowed) > 0

    cond do
      not has_github and not has_telegram ->
        """
        Invader CLI Commands

        No commands available with current scopes.
        """

      true ->
        github_section = build_github_section(github_grouped, has_github)
        telegram_section = build_telegram_section(telegram_allowed, has_telegram)

        """
        Invader CLI Commands

        Usage: invader <command> [args...]
        #{github_section}#{telegram_section}
        """
    end
  end

  defp build_github_section(_grouped, false), do: ""

  defp build_github_section(grouped, true) do
    categories =
      grouped
      |> Enum.sort_by(fn {cat, _} -> cat end)
      |> Enum.map(fn {cat, cat_scopes} ->
        actions =
          cat_scopes
          |> Enum.map(fn {scope, _} -> extract_action(scope) end)
          |> Enum.join(", ")

        "  #{cat}: #{actions}"
      end)
      |> Enum.join("\n")

    """

    GitHub Commands (invader gh):
    #{categories}
    """
  end

  defp build_telegram_section(_allowed, false), do: ""

  defp build_telegram_section(allowed, true) do
    actions =
      allowed
      |> Enum.map(fn {scope, info} ->
        action = extract_action(scope)
        "  #{action}: #{info.description}"
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    """

    Telegram Commands (invader telegram):
    #{actions}
    """
  end
end
