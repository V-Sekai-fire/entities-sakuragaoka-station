# GPU-free checks for a cloud session: headless gates, the godot-sandbox guests, and Hammersley
# renders on lavapipe (Mesa's CPU Vulkan) under Xvfb. Exits 1 if any step fails or is skipped.
#   apt-get install -y mesa-vulkan-drivers xvfb libvulkan1
#   GODOT=<godot 4.7 binary> PEN=<transport-meshing-pen checkout> elixir tools/cloud_check.exs [out_dir]

defmodule CloudCheck do
  @lavapipe "/usr/share/vulkan/icd.d/lvp_icd.json"
  @sandbox_bins ~w(libgodot_riscv.linux.template_release.x86_64.so
                   libgodot_riscv.linux.template_release.double.x86_64.so)

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
        {"slug elf_check", fn -> script(godot, "guest/slug/tests/elf_check.gd", []) end},
        {"hammersley renders (lavapipe)", fn -> render(godot, Path.join(out, "port")) end}
      ]
      |> Enum.map(fn {name, step} -> {name, run_step(name, step)} end)

    failed = Enum.reject(results, fn {_, r} -> r == :pass end)
    IO.puts("\nRESULT #{if failed == [], do: "PASS", else: "FAIL"}  #{length(results) - length(failed)}/#{length(results)} steps pass")
    Enum.each(failed, fn {name, r} -> IO.puts("  #{name}: #{inspect(r)}") end)
    IO.puts("renders: #{Path.join(out, "port")}")
    System.halt(if failed == [], do: 0, else: 1)
  end

  defp run_step(name, step) do
    IO.puts("== #{name}")
    step.()
  end

  defp preflight(godot) do
    missing =
      [{File.exists?(godot), "GODOT #{godot}"}, {File.exists?(@lavapipe), @lavapipe},
       {System.find_executable("xvfb-run") != nil, "xvfb-run"}]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    if missing == [], do: :pass, else: {:missing, missing}
  end

  # The addon tree comes from the pen, which tracks it; Linux binaries only.
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

        absent = Enum.reject(@sandbox_bins, &File.exists?(Path.join(dst, "bin/" <> &1)))
        if absent == [], do: :pass, else: {:missing, absent}
    end
  end

  defp script(godot, path, user_args) do
    args = ["--headless", "--script", path] ++ if(user_args == [], do: [], else: ["--" | user_args])
    godot(godot, args)
  end

  defp render(godot, shots) do
    File.mkdir_p!(shots)

    args =
      ["-a", "-s", "-screen 0 1920x1080x24", godot, "--rendering-driver", "vulkan", "--path", ".",
       "--resolution", "1920x1080", "--script", "tools/realize_check.gd", "--",
       "--shots=#{shots}", "--hammersley=8@-1,-11.4"]

    with :pass <- exec("xvfb-run", args, [{"VK_ICD_FILENAMES", @lavapipe}]) do
      n = length(Path.wildcard(Path.join(shots, "port-view_*.png")))
      if n == 8, do: :pass, else: {:renders, n}
    end
  end

  defp godot(godot, args), do: exec(godot, ["--path", "." | args], [])

  defp exec(cmd, args, env) do
    {_, code} = System.cmd(cmd, args, env: env, into: IO.stream(:stdio, :line), stderr_to_stdout: true)
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
