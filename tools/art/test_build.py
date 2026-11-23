import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build
import restyle
from PIL import Image


def test_split_shoulders_places_each_bumper_under_its_trigger():
    anchors = {
        "PADLTRIGGER": dict(x=0.27, y=0.09, w=0.08, h=0.12),
        "PADRTRIGGER": dict(x=0.72, y=0.09, w=0.08, h=0.11),
        "PADSHOULDERS": dict(x=0.5, y=0.15, w=0.56, h=0.12),
    }
    build.split_shoulders(anchors)
    assert "PADSHOULDERS" not in anchors
    assert anchors["PADLSHOULDER"]["x"] == 0.27
    assert anchors["PADRSHOULDER"]["y"] == 0.15


def test_back_grips_sit_at_the_edges_level_with_the_trackpads():
    anchors = {"LPAD": dict(x=0.15, y=0.6, w=0.1, h=0.2), "RPAD": dict(x=0.85, y=0.6, w=0.1, h=0.2)}
    build.back_grips(anchors)
    assert anchors["L4"]["x"] < 0.1 < 0.9 < anchors["R4"]["x"]
    assert anchors["L4"]["y"] < anchors["L5"]["y"]


def test_fit_centres_the_drawing_on_the_texture_canvas():
    canvas, (x, y, w, h) = build.fit(Image.new("RGBA", (1000, 400), (255, 255, 255, 255)))
    assert canvas.size == build.CANVAS
    assert w <= build.CANVAS[0] - 2 * build.MARGIN
    assert x == (build.CANVAS[0] - w) // 2 and y == (build.CANVAS[1] - h) // 2


def test_definitions_are_valid_lua_in_stylua_format(tmp_path):
    defs = [
        dict(
            id="x",
            name='Pad "One"',
            family="xbox",
            labelStyle="Letters",
            texture="A\\B",
            hidden=[],
            anchors={"PAD1": dict(x=0.5, y=0.5, w=0.1, h=0.1)},
        ),
        dict(
            id="y",
            name="Two",
            family="valve",
            labelStyle="Letters",
            texture="T",
            hidden=["L4"],
            anchors={"PAD2": dict(x=0.1, y=0.2, w=0.3, h=0.4)},
        ),
    ]
    path = tmp_path / "Definitions.lua"
    build.write_definitions(defs, path)
    lua = path.read_text(encoding="utf-8")
    assert 'name = "Pad \\"One\\"",' in lua
    assert 'texture = "A\\\\B",' in lua
    assert "hidden = {}," in lua and 'hidden = { "L4" },' in lua
    assert re.search(r"PAD2 = \{ x = 0\.1000, y = 0\.2000, w = 0\.3000, h = 0\.4000 \},", lua)


def test_transform_scale_handles_matrix_scale_and_translate():
    assert restyle.tf_scale("translate(10,20)") == 1
    assert abs(restyle.tf_scale("scale(2)") - 2) < 1e-9
    assert abs(restyle.tf_scale("matrix(2.5,0,0,2.5,-3,4)") - 2.5) < 1e-9
    assert abs(restyle.tf_scale("scale(2) matrix(0.5,0,0,0.5,0,0)") - 1) < 1e-9


def test_generated_definitions_cover_every_controller():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with open(os.path.join(root, "src", "Features", "Controllers", "Definitions.lua"), encoding="utf-8") as f:
        lua = f.read()
    ids = re.findall(r'id = "(\w+)"', lua)
    assert ids == build.ORDER
    for cid in ids:
        assert os.path.exists(os.path.join(root, "media", "controllers", cid + ".tga"))
