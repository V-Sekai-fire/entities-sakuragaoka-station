# The station's CI contact sheet: the town and the whole station from tools/export_usda.gd.
out = Path.expand(System.get_env("SHEET_OUT", "cloud-check"))
%{
  title: "sakuragaoka-station: realized station as scene.usda, CPU Mitsuba, sphere_hammersley_sequence",
  views: 8, size: 256, spp: 32, distance: 0.6, shared_frame: false,
  cases: [
    %{name: "town (station, plaza, sakura)", usda: Path.join(out, "town.usda"), verdict: "REFERENCE"},
    %{name: "station with environment", usda: Path.join(out, "station.usda"), verdict: "REFERENCE"}
  ]
}
