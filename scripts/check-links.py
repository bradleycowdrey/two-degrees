#!/usr/bin/env python3
"""Checks that every link in Two Degrees works.

It reads the README, the changelog, the web pages, the App Store metadata and the Mac, iPhone and
Android apps' sources, then fetches every web address it finds. It also crawls the live product pages
one level deep. Same-page links like #widgets must point at an id that exists, and relative links
must point at a file in the repository.

Usage:
  python3 scripts/check-links.py            check local files and every web address
  python3 scripts/check-links.py --offline  check local files and fragments only (no network)

It exits with 1 when any link really fails. Sites that block robots (403, 429 or LinkedIn's 999), and the App Store
page while the app is not live yet, are reported as unverified, not as failures.
"""

import argparse
import concurrent.futures
import html.parser
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "bradleycowdrey/two-degrees"

# The live pages. Each is fetched and every link on it is checked, one level deep.
LIVE_PAGES = [
    "https://bradcowdrey.com/two-degrees",
    "https://bradcowdrey.com/two-degrees/app",
    "https://bradcowdrey.com/legal",
    "https://bradleycowdrey.github.io/two-degrees/",
]

# Live addresses that serve a file in this repository, so offline mode can check fragments and files.
LIVE_TO_LOCAL = {
    "https://bradcowdrey.com/two-degrees": "docs/index.html",
    "https://bradcowdrey.com/two-degrees/": "docs/index.html",
    "https://bradcowdrey.com/two-degrees/app": "docs/app.html",
    "https://bradleycowdrey.github.io/two-degrees": "docs/index.html",
    "https://bradleycowdrey.github.io/two-degrees/": "docs/index.html",
}
PAGES_PREFIX = "https://bradleycowdrey.github.io/two-degrees/"
RAW_PREFIX = f"https://raw.githubusercontent.com/{REPO}/main/"
REPO_URL = f"https://github.com/{REPO}"

# Hosts that turn robots away. A 403, 429 or 999 (LinkedIn's answer to robots) from them says
# nothing about the link.
BOT_BLOCKING_HOSTS = {"apps.apple.com", "x.com", "twitter.com", "www.linkedin.com", "linkedin.com",
                      "www.instagram.com", "instagram.com", "sourceforge.net"}

# The App Store page answers 404 until the app is live.
APP_STORE_PAGE = "https://apps.apple.com/app/id6826694344"

# API endpoints that need parameters. For these only the host has to answer.
API_HOSTS = {"api.open-meteo.com", "geocoding-api.open-meteo.com", "archive-api.open-meteo.com",
             "air-quality-api.open-meteo.com", "api.weather.gov", "forecast.weather.gov"}

# Hosts a page only preconnects to. A bare link to one of them just has to answer.
PRECONNECT_HOSTS = {"fonts.googleapis.com", "fonts.gstatic.com"}

# Files that may not exist yet. The page that reads them falls back when they are missing.
OPTIONAL = {RAW_PREFIX + "docs/testflight.json": "read by the download button; it falls back to the App Store link when missing"}

# Addresses that are names, not links: XML namespaces and document types.
NAMESPACE_PREFIXES = ("http://schemas.android.com/", "http://www.apple.com/DTDs/", "http://www.w3.org/",
                      "https://www.w3.org/2000/svg", "http://www.w3.org/2000/svg")

USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

URL_RE = re.compile(r"""https?://[^\s"'<>`\\)\]]+""")
MD_LINK_RE = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
MD_REF_RE = re.compile(r"^\[[^\]]+\]:\s*(\S+)", re.M)
ATTR_RE = re.compile(r"""\b(?:href|src)\s*=\s*["']([^"']+)["']""", re.I)
ID_RE = re.compile(r"""\b(?:id|name)\s*=\s*["']([^"']+)["']""", re.I)


class Link:
    """One address, and every place it was found."""

    def __init__(self, url):
        self.url = url
        self.where = []
        self.status = ""
        self.detail = ""

    def add(self, where):
        if where not in self.where:
            self.where.append(where)


# Reading the repository

def line_of(text, index):
    return text.count("\n", 0, index) + 1


def tidy(url):
    # Prose and code often end a link with punctuation that is not part of it.
    url = url.rstrip(".,;:!?*_")
    while url.endswith(")") and url.count("(") < url.count(")"):
        url = url[:-1]
    return url


def slug(heading):
    # GitHub's anchor for a Markdown heading.
    text = re.sub(r"<[^>]+>", "", heading).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path):
    """Every id a link can jump to in a local file."""
    text = path.read_text(encoding="utf-8", errors="replace")
    ids = set(ID_RE.findall(text))
    if path.suffix == ".md":
        seen = {}
        for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
            base = slug(heading)
            n = seen.get(base, 0)
            ids.add(base if n == 0 else f"{base}-{n}")
            seen[base] = n + 1
    return ids


def source_files():
    """The files whose links are checked, with how their relative links resolve."""
    files = [(ROOT / "README.md", ROOT), (ROOT / "CHANGELOG.md", ROOT)]
    files += [(p, ROOT / "docs") for p in sorted((ROOT / "docs").glob("*.html"))]
    # The web pages are published from docs/, so their relative links resolve there.
    files += [(p, ROOT / "docs") for p in sorted((ROOT / "web").glob("*.html"))]
    files += [(ROOT / "appstore/metadata.json", ROOT / "appstore")]
    for folder, patterns in (("Sources", ["*.swift"]), ("Resources", ["*.plist", "*.json", "*.strings", "*.md"]),
                             ("android/app/src/main", ["*.kt", "*.xml"])):
        for pattern in patterns:
            files += [(p, None) for p in sorted((ROOT / folder).rglob(pattern))]
    return [(p, base) for p, base in files if p.is_file()]


def is_fixture(path):
    # Self-test addresses are sample input for a parser, not links anyone follows.
    return path.name == "SelfTest.swift"


def collect(local_failures):
    links = {}

    def note(url, where):
        links.setdefault(url, Link(url)).add(where)

    for path, base in source_files():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        page_ids = anchors(path) if path.suffix in (".md", ".html") else set()

        for m in URL_RE.finditer(text if not is_fixture(path) else ""):
            note(tidy(m.group(0)), f"{rel}:{line_of(text, m.start())}")

        if base is None:
            continue
        refs = []
        if path.suffix == ".md":
            refs += [(m.group(1), m.start(1)) for m in MD_LINK_RE.finditer(text)]
            refs += [(m.group(1), m.start(1)) for m in MD_REF_RE.finditer(text)]
        refs += [(m.group(1), m.start(1)) for m in ATTR_RE.finditer(text)]
        for ref, index in refs:
            where = f"{rel}:{line_of(text, index)}"
            if re.match(r"^(https?:|mailto:|tel:|javascript:|data:)", ref) or "${" in ref or "{" in ref:
                continue
            if ref.startswith("#"):
                if ref[1:] and ref[1:] not in page_ids:
                    local_failures.append((where, ref, f"no id \"{ref[1:]}\" in {rel}"))
                continue
            target, _, fragment = ref.partition("#")
            if target.startswith("/two-degrees/"):
                # A site-root link; the site serves docs/ at /two-degrees/.
                file = local_page(ROOT / "docs" / target[len("/two-degrees/"):])
            elif target.startswith("/"):
                continue
            else:
                file = local_page(base / urllib.parse.unquote(target))
            if file is None:
                local_failures.append((where, ref, "file not found in the repository"))
            elif fragment and fragment not in anchors(file):
                local_failures.append((where, ref, f"no id \"{fragment}\" in {file.relative_to(ROOT).as_posix()}"))

    # App Store screenshots named in the metadata must exist.
    meta_path = ROOT / "appstore/metadata.json"
    if meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        for names in meta.get("screenshots", {}).values():
            for name in names:
                if not (ROOT / "appstore/screenshots" / name).is_file():
                    local_failures.append(("appstore/metadata.json", name, "screenshot not found in appstore/screenshots"))

    # Every changelog version heading needs a link definition, or it shows as plain text.
    changelog = ROOT / "CHANGELOG.md"
    if changelog.is_file():
        text = changelog.read_text(encoding="utf-8", errors="replace")
        defined = set(re.findall(r"^\[([^\]]+)\]:", text, re.M))
        for m in re.finditer(r"^## \[([^\]]+)\]", text, re.M):
            if m.group(1) not in defined:
                local_failures.append((f"CHANGELOG.md:{line_of(text, m.start())}", f"[{m.group(1)}]",
                                       "heading has no link definition"))
    return links


def local_page(path):
    """The file a published path serves, the way GitHub Pages finds it."""
    for candidate in (path, path.with_name(path.name + ".html"), path / "index.html"):
        if candidate.is_file():
            return candidate
    return None


# Deciding how to check each address

def classify(url):
    """Returns (kind, address to fetch). Kinds: skip, page, host, optional."""
    if url.startswith(NAMESPACE_PREFIXES):
        return "skip", "XML namespace, not a link"
    parts = urllib.parse.urlsplit(url)
    if not parts.netloc or "." not in parts.netloc:
        return "skip", "not a complete address"
    if "${" in url or "{" in url:
        return "skip", "code template"
    if parts.netloc in API_HOSTS or (parts.netloc in PRECONNECT_HOSTS and parts.path in ("", "/")):
        return "host", f"{parts.scheme}://{parts.netloc}/"
    if re.search(r"%[.0-9]*[@sdf]", url):
        # A format string: check the page without its parameters.
        return "page", url.split("?", 1)[0]
    if url in OPTIONAL:
        return "optional", url
    return "page", url


def offline_check(link, fetch_url):
    """Checks what can be checked without the network: fragments and files on our own sites."""
    url, _, fragment = fetch_url.partition("#")
    local = None
    if url in LIVE_TO_LOCAL:
        local = ROOT / LIVE_TO_LOCAL[url]
    elif url.startswith(PAGES_PREFIX):
        local = local_page(ROOT / "docs" / url[len(PAGES_PREFIX):].split("?", 1)[0])
        if local is None:
            return "FAIL", "no such file in docs/ for GitHub Pages"
    elif url.startswith(RAW_PREFIX):
        path = ROOT / url[len(RAW_PREFIX):]
        if not path.is_file():
            return ("UNVERIFIED", "optional file, not in the repository yet") if fetch_url in OPTIONAL else ("FAIL", "file not in the repository")
        local = path
    elif url.rstrip("/") == REPO_URL and fragment:
        local = ROOT / "README.md"
    if local is None:
        return "NOT CHECKED", "offline"
    if fragment and fragment not in anchors(local):
        return "FAIL", f"no id \"{fragment}\" in {local.relative_to(ROOT).as_posix()}"
    return "OK", f"matches {local.relative_to(ROOT).as_posix()}" + (f"#{fragment}" if fragment else "")


# Fetching

def ssl_context():
    context = ssl.create_default_context()
    for bundle in (os.environ.get("SSL_CERT_FILE"), os.environ.get("REQUESTS_CA_BUNDLE"), "/root/.ccr/ca-bundle.crt"):
        if bundle and os.path.isfile(bundle):
            context.load_verify_locations(bundle)
    return context


CONTEXT = ssl_context()


def fetch(url, method):
    request = urllib.request.Request(url, method=method, headers={
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    })
    try:
        with urllib.request.urlopen(request, timeout=20, context=CONTEXT) as response:
            body = response.read(2_000_000) if method == "GET" else b""
            return response.status, response.geturl(), body, response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        return error.code, url, b"", ""


def get_status(url, want_body=False):
    """Returns (status code or None, final address, body, error). HEAD first, then GET, with two retries."""
    error = ""
    for attempt in range(3):
        try:
            if not want_body:
                code, final, body, ctype = fetch(url, "HEAD")
                if code < 400:
                    return code, final, body, ""
            code, final, body, ctype = fetch(url, "GET")
            if code in (429, 500, 502, 503, 504) and attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            return code, final, body, ""
        except Exception as e:  # Timeouts, DNS failures and refused connections.
            error = str(getattr(e, "reason", e)) or type(e).__name__
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
    return None, url, b"", error


PAGE_CACHE = {}


def page_ids(url):
    """The ids on a fetched page, for checking fragments."""
    if url not in PAGE_CACHE:
        code, final, body, _ = get_status(url, want_body=True)
        PAGE_CACHE[url] = set(ID_RE.findall(body.decode("utf-8", "replace"))) if code and code < 400 else None
    return PAGE_CACHE[url]


def online_check(link, kind, fetch_url):
    url, _, fragment = fetch_url.partition("#")
    host = urllib.parse.urlsplit(url).netloc
    code, final, _, error = get_status(url)
    if kind == "host":
        if code is None:
            return "FAIL", f"host did not answer: {error}"
        return "OK", f"host answers (HTTP {code}); the address itself needs parameters or is only preconnected"
    if kind == "optional":
        if code is not None and code < 400:
            return "OK", f"HTTP {code}"
        return "UNVERIFIED", f"optional file, HTTP {code or error}: {OPTIONAL[url]}"
    if code is None:
        return "FAIL", error
    if url == APP_STORE_PAGE and code == 404:
        return "UNVERIFIED", "HTTP 404: the App Store page appears once the app is live"
    if host in BOT_BLOCKING_HOSTS and code in (403, 429, 999):
        return "UNVERIFIED", f"HTTP {code}: this site blocks robots; open it in a browser to check"
    if code >= 400:
        return "FAIL", f"HTTP {code}"
    detail = f"HTTP {code}" + (f" via {final}" if final.rstrip("/") != url.rstrip("/") else "")
    if fragment:
        if url.rstrip("/") == REPO_URL:
            # GitHub renders README ids with a prefix, so the README itself is checked.
            ids = anchors(ROOT / "README.md")
        else:
            ids = page_ids(url)
        if ids is not None and fragment not in ids:
            return "FAIL", f"{detail}, but no id \"{fragment}\" on the page"
    return "OK", detail


# Crawling the live pages

class LinkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if value and name in ("href", "src") and tag in ("a", "link", "script", "iframe", "img", "source"):
                self.links.append(value.strip())


def crawl(links, failures):
    for page in LIVE_PAGES:
        code, final, body, error = get_status(page, want_body=True)
        if code is None or code >= 400:
            failures.append((page, f"live page did not load: {code or error}"))
            continue
        text = body.decode("utf-8", "replace")
        PAGE_CACHE[page] = set(ID_RE.findall(text))
        parser = LinkParser()
        parser.feed(text)
        for ref in parser.links:
            if re.match(r"^(mailto:|tel:|javascript:|data:)", ref):
                continue
            if ref.startswith("#"):
                if ref[1:] and ref[1:] not in PAGE_CACHE[page]:
                    failures.append((f"{page} {ref}", f"no id \"{ref[1:]}\" on the live page"))
                continue
            absolute = urllib.parse.urljoin(final, ref)
            links.setdefault(absolute, Link(absolute)).add(f"live: {page}")


# Reporting

def run_checks(links, offline):
    def check(link):
        kind, target = classify(link.url)
        if kind == "skip":
            return "SKIPPED", target
        local = offline_check(link, target)
        if offline:
            return local
        # The repository is what the next deploy publishes, so a local failure fails even if the live copy works.
        if local[0] == "FAIL":
            return local
        return online_check(link, kind, target)

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        for link, (status, detail) in zip(links, pool.map(check, links)):
            link.status, link.detail = status, detail


def cell(text):
    return str(text).replace("|", "\\|")


def report(links, local_failures, live_failures, offline):
    order = {"FAIL": 0, "UNVERIFIED": 1, "OK": 2, "NOT CHECKED": 3, "SKIPPED": 4}
    rows = sorted(links, key=lambda l: (order.get(l.status, 9), l.url))
    lines = ["## Link check" + (" (offline: local files and fragments only)" if offline else ""), ""]
    counts = {}
    for l in rows:
        counts[l.status] = counts.get(l.status, 0) + 1
    real_failures = counts.get("FAIL", 0) + len(local_failures) + len(live_failures)
    summary = ", ".join(f"{n} {s.lower()}" for s, n in sorted(counts.items(), key=lambda kv: order.get(kv[0], 9)))
    lines.append(f"**{len(rows)} addresses**: {summary}. **{len(local_failures)} local link failures**, "
                 f"**{len(live_failures)} live page failures**.")
    lines.append("")
    if local_failures or live_failures:
        lines += ["### Local and live page failures", "", "| Where | Link | Problem |", "|---|---|---|"]
        lines += [f"| {cell(w)} | {cell(r)} | {cell(p)} |" for w, r, p in local_failures]
        lines += [f"| live | {cell(w)} | {cell(p)} |" for w, p in live_failures]
        lines.append("")
    lines += ["### Addresses", "", "| Status | Address | Detail | Found in |", "|---|---|---|---|"]
    for l in rows:
        where = l.where[0] + (f" (+{len(l.where) - 1} more)" if len(l.where) > 1 else "")
        lines.append(f"| {l.status} | {cell(l.url)} | {cell(l.detail)} | {cell(where)} |")
    return "\n".join(lines) + "\n", real_failures


def annotate(links, local_failures, live_failures):
    def location(where):
        m = re.match(r"^([^:\s]+):(\d+)$", where)
        return f"file={m.group(1)},line={m.group(2)}" if m else ""

    for l in links:
        if l.status == "FAIL":
            where = next((w for w in l.where if not w.startswith("live:")), l.where[0])
            print(f"::error {location(where)}::Broken link {l.url}: {l.detail}")
        elif l.status == "UNVERIFIED":
            print(f"::warning {location(l.where[0])}::Unverified link {l.url}: {l.detail}")
    for where, ref, problem in local_failures:
        print(f"::error {location(where)}::Broken link {ref}: {problem}")
    for page, problem in live_failures:
        print(f"::error ::Live page {page}: {problem}")


def main():
    parser = argparse.ArgumentParser(description="Check every link in Two Degrees.")
    parser.add_argument("--offline", action="store_true", help="check local files and fragments only")
    parser.add_argument("--summary", help="also write the table to this Markdown file (default: $GITHUB_STEP_SUMMARY)")
    args = parser.parse_args()

    local_failures, live_failures = [], []
    links = collect(local_failures)
    if not args.offline:
        crawl(links, live_failures)
    ordered = list(links.values())
    run_checks(ordered, args.offline)
    table, failures = report(ordered, local_failures, live_failures, args.offline)
    print(table)

    summary = args.summary or os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(table)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        annotate(ordered, local_failures, live_failures)

    if failures:
        print(f"{failures} broken link(s).", file=sys.stderr)
        return 1
    print("Every link works.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
