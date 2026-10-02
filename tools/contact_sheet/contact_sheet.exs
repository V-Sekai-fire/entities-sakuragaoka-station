# A release contact sheet, in one step: elixir contact_sheet.exs <sheet.exs> <out.png>
#
# One row per case, failures first; one column per sphere_hammersley_sequence view. Each cell
# is a CPU Mitsuba render (mi_cell.py --worker, the only Python: Mitsuba has no other binding)
# with the 24-patch reference colour chart billboarded under the same lights, labelled with its
# view, coverage and the chart's neutral-patch drift. Layout, labels and PNG encoding are here,
# plain Elixir, no Mix, no dependencies, like the pen's tools/build.exs. The numbers are written
# beside the sheet as <out>.json.
#
# <sheet.exs> evaluates to a map:
#   %{title: "...", views: 8, size: 256, spp: 32, distance: 0.6, shared_frame: true,
#     cases: [%{name: "...", usda: "scene.usda", opacity: %{"body" => 0.3},
#               export: %{godot: "...", pen: "...", control: "drop_seam", strokes: "scripted"}}]}
# A case with `export` first runs the pen's replay headless (export_mesh.gd) into the usda's
# directory. `verdict` and `metric` default to the usda's customLayerData.
defmodule Sheet do
  @here __DIR__
  @label_h 44
  @head_w 220
  @bg {24, 24, 24}

  def main([spec_path, out]) do
    {spec, _} = Code.eval_file(spec_path)
    spec_dir = Path.dirname(Path.expand(spec_path))
    views = spec[:views] || 8
    size = spec[:size] || 256
    work = Path.rootname(out) <> ".cells"
    File.mkdir_p!(work)

    cases =
      spec.cases
      |> Enum.map(&resolve(&1, spec_dir))
      |> Enum.with_index()
      |> Enum.map(fn {c, i} -> export(c) |> Map.put(:json, write_case(c, work, i)) end)

    frame = if Map.get(spec, :shared_frame, true), do: shared_frame(cases), else: nil

    rendered =
      for {c, i} <- Enum.with_index(cases) do
        if frame, do: write_case(Map.put(c, :frame, frame), work, i)
        dir = Path.join(work, "case_#{i}")
        say("render #{c.name}")
        {lines, 0} =
          System.cmd("python3", [Path.join(@here, "mi_cell.py"), "--worker", c.json, dir,
                     "#{views}", "#{size}", "#{spec[:spp] || 32}", "#{spec[:distance] || 0.6}"])
        [verdict, metric] = File.read!(Path.join(dir, "case.tsv")) |> String.trim_trailing("\n") |> String.split("\t")
        cells =
          for l <- String.split(lines, "\n", trim: true),
              [v, yaw, pitch, cov, drift] = String.split(l, "\t"),
              do: %{view: String.to_integer(v), yaw: yaw, pitch: pitch, cover: String.to_float(cov),
                    drift: String.to_float(drift), rgb: File.read!(Path.join(dir, "view_#{v}.rgb"))}
        %{c | verdict: c[:verdict] || verdict, metric: c[:metric] || metric} |> Map.put(:cells, cells)
      end
      |> Enum.sort_by(&(&1.verdict != "FAIL"))

    canvas = compose(spec[:title] || "contact sheet", rendered, views, size)
    File.write!(out, Png.encode(canvas))
    File.write!(Path.rootname(out) <> ".json", numbers(rendered))
    say("wrote #{out}")
  end

  defp resolve(c, dir) do
    c = Map.merge(%{verdict: nil, metric: nil}, c)
    if c[:usda], do: %{c | usda: Path.expand(c.usda, dir)}, else: c
  end

  # The pen's saved-stroke replay, headless, written as the usda the case names.
  defp export(%{export: e, usda: usda} = c) do
    args = ["--headless", "--path", e.pen, "--xr-mode", "off", "--script", Path.join(@here, "export_mesh.gd"),
            "--", "--out=#{Path.dirname(usda)}"] ++ if(e[:control], do: ["--control=#{e.control}"], else: []) ++
           if(e[:strokes], do: ["--strokes=#{e.strokes}"], else: [])
    say("export #{c.name}")
    System.cmd(e.godot, args, stderr_to_stdout: true)
    c
  end

  defp export(c), do: c

  defp write_case(c, work, i) do
    path = Path.join(work, "case_#{i}.json")
    keep = Map.take(c, [:name, :usda, :opacity, :meshes, :verdict, :metric, :frame])
    File.write!(path, Json.encode(for {k, v} <- keep, v != nil, into: %{}, do: {Atom.to_string(k), v}))
    path
  end

  defp shared_frame(cases) do
    {out, 0} = System.cmd("python3", [Path.join(@here, "mi_cell.py"), "--bounds" | Enum.map(cases, & &1.json)])
    [x, y, z, s] = out |> String.trim() |> String.split("\t") |> Enum.map(&String.to_float/1)
    %{"centre" => [x, y, z], "scale" => s}
  end

  defp compose(title, cases, views, size) do
    w = @head_w + size * views
    h = 30 + (size + @label_h) * length(cases)
    img = Img.new(w, h, @bg) |> Img.text(8, 8, title, {240, 240, 240})

    cases
    |> Enum.with_index()
    |> Enum.reduce(img, fn {c, r}, img ->
      y0 = 30 + r * (size + @label_h)
      col = %{"FAIL" => {230, 80, 80}, "PASS" => {120, 210, 120}}[c.verdict] || {200, 200, 120}
      img =
        img
        |> Img.text(8, y0 + 8, c.name, {240, 240, 240})
        |> Img.text(8, y0 + 24, c.verdict, col)
        |> Img.text(8, y0 + 40, String.slice(c.metric, 0, 30), {200, 200, 200})

      Enum.reduce(c.cells, img, fn cell, img ->
        x0 = @head_w + cell.view * size
        img
        |> Img.blit(x0, y0, size, size, cell.rgb)
        |> Img.text(x0 + 4, y0 + size + 4, "view #{cell.view}  yaw #{round(String.to_float(cell.yaw))}  pitch #{round(String.to_float(cell.pitch))}", {220, 220, 220})
        |> Img.text(x0 + 4, y0 + size + 22, "cover #{Float.round(cell.cover * 100, 1)}%  grey drift #{cell.drift}/255", {220, 220, 220})
      end)
    end)
  end

  defp numbers(cases) do
    cells =
      for c <- cases, cell <- c.cells,
          do: %{"case" => c.name, "verdict" => c.verdict, "view" => cell.view, "yaw_deg" => cell.yaw,
                "pitch_deg" => cell.pitch, "coverage" => cell.cover, "grey_drift" => cell.drift}
    Json.encode(%{"generator" => "sphere_hammersley_sequence (anny-render-corpus/render_view.py)",
                  "variant" => "llvm_ad_rgb", "cells" => cells})
  end

  defp say(s), do: IO.puts("[sheet] " <> s)
end

Code.require_file("sheet_lib.exs", __DIR__)
Sheet.main(System.argv())
