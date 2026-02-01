defmodule Invader.Prompts.TemplateTest do
  use ExUnit.Case, async: true

  alias Invader.Prompts.Template

  describe "render/2" do
    test "replaces single variable" do
      template = "Wave {{wave_number}}"
      bindings = %{wave_number: 1}

      assert Template.render(template, bindings) == "Wave 1"
    end

    test "replaces multiple variables" do
      template = "Wave {{wave_number}} of {{max_waves}}"
      bindings = %{wave_number: 1, max_waves: 20}

      assert Template.render(template, bindings) == "Wave 1 of 20"
    end

    test "unknown variables remain intact" do
      template = "Mission: {{mission_id}} - Status: {{unknown}}"
      bindings = %{mission_id: "abc123"}

      assert Template.render(template, bindings) == "Mission: abc123 - Status: {{unknown}}"
    end

    test "converts non-string values to string" do
      template = "Count: {{count}}, Float: {{value}}, Bool: {{flag}}"
      bindings = %{count: 42, value: 3.14, flag: true}

      assert Template.render(template, bindings) == "Count: 42, Float: 3.14, Bool: true"
    end

    test "empty bindings leaves all variables intact" do
      template = "Wave {{wave_number}} of {{max_waves}}"
      bindings = %{}

      assert Template.render(template, bindings) == "Wave {{wave_number}} of {{max_waves}}"
    end

    test "empty template returns empty string" do
      template = ""
      bindings = %{wave_number: 1}

      assert Template.render(template, bindings) == ""
    end

    test "template without variables returns unchanged" do
      template = "This is a static prompt with no variables."
      bindings = %{wave_number: 1}

      assert Template.render(template, bindings) == template
    end

    test "handles multiline templates" do
      template = """
      # Mission Report
      Wave: {{wave_number}}/{{max_waves}}
      Sprite: {{sprite_name}}
      """

      bindings = %{wave_number: 5, max_waves: 10, sprite_name: "test-sprite"}

      expected = """
      # Mission Report
      Wave: 5/10
      Sprite: test-sprite
      """

      assert Template.render(template, bindings) == expected
    end

    test "handles variables with underscores" do
      template = "{{long_variable_name}}"
      bindings = %{long_variable_name: "value"}

      assert Template.render(template, bindings) == "value"
    end

    test "handles adjacent variables" do
      template = "{{a}}{{b}}{{c}}"
      bindings = %{a: "x", b: "y", c: "z"}

      assert Template.render(template, bindings) == "xyz"
    end

    test "atom values converted to string" do
      template = "Status: {{status}}"
      bindings = %{status: :running}

      assert Template.render(template, bindings) == "Status: running"
    end
  end
end
