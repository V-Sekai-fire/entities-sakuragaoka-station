# Img (an RGB canvas with a bitmap font), Png and Json, shared by contact_sheet.exs and contact_video.exs.
# An RGB canvas as a tuple of row binaries, so a blit rewrites only the rows it touches.
defmodule Img do
  defstruct [:w, :h, :rows]

  def new(w, h, {r, g, b}), do: %Img{w: w, h: h, rows: List.to_tuple(List.duplicate(:binary.copy(<<r, g, b>>, w), h))}

  def blit(img, x0, y0, w, h, rgb) do
    Enum.reduce(0..(h - 1), img, fn y, img ->
      row = elem(img.rows, y0 + y)
      <<pre::binary-size(x0 * 3), _::binary-size(w * 3), post::binary>> = row
      line = binary_part(rgb, y * w * 3, w * 3)
      %{img | rows: put_elem(img.rows, y0 + y, pre <> line <> post)}
    end)
  end

  # Text from a 7x15 DejaVu Sans Mono atlas (font_mono_12.bin), alpha-blended per pixel.
  def text(img, x, y, s, {r, g, b}) do
    {gw, gh, atlas} = font()
    s
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reduce(img, fn {ch, i}, img ->
      ch = if ch in 32..126, do: ch, else: ??
      glyph = binary_part(atlas, (ch - 32) * gw * gh, gw * gh)
      gx = x + i * gw
      if gx + gw > img.w, do: img, else:
        Enum.reduce(0..(gh - 1), img, fn yy, img ->
          row = elem(img.rows, y + yy)
          <<pre::binary-size(gx * 3), mid::binary-size(gw * 3), post::binary>> = row
          a = binary_part(glyph, yy * gw, gw)
          mid = for({<<pr, pg, pb>>, <<al>>} <- Enum.zip(chunks(mid, 3), chunks(a, 1)), into: <<>>,
                   do: <<mix(pr, r, al), mix(pg, g, al), mix(pb, b, al)>>)
          %{img | rows: put_elem(img.rows, y + yy, pre <> mid <> post)}
        end)
    end)
  end

  defp mix(a, b, al), do: div(a * (255 - al) + b * al, 255)
  defp chunks(bin, n), do: for(<<c::binary-size(n) <- bin>>, do: c)

  defp font do
    case Process.get(:font) do
      nil ->
        <<"FNT1", w, h, atlas::binary>> = File.read!(Path.join(__DIR__, "font_mono_12.bin"))
        Process.put(:font, {w, h, atlas})
        {w, h, atlas}
      f -> f
    end
  end
end

# PNG, 8-bit RGB, from :zlib and :erlang.crc32 in OTP itself.
defmodule Png do
  def encode(%Img{w: w, h: h, rows: rows}) do
    raw = for row <- Tuple.to_list(rows), into: <<>>, do: <<0>> <> row
    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", <<w::32, h::32, 8, 2, 0, 0, 0>>) <>
      chunk("IDAT", :zlib.compress(raw)) <> chunk("IEND", <<>>)
  end

  defp chunk(type, data), do: <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
end

# Enough JSON for a case file and the numbers: maps, lists, strings, numbers, booleans.
defmodule Json do
  def encode(m) when is_map(m), do: "{" <> Enum.map_join(m, ",", fn {k, v} -> encode(to_string(k)) <> ":" <> encode(v) end) <> "}"
  def encode(l) when is_list(l), do: "[" <> Enum.map_join(l, ",", &encode/1) <> "]"
  def encode(s) when is_binary(s), do: inspect(s, printable_limit: :infinity)
  def encode(b) when is_boolean(b), do: to_string(b)
  def encode(nil), do: "null"
  def encode(a) when is_atom(a), do: encode(Atom.to_string(a))
  def encode(n) when is_number(n), do: to_string(n)
end

