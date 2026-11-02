"""Tests for check.py. Run with: python3 -m unittest discover -s scripts"""

from __future__ import annotations

import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check  # noqa: E402


def write(root: Path, relative: str, text: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text).lstrip("\n"), encoding="utf-8")
    return path


class SlugifyTest(unittest.TestCase):
    def test_matches_github_anchors(self):
        cases = {
            "Known Issues in SDK 5.1.0": "known-issues-in-sdk-510",
            "Multicast (Beta) (SDK 5.1+)": "multicast-beta-sdk-51",
            "What Is Ditto?": "what-is-ditto",
            "Ditto.open, Ditto.openSync, and Ditto.init": "dittoopen-dittoopensync-and-dittoinit",
            "Pattern 1: Schema version in a composite `_id`": "pattern-1-schema-version-in-a-composite-_id",
            "INSERT ... SELECT (SDK 5.1+)": "insert--select-sdk-51",
            "✅ DO": "-do",
            "Café au lait": "café-au-lait",
        }
        for heading, expected in cases.items():
            with self.subTest(heading=heading):
                self.assertEqual(check.slugify(heading), expected)

    def test_repeated_headings_get_numbered_anchors(self):
        text = "# Title\n\n## Example\n\n## Example\n\n## Example 1\n"
        self.assertEqual(check.anchors(text), {"title", "example", "example-1", "example-1-1"})


class HeadingsTest(unittest.TestCase):
    def test_ignores_comments_in_code_blocks(self):
        text = "# Title\n\n```bash\n# not a heading\n```\n\n## Section\n"
        self.assertEqual(check.parse_headings(text), [(1, "Title"), (7, "Section")])

    def test_strips_closing_hashes_and_spaces(self):
        self.assertEqual(check.parse_headings("## Section ##  \n"), [(1, "Section")])

    def test_reports_headings_that_repeat_across_pages(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first = write(root, "knowledge/a.md", "# A\n\n## Shared\n")
            second = write(root, "best-practices/b.md", "# B\n\n## Shared\n")
            errors = check.check_unique_headings([first, second], root)
        self.assertEqual(len(errors), 1)
        self.assertIn("Shared", errors[0])
        self.assertIn("knowledge/a.md:3", errors[0])
        self.assertIn("best-practices/b.md:3", errors[0])

    def test_accepts_unique_headings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first = write(root, "a.md", "# A\n\n## One\n")
            second = write(root, "b.md", "# B\n\n## Two\n")
            self.assertEqual(check.check_unique_headings([first, second], root), [])


class LinksTest(unittest.TestCase):
    def test_parses_links_outside_code(self):
        text = (
            "See [b](b.md#two) and ![img](img.png).\n"
            "Inline code `[x](not-a-link.md)` is ignored.\n"
            "```md\n[y](inside-a-fence.md)\n```\n"
        )
        self.assertEqual(check.parse_links(text), [(1, "b.md#two"), (1, "img.png")])

    def test_checks_files_and_anchors(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "docs/b.md", "# B\n\n## Section Two\n")
            write(root, "docs/sub/c.txt", "plain\n")
            source = write(
                root,
                "docs/a.md",
                """
                # A

                ## Local Heading

                - [ok file](b.md)
                - [ok anchor](b.md#section-two)
                - [ok local](#local-heading)
                - [ok directory](sub/)
                - [ok external](https://docs.ditto.live/#anything)
                - [ok mail](mailto:someone@example.com)
                - [bad file](missing.md)
                - [bad anchor](b.md#section-three)
                - [bad local](#nowhere)
                """,
            )
            errors = check.check_links([source], root)
        self.assertEqual(len(errors), 3, errors)
        self.assertTrue(any("missing.md" in e and "docs/a.md:11" in e for e in errors), errors)
        self.assertTrue(any("b.md#section-three" in e for e in errors), errors)
        self.assertTrue(any("#nowhere" in e for e in errors), errors)

    def test_follows_symbolic_links_to_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "knowledge/README.md", "# Knowledge\n\n## Pages\n")
            (root / "skill" / "reference").mkdir(parents=True)
            (root / "skill" / "reference" / "knowledge").symlink_to(Path("..", "..", "knowledge"))
            source = write(root, "skill/SKILL.md", "[k](reference/knowledge/README.md#pages)\n")
            self.assertEqual(check.check_links([source], root), [])


class CitationsTest(unittest.TestCase):
    HEADINGS = {"Soft Delete", "Joining Collections (SDK 5.1+)", "Design `_id` for permission scoping"}

    def test_accepts_known_headings(self):
        text = (
            "Read `§ Soft Delete` and § Joining Collections (SDK 5.1+), "
            "and ``§ Design `_id` for permission scoping``.\n"
        )
        self.assertEqual(check.unknown_citations(text, self.HEADINGS), [])

    def test_reports_unknown_headings(self):
        text = "Read `§ Hard Delete` and § Disjoining Collections.\n"
        self.assertEqual(
            check.unknown_citations(text, self.HEADINGS),
            ["§ Hard Delete is not a heading of the guide",
             "§ Disjoining Collections does not start a heading of the guide"],
        )


class ChecklistSectionsTest(unittest.TestCase):
    HEADINGS = {
        "Requirements",
        "Choosing DELETE, Soft Delete, or EVICT",
        "Soft Delete",
        "Joining Collections (SDK 5.1+)",
    }

    def test_accepts_names_with_commas_and_without_labels(self):
        names = "Choosing DELETE, Soft Delete, or EVICT, Soft Delete, Joining Collections"
        self.assertEqual(check.unknown_sections(names, self.HEADINGS), [])

    def test_reports_unknown_names(self):
        self.assertEqual(
            check.unknown_sections("Requirements, Hard Delete, Soft Delete", self.HEADINGS),
            ["Hard Delete"],
        )

    def test_checks_the_guide_lines_of_a_checklist(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            checklist = write(
                root,
                "checklist/list.md",
                """
                ### ☐ Item

                **Best-practices guide:** Requirements, Hard Delete
                """,
            )
            errors = check.check_checklist_sections(checklist, self.HEADINGS, root)
        self.assertEqual(errors, ["checklist/list.md:3: section Hard Delete is not a heading of the guide"])


class ObservationLinksTest(unittest.TestCase):
    KNOWLEDGE = """
        # Connections

        ## The TCP limit

        ### A hub accepts six clients

        | | |
        |---|---|
        | Observed on | SDK 5.2.0, three runs |

        - Six of eight clients synced.

        ## Background

        How connections work.
        """

    def check(self, text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            knowledge = write(root, "knowledge/connections.md", self.KNOWLEDGE)
            page = write(root, "best-practices/page.md", text)
            return check.check_observation_links([page], [knowledge], root)

    def test_reports_observations_without_a_knowledge_link(self):
        errors = self.check("""
            # Page

            - In our testing with SDK 5.2.0, the hub accepted six clients.
            """)
        self.assertEqual(len(errors), 1)
        self.assertIn("best-practices/page.md:3", errors[0])

    def test_accepts_observations_that_link_to_an_observation(self):
        self.assertEqual(self.check("""
            # Page

            > **Note (SDK 5.2.0):** in our testing, the hub accepted six clients (see [The limit](../knowledge/connections.md#a-hub-accepts-six-clients)).

            - In our testing, it held (see [Connections](../knowledge/connections.md)).
            """), [])

    def test_reports_links_to_headings_without_an_observation(self):
        errors = self.check("""
            # Page

            - In our testing, it held (see [Background](../knowledge/connections.md#background)).
            """)
        self.assertEqual(len(errors), 1)

    def test_matches_in_testing_and_ignores_code_and_other_words(self):
        errors = self.check("""
            # Page

            | Case | In testing with SDK 5.1.0, it failed |

            ```dart
            // in our testing this is code
            ```

            Contesting the result is not an observation, nor is integration testing.
            """)
        self.assertEqual(len(errors), 1)
        self.assertIn("best-practices/page.md:3", errors[0])

    def test_ignores_the_quoted_phrase(self):
        self.assertEqual(self.check("""
            # Page

            Statements that say "in our testing" summarize the knowledge pages.
            """), [])

    def test_finds_the_observations_of_a_page(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = write(Path(tmp), "knowledge/connections.md", self.KNOWLEDGE)
            self.assertEqual(check.observation_anchors(page.read_text(encoding="utf-8")),
                             {"a-hub-accepts-six-clients"})


if __name__ == "__main__":
    unittest.main()
