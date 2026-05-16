"""
RSS Widget  –  calls the local RSS POST service and shows a feed-entry list.
Requires only the Python standard library (tkinter, urllib, webbrowser, json).
Run:  python app.py  [optional-path-to-config.json]
"""

import json
import os
import sys
import threading
import tkinter as tk
import urllib.request
import webbrowser
from tkinter import font as tkfont

# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------
BG_CHARCOAL   = "#1c1f22"
BG_SOFT       = "#252a2e"
TEXT_OFFWHITE = "#f2efe9"
TEXT_MUTED    = "#c8c3ba"
ACCENT_TEAL   = "#0f817a"
ACCENT_HOVER  = "#2baea6"
BORDER        = "#2f363b"

DEFAULT_CONFIG = os.path.join(os.path.dirname(__file__), "config", "feeds.json")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _clean(value):
    if not isinstance(value, str):
        return ""
    return " ".join(value.split())


def _display_subject(entry):
    subject = _clean(entry.get("subject", ""))
    if subject:
        return subject
    description = _clean(entry.get("description", ""))
    if description:
        return description[:60].rstrip() + ("..." if len(description) > 60 else "")
    return "(No subject)"


def load_config(path=None):
    with open(path or DEFAULT_CONFIG, encoding="utf-8") as fh:
        cfg = json.load(fh)
    if not isinstance(cfg, dict):
        raise ValueError("Config must be a JSON object.")
    if not cfg.get("serviceUrl"):
        raise ValueError("Config must have a non-empty serviceUrl.")
    if not isinstance(cfg.get("requests"), list):
        raise ValueError("Config must have a requests array.")
    return cfg


def fetch_feeds(config_path=None):
    cfg = load_config(config_path)
    payload = json.dumps({"requests": cfg["requests"]}).encode("utf-8")

    req = urllib.request.Request(
        cfg["serviceUrl"],
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8")

    summaries = json.loads(body)
    if not isinstance(summaries, list):
        raise ValueError("Service must return a JSON array.")

    entries = []
    for summary in summaries:
        feed_title = _clean(summary.get("title", ""))
        for entry in summary.get("entries") or []:
            entries.append({
                "feed_title": feed_title or "Feed",
                "subject":    _display_subject(entry),
                "link":       _clean(entry.get("link", "")),
                "published":  _clean(entry.get("published", "")),
            })
    return entries


# ---------------------------------------------------------------------------
# Scrollable list frame
# ---------------------------------------------------------------------------

class ScrollableList(tk.Frame):
    """A vertically scrollable frame.  Scrollbar appears only when needed."""

    def __init__(self, parent, **kw):
        super().__init__(parent, bg=BG_CHARCOAL, **kw)

        self._canvas = tk.Canvas(
            self, bg=BG_CHARCOAL, highlightthickness=0, bd=0
        )
        self._scrollbar = tk.Scrollbar(
            self, orient="vertical", command=self._canvas.yview,
            bg=BG_SOFT, troughcolor=BG_CHARCOAL, activebackground=ACCENT_TEAL,
        )
        self._canvas.configure(yscrollcommand=self._on_scroll_set)

        self._canvas.pack(side="left", fill="both", expand=True)

        self.inner = tk.Frame(self._canvas, bg=BG_CHARCOAL)
        self._window_id = self._canvas.create_window(
            (0, 0), window=self.inner, anchor="nw"
        )

        self.inner.bind("<Configure>", self._on_inner_configure)
        self._canvas.bind("<Configure>", self._on_canvas_configure)
        self._canvas.bind("<MouseWheel>", self._on_mousewheel)
        self.inner.bind("<MouseWheel>", self._on_mousewheel)

    def _on_scroll_set(self, lo, hi):
        if float(lo) <= 0.0 and float(hi) >= 1.0:
            self._scrollbar.pack_forget()
        else:
            self._scrollbar.pack(side="right", fill="y", before=self._canvas)
        self._scrollbar.set(lo, hi)

    def _on_inner_configure(self, _event=None):
        self._canvas.configure(scrollregion=self._canvas.bbox("all"))

    def _on_canvas_configure(self, event):
        self._canvas.itemconfigure(self._window_id, width=event.width)

    def _on_mousewheel(self, event):
        self._canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")


# ---------------------------------------------------------------------------
# Main widget window
# ---------------------------------------------------------------------------

class RssWidget(tk.Tk):
    def __init__(self, config_path=None):
        super().__init__()

        self._config_path = config_path
        self._entry_rows = []

        self.title("RSS Widget")
        self.configure(bg=BG_CHARCOAL)

        # size to 15 % of work area
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        w  = max(360, int(sw * 0.15))
        h  = max(380, int(sh * 0.15))
        self.geometry(f"{w}x{h}")
        self.minsize(360, 380)
        self.resizable(True, True)

        self._build_ui()
        self._load_config_info()

        # kick off the first refresh after the window is shown
        self.after(100, self._refresh_async)

    # --- build ---------------------------------------------------------------

    def _build_ui(self):
        body_font   = tkfont.Font(family="Segoe UI", size=8)
        small_font  = tkfont.Font(family="Segoe UI", size=7)
        link_font   = tkfont.Font(family="Segoe UI", size=8, underline=True)
        btn_font    = tkfont.Font(family="Segoe UI", size=8, weight="bold")

        self._fonts = {
            "body": body_font,
            "small": small_font,
            "link": link_font,
            "btn": btn_font,
        }

        # header bar
        header = tk.Frame(self, bg=BG_SOFT, pady=6, padx=8)
        header.pack(fill="x", side="top")

        title_frame = tk.Frame(header, bg=BG_SOFT)
        title_frame.pack(side="left", fill="both", expand=True)

        tk.Label(
            title_frame, text="RSS Widget", bg=BG_SOFT, fg=TEXT_OFFWHITE,
            font=tkfont.Font(family="Segoe UI", size=9, weight="bold"),
            anchor="w",
        ).pack(side="top", fill="x")

        self._lbl_info = tk.Label(
            title_frame, text="Loading config…", bg=BG_SOFT, fg=TEXT_MUTED,
            font=small_font, anchor="w",
        )
        self._lbl_info.pack(side="top", fill="x")

        self._btn_refresh = tk.Button(
            header, text="Refresh", bg=ACCENT_TEAL, fg=TEXT_OFFWHITE,
            activebackground=ACCENT_HOVER, activeforeground=TEXT_OFFWHITE,
            relief="flat", cursor="hand2", font=btn_font, padx=8, pady=3,
            bd=0, command=self._refresh_async,
        )
        self._btn_refresh.pack(side="right", padx=(6, 0))

        separator = tk.Frame(self, height=1, bg=BORDER)
        separator.pack(fill="x", side="top")

        # scrollable list
        self._list = ScrollableList(self)
        self._list.pack(fill="both", expand=True, side="top")

        separator2 = tk.Frame(self, height=1, bg=BORDER)
        separator2.pack(fill="x", side="bottom")

        # footer / status bar
        footer = tk.Frame(self, bg=BG_SOFT, padx=8, pady=4)
        footer.pack(fill="x", side="bottom")

        self._lbl_status = tk.Label(
            footer, text="Waiting for first refresh…", bg=BG_SOFT,
            fg=TEXT_MUTED, font=small_font, anchor="w",
        )
        self._lbl_status.pack(fill="x")

    # --- config info ---------------------------------------------------------

    def _load_config_info(self):
        try:
            cfg = load_config(self._config_path)
            count = len(cfg["requests"])
            self._lbl_info.configure(
                text=f"{cfg['serviceUrl']}  ·  {count} feed{'s' if count != 1 else ''}"
            )
        except Exception as exc:
            self._lbl_info.configure(text="Config error")
            self._set_status(f"Config: {exc}")

    # --- refresh (background thread) ----------------------------------------

    def _refresh_async(self):
        self._btn_refresh.configure(state="disabled")
        self._set_status("Refreshing feeds…")
        threading.Thread(target=self._fetch_thread, daemon=True).start()

    def _fetch_thread(self):
        try:
            entries = fetch_feeds(self._config_path)
            self.after(0, self._render_entries, entries)
        except Exception as exc:
            self.after(0, self._render_error, str(exc))

    # --- rendering -----------------------------------------------------------

    def _clear_list(self):
        for widget in self._list.inner.winfo_children():
            widget.destroy()
        self._entry_rows.clear()

    def _render_entries(self, entries):
        self._clear_list()
        self._btn_refresh.configure(state="normal")

        if not entries:
            tk.Label(
                self._list.inner, text="No feed entries returned.",
                bg=BG_CHARCOAL, fg=TEXT_MUTED,
                font=self._fonts["small"], anchor="w", padx=8, pady=6,
                wraplength=0,
            ).pack(fill="x")
            self._set_status("No entries.")
            return

        for entry in entries:
            self._add_row(entry)

        self._set_status(f"Loaded {len(entries)} entr{'y' if len(entries) == 1 else 'ies'}.")

    def _add_row(self, entry):
        row = tk.Frame(
            self._list.inner, bg=BG_CHARCOAL, pady=5, padx=8,
            highlightbackground=BORDER, highlightthickness=1,
        )
        row.pack(fill="x", side="top")
        row.bind("<MouseWheel>", self._list._on_mousewheel)

        subject = tk.Label(
            row, text=entry["subject"], bg=BG_CHARCOAL, fg=TEXT_OFFWHITE,
            font=self._fonts["body"], anchor="w", justify="left",
            wraplength=1,  # will be updated on resize
        )
        subject.pack(side="left", fill="both", expand=True)
        subject.bind("<MouseWheel>", self._list._on_mousewheel)
        subject.bind("<Configure>", lambda e, lbl=subject, row=row: self._update_wrap(lbl, row))

        if entry.get("link"):
            link_url = entry["link"]
            lbl_link = tk.Label(
                row, text="Link", bg=BG_CHARCOAL, fg=ACCENT_TEAL,
                font=self._fonts["link"], cursor="hand2", anchor="e",
            )
            lbl_link.pack(side="right", padx=(6, 0))
            lbl_link.bind("<Button-1>", lambda _e, url=link_url: self._open_url(url))
            lbl_link.bind("<Enter>",    lambda _e, w=lbl_link: w.configure(fg=ACCENT_HOVER))
            lbl_link.bind("<Leave>",    lambda _e, w=lbl_link: w.configure(fg=ACCENT_TEAL))
            lbl_link.bind("<MouseWheel>", self._list._on_mousewheel)

        self._entry_rows.append(row)

    def _update_wrap(self, label, row):
        # wrap subject text to leave room for the Link label (≈50 px)
        w = row.winfo_width()
        if w > 80:
            label.configure(wraplength=max(40, w - 56))

    def _render_error(self, message):
        self._clear_list()
        self._btn_refresh.configure(state="normal")
        tk.Label(
            self._list.inner, text="Unable to load entries.",
            bg=BG_CHARCOAL, fg=TEXT_MUTED,
            font=self._fonts["small"], anchor="w", padx=8, pady=6,
        ).pack(fill="x")
        self._set_status(message)

    # --- helpers -------------------------------------------------------------

    def _set_status(self, text):
        self._lbl_status.configure(text=text)

    def _open_url(self, url):
        if url.startswith("http"):
            webbrowser.open(url)
        else:
            self._set_status(f"Invalid URL: {url}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    config_arg = sys.argv[1] if len(sys.argv) > 1 else None
    RssWidget(config_path=config_arg).mainloop()
