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


def test_back_view_draws_shoulders_and_paddles_inside_the_outline():
    import back

    front = Image.new("RGBA", (400, 200), (0, 0, 0, 0))
    front.paste((43, 44, 51, 255), (20, 20, 380, 180))
    anchors = {"PADLTRIGGER": dict(cx=0.2, cy=0.12, w=0.1, h=0.05), "PADA": dict(cx=0.5, cy=0.5, w=0.1, h=0.1)}
    img, out = back.draw(front, anchors, "steamdeck", stroke=2)
    assert img.size == front.size
    assert set(out) == {"PADLTRIGGER", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4"}
    assert out["PADPADDLE3"]["cx"] < 0.5 < out["PADPADDLE1"]["cx"]  # L4 left, R4 right (seen through)
    assert back.labels("steamdeck")["PADPADDLE1"] == "R4"
    assert back.labels("switchpro") == {}


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
    assert ids == [v for cid in build.ORDER for v in (cid, cid + "_back")]  # every front has a back view
    for cid in ids:
        assert os.path.exists(os.path.join(root, "media", "controllers", cid + ".tga"))
