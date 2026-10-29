// Coucou in the top bar: a small Mochi that changes colour with what the agents
// are doing, and a panel with the sessions and Claude's last answer.
//
// It does not talk to Coucou: it reads ~/.local/share/coucou/status.json, which
// the Coucou app rewrites on every hook event (src-tauri/src/status.rs). It opens
// no connection and runs nothing but Coucou's own `--shortcut openChat` when you
// press "Open Coucou". If Coucou is not running the Mochi is grey.

namespace Coucou {
    public enum Mood {
        OFF, IDLE, FINISHED, WORKING, ERROR, WAITING;

        public static Mood parse (string? name) {
            switch (name) {
                case "idle": return IDLE;
                case "finished": return FINISHED;
                case "working": return WORKING;
                case "error": return ERROR;
                case "waiting": return WAITING;
                default: return IDLE;
            }
        }

        public bool pulses () {
            return this == WORKING || this == WAITING;
        }

        // Body colour of the Mochi in the bar.
        public void rgb (out double r, out double g, out double b) {
            switch (this) {
                case WORKING: r = 0.231; g = 0.620; b = 1.000; break;   // #3B9EFF
                case WAITING: r = 0.961; g = 0.647; b = 0.141; break;   // #F5A524
                case FINISHED: r = 0.204; g = 0.827; b = 0.600; break;  // #34D399
                case ERROR: r = 0.957; g = 0.314; b = 0.369; break;     // #F4505E
                case OFF: r = 0.45; g = 0.46; b = 0.50; break;
                default: r = 0.961; g = 0.965; b = 0.973; break;        // #F5F6F8
            }
        }
    }

    // Text in the user's language: Portuguese when the locale is, English otherwise.
    string tr (string en, string pt) {
        var lang = Environment.get_variable ("LANGUAGE") ?? Environment.get_variable ("LC_MESSAGES")
            ?? Environment.get_variable ("LANG") ?? "";
        return lang.has_prefix ("pt") ? pt : en;
    }

    public class Indicator : Wingpanel.Indicator {
        private Gtk.DrawingArea? mochi = null;
        private Gtk.Box? panel = null;
        private Gtk.DrawingArea? big_mochi = null;
        private static bool styled = false;

        private Mood mood = Mood.OFF;
        private string exe = "";
        private Json.Array? sessions = null;
        private string answer_project = "";
        private string answer_body = "";
        private int64 answer_at = 0;
        private uint64 phase = 0;
        private uint poll_id = 0;
        private uint tick_id = 0;
        private string last_raw = "";
        private bool blinking = false;
        private uint blink_id = 0;

        public Indicator () {
            Object (code_name: "coucou");
            visible = true;
        }

        private static string status_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "coucou", "status.json");
        }

        public override Gtk.Widget get_display_widget () {
            if (mochi == null) {
                mochi = new Gtk.DrawingArea ();
                mochi.set_size_request (wanted_width (), 28);
                mochi.draw.connect (draw_mochi);
                // He blinks now and then; between blinks nothing is redrawn.
                blink_id = Timeout.add (3600, () => {
                    blinking = true;
                    mochi.queue_draw ();
                    if (big_mochi != null) big_mochi.queue_draw ();
                    Timeout.add (150, () => { blinking = false; mochi.queue_draw (); if (big_mochi != null) big_mochi.queue_draw (); return false; });
                    return true;
                });
                refresh ();
                // The file is tiny: reading it once a second costs nothing.
                poll_id = Timeout.add_seconds (1, () => { refresh (); return true; });
            }
            return mochi;
        }

        public override Gtk.Widget? get_widget () {
            if (panel == null) {
                install_style ();
                panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                panel.get_style_context ().add_class ("coucou-island");
                update_panel ();
            }
            return panel;
        }

        public override void opened () {
            refresh ();
        }

        public override void closed () {
        }

        private void open_coucou () {
            close ();
            if (exe == "") {
                return;
            }
            try {
                // A second launch only brings the running Coucou forward (single instance).
                Process.spawn_async (null, { exe, "--shortcut", "openChat" }, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, null);
            } catch (Error e) {
                warning ("coucou: could not open: %s", e.message);
            }
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
            if (raw == last_raw && mood != Mood.OFF && !is_stale ()) {
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
                var next = Mood.parse (root.get_string_member_with_default ("state", "idle"));
                sessions = root.has_member ("sessions") ? root.get_array_member ("sessions") : null;
                answer_project = ""; answer_body = ""; answer_at = 0;
                if (root.has_member ("lastAnswer") && !root.get_null_member ("lastAnswer")) {
                    var a = root.get_object_member ("lastAnswer");
                    answer_project = a.get_string_member_with_default ("project", "");
                    answer_body = a.get_string_member_with_default ("text", "");
                    answer_at = a.get_int_member_with_default ("at", 0);
                }
                set_mood (next);
            } catch (Error e) {
                apply_off ();
            }
        }

        private bool is_stale () {
            return false;
        }

        private void apply_off () {
            sessions = null;
            last_raw = "";
            set_mood (Mood.OFF);
        }

        private void set_mood (Mood next) {
            mood = next;
            // Working and waiting breathe; the rest holds still and costs nothing.
            if (mood.pulses () && tick_id == 0) {
                tick_id = Timeout.add (90, () => {
                    phase++;
                    if (mochi != null) mochi.queue_draw ();
                    if (big_mochi != null) big_mochi.queue_draw ();
                    if (!mood.pulses ()) {
                        tick_id = 0;
                        return false;
                    }
                    return true;
                });
            }
            update_size ();
            if (mochi != null) {
                mochi.queue_draw ();
                string hint = mood_text (mood);
                if (sessions != null && sessions.get_length () > 0) {
                    var detail = sessions.get_object_element (0).get_string_member_with_default ("detail", "");
                    if (detail != "") hint = hint + " · " + detail;
                }
                mochi.set_tooltip_text (hint);
            }
            update_panel ();
        }

        // ── The island in the bar ────────────────────────────────────────────
        //
        // The same look as Coucou's compact island: a black capsule, Mochi on the
        // left (soft grey body, a highlight, two dark eyes that blink), and on the
        // right a small coloured Mochi for each session.

        private const double INK_R = 0.102;
        private const double INK_G = 0.078;
        private const double INK_B = 0.071;

        private static void squircle (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private static void mini_rgb (Mood m, out double r, out double g, out double b) {
            switch (m) {
                case Mood.WORKING: r = 0.231; g = 0.620; b = 1.000; break;
                case Mood.WAITING: r = 0.961; g = 0.647; b = 0.141; break;
                case Mood.FINISHED: r = 0.204; g = 0.827; b = 0.600; break;
                case Mood.ERROR: r = 0.957; g = 0.314; b = 0.369; break;
                default: r = 0.54; g = 0.56; b = 0.60; break;
            }
        }

        private double mochi_radius (double capsule_h) {
            return capsule_h * 0.37;
        }

        private int session_count () {
            return sessions == null ? 0 : (int) uint.min (sessions.get_length (), 4);
        }

        private int wanted_width () {
            double r = mochi_radius (24);
            double w = 7 + r * 2 * 1.12 + 7;
            int n = session_count ();
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                w += 5 + cols * 8 + (cols - 1) * 3;
            }
            return (int) Math.ceil (w);
        }

        private void update_size () {
            if (mochi != null) {
                mochi.set_size_request (wanted_width (), 28);
            }
        }

        private void paint_mochi (Cairo.Context cr, double cx, double cy, double R) {
            double breath = mood.pulses () ? 0.5 + 0.5 * Math.sin (phase * 0.35) : 0.0;
            double sc = 1.0 + 0.05 * breath;
            double rw = R * 1.12 * sc;
            double rh = R * 0.98 * sc;
            double alpha = mood == Mood.OFF ? 0.5 : 1.0;

            cr.save ();
            squircle (cr, cx - rw, cy - rh, rw * 2, rh * 2, rh * 0.84);
            cr.clip ();

            var body = new Cairo.Pattern.linear (cx + rw * 0.7, cy - rh * 0.85, cx - rw * 0.8, cy + rh * 0.9);
            body.add_color_stop_rgba (0, 0.929, 0.929, 0.937, alpha);
            body.add_color_stop_rgba (1, 0.769, 0.773, 0.792, alpha);
            cr.set_source (body);
            cr.paint ();

            // The colour of what is going on rises from the bottom, like Mochi's tint.
            double strength = 0;
            switch (mood) {
                case Mood.WORKING: strength = 0.45 + 0.35 * breath; break;
                case Mood.WAITING: strength = 0.6 + 0.3 * breath; break;
                case Mood.FINISHED: strength = 0.6; break;
                case Mood.ERROR: strength = 0.7; break;
                default: break;
            }
            if (strength > 0) {
                double tr_, tg, tb;
                mood.rgb (out tr_, out tg, out tb);
                var tint = new Cairo.Pattern.linear (0, cy + rh, 0, cy - rh);
                tint.add_color_stop_rgba (0, tr_, tg, tb, 0.85 * strength);
                tint.add_color_stop_rgba (1, tr_, tg, tb, 0);
                cr.set_source (tint);
                cr.paint ();
            }

            var shade = new Cairo.Pattern.radial (cx, cy, R * 0.15, cx, cy, R * 1.25);
            shade.add_color_stop_rgba (0, 0, 0, 0, 0);
            shade.add_color_stop_rgba (0.6, 0, 0, 0, 0);
            shade.add_color_stop_rgba (1, 0, 0, 0, 0.2);
            cr.set_source (shade);
            cr.paint ();

            var light = new Cairo.Pattern.radial (cx + rw * 0.34, cy - rh * 0.46, 0, cx + rw * 0.34, cy - rh * 0.46, R * 0.42);
            light.add_color_stop_rgba (0, 1, 1, 1, 0.55 * alpha * alpha);
            light.add_color_stop_rgba (1, 1, 1, 1, 0);
            cr.set_source (light);
            cr.paint ();
            cr.restore ();

            // Eyes.
            double ex = R * 0.37;
            double ey = cy - R * 0.12;
            double look = mood == Mood.WORKING ? Math.sin (phase * 0.22) * R * 0.14 : 0.0;
            cr.set_source_rgba (INK_R, INK_G, INK_B, alpha);
            if (mood == Mood.OFF) {
                cr.set_line_width (1.2);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.move_to (cx + sd * ex - R * 0.13, ey + R * 0.04);
                    cr.line_to (cx + sd * ex + R * 0.13, ey + R * 0.04);
                    cr.stroke ();
                }
            } else if (mood == Mood.FINISHED) {
                cr.set_line_width (1.4);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.new_sub_path ();
                    cr.arc (cx + sd * ex, ey + R * 0.1, R * 0.17, Math.PI, 2 * Math.PI);
                    cr.stroke ();
                }
            } else {
                double erx = mood == Mood.WAITING ? R * 0.17 : R * 0.14;
                double ery = (mood == Mood.WAITING ? R * 0.27 : R * 0.21) * (blinking ? 0.12 : 1.0);
                foreach (double sd in new double[] { -1, 1 }) {
                    cr.save ();
                    cr.translate (cx + sd * ex + look, ey);
                    cr.scale (erx, ery);
                    cr.arc (0, 0, 1, 0, 2 * Math.PI);
                    cr.restore ();
                    cr.fill ();
                }
            }

            // The badge Mochi wears when you are needed, or when something broke.
            if (mood == Mood.WAITING || mood == Mood.ERROR) {
                double br, bg, bb;
                mood.rgb (out br, out bg, out bb);
                cr.set_source_rgb (0, 0, 0);
                cr.arc (cx + rw * 0.92, cy - rh * 0.9, 3.6, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgb (br, bg, bb);
                cr.arc (cx + rw * 0.92, cy - rh * 0.9, 2.7, 0, 2 * Math.PI);
                cr.fill ();
            }
        }

        private void paint_mini (Cairo.Context cr, double x, double y, Mood m) {
            double r, g, b;
            mini_rgb (m, out r, out g, out b);
            squircle (cr, x, y, 8, 7, 2.8);
            cr.set_source_rgb (r, g, b);
            cr.fill ();
            cr.set_source_rgb (0.063, 0.075, 0.102);
            cr.arc (x + 2.6, y + 3.1, 0.85, 0, 2 * Math.PI);
            cr.fill ();
            cr.arc (x + 5.4, y + 3.1, 0.85, 0, 2 * Math.PI);
            cr.fill ();
        }

        private bool draw_mochi (Cairo.Context cr) {
            int w = mochi.get_allocated_width ();
            int h = mochi.get_allocated_height ();
            double ch = double.min (h - 4.0, 24.0);
            double top = (h - ch) / 2.0;
            double mid = h / 2.0;
            double width = double.min (w - 1.0, wanted_width () - 1.0);
            double x0 = (w - width) / 2.0;

            // The capsule: black, with the faintest rim.
            squircle (cr, x0, top, width, ch, ch / 2.0);
            cr.set_source_rgb (0, 0, 0);
            cr.fill_preserve ();
            cr.set_source_rgba (1, 1, 1, 0.1);
            cr.set_line_width (1);
            cr.stroke ();

            double R = mochi_radius (ch);
            paint_mochi (cr, x0 + 7 + R * 1.12, mid, R);

            int n = session_count ();
            if (n > 0) {
                int cols = n > 2 ? 2 : n;
                int rows = n > 2 ? 2 : 1;
                double gx = x0 + 7 + R * 2 * 1.12 + 5;
                double gy = mid - (rows * 7 + (rows - 1) * 3) / 2.0;
                for (int i = 0; i < n; i++) {
                    var s = sessions.get_object_element (i);
                    var m = Mood.parse (s.get_string_member_with_default ("state", "idle"));
                    paint_mini (cr, gx + (i % cols) * 11, gy + (i / cols) * 10, m);
                }
            }
            return true;
        }

        // ── The panel ────────────────────────────────────────────────────────

        private string mood_text (Mood m) {
            switch (m) {
                case WORKING: return tr ("Working…", "Trabalhando…");
                case WAITING: return tr ("needs permission", "precisa de permissão");
                case FINISHED: return tr ("Finished", "Terminou");
                case ERROR: return tr ("Something went wrong", "Algo deu errado");
                case OFF: return tr ("Coucou is not running", "O Coucou não está aberto");
                default: return tr ("Nothing running", "Nada rodando");
            }
        }

        private static string clock (int64 ms) {
            if (ms <= 0) return "";
            return new DateTime.from_unix_local (ms / 1000).format ("%H:%M");
        }

        private static string hex (Mood m) {
            double r, g, b;
            mini_rgb (m, out r, out g, out b);
            if (m == Mood.IDLE || m == Mood.OFF) {
                return "#8A8F98";
            }
            return "#%02X%02X%02X".printf ((int) (r * 255), (int) (g * 255), (int) (b * 255));
        }

        // The look of Coucou's open island: a black panel, dark cards with a fine rim.
        private static void install_style () {
            if (styled) {
                return;
            }
            styled = true;
            var css = new Gtk.CssProvider ();
            try {
                css.load_from_data ("""
                    .coucou-island { background: #000000; border-radius: 22px; padding: 12px; }
                    .coucou-card { background-image: linear-gradient(to bottom, #16181d, #0b0c0f);
                                   border: 1px solid rgba(255,255,255,0.09); border-radius: 18px; padding: 14px; }
                    .coucou-title { color: #ffffff; font-weight: 700; font-size: 13px; }
                    .coucou-kind { color: rgba(255,255,255,0.5); font-size: 12px; }
                    .coucou-sub { color: rgba(255,255,255,0.62); font-size: 12px; }
                    .coucou-step { color: #e8e9ec; font-family: monospace; font-size: 11.5px;
                                   background: rgba(255,255,255,0.08); border-radius: 9px; padding: 6px 10px; }
                    .coucou-stepnow { color: #ffffff; font-size: 12.5px; font-weight: 600; }
                    .coucou-answer { color: rgba(255,255,255,0.78); font-size: 12px; }
                    .coucou-link { color: #e8e9ec; font-weight: 700; font-size: 12px; background: none;
                                   border: none; box-shadow: none; padding: 2px 0; min-height: 0; }
                    .coucou-link:hover { color: #ffffff; text-decoration: underline; }
                    .coucou-cell { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.09);
                                   border-radius: 13px; padding: 6px 10px; }
                    .coucou-cell label { color: rgba(255,255,255,0.8); font-size: 12px; }
                    .coucou-dim { color: rgba(255,255,255,0.4); font-size: 11px; }
                """);
                Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            } catch (Error e) {
                warning ("coucou: style: %s", e.message);
            }
        }

        private Gtk.Label label (string text, string css_class, bool wrap = false) {
            var l = new Gtk.Label (null);
            l.set_markup ("");
            l.label = text;
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
            b.clicked.connect (open_coucou);
            return b;
        }

        private Gtk.Box dot_title (string project, string kind, Mood m) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 7);
            var dot = new Gtk.DrawingArea ();
            dot.set_size_request (8, 8);
            dot.valign = Gtk.Align.CENTER;
            dot.draw.connect ((cr) => {
                double r, g, b;
                mini_rgb (m, out r, out g, out b);
                cr.set_source_rgb (r, g, b);
                cr.arc (4, 4, 3.6, 0, 2 * Math.PI);
                cr.fill ();
                return true;
            });
            row.pack_start (dot, false, false, 0);
            row.pack_start (label (project == "" ? "Claude Code" : project, "coucou-title"), false, false, 0);
            row.pack_start (label (kind, "coucou-kind"), false, false, 0);
            return row;
        }

        private Gtk.Widget session_cell (Json.Object s) {
            var m = Mood.parse (s.get_string_member_with_default ("state", "idle"));
            var cell = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            cell.get_style_context ().add_class ("coucou-cell");
            var mini = new Gtk.DrawingArea ();
            mini.set_size_request (22, 19);
            mini.valign = Gtk.Align.CENTER;
            mini.draw.connect ((cr) => {
                cr.scale (2.6, 2.6);
                paint_mini (cr, 0, 0.6, m);
                return true;
            });
            cell.pack_start (mini, false, false, 0);
            var name = new Gtk.Label (s.get_string_member_with_default ("project", ""));
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 12;
            name.hexpand = true;
            cell.pack_start (name, true, true, 0);
            return cell;
        }

        private void update_panel () {
            if (panel == null) {
                return;
            }
            foreach (var child in panel.get_children ()) {
                panel.remove (child);
            }
            big_mochi = null;

            // Who the main card is about: the session that needs you most (the first one).
            Json.Object? top = null;
            if (sessions != null && sessions.get_length () > 0) {
                top = sessions.get_object_element (0);
            }
            string project = top != null ? top.get_string_member_with_default ("project", "") : "";
            string detail = top != null ? top.get_string_member_with_default ("detail", "") : "";
            bool has_answer = answer_body != "";

            // ── The main card: Mochi, who, what ──
            var main = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            main.get_style_context ().add_class ("coucou-card");
            main.set_size_request (360, -1);

            var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            big_mochi = new Gtk.DrawingArea ();
            big_mochi.set_size_request (76, 66);
            big_mochi.valign = Gtk.Align.CENTER;
            big_mochi.draw.connect ((cr) => {
                paint_mochi (cr, big_mochi.get_allocated_width () / 2.0, big_mochi.get_allocated_height () / 2.0, 25);
                return true;
            });
            top_row.pack_start (big_mochi, false, false, 0);

            var info = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            info.valign = Gtk.Align.CENTER;
            info.pack_start (dot_title (project, mood == Mood.WAITING ? mood_text (mood) : "Claude Code", mood), false, false, 0);
            // The last steps, newest at the bottom with its arrow, as on the island.
            bool any_step = false;
            if (top != null && top.has_member ("steps")) {
                var steps = top.get_array_member ("steps");
                uint count = steps.get_length ();
                for (uint i = 0; i < count; i++) {
                    bool newest = i == count - 1;
                    var line = label ((newest ? "› " : "") + steps.get_string_element (i), newest ? "coucou-stepnow" : "coucou-sub");
                    line.set_tooltip_text (steps.get_string_element (i));
                    info.pack_start (line, false, false, 0);
                    any_step = true;
                }
            }
            if (!any_step) {
                if (mood == Mood.WAITING && detail != "") {
                    info.pack_start (label (detail, "coucou-step"), false, false, 0);
                } else {
                    info.pack_start (label (mood_text (mood), "coucou-sub"), false, false, 0);
                }
            } else if (mood == Mood.WAITING && detail != "") {
                info.pack_start (label (detail, "coucou-step"), false, false, 0);
            } else if (mood != Mood.WORKING) {
                info.pack_start (label (mood_text (mood), "coucou-sub"), false, false, 0);
            }
            var links = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            links.sensitive = mood != Mood.OFF;
            links.pack_start (link (tr ("Open chat", "Abrir o chat")), false, false, 0);
            info.pack_start (links, false, false, 0);
            top_row.pack_start (info, true, true, 0);
            main.pack_start (top_row, false, false, 0);

            if (mood == Mood.WAITING) {
                main.pack_start (label (tr ("Answer in the Coucou island.", "Responda na ilha do Coucou."), "coucou-dim"), false, false, 0);
            }
            if (has_answer) {
                var when = clock (answer_at);
                main.pack_start (label (tr ("Last answer", "Última resposta")
                    + (answer_project != "" ? " · " + answer_project : "")
                    + (when != "" ? " · " + when : ""), "coucou-dim"), false, false, 0);
                var answer = label (answer_body, "coucou-answer", true);
                answer.lines = 7;
                answer.ellipsize = Pango.EllipsizeMode.END;
                answer.selectable = true;
                main.pack_start (answer, false, false, 0);
            }

            var body = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            body.pack_start (main, true, true, 0);

            // ── The other sessions, as on the island's right card ──
            if (sessions != null && sessions.get_length () > 1) {
                var side = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
                side.get_style_context ().add_class ("coucou-card");
                side.set_size_request (190, -1);
                uint n = uint.min (sessions.get_length (), 6);
                for (uint i = 1; i < n; i++) {
                    side.pack_start (session_cell (sessions.get_object_element (i)), false, false, 0);
                }
                body.pack_start (side, false, false, 0);
            }
            panel.pack_start (body, false, false, 0);
            panel.show_all ();
        }
    }
}

public Wingpanel.Indicator? get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    // Only in the user's session, never on the login screen.
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }
    return new Coucou.Indicator ();
}
