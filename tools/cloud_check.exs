# GPU-free checks for a cloud session: the headless gates, the godot-sandbox guests and a CPU Mitsuba
# contact sheet, with no GPU emulator (lavapipe, WARP, SwiftShader). Exits 1 if any step fails.
#   pip install mitsuba usd-core numpy pillow
#   GODOT=<godot 4.7 binary> PEN=<transport-meshing-pen checkout> elixir tools/cloud_check.exs [out_dir]

defmodule CloudCheck do
  @addon_tag "v20261002-addon.1"
  @addon_base "https://github.com/V-Sekai-fire/service-godot-build/releases/download/"
  @sandbox_bins ~w(libgodot_riscv.linux.template_release.x86_64.so
                   libgodot_riscv.linux.template_release.double.x86_64.so)
  @sandbox_elfs ~w(gdscript.elf gdscript.double.elf)

  def main(args) do
    root = File.cwd!()
    out = Path.expand(List.first(args) || "cloud-check", root)
    File.mkdir_p!(out)
    godot = System.get_env("GODOT") || fail_now("GODOT is not set")

    results =
      [
        {"preflight", fn -> preflight(godot) end},
        {"vendor godot_sandbox", fn -> vendor(root) end},
        {"import", fn -> godot(godot, ["--headless", "--import"]) end},
        {"gate_colliders", fn -> script(godot, "tools/gate_colliders.gd", []) end},
        {"gate_colliders drop_one (must FAIL)", fn -> negate(script(godot, "tools/gate_colliders.gd", ["--control=drop_one"])) end},
        {"gate_station", fn -> script(godot, "tools/gate_station.gd", []) end},
        {"gate_station drop_lot (must FAIL)", fn -> negate(script(godot, "tools/gate_station.gd", ["--control=drop_lot"])) end},
        {"precision_check", fn -> script(godot, "tools/precision_check.gd", []) end},
        {"precision_check swap (must FAIL)", fn -> negate(script(godot, "tools/precision_check.gd", ["--control=swap"])) end},
        {"sgd_check", fn -> script(godot, "tools/sgd_check.gd", []) end},
        {"export town.usda", fn -> script(godot, "tools/export_usda.gd", ["--out=#{out}/town.usda", "--modules=station,plaza,sakura"]) end},
        {"export station.usda", fn -> script(godot, "tools/export_usda.gd", ["--out=#{out}/station.usda"]) end},
        {"contact sheet", fn -> sheet(out) end},
        {"slug elf_check", fn -> script(godot, "guest/slug/tests/elf_check.gd", []) end}
      ]
      |> Enum.map(fn {name, step} -> {name, run_step(name, step)} end)

    failed = Enum.reject(results, fn {_, r} -> r == :pass end)
    IO.puts("\nRESULT #{if failed == [], do: "PASS", else: "FAIL"}  #{length(results) - length(failed)}/#{length(results)} steps pass")
    Enum.each(failed, fn {name, r} -> IO.puts("  #{name}: #{inspect(r)}") end)
    IO.puts("contact sheet: #{Path.join(out, "station-sheet.png")}")
    System.halt(if failed == [], do: 0, else: 1)
  end

  defp run_step(name, step) do
    IO.puts("== #{name}")
    step.()
  end

  defp preflight(godot) do
    if File.exists?(godot), do: :pass, else: {:missing, "GODOT #{godot}"}
  end

  # The addon tree comes from the pen; its Linux binaries and compiler ELFs from the pinned
  # release, which refuses a guest built for the other real_t.
  defp vendor(root) do
    pen = System.get_env("PEN")
    src = pen && Path.join(pen, "addons/godot_sandbox")

    cond do
      src == nil or not File.dir?(src) ->
        {:missing, "PEN=<transport-meshing-pen checkout> with addons/godot_sandbox"}

      true ->
        dst = Path.join(root, "addons/godot_sandbox")
        File.rm_rf!(dst)
        File.cp_r!(src, dst)

        Path.wildcard(Path.join(dst, "bin/*.{dll,framework}"))
        |> Enum.each(&File.rm_rf!/1)

        tag = System.get_env("ADDON_TAG", @addon_tag)
        files = Enum.map(@sandbox_bins, &{&1, Path.join(dst, "bin/" <> &1)}) ++
                Enum.map(@sandbox_elfs, &{&1, Path.join(dst, &1)})

        with {:ok, sums} <- fetch(tag, "SHA256SUMS") do
          bad =
            for {name, path} <- files,
                result = install(tag, name, path, sums),
                result != :ok,
                do: {name, result}

          if bad == [], do: :pass, else: {:addon, tag, bad}
        end
    end
  end

  defp install(tag, name, path, sums) do
    want = Regex.run(~r/^([0-9a-f]{64}) +\*?#{Regex.escape(name)}$/m, sums, capture: :all_but_first)

    with [hex] <- want || :not_in_sums,
         {:ok, bin} <- fetch(tag, name),
         ^hex <- Base.encode16(:crypto.hash(:sha256, bin), case: :lower) do
      File.write!(path, bin)
      :ok
    else
      {:error, _} = e -> e
      :not_in_sums -> :not_in_sums
      _ -> :sha256_mismatch
    end
  end

  defp fetch(tag, name) do
    tmp = Path.join(System.tmp_dir!(), "addon-" <> name)
    case System.cmd("curl", ["-fsSL", "-o", tmp, @addon_base <> tag <> "/" <> name], stderr_to_stdout: true) do
      {_, 0} -> {:ok, File.read!(tmp)}
      {out, code} -> {:error, {code, String.trim(out)}}
    end
  end

  defp script(godot, path, user_args) do
    args = ["--headless", "--script", path] ++ if(user_args == [], do: [], else: ["--" | user_args])
    godot(godot, args)
  end

  defp sheet(out) do
    png = Path.join(out, "station-sheet.png")
    {_, code} =
      System.cmd("elixir", ["tools/contact_sheet/contact_sheet.exs", "tools/contact_sheet/station.exs", png],
        env: [{"SHEET_OUT", out}], into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    cond do
      code != 0 -> {:exit, code}
      not File.exists?(png) -> {:missing, png}
      true -> :pass
    end
  end

  defp godot(godot, args) do
    {_, code} = System.cmd(godot, ["--path", "." | args], into: IO.stream(:stdio, :line), stderr_to_stdout: true)
    if code == 0, do: :pass, else: {:exit, code}
  end

  defp negate(:pass), do: {:control_passed, "a control that must FAIL passed"}
  defp negate({:exit, _}), do: :pass
  defp negate(other), do: other

  defp fail_now(msg) do
    IO.puts("RESULT FAIL  #{msg}")
    System.halt(1)
  end
end

CloudCheck.main(System.argv())
