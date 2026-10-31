"""
Unit tests for collision routines, obstacle queries, and wall sliding.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.entities import Vec2, BoundingBox
from game.collisions import (
    circle_intersects_circle,
    circle_intersects_rect,
    resolve_circle_rect_collision,
    line_intersects_rect,
    has_line_of_sight,
)


class TestCollisions(unittest.TestCase):

    def test_circle_circle_intersection(self):
        c1 = Vec2(100, 100)
        c2 = Vec2(120, 100)
        self.assertTrue(circle_intersects_circle(c1, 15, c2, 10))  # dist 20 <= 25

        c3 = Vec2(140, 100)
        self.assertFalse(circle_intersects_circle(c1, 15, c3, 10)) # dist 40 > 25

    def test_circle_rect_intersection(self):
        box = BoundingBox(100, 100, 50, 50)
        self.assertTrue(circle_intersects_rect(Vec2(95, 125), 10, box))
        self.assertFalse(circle_intersects_rect(Vec2(70, 125), 10, box))

    def test_wall_slide_resolution(self):
        """Verify that a player circle is smoothly pushed out of a solid wall."""
        wall = BoundingBox(200, 100, 40, 200)
        # Circle overlapping left edge
        pos = Vec2(195, 150)
        radius = 16.0
        resolved = resolve_circle_rect_collision(pos, radius, wall)

        self.assertLessEqual(resolved.x, wall.left - radius + 1e-4)
        self.assertEqual(resolved.y, 150)

    def test_line_of_sight(self):
        wall = BoundingBox(300, 100, 50, 300)
        p_left = Vec2(100, 200)
        p_right = Vec2(500, 200)
        self.assertFalse(has_line_of_sight(p_left, p_right, [wall]))

        p_top = Vec2(325, 50)
        self.assertTrue(has_line_of_sight(p_left, p_top, [wall]))


if __name__ == "__main__":
    unittest.main()
