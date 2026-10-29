// SlimIA in the top bar: the island, in the panel.
//
// A black capsule with Mochi (the one of the pill in front) and a small Mochi for
// each of the other pills, as on SlimIA's compact island. Mochi has the island's
// moods (thinking, working, asking, waiting for a permission, rate limit, error,
// finished, asleep), dances to Spotify, and the panel is the open island: the pill
// in front on the left, the others on the right, a click brings one to the front.
//
// It does not talk to SlimIA: it reads ~/.local/share/coucou/status.json, which the
// SlimIA app rewrites on every hook event and every Spotify change
// (src-tauri/src/status.rs). It opens no connection. The only things it runs are
// SlimIA's own `--shortcut openChat` and `--spotify playPause|next|previous`.
// If SlimIA is not running Mochi is grey.

namespace SlimIA {
    // The moods of BOT_STATES (src/mochi/engine.ts) a hook can cause.
    public enum Mood {
        OFF, SLEEPING, IDLE, FINISHED, THINKING, WORKING, RATELIMIT, ERROR, QUESTION, APPROVAL;

        public static Mood parse (string? name) {
            switch (name) {
                case "finished": return FINISHED;
                case "thinking": return THINKING;
                case "working": return WORKING;
                case "ratelimit": return RATELIMIT;
                case "error": return ERROR;
                case "question": return QUESTION;
                case "approval": return APPROVAL;
                default: return IDLE;
            }
        }

        // Who comes first when several pills disagree: the one that needs you.
        public int rank () {
            switch (this) {
                case APPROVAL: return 8;
                case QUESTION: return 7;
                case ERROR: return 6;
                case RATELIMIT: return 5;
                case WORKING: return 4;
                case THINKING: return 3;
                case FINISHED: return 2;
                case IDLE: return 1;
                default: return 0;
            }
        }

        public bool alerts () {
            return this == APPROVAL || this == QUESTION || this == ERROR;
        }

        // The island's colour for the mood (C in engine.ts).
        public void rgb (out double r, out double g, out double b) {
            switch (this) {
                case WORKING: r = 0.231; g = 0.620; b = 1.000; break;
                case THINKING: r = 0.545; g = 0.361; b = 0.965; break;
                case APPROVAL: r = 0.961; g = 0.647; b = 0.141; break;
                case QUESTION: r = 0.133; g = 0.827; b = 0.933; break;
                case ERROR: r = 0.957; g = 0.314; b = 0.369; break;
                case FINISHED: r = 0.204; g = 0.831; b = 0.600; break;
                case RATELIMIT: r = 0.984; g = 0.573; b = 0.235; break;
                case SLEEPING: r = 0.58; g = 0.635; b = 0.722; break;
                case OFF: r = 0.45; g = 0.46; b = 0.50; break;
                default: r = 0.902; g = 0.914; b = 0.933; break;
            }
        }

        // How much of the colour rises through the body (BotStateCfg.tint).
        public double tint () {
            switch (this) {
                case WORKING: case THINKING: case RATELIMIT: return 0.72;
                case APPROVAL: return 0.78;
                case QUESTION: return 0.75;
                case ERROR: return 0.78;
                case FINISHED: return 0.35;
                case SLEEPING: return 0.32;
                default: return 0.0;
            }
        }
    }

    // Text in the user's language: Portuguese when the locale is, English otherwise.
    string tr (string en, string pt) {
        var lang = Environment.get_variable ("LANGUAGE") ?? Environment.get_variable ("LC_MESSAGES")
            ?? Environment.get_variable ("LANG") ?? "";
        return lang.has_prefix ("pt") ? pt : en;
    }

    string mood_text (Mood m) {
        switch (m) {
            case Mood.THINKING: return tr ("Thinking…", "Pensando…");
            case Mood.WORKING: return tr ("Working…", "Trabalhando…");
            case Mood.APPROVAL: return tr ("needs permission", "precisa de permissão");
            case Mood.QUESTION: return tr ("has a question", "tem uma pergunta");
            case Mood.RATELIMIT: return tr ("Rate limit reached", "Limite de uso atingido");
            case Mood.FINISHED: return tr ("Finished", "Terminou");
            case Mood.ERROR: return tr ("Something went wrong", "Algo deu errado");
            case Mood.SLEEPING: return tr ("Sleeping", "Dormindo");
            case Mood.OFF: return tr ("SlimIA is not running", "O SlimIA não está aberto");
            default: return tr ("Nothing running", "Nada rodando");
        }
    }

    // The name of an agent as the island writes it (sessionSubtitle, island/agents.ts).
    string agent_name (string agent) {
        switch (agent) {
            case "claude": return "Claude Code";
            case "cursor": return "Cursor";
            case "codex": return "Codex";
            case "gemini": return "Gemini CLI";
            case "copilot": return "Copilot CLI";
            case "muse": return "Muse Code";
            case "opencode": return "OpenCode";
            case "amp": return "Amp";
            case "hermes": return "Hermes";
            case "antigravity": return "Antigravity";
            default: return agent.length > 0 ? agent.substring (0, 1).up () + agent.substring (1) : "Agent";
        }
    }

    // One pill of the island: a session of an agent, or the music.
    public class Pill {
        public string id = "";
        public bool is_music = false;
        public string label = "";
        public string detail = "";
        public Mood mood = Mood.IDLE;
        public double r = 0.96;
        public double g = 0.96;
        public double b = 0.97;
        // The workspace tools (Claude Code…) wear Mochi's own body; the others, a flat colour.
        public bool flat = false;
        // "Claude Code", "Gemini CLI"…: the agent behind the pill.
        public string kind = "Claude Code";
        // The app's name, which is what a pill is called: Claude Code, Spotify…
        public string app = "Claude Code";
        public Json.Array? steps = null;
        public int64 updated_at = 0;
        // The permission request waiting on the island: the bar can answer it.
        public string request = "";
        // The capsule was clicked since this state began.
        public bool seen = false;
    }

    public class Indicator : Wingpanel.Indicator {
        private const double INK_R = 0.102;
        private const double INK_G = 0.078;
        private const double INK_B = 0.071;
        // The 112 BPM of the island's dance (danceTransform in engine.ts).
        private const double BPM = 112.0;

        // Where the page with the island's own Mochi engine is installed (web/).
        private const string WEB_DIR = "/usr/share/coucou-indicator/";

        private Gtk.EventBox? capsule = null;
        private Gtk.DrawingArea? cap_draw = null;
        private WebKit.WebView? cap_view = null;
        private WebKit.WebView? big_view = null;
        private Gtk.EventBox? big_box = null;
        private string last_scene = "";
        private WebKit.WebView? answer_view = null;
        private string answer_sent = "";
        private Gtk.Box? panel = null;
        private Gtk.Revealer? reveal = null;
        private Gtk.DrawingArea? big_mochi = null;
        private Gtk.DrawingArea? progress_bar = null;
        private Gtk.Label? time_now = null;
        private Gtk.Label? time_total = null;
        private static bool styled = false;

        private Mood mood = Mood.OFF;
        private string exe = "";
        private GLib.List<Pill> pills = new GLib.List<Pill> ();
        private Json.Object? music = null;
        private string answer_project = "";
        private string answer_body = "";
        private int64 answer_at = 0;
        private int64 file_updated_at = 0;
        private string? pinned = null;
        private string last_raw = "";
        private bool popup_open = false;
        private bool blinking = false;
        private uint poll_id = 0;
        private uint tick_id = 0;
        private uint blink_id = 0;
        private double t0 = 0;
        // When the front pill finished: Mochi hops once.
        private double finished_at = -10;
        private Mood last_front_mood = Mood.OFF;
        // Interaction and easing: hover, a click's pop, the tint fading between moods.
        private double hover_k = 0;
        private double hover_to = 0;
        private double look_x = 0;
        private double pop_at = -10;
        private double tint_from = 0;
        private double tint_at = -10;
        private double shown_w = 0;
        private double hover_since = 0;
        private double pet_at = -10;
        private double dance_level = 0;

        public Indicator () {
            Object (code_name: "coucou");
            visible = true;
            t0 = now_s ();
        }

        private static double now_s () {
            return GLib.get_monotonic_time () / 1000000.0;
        }

        private static string status_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "coucou", "status.json");
        }

        // ── Wingpanel ────────────────────────────────────────────────────────

        public override Gtk.Widget get_display_widget () {
            if (capsule == null) {
                capsule = new Gtk.EventBox ();
                capsule.visible_window = false;
                capsule.above_child = true;
                capsule.set_size_request (wanted_width (), 28);
                // The island's own Mochi when its page is installed; else a Cairo copy.
                cap_view = make_view ("index.html", "", wanted_width (), 28);
                if (cap_view != null) {
                    capsule.add (cap_view);
                } else {
                    cap_draw = new Gtk.DrawingArea ();
                    cap_draw.draw.connect (draw_capsule);
                    capsule.add (cap_draw);
                }
                capsule.show_all ();
                capsule.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK
                    | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK
                    | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK);
                capsule.enter_notify_event.connect (() => { hover_to = 1; hover_since = now_s (); js (cap_view, "coucou.hover(true)"); ensure_tick (); return false; });
                capsule.leave_notify_event.connect (() => { hover_to = 0; hover_since = 0; look_x = 0; js (cap_view, "coucou.hover(false)"); ensure_tick (); return false; });
                capsule.motion_notify_event.connect ((ev) => {
                    double half = capsule.get_allocated_width () / 2.0;
                    look_x = double.max (-1.0, double.min (1.0, (ev.x - half) / half));
                    double vy = (ev.y - capsule.get_allocated_height () / 2.0) / 40.0;
                    js (cap_view, "coucou.look(%.3f,%.3f)".printf (look_x * 0.6, vy));
                    return false;
                });
                capsule.button_press_event.connect ((ev) => {
                    pop_at = now_s ();
                    js (cap_view, "coucou.click()");
                    // The click is the "seen" of whatever was blinking.
                    run_coucou ({ "--ack" });
                    ensure_tick ();
                    if (ev.button == 2 && music_playing ()) {
                        // Middle click: play/pause without opening anything.
                        player ("playPause");
                        return true;
                    }
                    return false;
                });
                capsule.scroll_event.connect ((ev) => {
                    cycle (ev.direction == Gdk.ScrollDirection.UP
                        || (ev.direction == Gdk.ScrollDirection.SMOOTH && ev.delta_y < 0) ? -1 : 1);
                    return true;
                });
                refresh ();
                // The file is tiny: reading it once a second costs nothing.
                poll_id = Timeout.add_seconds (1, () => { refresh (); return true; });
                // He blinks every 2–5 s, sometimes twice, as the island does.
                schedule_blink ();
            }
            return capsule;
        }

        public override Gtk.Widget? get_widget () {
            if (panel == null) {
                install_style ();
                panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                panel.get_style_context ().add_class ("coucou-island");
                update_panel ();
                reveal = new Gtk.Revealer ();
                reveal.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
                reveal.transition_duration = 260;
                reveal.add (panel);
                reveal.show_all ();
            }
            return reveal;
        }

        public override void opened () {
            popup_open = true;
            refresh ();
            update_panel ();
            ensure_tick ();
            // The island grows out of the capsule, like the original.
            reveal.reveal_child = false;
            Idle.add (() => { reveal.reveal_child = true; return false; });
            var top = panel.get_toplevel ();
            if (top != null) {
                top.get_style_context ().add_class ("coucou-pop");
            }
        }

        public override void closed () {
            popup_open = false;
        }

        // The wheel over the capsule walks through the pills (agents, then the music).
        private void cycle (int step) {
            int n = (int) pills.length ();
            if (n < 2) {
                return;
            }
            var f = front ();
            int at = 0;
            for (int i = 0; i < n; i++) {
                if (f != null && pills.nth_data (i).id == f.id) {
                    at = i;
                }
            }
            pinned = pills.nth_data (((at + step) % n + n) % n).id;
            pop_at = now_s ();
            recompute_mood ();
            if (popup_open) {
                update_panel ();
            }
            update_size ();
            redraw ();
        }

        private static void heart (Cairo.Context cr, double x, double y, double s) {
            cr.new_path ();
            cr.move_to (x, y + s * 0.9);
            cr.curve_to (x - s * 1.4, y - s * 0.2, x - s * 0.6, y - s * 1.1, x, y - s * 0.35);
            cr.curve_to (x + s * 0.6, y - s * 1.1, x + s * 1.4, y - s * 0.2, x, y + s * 0.9);
            cr.close_path ();
        }

        private static void star (Cairo.Context cr, double x, double y, double s) {
            cr.new_path ();
            for (int i = 0; i < 8; i++) {
                double a = i * Math.PI / 4 - Math.PI / 2;
                double rr = i % 2 == 0 ? s : s * 0.3;
                if (i == 0) cr.move_to (x + Math.cos (a) * rr, y + Math.sin (a) * rr);
                else cr.line_to (x + Math.cos (a) * rr, y + Math.sin (a) * rr);
            }
            cr.close_path ();
        }

        // Hearts floating up while he is petted (hovered a while, or the big Mochi clicked).
        private void paint_hearts (Cairo.Context cr, double cx, double cy, double R, double rise) {
            double u = (now_s () - pet_at) / 1.8;
            if (u < 0 || u >= 1) {
                return;
            }
            for (int i = 0; i < 3; i++) {
                double k = double.max (0.0, double.min (1.0, u * 1.25 - i * 0.18));
                if (k <= 0 || k >= 1) continue;
                cr.set_source_rgba (1.0, 0.45, 0.62, 1.0 - k * k);
                heart (cr, cx + (i - 1) * R * 0.95 + Math.sin (k * 5 + i) * R * 0.2, cy - R * 0.5 - k * rise,
                    R * 0.3 * (0.6 + 0.4 * Math.sin (Math.PI * k)));
                cr.fill ();
            }
        }

        private static double ease (double u) {
            u = double.max (0.0, double.min (1.0, u));
            return u * u * (3 - 2 * u);
        }

        private double cur_tint () {
            double to = mood.tint ();
            return tint_from + (to - tint_from) * ease ((now_s () - tint_at) / 0.4);
        }

        private void blink_once () {
            blinking = true;
            redraw ();
            Timeout.add (130, () => { blinking = false; redraw (); return false; });
        }

        private void schedule_blink () {
            uint wait = (uint) ((2.2 + Random.next_double () * 3.2) * 1000);
            blink_id = Timeout.add (wait, () => {
                if (mood != Mood.SLEEPING && mood != Mood.OFF) {
                    blink_once ();
                    if (Random.next_double () < 0.22) {
                        Timeout.add (230, () => { blink_once (); return false; });
                    }
                }
                schedule_blink ();
                return false;
            });
        }

        // ── The page with the island's Mochi ─────────────────────────────────

        private WebKit.WebView? make_view (string page, string hash, int w, int h) {
            if (!FileUtils.test (WEB_DIR + page, FileTest.EXISTS)) {
                return null;
            }
            // Nothing is kept: no cookies, no cache, no storage.
            var view = new WebKit.WebView.with_context (new WebKit.WebContext.ephemeral ());
            view.set_background_color ({ 0, 0, 0, 0 });
            view.set_size_request (w, h);
            view.can_focus = false;
            view.get_settings ().enable_developer_extras = false;
            view.context_menu.connect (() => true);
            // It only ever shows its own page.
            view.decide_policy.connect ((decision, type) => {
                if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                    var nav = (WebKit.NavigationPolicyDecision) decision;
                    if (!nav.navigation_action.get_request ().uri.has_prefix ("file://")) {
                        decision.ignore ();
                        return true;
                    }
                }
                return false;
            });
            view.load_changed.connect ((ev) => {
                if (ev == WebKit.LoadEvent.FINISHED) {
                    last_scene = "";
                    push_scene ();
                    answer_sent = "";
                    push_answer ();
                }
            });
            view.load_uri ("file://" + WEB_DIR + page + hash);
            return view;
        }

        private void js (WebKit.WebView? view, string code) {
            if (view != null) {
                view.run_javascript.begin (code, null);
            }
        }

        private static string mood_key (Mood m) {
            switch (m) {
                case Mood.SLEEPING: return "sleeping";
                case Mood.FINISHED: return "finished";
                case Mood.THINKING: return "thinking";
                case Mood.WORKING: return "working";
                case Mood.RATELIMIT: return "ratelimit";
                case Mood.ERROR: return "error";
                case Mood.QUESTION: return "question";
                case Mood.APPROVAL: return "approval";
                default: return "idle";
            }
        }

        private static string pill_json (Pill p, Mood mood, bool dancing) {
            return "{\"id\":\"%s\",\"state\":\"%s\",\"color\":\"#%02x%02x%02x\",\"flat\":%s,\"dancing\":%s,\"seen\":%s}".printf (
                p.id.replace ("\\", "").replace ("\"", ""), mood_key (mood),
                (int) Math.round (p.r * 255), (int) Math.round (p.g * 255), (int) Math.round (p.b * 255),
                p.flat ? "true" : "false", dancing ? "true" : "false", p.seen ? "true" : "false");
        }

        // What the page draws: the pill in front, and the others as minis.
        private void push_scene () {
            if (cap_view == null) {
                return;
            }
            var f = front ();
            var sb = new StringBuilder ("{\"front\":");
            sb.append (f != null ? pill_json (f, mood, dancing ()) : "null");
            sb.append (",\"others\":[");
            int n = 0;
            foreach (var p in others (f)) {
                if (n >= 4) break;
                if (n > 0) sb.append (",");
                sb.append (pill_json (p, p.mood, p.is_music && music_playing ()));
                n++;
            }
            sb.append ("]}");
            string scene = sb.str;
            if (scene == last_scene) {
                return;
            }
            last_scene = scene;
            js (cap_view, "coucou.set(" + scene + ")");
            js (big_view, "coucou.set(" + scene + ")");
        }

        // The last answer goes to its page as a JSON string; the page draws the markdown.
        private void push_answer () {
            if (answer_view == null || answer_body == "" || answer_body == answer_sent) {
                return;
            }
            var node = new Json.Node (Json.NodeType.VALUE);
            node.set_string (answer_body);
            var gen = new Json.Generator ();
            gen.root = node;
            answer_sent = answer_body;
            js (answer_view, "coucou.answer(" + gen.to_data (null) + ")");
        }

        private void redraw () {
            if (cap_draw != null) cap_draw.queue_draw ();
            if (big_mochi != null) big_mochi.queue_draw ();
        }

        // ── Commands to SlimIA ───────────────────────────────────────────────

        private void run_coucou (string[] args) {
            if (exe == "") {
                return;
            }
            string[] argv = { exe };
            foreach (var a in args) {
                argv += a;
            }
            try {
                Process.spawn_async (null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, null);
            } catch (Error e) {
                warning ("coucou: could not run: %s", e.message);
            }
        }

        // Allow / Deny for the request the island is waiting on.
        private void decide (string decision, string request) {
            foreach (var p in pills) {
                if (p.request == request) {
                    p.request = "";
                }
            }
            pop_at = now_s ();
            run_coucou ({ "--decide", decision, request });
            close ();
        }

        private void open_chat () {
            close ();
            // A second launch only brings the running SlimIA forward (single instance).
            run_coucou ({ "--shortcut", "openChat" });
        }

        private void player (string action) {
            run_coucou ({ "--spotify", action });
        }

        // ── Reading the status file ──────────────────────────────────────────

        private void refresh () {
            string raw;
            try {
                FileUtils.get_contents (status_path (), out raw);
            } catch (Error e) {
                apply_off ();
                return;
            }
            if (raw == last_raw && mood != Mood.OFF) {
                // Nothing new in the file: only the clock (sleep) can have changed.
                recompute_mood ();
                return;
            }
            last_raw = raw;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (raw);
                var root = parser.get_root ().get_object ();
                var pid = (uint) root.get_int_member_with_default ("pid", 0);
                if (pid == 0 || !FileUtils.test ("/proc/%u".printf (pid), FileTest.EXISTS)) {
                    apply_off ();
                    return;
                }
                exe = root.get_string_member_with_default ("exe", "");
                file_updated_at = root.get_int_member_with_default ("updatedAt", 0);
                load_pills (root);
                answer_project = ""; answer_body = ""; answer_at = 0;
                if (root.has_member ("lastAnswer") && !root.get_null_member ("lastAnswer")) {
                    var a = root.get_object_member ("lastAnswer");
                    answer_project = a.get_string_member_with_default ("project", "");
                    answer_body = a.get_string_member_with_default ("text", "");
                    answer_at = a.get_int_member_with_default ("at", 0);
                }
                recompute_mood ();
                update_panel ();
            } catch (Error e) {
                apply_off ();
            }
        }

        private static void parse_hex (string hex, out double r, out double g, out double b) {
            r = 0.6; g = 0.62; b = 0.66;
            if (hex.length == 7 && hex.has_prefix ("#")) {
                uint64 v = 0;
                if (uint64.try_parse (hex.substring (1), out v, null, 16)) {
                    r = ((v >> 16) & 255) / 255.0;
                    g = ((v >> 8) & 255) / 255.0;
                    b = (v & 255) / 255.0;
                }
            }
        }

        private void load_pills (Json.Object root) {
            pills = new GLib.List<Pill> ();
            if (root.has_member ("sessions")) {
                var arr = root.get_array_member ("sessions");
                string newest_claude = "";
                int64 newest_at = -1;
                for (uint k = 0; k < arr.get_length (); k++) {
                    var c = arr.get_object_element (k);
                    int64 at = c.get_int_member_with_default ("updatedAt", 0);
                    if (c.get_string_member_with_default ("agent", "claude") == "claude" && at > newest_at) {
                        newest_at = at;
                        newest_claude = c.get_string_member_with_default ("id", "");
                    }
                }
                for (uint i = 0; i < arr.get_length (); i++) {
                    var s = arr.get_object_element (i);
                    var p = new Pill ();
                    p.id = s.get_string_member_with_default ("id", "");
                    p.label = s.get_string_member_with_default ("project", "");
                    p.detail = s.get_string_member_with_default ("detail", "");
                    p.request = s.get_string_member_with_default ("request", "");
                    p.seen = s.get_boolean_member_with_default ("seen", false);
                    p.mood = Mood.parse (s.get_string_member_with_default ("state", "idle"));
                    // An idle or finished session that nobody touched for two minutes is not shown
                    // (the file only changes when something happens).
                    int64 age = GLib.get_real_time () / 1000 - s.get_int_member_with_default ("updatedAt", 0);
                    // Finished and failed, once seen, rest after two minutes.
                    if ((p.mood == Mood.FINISHED || p.mood == Mood.ERROR) && p.seen && age > 2 * 60 * 1000) {
                        p.mood = Mood.IDLE;
                    }
                    bool quiet = p.mood == Mood.IDLE && age > 2 * 60 * 1000;
                    // The newest Claude Code pill stays online, whatever it is doing.
                    if (quiet && !(s.get_string_member_with_default ("agent", "claude") == "claude"
                                   && s.get_string_member_with_default ("id", "") == newest_claude)) {
                        continue;
                    }
                    parse_hex (s.get_string_member_with_default ("color", "#F5F6F8"), out p.r, out p.g, out p.b);
                    var agent = s.get_string_member_with_default ("agent", "claude");
                    p.kind = agent_name (agent);
                    p.app = p.kind;
                    p.flat = !(agent == "claude" || agent == "cursor" || agent == "codex" || agent == "antigravity");
                    p.steps = s.has_member ("steps") ? s.get_array_member ("steps") : null;
                    p.updated_at = s.get_int_member_with_default ("updatedAt", 0);
                    pills.append (p);
                }
            }
            music = null;
            if (root.has_member ("music") && !root.get_null_member ("music")) {
                var m = root.get_object_member ("music");
                if (m.has_member ("track") && !m.get_null_member ("track")) {
                    music = m;
                    var p = new Pill ();
                    p.id = "spotify";
                    p.is_music = true;
                    p.app = "Spotify";
                    var track = m.get_object_member ("track");
                    var title = track.get_string_member_with_default ("title", "");
                    p.label = title != "" ? title : "Spotify";
                    p.detail = track.get_string_member_with_default ("artist", "");
                    p.mood = Mood.IDLE;
                    p.r = 0.114; p.g = 0.725; p.b = 0.329;   // #1DB954
                    p.flat = true;
                    pills.append (p);
                }
            }
        }

        private bool music_playing () {
            return music != null && music.get_boolean_member_with_default ("playing", false);
        }

        // The pill in front: an alert wins, then the one you picked, then the busiest;
        // the music when nothing else is going on.
        private Pill? front () {
            Pill? best = null;
            foreach (var p in pills) {
                if (p.mood.alerts () && (best == null || p.mood.rank () > best.mood.rank ())) {
                    best = p;
                }
            }
            if (best != null) {
                return best;
            }
            if (pinned != null) {
                foreach (var p in pills) {
                    if (p.id == pinned) {
                        return p;
                    }
                }
                pinned = null;
            }
            foreach (var p in pills) {
                if (!p.is_music && (best == null || p.mood.rank () > best.mood.rank ())) {
                    best = p;
                }
            }
            if (best == null || best.mood.rank () <= Mood.FINISHED.rank ()) {
                foreach (var p in pills) {
                    if (p.is_music && music_playing ()) {
                        return p;
                    }
                }
            }
            return best;
        }

        private GLib.List<Pill> others (Pill? of) {
            var list = new GLib.List<Pill> ();
            foreach (var p in pills) {
                if (of == null || p.id != of.id) {
                    list.append (p);
                }
            }
            return list;
        }

        // What Mochi shows: the front pill's mood, or asleep after a long rest.
        private void recompute_mood () {
            var f = front ();
            Mood next = f != null ? f.mood : Mood.IDLE;
            if (next == Mood.IDLE && !music_playing ()) {
                int64 now_ms = GLib.get_real_time () / 1000;
                if (file_updated_at > 0 && now_ms - file_updated_at > 5 * 60 * 1000) {
                    next = Mood.SLEEPING;
                }
            }
            set_mood (next);
        }

        private void apply_off () {
            pills = new GLib.List<Pill> ();
            music = null;
            last_raw = "";
            set_mood (Mood.OFF);
            update_panel ();
        }

        private void set_mood (Mood next) {
            if (next == Mood.FINISHED && last_front_mood != Mood.FINISHED) {
                finished_at = now_s ();
            }
            bool changed = next != mood;
            if (changed) {
                tint_from = cur_tint ();
                if (mood != Mood.OFF && next != Mood.SLEEPING) {
                    blink_once ();
                }
                tint_at = now_s ();
                pop_at = now_s ();
            }
            last_front_mood = next;
            mood = next;
            update_size ();
            if (capsule != null) {
                string hint = mood_text (mood);
                var f = front ();
                if (f != null && f.detail != "") {
                    hint = (f.is_music ? f.label + " · " : "") + f.detail;
                }
                capsule.set_tooltip_text (hint);
            }
            if (changed) {
                redraw ();
            }
            push_scene ();
            ensure_tick ();
        }

        // ── Animation clock ──────────────────────────────────────────────────

        private bool dancing () {
            if (!music_playing ()) {
                return false;
            }
            // The states Mochi dances in; the rest (an alert, an error, sleep) win.
            return mood == Mood.IDLE || mood == Mood.WORKING || mood == Mood.THINKING || mood == Mood.FINISHED;
        }

        private bool animating () {
            if (mood == Mood.OFF) {
                return false;
            }
            if (cap_view != null) {
                // The page animates itself; only the progress bar needs a clock.
                return popup_open && music_playing ();
            }
            if (others_count () > 0 || (dancing () ? 1.0 : 0.0) != dance_level) {
                return true;
            }
            if (dancing () || mood == Mood.THINKING || mood == Mood.WORKING || mood == Mood.APPROVAL
                || mood == Mood.QUESTION || mood == Mood.RATELIMIT || mood == Mood.SLEEPING) {
                return true;
            }
            if (now_s () - finished_at < 1.0) {
                return true;
            }
            if (now_s () - pet_at < 1.9 || hover_k != hover_to || now_s () - pop_at < 0.55 || now_s () - tint_at < 0.45
                || Math.fabs (shown_w - wanted_width ()) > 0.4) {
                return true;
            }
            return popup_open && music_playing ();
        }

        private void ensure_tick () {
            if (tick_id == 0 && animating ()) {
                tick_id = Timeout.add (40, () => {
                    hover_k += (hover_to - hover_k) * 0.35;
                    if (Math.fabs (hover_to - hover_k) < 0.01) hover_k = hover_to;
                    shown_w += (wanted_width () - shown_w) * 0.3;
                    // The dance fades in over 0.3 s and out over 0.5 s.
                    double dt_ = dancing () ? 1.0 : 0.0;
                    dance_level = dt_ > dance_level ? double.min (dt_, dance_level + 0.04 / 0.3)
                                                    : double.max (dt_, dance_level - 0.04 / 0.5);
                    // Left hovering for a while: he enjoys it.
                    if (hover_since > 0 && now_s () - hover_since > 1.2 && now_s () - pet_at > 2.8) {
                        pet_at = now_s ();
                    }
                    redraw ();
                    update_progress ();
                    if (!animating ()) {
                        tick_id = 0;
                        redraw ();
                        return false;
                    }
                    return true;
                });
            }
        }

        // ── Drawing ──────────────────────────────────────────────────────────
        //
        // The same look as SlimIA's island: a soft grey body with a highlight, two
        // dark eyes that blink, the colour of the mood rising from the bottom, a badge
        // when something needs you. Flat-coloured for the pills that are not workspace
        // tools, as the island does.

        private static void squircle (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private static void ellipse (Cairo.Context cr, double cx, double cy, double rx, double ry) {
            cr.save ();
            cr.translate (cx, cy);
            cr.scale (rx, ry);
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.restore ();
        }

        // The island's badge: a ring and a disc of the mood's colour, with what it means inside.
        private void paint_badge (Cairo.Context cr, double x, double y, double size, Mood m, double t) {
            double r, g, b;
            m.rgb (out r, out g, out b);
            cr.set_source_rgb (0, 0, 0);
            cr.arc (x, y, size * 1.18, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgb (r, g, b);
            cr.arc (x, y, size, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgb (1, 1, 1);
            if (m == Mood.WORKING || m == Mood.THINKING) {
                // Three dots, one after the other.
                for (int i = 0; i < 3; i++) {
                    double k = 0.5 + 0.5 * Math.sin (t * 7.0 - i * 0.9);
                    cr.arc (x + (i - 1) * size * 0.52, y, size * (0.13 + 0.07 * k), 0, 2 * Math.PI);
                    cr.fill ();
                }
            } else if (m == Mood.APPROVAL) {
                cr.set_line_width (size * 0.28);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.move_to (x, y - size * 0.5);
                cr.line_to (x, y + size * 0.12);
                cr.stroke ();
                cr.arc (x, y + size * 0.5, size * 0.15, 0, 2 * Math.PI);
                cr.fill ();
            } else if (m == Mood.QUESTION) {
                cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                cr.set_font_size (size * 1.5);
                Cairo.TextExtents ext;
                cr.text_extents ("?", out ext);
                cr.move_to (x - ext.width / 2 - ext.x_bearing, y - ext.height / 2 - ext.y_bearing);
                cr.show_text ("?");
            }
        }

        private void paint_mochi (Cairo.Context cr, double cx, double cy, double R, Mood m, Pill? pill, bool dance, double t) {
            double sx = 1.0, sy = 1.0, dx = 0.0, dy = 0.0, rot = 0.0;
            // Breathing and the small motions of each mood.
            switch (m) {
                case Mood.SLEEPING:
                    sy = 1.0 + 0.035 * Math.sin (t * 1.6);
                    sx = 1.0 - 0.02 * Math.sin (t * 1.6);
                    break;
                case Mood.APPROVAL:
                    // Bounces, asking to be answered.
                    dy = -0.16 * R * Math.fabs (Math.sin (t * Math.PI * 1.7));
                    break;
                case Mood.QUESTION:
                    rot = 0.17 + 0.03 * Math.sin (t * 2.2);
                    break;
                case Mood.WORKING:
                case Mood.THINKING:
                    sy = 1.0 + 0.02 * Math.sin (t * 4.0);
                    break;
                default:
                    break;
            }
            if (m == Mood.ERROR) {
                double u = now_s () - tint_at;
                // The island's ox keys: +0.08, -0.08, +0.05, 0 over 50/70/70/90 ms.
                double[] at = { 0.0, 0.05, 0.12, 0.19, 0.28 };
                double[] to = { 0.0, 0.08, -0.08, 0.05, 0.0 };
                for (int i = 1; i < 5 && u >= 0 && u < 0.28; i++) {
                    if (u < at[i]) {
                        dx += (to[i - 1] + (to[i] - to[i - 1]) * ease ((u - at[i - 1]) / (at[i] - at[i - 1]))) * 2 * R;
                        break;
                    }
                }
            }
            if (m == Mood.APPROVAL) {
                // Up 0.2 and back with a little overshoot when the request arrives.
                double u = now_s () - tint_at;
                if (u >= 0 && u < 0.45) {
                    dy -= (u < 0.15 ? ease (u / 0.15) : 1 - ease ((u - 0.15) / 0.3)) * 0.4 * R;
                }
            }
            // A hop when the work is done.
            double since = now_s () - finished_at;
            if (m == Mood.FINISHED && since >= 0 && since < 0.95) {
                // A full roll in 950 ms, like the island.
                rot += 2 * Math.PI * ease (since / 0.95);
                double u = 0;
                u = 0;
            }
            if (dance_level > 0) {
                double dl = dance_level;
                // danceTransform: a sway, a hop, a tilt and a squash on landing.
                double beat = t * BPM / 60.0;
                double hop = Math.fabs (Math.sin (Math.PI * beat));
                double land = Math.pow (1 - hop, 6);
                dx += 0.08 * R * Math.sin (Math.PI * beat) * dl;
                dy += -0.2 * R * hop * dl;
                rot += 0.1 * Math.sin (Math.PI * beat) * dl;
                sx *= 1 + 0.045 * land * dl;
                sy *= 1 - 0.06 * land * dl;
            }

            // Hover: he perks up. A click or a change of mood: a little pop.
            {
                double pu = (now_s () - pop_at) / 0.5;
                double pop = (pu >= 0 && pu < 1) ? 0.16 * Math.sin (Math.PI * pu) * (1 - pu) : 0.0;
                sx *= 1 + pop;
                sy *= 1 - pop * 0.7;
            }

            double rw = R * 1.12;
            double rh = R * 0.98;
            double alpha = m == Mood.OFF ? 0.5 : 1.0;
            bool flat = pill != null && pill.flat;

            cr.save ();
            cr.translate (cx + dx, cy + dy);
            cr.rotate (rot);
            cr.scale (sx, sy);

            cr.save ();
            squircle (cr, -rw, -rh, rw * 2, rh * 2, rh * 0.84);
            cr.clip ();
            if (flat) {
                cr.set_source_rgba (pill.r, pill.g, pill.b, 1);
                cr.paint ();
            } else {
                var body = new Cairo.Pattern.linear (rw * 0.7, -rh * 0.85, -rw * 0.8, rh * 0.9);
                body.add_color_stop_rgba (0, 0.929, 0.929, 0.937, alpha);
                body.add_color_stop_rgba (1, 0.769, 0.773, 0.792, alpha);
                cr.set_source (body);
                cr.paint ();
                double tint = cur_tint ();
                if (tint > 0) {
                    double tr_, tg, tb;
                    m.rgb (out tr_, out tg, out tb);
                    var tp = new Cairo.Pattern.linear (0, rh, 0, -rh);
                    tp.add_color_stop_rgba (0, tr_, tg, tb, tint);
                    tp.add_color_stop_rgba (1, tr_, tg, tb, 0);
                    cr.set_source (tp);
                    cr.paint ();
                }
                var shade = new Cairo.Pattern.radial (0, 0, R * 0.15, 0, 0, R * 1.25);
                shade.add_color_stop_rgba (0, 0, 0, 0, 0);
                shade.add_color_stop_rgba (0.6, 0, 0, 0, 0);
                shade.add_color_stop_rgba (1, 0, 0, 0, 0.2);
                cr.set_source (shade);
                cr.paint ();
                var light = new Cairo.Pattern.radial (rw * 0.34, -rh * 0.46, 0, rw * 0.34, -rh * 0.46, R * 0.42);
                light.add_color_stop_rgba (0, 1, 1, 1, 0.55 * alpha * alpha);
                light.add_color_stop_rgba (1, 1, 1, 1, 0);
                cr.set_source (light);
                cr.paint ();
            }
            cr.restore ();

            paint_eyes (cr, R, m, dance, flat, t);

            // Badge, as the island: dots while it works, ! when it needs you, ? when it asks.
            switch (m) {
                case Mood.WORKING: case Mood.THINKING: case Mood.APPROVAL: case Mood.QUESTION:
                case Mood.ERROR: case Mood.FINISHED: case Mood.RATELIMIT:
                    {
                        // The badge pops in with a little overshoot, 100 ms after the mood.
                        double bu = double.max (0.0, double.min (1.0, (now_s () - tint_at - 0.1) / 0.28));
                        double bs = 1 + 2.70158 * Math.pow (bu - 1, 3) + 1.70158 * Math.pow (bu - 1, 2);
                        paint_badge (cr, rw * 0.9, -rh * 0.9, double.max (R * 0.36, 3.0) * bs, m, t);
                    }
                    break;
                default:
                    break;
            }

            // Sweat while the rate limit holds him back; z's while he sleeps.
            if (m == Mood.RATELIMIT) {
                double fall = (t * 0.9) - Math.floor (t * 0.9);
                cr.set_source_rgba (0.55, 0.78, 1.0, 1.0 - fall * 0.7);
                cr.arc (-rw * 0.85, -rh * 0.3 + fall * R * 0.7, R * 0.12, 0, 2 * Math.PI);
                cr.fill ();
            }
            if (m == Mood.SLEEPING) {
                cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                for (int i = 0; i < 2; i++) {
                    double k = ((t * 0.5 + i * 0.5) - Math.floor (t * 0.5 + i * 0.5));
                    cr.set_font_size (R * (0.45 + 0.25 * k));
                    cr.set_source_rgba (0.8, 0.85, 0.95, 1.0 - k);
                    cr.move_to (rw * 0.55 + k * R * 0.5, -rh * 0.5 - k * R * 0.9);
                    cr.show_text ("z");
                }
            }
            cr.restore ();
        }

        private void paint_eyes (Cairo.Context cr, double R, Mood m, bool dance, bool flat, double t) {
            double ex = R * 0.37;
            double ey = -R * 0.12;
            if (flat) {
                cr.set_source_rgb (0.063, 0.075, 0.102);
            } else {
                cr.set_source_rgba (INK_R, INK_G, INK_B, m == Mood.OFF ? 0.55 : 1.0);
            }
            double lx = look_x * hover_k * R * 0.13, ly = 0;
            if (m == Mood.THINKING) {
                lx = R * 0.14; ly = -R * 0.12;
            } else if (m == Mood.WORKING) {
                lx = Math.sin (t * 2.4) * R * 0.14;
            }
            cr.set_line_cap (Cairo.LineCap.ROUND);
            bool calm_happy = (dance || now_s () - pet_at < 1.8) && (m == Mood.IDLE || m == Mood.FINISHED || m == Mood.THINKING || m == Mood.WORKING);
            if (m == Mood.OFF || m == Mood.SLEEPING) {
                // A sleeping Mochi's eyes are small arcs, a closed one's are lines.
                cr.set_line_width (R * 0.13 + 0.5);
                foreach (double sd in new double[] { -1, 1 }) {
                    if (m == Mood.SLEEPING) {
                        cr.new_sub_path ();
                        cr.arc (sd * ex, ey, R * 0.15, 0.15 * Math.PI, 0.85 * Math.PI);
                    } else {
                        cr.move_to (sd * ex - R * 0.14, ey + R * 0.04);
                        cr.line_to (sd * ex + R * 0.14, ey + R * 0.04);
                    }
                    cr.stroke ();
                }
            } else if (m == Mood.FINISHED || calm_happy) {
                cr.set_line_width (R * 0.15 + 0.5);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.new_sub_path ();
                    cr.arc (sd * ex + lx, ey + R * 0.1, R * 0.17, Math.PI, 2 * Math.PI);
                    cr.stroke ();
                }
            } else if (m == Mood.ERROR) {
                // Flat: two straight dashes.
                cr.set_line_width (R * 0.16 + 0.5);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.move_to (sd * ex - R * 0.14, ey + R * 0.05);
                    cr.line_to (sd * ex + R * 0.14, ey + R * 0.05);
                    cr.stroke ();
                }
            } else if (m == Mood.RATELIMIT) {
                // Tired: heavy lids, the lower half of the eye only.
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.new_sub_path ();
                    cr.save ();
                    cr.translate (sd * ex, ey + R * 0.04);
                    cr.scale (R * 0.15, R * 0.17);
                    cr.arc (0, 0, 1, 0, Math.PI);
                    cr.close_path ();
                    cr.restore ();
                    cr.fill ();
                }
            } else {
                double erx = m == Mood.APPROVAL ? R * 0.17 : R * 0.14;
                double ery = (m == Mood.APPROVAL ? R * 0.27 : R * 0.21) * (blinking ? 0.12 : 1.0);
                foreach (double sd in new double[] { -1, 1 }) {
                    ellipse (cr, sd * ex + lx, ey + ly, erx, ery);
                    cr.fill ();
                }
            }
        }

        // A small Mochi of another pill: its colour, two tiny eyes, and a dot of the
        // mood when something is going on (the island's pill badge).
        private void paint_mini (Cairo.Context cr, double x, double y, double scale, Pill p, double t) {
            double dy = 0;
            if (p.is_music && music_playing ()) {
                double beat = t * BPM / 60.0;
                dy = -0.14 * 7 * scale * Math.fabs (Math.sin (Math.PI * beat));
            } else if (p.mood == Mood.WORKING || p.mood == Mood.THINKING) {
                dy = -0.06 * 7 * scale * Math.fabs (Math.sin (t * 5.0));
            } else if (p.mood == Mood.APPROVAL) {
                dy = -0.16 * 7 * scale * Math.fabs (Math.sin (t * Math.PI * 1.7));
            }
            // Minis breathe and let their eyes wander, never following the mouse.
            double seed = 0;
            foreach (char ch in p.id.to_utf8 ()) seed += ch;
            double step = t / 1.3 + seed;
            double k0 = Math.floor (step);
            double a0 = Math.sin (k0 * 12.9898 + seed) * 0.5;
            double a1 = Math.sin ((k0 + 1) * 12.9898 + seed) * 0.5;
            double wander = (a0 + (a1 - a0) * ease (step - k0)) * 1.1;
            cr.save ();
            cr.translate (x, y + dy);
            cr.scale (scale * (1 - 0.02 * Math.sin (t * 2.2)), scale * (1 + 0.04 * Math.sin (t * 2.2)));
            squircle (cr, 0, 0, 8, 7, 2.8);
            cr.set_source_rgb (p.r, p.g, p.b);
            cr.fill ();
            cr.set_source_rgb (0.063, 0.075, 0.102);
            if (p.mood == Mood.FINISHED) {
                cr.set_line_width (0.8);
                cr.new_sub_path (); cr.arc (2.6, 3.5, 0.9, Math.PI, 2 * Math.PI); cr.stroke ();
                cr.new_sub_path (); cr.arc (5.4, 3.5, 0.9, Math.PI, 2 * Math.PI); cr.stroke ();
            } else {
                cr.arc (2.6 + wander, 3.1, 0.85, 0, 2 * Math.PI);
                cr.fill ();
                cr.arc (5.4 + wander, 3.1, 0.85, 0, 2 * Math.PI);
                cr.fill ();
            }
            if (!p.is_music && p.mood != Mood.IDLE) {
                double r, g, b;
                p.mood.rgb (out r, out g, out b);
                cr.set_source_rgb (0, 0, 0);
                cr.arc (7.4, 0.8, 2.1, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgb (r, g, b);
                cr.arc (7.4, 0.8, 1.5, 0, 2 * Math.PI);
                cr.fill ();
            }
            cr.restore ();
        }

        private int others_count () {
            return (int) uint.min (others (front ()).length (), 4);
        }

        private int wanted_width () {
            double r = 24 * 0.37;
            double w = 7 + r * 2 * 1.12 + 7;
            int n = others_count ();
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                w += 5 + cols * 8 + (cols - 1) * 3 + 2;
            }
            return (int) Math.ceil (w);
        }

        private void update_size () {
            if (capsule != null) {
                capsule.set_size_request (wanted_width (), 28);
                if (cap_view != null) cap_view.set_size_request (wanted_width (), 28);
            }
        }

        private bool draw_capsule (Cairo.Context cr) {
            int w = capsule.get_allocated_width ();
            int h = capsule.get_allocated_height ();
            double ch = double.min (h - 4.0, 24.0);
            double top = (h - ch) / 2.0;
            double mid = h / 2.0;
            if (shown_w <= 0) {
                shown_w = wanted_width ();
            }
            double width = double.min (w - 1.0, shown_w - 1.0);
            double x0 = (w - width) / 2.0;
            double t = now_s () - t0;

            // The capsule: black, with the faintest rim.
            squircle (cr, x0, top, width, ch, ch / 2.0);
            cr.set_source_rgb (0, 0, 0);
            cr.fill_preserve ();
            cr.set_source_rgba (1, 1, 1, 0.1);
            cr.set_line_width (1);
            cr.stroke ();

            double R = ch * 0.37;
            var f = front ();
            double mcx = x0 + 7 + R * 1.12;
            double now = now_s ();
            double mr, mg, mb;
            mood.rgb (out mr, out mg, out mb);

            cr.save ();
            squircle (cr, x0, top, width, ch, ch / 2.0);
            cr.clip ();
            // Sparkles when something finishes.
            double su = (now - finished_at - 0.5) / 0.9;
            if (mood == Mood.FINISHED && su >= 0 && su < 1) {  // five sparks, half a second in
                for (int i = 0; i < 5; i++) {
                    double a = i * Math.PI * 2 / 5 + 0.4;
                    double rad = R * 1.25 + su * 9;
                    cr.set_source_rgba (i % 2 == 0 ? 0.55 : 1.0, i % 2 == 0 ? 0.95 : 0.85, 0.5, 1 - su);
                    star (cr, mcx + Math.cos (a) * rad, mid + Math.sin (a) * rad, 1.0 + (1 - su) * 1.8);
                    cr.fill ();
                }
            }
            cr.restore ();

            paint_mochi (cr, mcx, mid, R, mood, f, dancing (), t);
            paint_hearts (cr, mcx, mid, R, 10);

            var rest = others (f);
            int n = (int) uint.min (rest.length (), 4);
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                int rows = n > 2 ? 2 : 1;
                double gx = x0 + 7 + R * 2 * 1.12 + 5;
                double gy = mid - (rows * 7 + (rows - 1) * 3) / 2.0;
                for (int i = 0; i < n; i++) {
                    paint_mini (cr, gx + (i % cols) * 11, gy + (i / cols) * 10, 1.0, rest.nth_data (i), t);
                }
            }
            return true;
        }

        // ── The panel: the open island ───────────────────────────────────────

        private static string clock (int64 ms) {
            if (ms <= 0) return "";
            return new DateTime.from_unix_local (ms / 1000).format ("%H:%M");
        }

        private static string stamp (double seconds) {
            int s = (int) Math.fmax (0, Math.floor (seconds));
            return "%d:%02d".printf (s / 60, s % 60);
        }

        private static void install_style () {
            if (styled) {
                return;
            }
            styled = true;
            var css = new Gtk.CssProvider ();
            try {
                css.load_from_data ("""
                    .coucou-pop, .coucou-pop decoration { background: transparent; box-shadow: none;
                                                          border: none; }
                    .coucou-island { background: #000000; border-radius: 0 0 26px 26px; padding: 12px; }
                    .coucou-card { background-image: linear-gradient(to bottom, #16181d, #0b0c0f);
                                   border: 1px solid rgba(255,255,255,0.09); border-radius: 18px; padding: 14px; }
                    .coucou-title { color: #ffffff; font-weight: 700; font-size: 13px; }
                    .coucou-kind { color: rgba(255,255,255,0.5); font-size: 12px; }
                    .coucou-sub { color: rgba(255,255,255,0.62); font-size: 12px; }
                    .coucou-stepnow { color: #ffffff; font-size: 12.5px; font-weight: 600; }
                    .coucou-step { color: #e8e9ec; font-family: monospace; font-size: 11.5px;
                                   background: rgba(255,255,255,0.08); border-radius: 9px; padding: 6px 10px; }
                    .coucou-answer { color: rgba(255,255,255,0.78); font-size: 12px; }
                    .coucou-link { color: #e8e9ec; font-weight: 700; font-size: 12px; background: none;
                                   border: none; box-shadow: none; padding: 2px 0; min-height: 0; }
                    .coucou-link:hover { color: #ffffff; text-decoration: underline; }
                    .coucou-cell { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.09);
                                   border-radius: 13px; padding: 6px 10px; box-shadow: none; }
                    .coucou-cell:hover { background: rgba(255,255,255,0.11); border-color: rgba(255,255,255,0.22); }
                    .coucou-cell label { color: rgba(255,255,255,0.82); font-size: 12px; }
                    .coucou-dim { color: rgba(255,255,255,0.4); font-size: 11px; }
                    .coucou-ctl { color: #ffffff; background: none; border: none; box-shadow: none;
                                  padding: 4px 8px; min-height: 0; min-width: 0; border-radius: 14px; }
                    .coucou-ctl:hover { background: rgba(255,255,255,0.14); }
                    .coucou-play { color: #000000; background: #ffffff; border: none; box-shadow: none;
                                   border-radius: 16px; padding: 5px 10px; min-height: 0; min-width: 0; }
                    .coucou-play:hover { background: #dddddd; }
                    .coucou-allow { color: #04210f; background: #34d399; border: none; box-shadow: none;
                                    border-radius: 14px; padding: 6px 12px; font-weight: 700; min-height: 0; }
                    .coucou-allow:hover { background: #6ee7b7; }
                    .coucou-deny { color: #ffffff; background: rgba(255,255,255,0.12); border: none; box-shadow: none;
                                   border-radius: 14px; padding: 6px 12px; font-weight: 700; min-height: 0; }
                    .coucou-deny:hover { background: rgba(255,90,90,0.55); }
                    .coucou-time { color: rgba(255,255,255,0.5); font-size: 10.5px; }
                """);
                Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            } catch (Error e) {
                warning ("coucou: style: %s", e.message);
            }
        }

        private Gtk.Label label (string text, string css_class, bool wrap = false) {
            var l = new Gtk.Label (text);
            l.xalign = 0;
            l.get_style_context ().add_class (css_class);
            if (wrap) {
                l.wrap = true;
                l.wrap_mode = Pango.WrapMode.WORD_CHAR;
                l.max_width_chars = 44;
                l.yalign = 0;
            } else {
                l.ellipsize = Pango.EllipsizeMode.END;
            }
            return l;
        }

        private Gtk.Button link (string text) {
            var b = new Gtk.Button.with_label (text);
            b.relief = Gtk.ReliefStyle.NONE;
            b.get_style_context ().add_class ("coucou-link");
            b.clicked.connect (open_chat);
            return b;
        }

        private Gtk.Button icon_button (string icon, string css_class, string action) {
            var b = new Gtk.Button ();
            b.relief = Gtk.ReliefStyle.NONE;
            b.image = new Gtk.Image.from_icon_name (icon, Gtk.IconSize.BUTTON);
            b.get_style_context ().add_class (css_class);
            b.clicked.connect (() => player (action));
            return b;
        }

        private Gtk.Box dot_title (string title, string kind, double r, double g, double b) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 7);
            var dot = new Gtk.DrawingArea ();
            dot.set_size_request (8, 8);
            dot.valign = Gtk.Align.CENTER;
            dot.draw.connect ((cr) => {
                cr.set_source_rgb (r, g, b);
                cr.arc (4, 4, 3.6, 0, 2 * Math.PI);
                cr.fill ();
                return true;
            });
            row.pack_start (dot, false, false, 0);
            row.pack_start (label (title, "coucou-title"), false, false, 0);
            row.pack_start (label (kind, "coucou-kind"), false, false, 0);
            return row;
        }

        // A cell of the right-hand card: a click brings that pill to the front.
        private Gtk.Widget cell (Pill p) {
            var button = new Gtk.Button ();
            button.relief = Gtk.ReliefStyle.NONE;
            button.get_style_context ().add_class ("coucou-cell");
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var mini = new Gtk.DrawingArea ();
            mini.set_size_request (24, 21);
            mini.valign = Gtk.Align.CENTER;
            mini.draw.connect ((cr) => {
                paint_mini (cr, 0, 2, 2.8, p, now_s () - t0);
                return true;
            });
            row.pack_start (mini, false, false, 0);
            string shown = p.app;
            if (!p.is_music && p.label != "") {
                foreach (var q in pills) {
                    if (q.id != p.id && q.app == p.app) {
                        shown = p.app + " · " + p.label;
                        break;
                    }
                }
            }
            var name = new Gtk.Label (shown);
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 12;
            name.hexpand = true;
            row.pack_start (name, true, true, 0);
            button.add (row);
            button.set_tooltip_text (p.is_music ? p.label + " · " + p.detail
                : (p.label != "" ? p.label + " · " : "") + (p.detail != "" ? p.detail : mood_text (p.mood)));
            button.clicked.connect (() => {
                pinned = p.id;
                recompute_mood ();
                update_panel ();
                redraw ();
            });
            return button;
        }

        private void update_progress () {
            if (!popup_open || music == null || progress_bar == null) {
                return;
            }
            progress_bar.queue_draw ();
            if (time_now != null) {
                time_now.label = stamp (music_position ());
            }
        }

        private double music_position () {
            if (music == null) {
                return 0;
            }
            double pos = music.get_double_member_with_default ("position", 0);
            double at = music.get_double_member_with_default ("positionAt", 0);
            double dur = music_duration ();
            if (music_playing () && at > 0) {
                pos += Math.fmax (0, (GLib.get_real_time () / 1000.0 - at) / 1000.0);
            }
            return dur > 0 ? Math.fmin (pos, dur) : pos;
        }

        private double music_duration () {
            if (music == null || !music.has_member ("track") || music.get_null_member ("track")) {
                return 0;
            }
            return music.get_object_member ("track").get_double_member_with_default ("duration", 0);
        }

        private void update_panel () {
            if (panel == null) {
                return;
            }
            // The big Mochi's page lives on between rebuilds of the card.
            if (big_box != null && big_box.get_parent () != null) {
                big_box.get_parent ().remove (big_box);
            }
            if (answer_view != null && answer_view.get_parent () != null) {
                answer_view.get_parent ().remove (answer_view);
            }
            foreach (var child in panel.get_children ()) {
                panel.remove (child);
            }
            big_mochi = null;
            progress_bar = null;
            time_now = null;
            time_total = null;

            var f = front ();
            var main = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            main.get_style_context ().add_class ("coucou-card");
            main.set_size_request (360, -1);

            var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            if (big_view == null) {
                big_view = make_view ("index.html", "#big", 84, 76);
                if (big_view != null) {
                    big_box = new Gtk.EventBox ();
                    big_box.visible_window = false;
                    big_box.above_child = true;
                    big_box.valign = Gtk.Align.CENTER;
                    big_box.add (big_view);
                    big_box.add_events (Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK);
                    big_box.enter_notify_event.connect (() => { js (big_view, "coucou.hover(true)"); return false; });
                    big_box.leave_notify_event.connect (() => { js (big_view, "coucou.hover(false)"); return false; });
                    big_box.motion_notify_event.connect ((ev) => {
                        js (big_view, "coucou.look(%.3f,%.3f)".printf ((ev.x - 42) / 42.0, (ev.y - 38) / 38.0));
                        return false;
                    });
                    big_box.button_press_event.connect (() => {
                        js (big_view, "coucou.click()");
                        return true;
                    });
                    big_box.show_all ();
                }
            }
            if (big_box != null) {
                top_row.pack_start (big_box, false, false, 0);
            } else {
            big_mochi = new Gtk.DrawingArea ();
            big_mochi.set_size_request (76, 66);
            big_mochi.valign = Gtk.Align.CENTER;
            big_mochi.add_events (Gdk.EventMask.BUTTON_PRESS_MASK);
            big_mochi.button_press_event.connect (() => {
                pet_at = now_s ();
                pop_at = now_s ();
                ensure_tick ();
                return true;
            });
            big_mochi.draw.connect ((cr) => {
                paint_hearts (cr, big_mochi.get_allocated_width () / 2.0, big_mochi.get_allocated_height () / 2.0, 24, 30);
                paint_mochi (cr, big_mochi.get_allocated_width () / 2.0, big_mochi.get_allocated_height () / 2.0 + 2,
                    25, mood, f, dancing (), now_s () - t0);
                return true;
            });
            top_row.pack_start (big_mochi, false, false, 0);
            }

            var info = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            info.valign = Gtk.Align.CENTER;

            if (f != null && f.is_music) {
                build_music_card (info, f);
            } else {
                build_session_card (main, info, f);
            }
            top_row.pack_start (info, true, true, 0);
            main.pack_start (top_row, false, false, 0);
            if (f != null && f.is_music) {
                add_player (main);
            } else {
                if (f != null && f.mood.alerts () && !(f.mood == Mood.APPROVAL && f.request != "")) {
                    main.pack_start (label (tr ("Answer in the terminal.", "Responda no terminal."), "coucou-dim"), false, false, 0);
                }
                add_answer (main, f);
            }

            var body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            body.pack_start (main, true, true, 0);

            // The other pills, as on the island's right card.
            var rest = others (f);
            if (rest.length () > 0) {
                var side = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
                side.get_style_context ().add_class ("coucou-card");
                side.set_size_request (190, -1);
                uint n = uint.min (rest.length (), 6);
                for (uint i = 0; i < n; i++) {
                    side.pack_start (cell (rest.nth_data (i)), false, false, 0);
                }
                body.pack_start (side, false, false, 0);
            }
            panel.pack_start (body, false, false, 0);
            panel.show_all ();
        }

        private void build_session_card (Gtk.Box main, Gtk.Box info, Pill? f) {
            string project = f != null ? f.label : "";
            double r, g, b;
            if (f != null && f.mood != Mood.IDLE) {
                f.mood.rgb (out r, out g, out b);
            } else {
                r = 0.54; g = 0.56; b = 0.60;
            }
            string app = f != null ? f.app : "Claude Code";
            string sub = (f != null && f.mood.alerts ()) ? mood_text (f.mood) : "";
            if (project != "") {
                sub = sub == "" ? project : project + " · " + sub;
            }
            info.pack_start (dot_title (app, sub, r, g, b), false, false, 0);
            bool any = false;
            if (f != null && f.steps != null) {
                uint count = f.steps.get_length ();
                for (uint i = 0; i < count; i++) {
                    bool newest = i == count - 1;
                    var line = label ((newest ? "› " : "") + f.steps.get_string_element (i), newest ? "coucou-stepnow" : "coucou-sub");
                    line.set_tooltip_text (f.steps.get_string_element (i));
                    info.pack_start (line, false, false, 0);
                    any = true;
                }
            }
            string newest_step = (f != null && f.steps != null && f.steps.get_length () > 0)
                ? f.steps.get_string_element (f.steps.get_length () - 1) : "";
            if (f != null && f.mood.alerts () && f.detail != "" && f.detail != newest_step) {
                info.pack_start (label (f.detail, "coucou-step"), false, false, 0);
            } else if (!any || mood == Mood.OFF || mood == Mood.SLEEPING || mood == Mood.IDLE || mood == Mood.FINISHED) {
                info.pack_start (label (mood_text (mood), "coucou-sub"), false, false, 0);
            }
            if (f != null && f.mood == Mood.APPROVAL && f.request != "") {
                var ask = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                ask.margin_top = 4;
                var deny = new Gtk.Button.with_label (tr ("Deny", "Negar"));
                deny.get_style_context ().add_class ("coucou-deny");
                var allow = new Gtk.Button.with_label (tr ("Allow", "Permitir"));
                allow.get_style_context ().add_class ("coucou-allow");
                string req = f.request;
                deny.clicked.connect (() => decide ("deny", req));
                allow.clicked.connect (() => decide ("allow", req));
                ask.pack_start (deny, true, true, 0);
                ask.pack_start (allow, true, true, 0);
                info.pack_start (ask, false, false, 0);
            }
            var links = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            links.sensitive = mood != Mood.OFF;
            links.pack_start (link (tr ("Open chat", "Abrir o chat")), false, false, 0);
            info.pack_start (links, false, false, 0);
        }

        private void add_answer (Gtk.Box main, Pill? f) {
            if (answer_body == "" || f == null || (answer_project != f.label && f.label != "")) {
                return;
            }
            var when = clock (answer_at);
            main.pack_start (label (tr ("Last answer", "Última resposta")
                + (answer_project != "" ? " · " + answer_project : "")
                + (when != "" ? " · " + when : ""), "coucou-dim"), false, false, 0);
            if (answer_view == null) {
                answer_view = make_view ("answer.html", "", 330, 40);
                if (answer_view != null) {
                    // The page says how tall its text is (its title); up to a screenful, then it scrolls.
                    answer_view.notify["title"].connect (() => {
                        int want = int.parse (answer_view.title ?? "0");
                        answer_view.set_size_request (330, int.max (40, int.min (want + 4, 280)));
                    });
                    answer_view.show ();
                }
            }
            if (answer_view != null) {
                main.pack_start (answer_view, false, false, 0);
                push_answer ();
                return;
            }
            var answer = label (answer_body, "coucou-answer", true);
            answer.lines = 7;
            answer.ellipsize = Pango.EllipsizeMode.END;
            answer.selectable = true;
            main.pack_start (answer, false, false, 0);
        }

        // The Spotify card: the track, where it is, and its three buttons.
        private void build_music_card (Gtk.Box info, Pill f) {
            info.pack_start (dot_title ("Spotify", music_playing () ? tr ("playing", "tocando") : tr ("paused", "pausado"),
                0.114, 0.725, 0.329), false, false, 0);
            info.pack_start (label (f.label, "coucou-stepnow"), false, false, 0);
            info.pack_start (label (f.detail != "" ? f.detail : tr ("Nothing playing", "Nada tocando"), "coucou-sub"), false, false, 0);
            var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            controls.pack_start (icon_button ("media-skip-backward-symbolic", "coucou-ctl", "previous"), false, false, 0);
            controls.pack_start (icon_button (music_playing () ? "media-playback-pause-symbolic" : "media-playback-start-symbolic",
                "coucou-play", "playPause"), false, false, 0);
            controls.pack_start (icon_button ("media-skip-forward-symbolic", "coucou-ctl", "next"), false, false, 0);
            info.pack_start (controls, false, false, 0);
        }

        private void add_player (Gtk.Box main) {
            double duration = music_duration ();
            if (duration <= 0) {
                return;
            }
            progress_bar = new Gtk.DrawingArea ();
            progress_bar.set_size_request (-1, 8);
            progress_bar.draw.connect ((cr) => {
                double w = progress_bar.get_allocated_width ();
                double frac = Math.fmin (1.0, music_position () / duration);
                squircle (cr, 0, 2, w, 4, 2);
                cr.set_source_rgba (1, 1, 1, 0.18);
                cr.fill ();
                squircle (cr, 0, 2, Math.fmax (4, w * frac), 4, 2);
                cr.set_source_rgb (0.114, 0.725, 0.329);
                cr.fill ();
                return true;
            });
            main.pack_start (progress_bar, false, false, 0);
            var times = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            time_now = label (stamp (music_position ()), "coucou-time");
            time_total = label (stamp (duration), "coucou-time");
            time_total.xalign = 1;
            times.pack_start (time_now, true, true, 0);
            times.pack_start (time_total, false, false, 0);
            main.pack_start (times, false, false, 0);
        }
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    // Only in the user's session, never on the login screen.
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }
    return new SlimIA.Indicator ();
}
